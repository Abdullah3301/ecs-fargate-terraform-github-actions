# The two services we want to scale
locals {
  scaled_services = {
    frontend = aws_ecs_service.frontend.name
    backend  = aws_ecs_service.backend.name
  }
}

# SCALABLE TARGET: each service's task count, min 1 and max 4
resource "aws_appautoscaling_target" "ecs" {
  for_each           = local.scaled_services
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${each.value}"
  min_capacity       = 1
  max_capacity       = 4
}

# SCALING POLICY: target tracking, which keeps average CPU near 50%
resource "aws_appautoscaling_policy" "cpu" {
  for_each           = aws_appautoscaling_target.ecs
  name               = "${var.project_name}-${each.key}-cpu-50"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = each.value.service_namespace
  scalable_dimension = each.value.scalable_dimension
  resource_id        = each.value.resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = 50  # the CPU % to aim for
    scale_out_cooldown = 60  # after adding tasks, wait 60s before adding more
    scale_in_cooldown  = 120 # remove tasks more cautiously, to avoid flip-flopping

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}