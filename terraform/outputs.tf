output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "configure_kubectl" {
  description = "Command to update local kubeconfig for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "crossplane_irsa_role_arn" {
  description = "IAM role ARN the Crossplane AWS provider assumes via IRSA."
  value       = aws_iam_role.crossplane_s3.arn
}

output "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN."
  value       = module.eks.oidc_provider_arn
}
