terraform {
  backend "s3" {} # partial config — bucket/key/region/dynamodb_table supplied at `terraform init -backend-config=...`
}
