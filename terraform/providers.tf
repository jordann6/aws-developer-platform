terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "tf-state-jordprojs"
    key          = "aws-developer-platform/dev.terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region

  # Keys are PascalCase deliberately. AWS treats "Owner" and "owner" as two
  # distinct tags, so mixing the two casings splits a cost allocation report
  # into groups that never add up. These must stay identical to local.tags.
  # CostCenter is the chargeback key every showback and unit-economics report
  # groups by. Setting it in default_tags is what satisfies the shared FinOps
  # allocation gate (platform-guardrails finops.rego): because this repo uses
  # module blocks, static analysis cannot see resources created inside them, so
  # provider default_tags is the only guarantee the key reaches every resource.
  default_tags {
    tags = {
      Project     = "aws-developer-platform"
      Environment = var.environment
      Owner       = "jordann6"
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
    }
  }
}
