variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix used in resource names"
  type        = string
  default     = "ecs-demo"
}

variable "image_tag" {
  description = "Image tag for the first deployment"
  type        = string
  default     = "initial"
}