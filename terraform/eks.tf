module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  # Public endpoint so we can drive kubectl/helm from a workstation
  cluster_endpoint_public_access = true

  # Grant the Terraform caller cluster-admin so bootstrap works without aws-auth juggling
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_desired_size
      max_size       = var.node_desired_size + 1
      desired_size   = var.node_desired_size
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = local.tags
}
