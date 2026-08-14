module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  # Public endpoint so we can drive kubectl/helm from a workstation. The access
  # list is a variable rather than the module default of 0.0.0.0/0, so a real
  # run can be scoped to one address. Trivy still flags this either way: its
  # checks fire on a public endpoint existing at all and on any public CIDR
  # reaching it, a /32 included. See .trivyignore.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_public_access_cidrs

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
