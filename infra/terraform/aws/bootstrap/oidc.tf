###############################################################################
# GitHub Actions OIDC provider + deployer role
#
# Mirrors the setup in tests/terratest/README.md (### AWS): a federated role
# that e2e-cloud.yaml (Environment `e2e-aws`) and infra-validate.yaml's
# plan-aws job (no Environment, `pull_request` subject) both assume.
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

locals {
  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]

  # Repo slugs accepted in the OIDC `sub`: always the classic OWNER/REPO, plus —
  # when the numeric IDs are supplied — the immutable OWNER@OWNER_ID/REPO@REPO_ID
  # slug GitHub embeds for repos created after 2026-07-15. Accepting both keeps
  # AssumeRoleWithWebIdentity working across the classic and immutable formats.
  github_repo_slugs = compact([
    var.github_repository,
    var.github_owner_id != "" && var.github_repo_id != "" ? "${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repo_id}" : "",
  ])

  # Still scoped to specific workflows (one subject per Environment + the
  # pull_request plan job), not a broad `:*`, for each accepted slug.
  oidc_subject_suffixes = concat(
    [for env in var.environments : "environment:${env}"],
    ["pull_request"],
  )

  oidc_subjects = [
    for pair in setproduct(local.github_repo_slugs, local.oidc_subject_suffixes) :
    "repo:${pair[0]}:${pair[1]}"
  ]
}

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.oidc_subjects
    }
  }
}

resource "aws_iam_role" "deployer" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json
}

# Scoped deployer permissions - the exact 6-statement policy from
# tests/terratest/README.md's deployer-policy.json, plus backend-access
# statements so the role can also read/write the state bucket and lock table.
data "aws_iam_policy_document" "deployer" {
  statement {
    sid    = "NetworkingAndCompute"
    effect = "Allow"
    actions = [
      "ec2:*",
      "autoscaling:Describe*",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteTags",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EKS"
    effect    = "Allow"
    actions   = ["eks:*"]
    resources = ["*"]
  }

  statement {
    sid    = "IAMClusterNodeAndIRSARoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:CreateServiceLinkedRole",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SecretsEncryptionKMS"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListAliases",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CreateGrant",
      "kms:TagResource",
      "kms:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ControlPlaneLogging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DescribeLogGroups",
      "logs:PutRetentionPolicy",
      "logs:ListTagsForResource",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "Identity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  # Backend access: lets the role read/write the main stack's remote state
  # and take/release the lock during `plan`/`apply`. Scoped to the two
  # resources this config creates, unlike the statements above (whose
  # underlying resources don't exist until the main stack applies).
  statement {
    sid    = "TerraformStateBackend"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
  }

  statement {
    sid    = "TerraformStateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.lock.arn]
  }
}

resource "aws_iam_role_policy" "deployer" {
  name   = "keda-gpu-scaler-e2e-deployer"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json
}
