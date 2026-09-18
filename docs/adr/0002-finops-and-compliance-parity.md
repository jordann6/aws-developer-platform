# ADR-0002: Make the platform's controls parity-match the governed data pipeline

- **Status:** accepted
- **Date:** 2026-09-18

## Context

The platform already made the safe path the only path for *shape* (public access
blocked, encryption on, versioning) and for *ownership* (a required team label).
Two gaps remained against what a regulated, cost-conscious org actually audits:

- **FinOps.** Nothing forced spend to be attributable or bounded. A resource
  could be perfectly tagged for identity and still be a hole in the chargeback
  report, and no gate stopped a change that quietly raised the monthly bill.
- **Control parity with the flagship.** The self-service bucket was weaker than a
  bucket provisioned by the audited `governed-data-pipeline` Terraform module: it
  used SSE-S3, not a customer-managed key, and had no TLS-only policy. Two paths
  to a bucket, two different control sets, is itself an audit finding.

The binding constraints: a GxP + SOC 2 target (change must be provable and
attested), a real fear of unbounded spend, and a deploy/demo/destroy budget that
rules out always-on tooling.

## Decision

Enforce the same controls on both sides of the wall and close the FinOps loop:

- **Cost attribution + budget, at the gate.** A `CostCenter` tag (house format
  `cc-NNNN`) is required on every Terraform resource via provider `default_tags`,
  enforced by the shared `finops.rego` allocation gate, and a per-PR Infracost
  threshold fails a change that adds more than $50/mo without a `cost-approved`
  label. The same `cost-center` label is required on workloads at admission by a
  Kyverno policy, so CI and the cluster enforce one attribution key.
- **Encryption + transport parity.** The Crossplane bucket Composition now uses a
  customer-managed KMS key with rotation (SSE-KMS) and a TLS-only bucket policy,
  matching the flagship's zones control-for-control.
- **Baseline runtime hardening + supply chain.** Kyverno enforces non-root, no
  privilege escalation, resource limits, and no `:latest` in enforced namespaces,
  and audits image signatures (cosign keyless) as the runtime end of the
  build-time signing chain.
- **Cost visibility + incident loop.** OpenCost attributes cluster spend by the
  same key; page-severity burn-rate alerts route to the incident responder
  (Claude summary + Slack verify/escalate, human in the loop) instead of a null
  receiver.
- **Golden path inherits all of it.** A scaffolded service is born with a cost
  centre label, resource limits, a pinned image tag, a burn-rate SLO, and a
  runbook.

## Alternatives rejected

| Option | Why not |
| ------ | ------- |
| Cost dashboard only (detective) | Tells you after the overspend. The $15k-class problem needs a preventive gate at the PR, not a report next month. |
| Enforce image signatures immediately | Would block every unsigned upstream image and brick the platform. Audit first, enforce per namespace once teams sign. |
| Leave the self-service bucket on SSE-S3 | Two paths to a bucket with two control sets is the exact inconsistency an auditor flags. Parity is the point. |

## Consequences

- Enforced namespaces now reject non-compliant workloads, so teams must set the
  cost-center label, resource limits, and a pinned tag. That friction is the
  guardrail working; it is scoped by `team-policy=enforce` so platform namespaces
  are unaffected.
- The cost job needs an `INFRACOST_API_KEY` repo secret (free tier); without it
  the PR-only cost job fails while the credential-free allocation gate still
  enforces and the main-branch badge stays green.
- Compliance mapping (SOC 2 CC6/CC7/CC8, ISO 27001 crypto, GxP / 21 CFR Part 11
  change integrity) is now the same story on both the data pipeline and the app
  platform, which is the point: one paved road, two substrates.
- Revisit signal: if the Audit-mode image policy shows teams are publishing
  signed images, flip `verify-image-signatures` to Enforce per namespace.
