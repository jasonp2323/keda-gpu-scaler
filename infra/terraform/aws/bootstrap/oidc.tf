# GitHub Actions OIDC provider + deployer role — mirrors tests/terratest/README.md (### AWS).

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Looked up instead of created when the toggle is false — only one OIDC provider is allowed per AWS account.
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  github_owner = split("/", var.github_repository)[0]
  github_repo  = split("/", var.github_repository)[1]

  # Repo slugs accepted in `sub`: classic OWNER/REPO, plus immutable OWNER@OWNER_ID/REPO@REPO_ID for repos created after 2026-07-15 (when IDs are supplied).
  github_repo_slugs = compact([
    var.github_repository,
    var.github_owner_id != "" && var.github_repo_id != "" ? "${local.github_owner}@${var.github_owner_id}/${local.github_repo}@${var.github_repo_id}" : "",
  ])

  # Scoped per workflow (one subject per Environment + pull_request), not a broad `:*`.
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
      identifiers = [local.oidc_provider_arn]
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

# Deployer permissions: the 6-statement policy from tests/terratest/README.md's deployer-policy.json, plus backend access to the state bucket (its native S3 lock file included).
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

  # Backend access: read/write the main stack's remote state and its native S3
  # lock file (a `.tflock` object) during plan/apply. Scoped to this bucket,
  # unlike the statements above (whose resources don't exist until apply).
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
}

resource "aws_iam_role_policy" "deployer" {
  name   = "keda-gpu-scaler-e2e-deployer"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer.json
}
