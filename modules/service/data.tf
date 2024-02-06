data "aws_service_discovery_dns_namespace" "selected" {
  count = length(lookup(var.service_registries, "namespace_name", "")) > 0 ? 1 : 0
  name  = lookup(var.service_registries, "namespace_name", null)
  type  = "DNS_PRIVATE"
}

data "aws_service_discovery_service" "selected" {
  count        = length(lookup(var.service_registries, "registry_name", "")) > 0 ? 1 : 0
  name         = lookup(var.service_registries, "registry_name", null)
  namespace_id = data.aws_service_discovery_dns_namespace.selected[0].id
}


data "aws_vpc" "default" {
  count = var.vpc_name != null ? 1 : 0
  tags = {
    Name = var.vpc_name
  }
}

locals {
  is_valid_network_config = length(var.network_configuration) > 0 && alltrue([for config in var.network_configuration : can(config.subnet_names)])
}

data "aws_subnet" "default" {
  count  = local.is_valid_network_config ? length(var.network_configuration[0].subnet_names) : 0
  vpc_id = var.vpc_name != null ? data.aws_vpc.default[0].id : var.vpc_id
  filter {
    name   = "tag:Name"
    values = local.is_valid_network_config ? [var.network_configuration[0].subnet_names[count.index]] : []
  }
}
