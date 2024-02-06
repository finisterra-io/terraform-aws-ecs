data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}


################################################################################
# Service
################################################################################

locals {
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-external.html
  is_external_deployment = try(var.deployment_controller.type, null) == "EXTERNAL"
  is_daemon              = var.scheduling_strategy == "DAEMON"
  is_fargate             = var.launch_type == "FARGATE"

}



resource "aws_ecs_service" "this" {
  count = var.create && !var.ignore_task_definition_changes ? 1 : 0

  dynamic "alarms" {
    for_each = length(var.alarms) > 0 ? [var.alarms] : []

    content {
      alarm_names = alarms.value.alarm_names
      enable      = try(alarms.value.enable, true)
      rollback    = try(alarms.value.rollback, true)
    }
  }

  dynamic "capacity_provider_strategy" {
    # Set by task set if deployment controller is external
    for_each = { for k, v in var.capacity_provider_strategy : k => v if !local.is_external_deployment }

    content {
      base              = try(capacity_provider_strategy.value.base, null)
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
    }
  }

  cluster = var.cluster_arn

  dynamic "deployment_circuit_breaker" {
    for_each = length(var.deployment_circuit_breaker) > 0 ? [var.deployment_circuit_breaker] : []

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "deployment_controller" {
    for_each = length(var.deployment_controller) > 0 ? [var.deployment_controller] : []

    content {
      type = try(deployment_controller.value.type, null)
    }
  }

  deployment_maximum_percent         = local.is_daemon || local.is_external_deployment ? null : var.deployment_maximum_percent
  deployment_minimum_healthy_percent = local.is_daemon || local.is_external_deployment ? null : var.deployment_minimum_healthy_percent
  desired_count                      = local.is_daemon || local.is_external_deployment ? null : var.desired_count
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  enable_execute_command             = var.enable_execute_command
  force_new_deployment               = local.is_external_deployment ? null : var.force_new_deployment
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  iam_role                           = var.iam_role
  launch_type                        = local.is_external_deployment || length(var.capacity_provider_strategy) > 0 ? null : var.launch_type

  dynamic "load_balancer" {
    # Set by task set if deployment controller is external
    for_each = var.load_balancer

    content {
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
      elb_name         = try(load_balancer.value.elb_name, null)
      target_group_arn = load_balancer.value.target_group_arn
    }
  }

  name = var.name

  dynamic "network_configuration" {
    # Set by task set if deployment controller is external
    for_each = var.network_configuration

    content {
      assign_public_ip = network_configuration.value.assign_public_ip
      security_groups  = network_configuration.value.security_groups
      subnets          = network_configuration.value.subnet_names != null ? data.aws_subnet.default[*].id : network_configuration.value.subnets
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.ordered_placement_strategy

    content {
      field = try(ordered_placement_strategy.value.field, null)
      type  = ordered_placement_strategy.value.type
    }
  }

  dynamic "placement_constraints" {
    for_each = var.placement_constraints

    content {
      expression = try(placement_constraints.value.expression, null)
      type       = placement_constraints.value.type
    }
  }

  # Set by task set if deployment controller is external
  platform_version    = local.is_fargate && !local.is_external_deployment ? var.platform_version : null
  scheduling_strategy = local.is_fargate ? "REPLICA" : var.scheduling_strategy

  dynamic "service_connect_configuration" {
    for_each = length(var.service_connect_configuration) > 0 ? [var.service_connect_configuration] : []

    content {
      enabled = try(service_connect_configuration.value.enabled, true)

      dynamic "log_configuration" {
        for_each = try([service_connect_configuration.value.log_configuration], [])

        content {
          log_driver = try(log_configuration.value.log_driver, null)
          options    = try(log_configuration.value.options, null)

          dynamic "secret_option" {
            for_each = try(log_configuration.value.secret_option, [])

            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      namespace = lookup(service_connect_configuration.value, "namespace", null)

      dynamic "service" {
        for_each = try([service_connect_configuration.value.service], [])

        content {

          dynamic "client_alias" {
            for_each = try([service.value.client_alias], [])

            content {
              dns_name = try(client_alias.value.dns_name, null)
              port     = client_alias.value.port
            }
          }

          discovery_name        = try(service.value.discovery_name, null)
          ingress_port_override = try(service.value.ingress_port_override, null)
          port_name             = service.value.port_name
        }
      }
    }
  }

  dynamic "service_registries" {
    # Set by task set if deployment controller is external
    for_each = length(var.service_registries) > 0 ? [{ for k, v in var.service_registries : k => v if !local.is_external_deployment }] : []

    content {
      container_name = try(service_registries.value.container_name, null)
      container_port = try(service_registries.value.container_port, null)
      port           = try(service_registries.value.port, null)
      registry_arn   = try(data.aws_service_discovery_service.selected[0].arn, null)
    }
  }

  task_definition       = local.task_definition
  triggers              = var.triggers
  wait_for_steady_state = var.wait_for_steady_state

  propagate_tags = var.propagate_tags
  tags           = var.tags



  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
    ]
  }
}

################################################################################
# Service - Ignore `task_definition`
################################################################################

resource "aws_ecs_service" "ignore_task_definition" {
  count = var.create && var.ignore_task_definition_changes ? 1 : 0

  dynamic "alarms" {
    for_each = var.alarms

    content {
      alarm_names = alarms.value.alarm_names
      enable      = try(alarms.value.enable, true)
      rollback    = try(alarms.value.rollback, true)
    }
  }

  dynamic "capacity_provider_strategy" {
    # Set by task set if deployment controller is external
    for_each = !local.is_external_deployment ? var.capacity_provider_strategy : []

    content {
      base              = try(capacity_provider_strategy.value.base, null)
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
    }
  }

  cluster = var.cluster_arn

  dynamic "deployment_circuit_breaker" {
    for_each = var.deployment_circuit_breaker

    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "deployment_controller" {
    for_each = var.deployment_controller

    content {
      type = try(deployment_controller.value.type, null)
    }
  }

  deployment_maximum_percent         = local.is_daemon || local.is_external_deployment ? null : var.deployment_maximum_percent
  deployment_minimum_healthy_percent = local.is_daemon || local.is_external_deployment ? null : var.deployment_minimum_healthy_percent
  desired_count                      = local.is_daemon || local.is_external_deployment ? null : var.desired_count
  enable_ecs_managed_tags            = var.enable_ecs_managed_tags
  enable_execute_command             = var.enable_execute_command
  force_new_deployment               = local.is_external_deployment ? null : var.force_new_deployment
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  iam_role                           = var.iam_role_arn
  launch_type                        = local.is_external_deployment || length(var.capacity_provider_strategy) > 0 ? null : var.launch_type

  dynamic "load_balancer" {
    # Set by task set if deployment controller is external
    for_each = { for k, v in var.load_balancer : k => v if !local.is_external_deployment }

    content {
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
      elb_name         = try(load_balancer.value.elb_name, null)
      target_group_arn = load_balancer.value.target_group_arn
    }
  }

  name = var.name

  dynamic "network_configuration" {
    # Set by task set if deployment controller is external
    for_each = var.network_configuration

    content {
      assign_public_ip = network_configuration.value.assign_public_ip
      security_groups  = network_configuration.value.security_groups
      subnets          = network_configuration.value.subnet_names != null ? data.aws_subnet.default[*].id : network_configuration.value.subnets
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = var.ordered_placement_strategy

    content {
      field = try(ordered_placement_strategy.value.field, null)
      type  = ordered_placement_strategy.value.type
    }
  }

  dynamic "placement_constraints" {
    for_each = var.placement_constraints

    content {
      expression = try(placement_constraints.value.expression, null)
      type       = placement_constraints.value.type
    }
  }

  # Set by task set if deployment controller is external
  platform_version    = local.is_fargate && !local.is_external_deployment ? var.platform_version : null
  scheduling_strategy = local.is_fargate ? "REPLICA" : var.scheduling_strategy

  dynamic "service_connect_configuration" {
    for_each = var.service_connect_configuration

    content {
      enabled = try(service_connect_configuration.value.enabled, true)

      dynamic "log_configuration" {
        for_each = try([service_connect_configuration.value.log_configuration], [])

        content {
          log_driver = try(log_configuration.value.log_driver, null)
          options    = try(log_configuration.value.options, null)

          dynamic "secret_option" {
            for_each = try(log_configuration.value.secret_option, [])

            content {
              name       = secret_option.value.name
              value_from = secret_option.value.value_from
            }
          }
        }
      }

      namespace = lookup(service_connect_configuration.value, "namespace", null)

      dynamic "service" {
        for_each = try([service_connect_configuration.value.service], [])

        content {

          dynamic "client_alias" {
            for_each = try([service.value.client_alias], [])

            content {
              dns_name = try(client_alias.value.dns_name, null)
              port     = client_alias.value.port
            }
          }

          discovery_name        = try(service.value.discovery_name, null)
          ingress_port_override = try(service.value.ingress_port_override, null)
          port_name             = service.value.port_name
        }
      }
    }
  }

  dynamic "service_registries" {
    # Set by task set if deployment controller is external
    for_each = length(var.service_registries) > 0 ? [{ for k, v in var.service_registries : k => v if !local.is_external_deployment }] : []

    content {
      container_name = try(service_registries.value.container_name, null)
      container_port = try(service_registries.value.container_port, null)
      port           = try(service_registries.value.port, null)
      registry_arn   = try(data.aws_service_discovery_service.selected[0].arn, null)
    }
  }

  task_definition       = local.task_definition
  triggers              = var.triggers
  wait_for_steady_state = var.wait_for_steady_state

  propagate_tags = var.propagate_tags
  tags           = var.tags



  # depends_on = [aws_iam_role_policy_attachment.service]

  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
      task_definition,
      load_balancer,
    ]
  }
}



################################################################################
# Task Definition
################################################################################

locals {
  create_task_definition = var.create && var.create_task_definition

  # This allows us to query both the existing as well as Terraform's state and get
  # and get the max version of either source, useful for when external resources
  # update the container definition
  max_task_def_revision = local.create_task_definition ? data.aws_ecs_task_definition.this[0].revision : 0
  task_definition       = local.create_task_definition ? "${var.family}:${local.max_task_def_revision}" : var.task_definition_arn
}

# This allows us to query both the existing as well as Terraform's state and get
# and get the max version of either source, useful for when external resources
# update the container definition
data "aws_ecs_task_definition" "this" {
  count = local.create_task_definition ? 1 : 0

  task_definition = var.family

  depends_on = [
    # Needs to exist first on first deployment
    aws_ecs_task_definition.this
  ]
}

resource "aws_ecs_task_definition" "this" {
  count = local.create_task_definition ? 1 : 0

  # Convert map of maps to array of maps before JSON encoding
  container_definitions = var.container_definitions
  cpu                   = var.cpu

  dynamic "ephemeral_storage" {
    for_each = length(var.ephemeral_storage) > 0 ? [var.ephemeral_storage] : []

    content {
      size_in_gib = ephemeral_storage.value.size_in_gib
    }
  }

  execution_role_arn = var.execution_role_arn
  family             = coalesce(var.family, var.name)

  dynamic "inference_accelerator" {
    for_each = var.inference_accelerator

    content {
      device_name = inference_accelerator.value.device_name
      device_type = inference_accelerator.value.device_type
    }
  }

  ipc_mode     = var.ipc_mode
  memory       = var.memory
  network_mode = var.network_mode
  pid_mode     = var.pid_mode

  dynamic "placement_constraints" {
    for_each = var.task_definition_placement_constraints

    content {
      expression = try(placement_constraints.value.expression, null)
      type       = placement_constraints.value.type
    }
  }

  dynamic "proxy_configuration" {
    for_each = length(var.proxy_configuration) > 0 ? [var.proxy_configuration] : []

    content {
      container_name = proxy_configuration.value.container_name
      properties     = try(proxy_configuration.value.properties, null)
      type           = try(proxy_configuration.value.type, null)
    }
  }

  requires_compatibilities = var.requires_compatibilities

  dynamic "runtime_platform" {
    for_each = length(var.runtime_platform) > 0 ? [var.runtime_platform] : []

    content {
      cpu_architecture        = try(runtime_platform.value.cpu_architecture, null)
      operating_system_family = try(runtime_platform.value.operating_system_family, null)
    }
  }

  skip_destroy  = var.skip_destroy
  task_role_arn = var.task_role_arn

  dynamic "volume" {
    for_each = var.volume

    content {
      dynamic "docker_volume_configuration" {
        for_each = try([volume.value.docker_volume_configuration], [])

        content {
          autoprovision = try(docker_volume_configuration.value.autoprovision, null)
          driver        = try(docker_volume_configuration.value.driver, null)
          driver_opts   = try(docker_volume_configuration.value.driver_opts, null)
          labels        = try(docker_volume_configuration.value.labels, null)
          scope         = try(docker_volume_configuration.value.scope, null)
        }
      }

      dynamic "efs_volume_configuration" {
        for_each = try([volume.value.efs_volume_configuration], [])

        content {
          dynamic "authorization_config" {
            for_each = try([efs_volume_configuration.value.authorization_config], [])

            content {
              access_point_id = try(authorization_config.value.access_point_id, null)
              iam             = try(authorization_config.value.iam, null)
            }
          }

          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = try(efs_volume_configuration.value.root_directory, null)
          transit_encryption      = try(efs_volume_configuration.value.transit_encryption, null)
          transit_encryption_port = try(efs_volume_configuration.value.transit_encryption_port, null)
        }
      }

      dynamic "fsx_windows_file_server_volume_configuration" {
        for_each = try([volume.value.fsx_windows_file_server_volume_configuration], [])

        content {
          dynamic "authorization_config" {
            for_each = try([fsx_windows_file_server_volume_configuration.value.authorization_config], [])

            content {
              credentials_parameter = authorization_config.value.credentials_parameter
              domain                = authorization_config.value.domain
            }
          }

          file_system_id = fsx_windows_file_server_volume_configuration.value.file_system_id
          root_directory = fsx_windows_file_server_volume_configuration.value.root_directory
        }
      }

      host_path = try(volume.value.host_path, null)
      name      = try(volume.value.name, volume.key)
    }
  }

  tags = var.task_tags

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Task Set
################################################################################

resource "aws_ecs_task_set" "this" {
  # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-taskset.html
  count = local.create_task_definition && local.is_external_deployment && !var.ignore_task_definition_changes ? 1 : 0

  service         = try(aws_ecs_service.this[0].id, aws_ecs_service.ignore_task_definition[0].id)
  cluster         = var.cluster_arn
  external_id     = var.external_id
  task_definition = local.task_definition

  dynamic "network_configuration" {
    # Set by task set if deployment controller is external
    for_each = var.network_configuration

    content {
      assign_public_ip = network_configuration.value.assign_public_ip
      security_groups  = network_configuration.value.security_groups
      subnets          = network_configuration.value.subnet_names != null ? data.aws_subnet.default[*].id : network_configuration.value.subnets
    }
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer

    content {
      load_balancer_name = try(load_balancer.value.load_balancer_name, null)
      target_group_arn   = try(load_balancer.value.target_group_arn, null)
      container_name     = load_balancer.value.container_name
      container_port     = try(load_balancer.value.container_port, null)
    }
  }

  dynamic "service_registries" {
    for_each = length(var.service_registries) > 0 ? [var.service_registries] : []

    content {
      container_name = try(service_registries.value.container_name, null)
      container_port = try(service_registries.value.container_port, null)
      port           = try(service_registries.value.port, null)
      registry_arn   = try(data.aws_service_discovery_service.selected[0].arn, null)
    }
  }

  launch_type = length(var.capacity_provider_strategy) > 0 ? null : var.launch_type

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      base              = try(capacity_provider_strategy.value.base, null)
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
    }
  }

  platform_version = local.is_fargate ? var.platform_version : null

  dynamic "scale" {
    for_each = length(var.scale) > 0 ? [var.scale] : []

    content {
      unit  = try(scale.value.unit, null)
      value = try(scale.value.value, null)
    }
  }

  force_delete              = var.force_delete
  wait_until_stable         = var.wait_until_stable
  wait_until_stable_timeout = var.wait_until_stable_timeout

  tags = var.task_tags

  lifecycle {
    ignore_changes = [
      scale, # Always ignored
    ]
  }
}

################################################################################
# Task Set - Ignore `task_definition`
################################################################################

resource "aws_ecs_task_set" "ignore_task_definition" {
  # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecs-taskset.html
  count = local.create_task_definition && local.is_external_deployment && var.ignore_task_definition_changes ? 1 : 0

  service         = try(aws_ecs_service.this[0].id, aws_ecs_service.ignore_task_definition[0].id)
  cluster         = var.cluster_arn
  external_id     = var.external_id
  task_definition = local.task_definition

  dynamic "network_configuration" {
    # Set by task set if deployment controller is external
    for_each = var.network_configuration

    content {
      assign_public_ip = network_configuration.value.assign_public_ip
      security_groups  = network_configuration.value.security_groups
      subnets          = network_configuration.value.subnet_names != null ? data.aws_subnet.default[*].id : network_configuration.value.subnets
    }
  }

  dynamic "load_balancer" {
    for_each = var.load_balancer

    content {
      load_balancer_name = try(load_balancer.value.load_balancer_name, null)
      target_group_arn   = try(load_balancer.value.target_group_arn, null)
      container_name     = load_balancer.value.container_name
      container_port     = try(load_balancer.value.container_port, null)
    }
  }

  dynamic "service_registries" {
    for_each = length(var.service_registries) > 0 ? [var.service_registries] : []

    content {
      container_name = try(service_registries.value.container_name, null)
      container_port = try(service_registries.value.container_port, null)
      port           = try(service_registries.value.port, null)
      registry_arn   = try(data.aws_service_discovery_service.selected[0].arn, null)
    }
  }

  launch_type = length(var.capacity_provider_strategy) > 0 ? null : var.launch_type

  dynamic "capacity_provider_strategy" {
    for_each = var.capacity_provider_strategy

    content {
      base              = try(capacity_provider_strategy.value.base, null)
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = try(capacity_provider_strategy.value.weight, null)
    }
  }

  platform_version = local.is_fargate ? var.platform_version : null

  dynamic "scale" {
    for_each = length(var.scale) > 0 ? [var.scale] : []

    content {
      unit  = try(scale.value.unit, null)
      value = try(scale.value.value, null)
    }
  }

  force_delete              = var.force_delete
  wait_until_stable         = var.wait_until_stable
  wait_until_stable_timeout = var.wait_until_stable_timeout

  tags = var.task_tags

  lifecycle {
    ignore_changes = [
      scale, # Always ignored
      task_definition,
    ]
  }
}

################################################################################
# Autoscaling
################################################################################

locals {
  enable_autoscaling = var.create && var.enable_autoscaling && !local.is_daemon

  cluster_name = element(split("/", var.cluster_arn), 1)
}

resource "aws_appautoscaling_target" "this" {
  count = local.enable_autoscaling ? 1 : 0

  # Desired needs to be between or equal to min/max
  min_capacity = var.autoscaling_min_capacity
  max_capacity = var.autoscaling_max_capacity

  resource_id        = "service/${local.cluster_name}/${try(aws_ecs_service.this[0].name, aws_ecs_service.ignore_task_definition[0].name)}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  tags               = var.autoscaling_tags
}

resource "aws_appautoscaling_policy" "this" {
  for_each = { for k, v in var.autoscaling_policies : k => v if local.enable_autoscaling }

  name               = try(each.value.name, each.key)
  policy_type        = try(each.value.policy_type, "TargetTrackingScaling")
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  dynamic "step_scaling_policy_configuration" {
    for_each = try(each.value.step_scaling_policy_configuration, [])

    content {
      adjustment_type          = try(step_scaling_policy_configuration.value.adjustment_type, null)
      cooldown                 = try(step_scaling_policy_configuration.value.cooldown, null)
      metric_aggregation_type  = try(step_scaling_policy_configuration.value.metric_aggregation_type, null)
      min_adjustment_magnitude = try(step_scaling_policy_configuration.value.min_adjustment_magnitude, null)

      dynamic "step_adjustment" {
        for_each = try(step_scaling_policy_configuration.value.step_adjustment, [])

        content {
          metric_interval_lower_bound = try(step_adjustment.value.metric_interval_lower_bound, null)
          metric_interval_upper_bound = try(step_adjustment.value.metric_interval_upper_bound, null)
          scaling_adjustment          = try(step_adjustment.value.scaling_adjustment, null)
        }
      }
    }
  }

  dynamic "target_tracking_scaling_policy_configuration" {
    for_each = try(each.value.policy_type, null) == "TargetTrackingScaling" ? try([each.value.target_tracking_scaling_policy_configuration], []) : []

    content {
      dynamic "customized_metric_specification" {
        for_each = try([target_tracking_scaling_policy_configuration.value.customized_metric_specification], [])

        content {
          dynamic "dimensions" {
            for_each = try(customized_metric_specification.value.dimensions, [])

            content {
              name  = dimensions.value.name
              value = dimensions.value.value
            }
          }

          metric_name = customized_metric_specification.value.metric_name
          namespace   = customized_metric_specification.value.namespace
          statistic   = customized_metric_specification.value.statistic
          unit        = try(customized_metric_specification.value.unit, null)
        }
      }

      disable_scale_in = try(target_tracking_scaling_policy_configuration.value.disable_scale_in, null)

      dynamic "predefined_metric_specification" {
        for_each = try([target_tracking_scaling_policy_configuration.value.predefined_metric_specification], [])

        content {
          predefined_metric_type = predefined_metric_specification.value.predefined_metric_type
          resource_label         = try(predefined_metric_specification.value.resource_label, null)
        }
      }

      scale_in_cooldown  = try(target_tracking_scaling_policy_configuration.value.scale_in_cooldown, 300)
      scale_out_cooldown = try(target_tracking_scaling_policy_configuration.value.scale_out_cooldown, 60)
      target_value       = try(target_tracking_scaling_policy_configuration.value.target_value, 75)
    }
  }
}

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = { for k, v in var.autoscaling_scheduled_actions : k => v if local.enable_autoscaling }

  name               = try(each.value.name, each.key)
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }

  schedule   = each.value.schedule
  start_time = try(each.value.start_time, null)
  end_time   = try(each.value.end_time, null)
  timezone   = try(each.value.timezone, null)
}


################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  count = var.create && var.create_cloudwatch_log_group ? 1 : 0

  name              = var.cloudwatch_log_group_name
  retention_in_days = 90
  # kms_key_id        = var.cloudwatch_log_group_kms_key_id

  tags = var.cloudwatch_log_group_tags
}
