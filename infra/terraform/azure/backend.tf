terraform {
  # Partial config — account/container/key supplied via `-backend-config` at `terraform init`; provisioned once by infra/terraform/azure/bootstrap (see its README).
  backend "azurerm" {}
}
