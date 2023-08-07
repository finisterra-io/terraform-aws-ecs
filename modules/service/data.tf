data "aws_service_discovery_service" "selected" {
  count = length(lookup(var.service_registries, "registry_name", "")) > 0 ? 1 : 0
  name  = lookup(var.service_registries, "registry_name", null)
}
