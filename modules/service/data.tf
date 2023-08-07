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
  count = var.create_target_group ? 1 : 0
  tags = {
    Name = var.vpc_name
  }
}
