# AWS ECS Terraform

This composition deploys the application as a business-style container platform:

- public frontend ALB protected by AWS WAF;
- API Gateway HTTP API protected by AWS WAF;
- API Gateway VPC Link to an internal backend ALB;
- ECS Fargate services in private subnets;
- RDS PostgreSQL in private subnets;
- ECR, Secrets Manager, CloudWatch Logs, IAM roles, and GitHub OIDC.

## First Deploy

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Set `github_repository` to `owner/repo`.
3. Run:

```bash
terraform init
terraform apply
```

For GitHub Actions, create repository variables:

- `AWS_REGION`: for example `ap-southeast-1`
- `AWS_ROLE_ARN`: output `github_deploy_role_arn`
- `TF_PROJECT_NAME`: for example `fastapi-ecs`
- `TF_ENVIRONMENT`: for example `dev`

The deploy workflow bootstraps ECR, builds both containers, applies Terraform,
gets the API Gateway URL, rebuilds the frontend with that URL, then applies the
final ECS task definition.

## Cost Notes

This stack uses NAT Gateways, ALB, API Gateway, WAF, ECS, and RDS. For a cheaper
dev environment, set ECS desired counts to `1`, disable Multi-AZ RDS, and destroy
the stack when not needed.
