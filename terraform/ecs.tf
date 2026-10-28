# ---------- CLUSTER: the workspace our services run in ----------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# ---------- LOGS: where container output goes, kept 7 days ----------
resource "aws_cloudwatch_log_group" "app" {
  for_each          = toset(["frontend", "backend"])
  name              = "/ecs/${var.project_name}-${each.key}"
  retention_in_days = 7 # old logs auto-delete, so storage costs stay near zero
}

# ---------- EXECUTION ROLE: lets ECS pull images and write logs ----------
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-task-execution"

  # Trust policy: only the ECS service is allowed to use this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS's ready-made, narrowly scoped policy: pull from ECR and write to CloudWatch Logs only
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------- TASK DEFINITION: the recipe for the frontend container ----------
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project_name}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own IP address
  cpu                      = "512"    # 0.5 vCPU, as the challenge requires
  memory                   = "1024"   # 1 GB, as the challenge requires
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # matches the images built on your PC
  }

  container_definitions = jsonencode([{
    name         = "frontend"
    image        = "${aws_ecr_repository.app["frontend"].repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 80, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app["frontend"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "frontend"
      }
    }
  }])
}

# ---------- TASK DEFINITION: the recipe for the backend container ----------
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = "backend"
    image        = "${aws_ecr_repository.app["backend"].repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]

    # Your Part 2 change in action: CORS setting passed in from outside the code
    environment = [
      { name = "CORS_ORIGIN", value = "http://${aws_lb.main.dns_name}" }
    ]

    # Same as --init locally: Node shuts down cleanly when ECS stops the task
    linuxParameters = { initProcessEnabled = true }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app["backend"].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "backend"
      }
    }
  }])
}

# ---------- SERVICE: keeps the frontend running and connected to the load balancer ----------
resource "aws_ecs_service" "frontend" {
  name            = "${var.project_name}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1 # start with one copy; autoscaling adjusts this
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.tasks.id] # only the load balancer can reach it
    assign_public_ip = true                          # needed to pull images without a NAT Gateway
  }

  # Register each running copy in the frontend target group
  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  # If a new version fails to start, roll back to the last working one
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    # Autoscaling changes the count and GitHub Actions changes the version;
    # Terraform shouldn't undo either
    ignore_changes = [desired_count, task_definition]
  }
}

# ---------- SERVICE: the same for the backend ----------
resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.api]

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}