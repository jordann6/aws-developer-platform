# IRSA role assumed by the Crossplane AWS S3 provider's controller pod.
# The provider ServiceAccount is pinned to "provider-aws" in crossplane-system
# via a DeploymentRuntimeConfig (see platform/crossplane/), and annotated with
# this role ARN. ProviderConfig source: IRSA -> no static credentials anywhere.

data "aws_iam_policy_document" "crossplane_assume" {
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
      values   = ["system:serviceaccount:crossplane-system:provider-aws"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crossplane_s3" {
  name               = "${local.name}-crossplane-s3"
  assume_role_policy = data.aws_iam_policy_document.crossplane_assume.json
  tags               = local.tags
}

# Scoped to the S3 actions Crossplane needs to provision hardened buckets.
data "aws_iam_policy_document" "crossplane_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:ListAllMyBuckets",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy",
      "s3:GetBucketLocation",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketCors",
      "s3:GetBucketWebsite",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketLogging",
      "s3:GetBucketNotification",
      "s3:GetBucketOwnershipControls",
      "s3:PutBucketOwnershipControls"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "crossplane_s3" {
  name   = "s3-management"
  role   = aws_iam_role.crossplane_s3.id
  policy = data.aws_iam_policy_document.crossplane_s3.json
}
