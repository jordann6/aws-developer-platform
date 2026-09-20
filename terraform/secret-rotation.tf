# Secret rotation for the platform's paved-road secrets.
#
# External Secrets (external-secrets.tf) distributes a secret into the cluster.
# This file closes the other half of the loop: a rotation Lambda that rotates
# the secret on a schedule via the AWS four-step contract, so the README's
# "rotation" control is backed by code rather than asserted.
#
# Privilege separation is the point. The ESO role is read-only (GetSecretValue,
# DescribeSecret). This rotation role is the ONLY identity in the platform
# allowed to write a secret value, and it is scoped to the one demo secret, so
# distribution and rotation never share a credential.

data "aws_iam_policy_document" "rotation_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation" {
  name               = "${local.name}-secret-rotation"
  assume_role_policy = data.aws_iam_policy_document.rotation_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "rotation" {
  # Value read/write and staging, scoped to the single demo secret rather than
  # the adp/* path the read-only ESO role uses.
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecretVersionStage",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.demo.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetRandomPassword"]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${local.name}-secret-rotation:*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "rotation" {
  name   = "secret-rotate"
  role   = aws_iam_role.rotation.id
  policy = data.aws_iam_policy_document.rotation.json
}

data "archive_file" "rotation" {
  type        = "zip"
  source_file = "${path.module}/rotation/rotation.py"
  output_path = "${path.module}/rotation/rotation.zip"
}

resource "aws_lambda_function" "rotation" {
  function_name    = "${local.name}-secret-rotation"
  role             = aws_iam_role.rotation.arn
  runtime          = "python3.12"
  handler          = "rotation.handler"
  architectures    = ["arm64"]
  filename         = data.archive_file.rotation.output_path
  source_code_hash = data.archive_file.rotation.output_base64sha256
  timeout          = 60
  memory_size      = 128
  tags             = local.tags

  # Rotation is infrequent, so a small reserved pool both bounds cost and
  # satisfies the function-level concurrency control.
  reserved_concurrent_executions = 2

  tracing_config {
    mode = "Active"
  }
}

resource "aws_cloudwatch_log_group" "rotation" {
  name              = "/aws/lambda/${local.name}-secret-rotation"
  retention_in_days = 365
  tags              = local.tags
}

# Lets Secrets Manager invoke the rotation function for the four-step contract.
resource "aws_lambda_permission" "rotation" {
  statement_id   = "AllowSecretsManagerInvoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.rotation.function_name
  principal      = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

# Turns the demo secret's "rotation" claim into an enforced control: Secrets
# Manager drives the four-step contract on this schedule.
resource "aws_secretsmanager_secret_rotation" "demo" {
  secret_id           = aws_secretsmanager_secret.demo.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_lambda_permission.rotation]
}

output "rotation_lambda_arn" {
  description = "IAM-fenced rotation Lambda that rotates the demo secret via the four-step contract."
  value       = aws_lambda_function.rotation.arn
}
