variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment. Tagged onto every resource for cost allocation."
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "adp-dev"
}

variable "cost_center" {
  description = <<-EOT
    Chargeback cost centre code, stamped on every resource via default_tags so
    all platform spend bills back to one budget line. Pinned to the house format
    the shared FinOps gate enforces; a free-text value would split the
    allocation report into synonyms that never add up.
  EOT
  type        = string
  default     = "cc-1001"

  validation {
    condition     = can(regex("^cc-[0-9]{4}$", var.cost_center))
    error_message = "cost_center must match the house format cc-NNNN (e.g. cc-1001)."
  }
}

variable "cluster_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the public EKS API endpoint. The module default is
    0.0.0.0/0, which puts the control plane endpoint in front of the whole
    internet. It is still IAM-authenticated, but pass your workstation /32 here
    for any run that is not a throwaway demo:

      terraform apply -var='cluster_public_access_cidrs=["$(curl -s ifconfig.me)/32"]'
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "Instance type for the managed node group."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC."
  type        = string
  default     = "10.0.0.0/16"
}
