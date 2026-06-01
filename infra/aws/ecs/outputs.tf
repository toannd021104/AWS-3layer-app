output "frontend_url" {
  description = "Public frontend URL."
  value       = local.frontend_origin
}

output "frontend_alb_dns_name" {
  description = "Public frontend ALB DNS name."
  value       = aws_lb.frontend.dns_name
}

output "api_gateway_url" {
  description = "Public API Gateway invoke URL."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "backend_internal_alb_dns_name" {
  description = "Internal backend ALB DNS name."
  value       = aws_lb.backend.dns_name
}

output "backend_ecr_repository_url" {
  description = "Backend ECR repository URL."
  value       = aws_ecr_repository.backend.repository_url
}

output "frontend_ecr_repository_url" {
  description = "Frontend ECR repository URL."
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "backend_service_name" {
  description = "Backend ECS service name."
  value       = aws_ecs_service.backend.name
}

output "frontend_service_name" {
  description = "Frontend ECS service name."
  value       = aws_ecs_service.frontend.name
}

output "app_secret_arn" {
  description = "Secrets Manager application secret ARN."
  value       = aws_secretsmanager_secret.app.arn
}

output "github_deploy_role_arn" {
  description = "GitHub Actions OIDC role ARN, when enabled."
  value       = var.create_github_oidc_role && var.github_repository != "" ? aws_iam_role.github_deploy[0].arn : null
}
