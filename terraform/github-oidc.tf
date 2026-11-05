# Your repo, in the form GitHub puts inside the token
variable "github_repo" {
  description = "owner/repo allowed to assume the deploy role"
  type        = string
  default     = "Abdullah3301/ecs-fargate-terraform-github-actions"
}

# Fetch GitHub's live TLS certificate chain at apply time
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Every fingerprint in the chain, computed now rather than hardcoded,
  # so it can't go stale when GitHub rotates certificates
  thumbprint_list = [for c in data.tls_certificate.github.certificates : c.sha1_fingerprint]
}


# 2. THE ROLE GitHub assumes, with a trust policy that pins it to your repo and branch
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # the token must be meant for AWS
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # and must come from YOUR repo, on the main branch, and nowhere else
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# 3. PERMISSIONS: the smallest set the pipeline needs
resource "aws_iam_role_policy" "github_actions" {
  name = "${var.project_name}-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Get a temporary password for ECR. This one can't be scoped to a resource.
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # Push images, but only to THESE two repositories
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = [for r in aws_ecr_repository.app : r.arn]
      },
      {
        # Read the current task definition and register a new version of it
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        # Update ONLY our two services, and watch the rollout
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = [aws_ecs_service.frontend.id, aws_ecs_service.backend.id]
      },
      {
        # Let the new task definition carry the execution role ECS already uses
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = aws_iam_role.task_execution.arn
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
    ]
  })
}