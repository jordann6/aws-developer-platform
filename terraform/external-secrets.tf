# External Secrets Operator (ESO) support.
#
# ESO syncs secrets from AWS Secrets Manager into native Kubernetes Secrets so a
# developer references a secret by name and never sees a credential, and nothing
# plaintext lives in Git. ESO authenticates via IRSA (no static keys), the same
# pattern as the Crossplane provider. This is the platform's secret-distribution
# paved road, and it maps to Veeva's stack (Secrets Manager) and controls
# (rotation, least privilege, no secrets in source).

# IRSA role assumed by the ESO controller's ServiceAccount
# (external-secrets/external-secrets), scoped to reading this platform's secrets.
data "aws_iam_policy_document" "eso_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
  tags               = local.tags
}

# Read-only, and scoped to this platform's secret path (adp/*) rather than the
# whole account. kms:Decrypt is limited to calls made through Secrets Manager,
# so the role cannot decrypt anything else with the key.
data "aws_iam_policy_document" "eso" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = ["arn:aws:secretsmanager:${var.region}:*:secret:adp/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "eso" {
  name   = "secrets-read"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso.json
}

# A demo secret for the golden-path walkthrough. recovery_window_in_days = 0 so a
# destroy removes it immediately instead of holding the name for 7-30 days, which
# matters for a deploy/demo/destroy environment. The value is a throwaway.
resource "aws_secretsmanager_secret" "demo" {
  name                    = "adp/dev/demo-db"
  description             = "Demo credential synced into the cluster by ESO (aws-developer-platform)."
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "demo" {
  secret_id     = aws_secretsmanager_secret.demo.id
  secret_string = jsonencode({ username = "app", password = "not-a-real-secret-demo-only" })
}

output "eso_role_arn" {
  description = "IAM role ARN the External Secrets Operator assumes via IRSA."
  value       = aws_iam_role.eso.arn
}
