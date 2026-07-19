terraform {
  # Remote state in Azure Storage. Partial config on purpose — no hardcoded
  # account/container/key here, so this same config works for any state
  # account or cluster instance. Supply the rest at `terraform init`:
  #
  #   terraform init \
  #     -backend-config="resource_group_name=<state_resource_group>" \
  #     -backend-config="storage_account_name=<state_storage_account>" \
  #     -backend-config="container_name=<state_container>" \
  #     -backend-config="key=e2e/azure/<cluster_name>.tfstate"
  #
  # The state account/container/role granting CI access to it are provisioned
  # once by infra/terraform/azure/bootstrap (see its README for the exact
  # values and a ready-made `backend_config_hint` output).
  backend "azurerm" {}
}
