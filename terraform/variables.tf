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
