provider "aws" {
  region = var.region
}

# --- Layered Configuration Logic ---
locals {
  # 1. Load the Default Configuration
  default_config = jsondecode(file("${path.module}/config/default.json"))

  # 2. Load the Environment Specific Configuration (if environment matches)
  #    Workaround for "Inconsistent conditional result types" error:
  #    Instead of a ternary returning an object or empty map (which have different types),
  #    we create a list that contains the decoded object if the environment matches,
  #    or an empty list if it doesn't.
  env_config_list = var.environment == "development" ? [jsondecode(file("${path.module}/config/development.json"))] : []

  # 3. Merge Layers: Defaults <- Overridden by Env Config
  #    We use the expansion operator (...) to merge the list elements if they exist.
  config = merge(local.default_config, local.env_config_list...)

  # Common tags merged with config specific tags
  common_tags = merge({
    ManagedBy = "Terraform"
  }, lookup(local.config, "tags", {}))
}

data "aws_availability_zones" "available" {
  state = "available"
}