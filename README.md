# AWS Developer Platform

[![Security Gate](https://github.com/jordann6/aws-developer-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/jordann6/aws-developer-platform/actions/workflows/ci.yml)

An Internal Developer Platform on EKS that gives application teams a paved road: self-service infrastructure, GitOps delivery, golden-path scaffolding, and policy guardrails. Developers consume simple, safe abstractions; the platform handles the hardening, IAM, and reconciliation underneath.

## Architecture

![Architecture](docs/architecture.png)

| Layer | Tool | Role |
|---|---|---|
| Cluster substrate | **EKS** (Terraform) | VPC, managed node group, OIDC/IRSA, provisioned as code |
| GitOps | **ArgoCD** (app-of-apps) | Reconciles every platform component from this repo |
| Self-service infra | **Crossplane** + AWS provider | A `Bucket` claim provisions a real, hardened S3 bucket (SSE-KMS + TLS-only) |
| Guardrails | **Kyverno** | Policy-as-code admission control: attribution, hardening, image signing |
| FinOps | **finops.rego gate** + **OpenCost** | CostCenter enforced in CI and at admission; cluster spend attributed by the same key |
| Developer portal | **Backstage** | Catalog plus a golden-path microservice template |

## The self-service flow

A developer applies a tiny claim (or uses the Backstage golden path):

```yaml
apiVersion: platform.jordann6.io/v1alpha1
kind: Bucket
metadata:
  name: demo-bucket
  namespace: team-apps
spec:
  parameters:
    region: us-east-1
    team: payments
    costCenter: cc-1001
```

Crossplane composes that into a real S3 bucket that is **hardened by default**, with no way for the developer to opt out. The control set is deliberately identical to the [`governed-data-pipeline`](https://github.com/jordann6/governed-data-pipeline) Terraform module's S3 zones, so a bucket born from a one-line claim carries the same guarantees as one from the audited pipeline:

- **SSE-KMS** with a customer-managed key (rotation on), not SSE-S3
- **TLS-only** bucket policy (deny `aws:SecureTransport=false`)
- All four public-access-block settings on
- Versioning enabled
- Owning-team and **CostCenter** tags applied

Crossplane authenticates to AWS via **IRSA** (the provider pod assumes an IAM role through its projected ServiceAccount token), so there are no static credentials anywhere in the platform.

## How it is wired

- **App-of-apps:** `platform/argocd/root-app.yaml` points ArgoCD at `platform/argocd/apps`, which declares one `Application` per component. Sync waves order the install (control planes first, then their configuration).
- **Crossplane:** `platform/crossplane/` holds the AWS provider (with an IRSA `DeploymentRuntimeConfig`), the `ProviderConfig`, and the `XRD` + `Composition` that define the `Bucket` API.
- **Kyverno:** `platform/kyverno/` enforces, in namespaces labeled `team-policy=enforce`, an owning-team label, a `cost-center` label (the admission-time twin of the CI FinOps gate), and a baseline-hardening set (non-root, no privilege escalation, resource limits, no `:latest`). It also audits image signatures (cosign keyless) as the runtime end of the supply-chain signing story. All scoped by namespace selector so platform namespaces are untouched.
- **FinOps gate:** `.github/workflows/guardrails.yml` calls the shared `platform-guardrails` pipeline. `finops.rego` fails a PR whose Terraform is missing or placeholders the `CostCenter` allocation tag, and an Infracost job fails a PR that raises projected spend past $50/mo without a `cost-approved` label. `OpenCost` (`platform/argocd/apps/opencost.yaml`) then attributes running cluster spend by the same key.
- **Incident response:** page-severity SLO burn-rate alerts route to an incident responder (Claude summary + Slack verify/escalate, human in the loop) rather than a null receiver. See `docs/runbooks/incident-auto-response.md`.
- **Backstage:** `backstage/` is a real scaffolded app. The golden-path template at `backstage/templates/microservice/` produces a new service born compliant: a Dockerfile, a hardened Helm chart (cost-center label, resource limits, pinned image tag), a burn-rate SLO, a runbook, and an ArgoCD `Application`, so a new service is GitOps-deployable and governed the moment it exists.

## Deploy

```bash
# 1. Provision the cluster
cd terraform
terraform init
terraform apply
eval "$(terraform output -raw configure_kubectl)"

# 2. Bootstrap GitOps
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argo-cd argo/argo-cd -n argocd --create-namespace \
  --set dex.enabled=false --set notifications.enabled=false --set applicationSet.enabled=false
kubectl apply -f platform/argocd/root-app.yaml
```

ArgoCD then reconciles Crossplane, Kyverno, and Backstage from this repo.

## Try the self-service path

```bash
kubectl create namespace team-apps
kubectl apply -f examples/bucket-claim.yaml

# Watch the claim go Ready, then confirm the real bucket is hardened
kubectl get bucket.platform.jordann6.io -n team-apps
BUCKET=$(kubectl get bucket.s3.aws.upbound.io -o jsonpath='{.items[0].status.atProvider.id}')
aws s3api get-bucket-encryption --bucket "$BUCKET"
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws s3api get-public-access-block --bucket "$BUCKET"

# Reclaim: deleting the claim deletes the bucket
kubectl delete bucket.platform.jordann6.io/demo-bucket -n team-apps
```

## Guardrail demo

```bash
kubectl create namespace demo && kubectl label namespace demo team-policy=enforce

# Denied: an enforced namespace requires a team label, a cost-center label,
# resource limits, a non-root securityContext, and a pinned (non-:latest) image.
kubectl run nginx --image=nginx -n demo

# Allowed: a pod that satisfies every policy (labels + hardening + limits).
kubectl apply -n demo -f examples/compliant-pod.yaml
```

The bare `kubectl run` trips several policies at once, which is the point: the
attribution and hardening controls are un-skippable in an enforced namespace. See
`kubectl get cpol` and `kubectl describe cpol <name>` for the full set.

## Teardown

```bash
# Delete Crossplane claims first so managed AWS resources are removed
kubectl delete bucket.platform.jordann6.io --all -A
cd terraform && terraform destroy
```

Order matters: Crossplane-managed resources live outside the cluster, so claims are deleted before the cluster is torn down to avoid orphaned buckets.

## Cost

The only meaningful cost is the EKS cluster while it runs: control plane (~$0.10/hr) plus two `t3.large` nodes and a single NAT gateway, roughly $0.40 to $0.60/hr. This is a spin-up, demo, tear-down environment. OpenCost and the added guardrails run inside the existing node group and add nothing. Each self-service bucket now owns a customer-managed KMS key (~$1/mo prorated while it exists, plus per-request charges); deleting the claim deletes the key, so a demo run adds cents.

## Compliance mapping

The platform's controls, and the audit expectations they answer, are the same story as the [`governed-data-pipeline`](https://github.com/jordann6/governed-data-pipeline) flagship, expressed here through Kubernetes admission and a Crossplane API instead of a Terraform module and a CI gate.

| Control | Implementation | Satisfies |
|---|---|---|
| Cost attribution | `CostCenter` in `default_tags`, `finops.rego` gate; `cost-center` label at admission | FinOps chargeback, SOC 2 accountability |
| Cost ceiling | Infracost per-PR threshold ($50/mo), `cost-approved` override | preventive FinOps |
| Cost visibility | OpenCost, attributed by namespace / workload / cost-center | detective FinOps, ongoing ownership |
| Encrypt at rest | Crossplane CMK + SSE-KMS, rotation on | SOC 2 CC6.1, ISO 27001 crypto |
| Encrypt in transit | TLS-only bucket policy (`DenyInsecureTransport`) | SOC 2 CC6.7 |
| No public data | public-access-block, all four, every bucket | SOC 2 CC6, confidentiality |
| Least privilege | IRSA (no static creds), scoped IAM per workload | SOC 2 CC6.3 |
| Runtime hardening | Kyverno: non-root, no priv-esc, limits, no `:latest` | CIS Kubernetes, SOC 2 CC6/CC7 |
| Supply-chain integrity | Kyverno cosign image verification (Audit) | SOC 2 CC8, SLSA provenance |
| Change control | GitOps: Git is the source of truth, ArgoCD reconciles | SOC 2 CC8.1, GxP / 21 CFR Part 11 |
| Incident response | burn-rate pages routed to responder, human in the loop | operational resilience, SOC 2 CC7 |

## Tech Stack

- **Terraform** `>= 1.6` with `terraform-aws-modules/eks` and `vpc`, S3 state backend
- **Amazon EKS** v1.33, managed node group, IRSA/OIDC
- **ArgoCD** app-of-apps GitOps
- **Crossplane** 1.20 with the Upbound AWS S3 + KMS providers, IRSA auth, XRD + Composition
- **Kyverno** 1.13 policy-as-code: attribution, baseline hardening, cosign image verification
- **FinOps** shared `finops.rego` + Infracost gate (via `platform-guardrails`), **OpenCost** for cluster cost attribution
- **Backstage** scaffolder golden-path template (born compliant: labels, limits, SLO, runbook)