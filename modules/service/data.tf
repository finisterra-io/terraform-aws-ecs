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

data "aws_lb" "default" {
  count = var.create_aws_lb_listener ? 1 : 0
  name  = var.lb_name
}

data "aws_lb" "listener_rule" {
  count = var.create_aws_lb_listener_rule && var.create_aws_lb_listener == false ? 1 : 0
  name  = var.listener_rule_lb_name
}

data "aws_lb_listener" "listener_rule" {
  for_each          = var.create_aws_lb_listener_rule && var.create_aws_lb_listener == false ? var.listener_rules : {}
  load_balancer_arn = data.aws_lb.listener_rule[0].arn
  port              = each.value.port
}


# data "aws_acm_certificate" "this" {
#   for_each = var.create_aws_lb_listener ? var.listeners : {}
#   domain   = each.value.domain_name
#   statuses = ["ISSUED"]
# }

# data "aws_iam_policy" "service" {
#   count = local.create_iam_policy ? 0 : 1
#   name  = local.iam_policy_name
# }

data "aws_iam_role" "service" {
  count = var.iam_role_name != null ? 1 : 0
  name  = var.iam_role_name
}

data "aws_iam_role" "tasks" {
  count = var.tasks_iam_role_name != null ? 1 : 0
  name  = var.tasks_iam_role_name
}

data "aws_iam_role" "task_exec" {
  count = var.task_exec_iam_role_name != null ? 1 : 0
  name  = var.task_exec_iam_role_name
}

