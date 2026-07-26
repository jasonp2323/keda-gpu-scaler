output "state_bucket" {
  description = "S3 bucket holding the main stack's Terraform state."
  value       = aws_s3_bucket.state.id
}

output "region" {
  description = "AWS region the backend and OIDC role were created in."
  value       = var.region
}

output "role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC. Store as the AWS_E2E_ROLE_ARN repo secret."
  value       = aws_iam_role.deployer.arn
}

output "backend_config_hint" {
  description = "-backend-config flags to `terraform init` the main stack's S3 backend. Replace <cluster_name> with the cluster_name you'll pass to that stack."
  value       = <<-EOT
    terraform init \
      -backend-config="bucket=${aws_s3_bucket.state.id}" \
      -backend-config="key=e2e/aws/<cluster_name>.tfstate" \
      -backend-config="region=${var.region}" \
      -backend-config="encrypt=true"
  EOT
}
