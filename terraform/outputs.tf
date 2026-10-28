output "ecr_repository_urls" {
  description = "Where to push the Docker images"
  value       = { for name, repo in aws_ecr_repository.app : name => repo.repository_url }
}
output "app_url" {
  description = "Open this in your browser"
  value       = "http://${aws_lb.main.dns_name}"
}









