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
  default_tags {
    tags = {
      Project     = "aws-developer-platform"
      Environment = var.environment
      Owner       = "jordann6"
      ManagedBy   = "terraform"
    }
  }
}
