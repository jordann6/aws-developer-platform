from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.storage import S3
from diagrams.aws.security import IAMRole, KMS, SecretsManager
from diagrams.aws.network import VPC
from diagrams.aws.management import Cloudwatch
from diagrams.onprem.gitops import ArgoCD
from diagrams.onprem.monitoring import Prometheus
from diagrams.k8s.compute import Deploy
from diagrams.onprem.vcs import Github

graph_attrs = {"fontsize": "13", "bgcolor": "white", "pad": "0.5", "splines": "ortho"}
node_attrs = {"fontsize": "11"}

with Diagram(
    "AWS Developer Platform",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    repo = Github("Platform repo\n(GitOps source)")

    with Cluster("AWS Account · us-east-1"):
        with Cluster("VPC (Terraform)"):
            with Cluster("EKS cluster (adp-dev)"):
                argo = ArgoCD("ArgoCD\napp-of-apps")

                with Cluster("Platform components"):
                    crossplane = Deploy("Crossplane\n+ S3/KMS providers")
                    kyverno = Deploy("Kyverno\nattribution + hardening")
                    eso = Deploy("External Secrets\nOperator")
                    opencost = Deploy("OpenCost\ncost by namespace")
                    observ = Prometheus("Prometheus\nSLO burn-rate")

        irsa = IAMRole("IRSA roles\n(no static keys)")
        kms = KMS("Customer-managed\nkey · rotation")
        bucket = S3("Hardened S3 bucket\nSSE-KMS · TLS-only\npublic-access-blocked")
        secrets = SecretsManager("Secrets Manager\nadp/*")

    repo >> Edge(label="reconciles") >> argo
    argo >> Edge(label="syncs") >> [crossplane, kyverno, eso, opencost, observ]
    crossplane >> Edge(label="assumes") >> irsa
    irsa >> Edge(label="provisions on claim") >> bucket
    bucket >> Edge(label="SSE-KMS", style="dashed") >> kms
    eso >> Edge(label="syncs secrets (IRSA)") >> secrets
