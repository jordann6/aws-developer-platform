data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = var.cluster_name
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  tags = {
    project    = "aws-developer-platform"
    owner      = "jordann6"
    managed_by = "terraform"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Single NAT gateway keeps cost down for a portfolio environment
  enable_nat_gateway = true
  single_nat_gateway = true

  # Tags required for EKS subnet auto-discovery and load balancer placement
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.tags
}
