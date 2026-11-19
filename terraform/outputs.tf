output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.app.dns_name
}

output "info_url" {
  description = "URL of the app's /info endpoint (available once an image is deployed)."
  value       = "http://${aws_lb.app.dns_name}/info"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "instance_id" {
  value = aws_instance.app.id
}

output "aws_region" {
  value = var.aws_region
}
