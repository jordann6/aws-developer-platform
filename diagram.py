from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import EKS
from diagrams.aws.storage import S3
from diagrams.aws.security import IAMRole
from diagrams.aws.network import VPC
from diagrams.onprem.gitops import ArgoCD
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
                    crossplane = Deploy("Crossplane\n+ AWS provider")
                    kyverno = Deploy("Kyverno\nguardrails")
                    backstage = Deploy("Backstage\ngolden-path portal")

        irsa = IAMRole("IRSA role\n(no static keys)")
        bucket = S3("Hardened S3 bucket\nAES256 · versioned\npublic-access-blocked")

    repo >> Edge(label="reconciles") >> argo
    argo >> Edge(label="syncs") >> [crossplane, kyverno, backstage]
    crossplane >> Edge(label="assumes") >> irsa
    irsa >> Edge(label="provisions on claim") >> bucket
