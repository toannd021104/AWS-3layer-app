data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

locals {
  name           = "${var.project_name}-${var.environment}"
  create_network = var.existing_vpc_id == ""

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  frontend_origin    = var.acm_certificate_arn != "" ? "https://${local.public_host}" : "http://${local.public_host}"
  public_host        = var.domain_name != "" ? var.domain_name : aws_lb.frontend.dns_name
  vpc_id             = local.create_network ? aws_vpc.this[0].id : var.existing_vpc_id
  public_subnet_ids  = local.create_network ? aws_subnet.public[*].id : var.existing_public_subnet_ids
  private_subnet_ids = local.create_network ? aws_subnet.private[*].id : var.existing_private_subnet_ids

  backend_secret_keys = [
    "DOMAIN",
    "FRONTEND_HOST",
    "ENVIRONMENT",
    "BACKEND_CORS_ORIGINS",
    "SECRET_KEY",
    "FIRST_SUPERUSER",
    "FIRST_SUPERUSER_PASSWORD",
    "SMTP_HOST",
    "SMTP_USER",
    "SMTP_PASSWORD",
    "EMAILS_FROM_EMAIL",
    "POSTGRES_SERVER",
    "POSTGRES_PORT",
    "POSTGRES_DB",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "SENTRY_DSN"
  ]
}

resource "random_password" "postgres" {
  length  = 32
  special = true
}

resource "random_password" "first_superuser" {
  length  = 32
  special = true
}

resource "random_password" "secret_key" {
  length  = 48
  special = false
}

resource "aws_vpc" "this" {
  count = local.create_network ? 1 : 0

  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  count = local.create_network ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(local.common_tags, {
    Name = "${local.name}-igw"
  })
}

resource "aws_subnet" "public" {
  count = local.create_network ? length(var.public_subnet_cidr_blocks) : 0

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = var.public_subnet_cidr_blocks[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = local.create_network ? length(var.private_subnet_cidr_blocks) : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  count = local.create_network ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this[0].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count = local.create_network ? length(aws_subnet.public) : 0

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-eip-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this[0]]
}

resource "aws_nat_gateway" "this" {
  count = local.create_network ? length(aws_subnet.public) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${local.name}-nat-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.this[0]]
}

resource "aws_route_table" "private" {
  count = local.create_network ? length(aws_subnet.private) : 0

  vpc_id = aws_vpc.this[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-rt-${count.index + 1}"
  })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_security_group" "frontend_alb" {
  name        = "${local.name}-frontend-alb"
  description = "Public frontend ALB ingress"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr_blocks
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidr_blocks
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-frontend-alb-sg"
  })
}

resource "aws_security_group" "api_gateway_link" {
  name        = "${local.name}-apigw-link"
  description = "API Gateway VPC Link"
  vpc_id      = local.vpc_id

  egress {
    description = "Backend ALB"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidr_blocks
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-apigw-link-sg"
  })
}

resource "aws_security_group" "backend_alb" {
  name        = "${local.name}-backend-alb"
  description = "Internal backend ALB"
  vpc_id      = local.vpc_id

  ingress {
    description     = "API Gateway VPC Link"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway_link.id]
  }

  egress {
    description = "Backend ECS service"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidr_blocks
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-backend-alb-sg"
  })
}

resource "aws_security_group" "frontend" {
  name        = "${local.name}-frontend"
  description = "Frontend ECS service"
  vpc_id      = local.vpc_id

  ingress {
    description     = "Frontend from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-frontend-sg"
  })
}

resource "aws_security_group" "backend" {
  name        = "${local.name}-backend"
  description = "Backend ECS service"
  vpc_id      = local.vpc_id

  ingress {
    description     = "Backend from internal ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-backend-sg"
  })
}

resource "aws_security_group" "database" {
  name        = "${local.name}-database"
  description = "RDS PostgreSQL"
  vpc_id      = local.vpc_id

  ingress {
    description     = "PostgreSQL from backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name}-database-sg"
  })
}

resource "aws_ecr_repository" "backend" {
  name                 = "${local.name}/backend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${local.name}/frontend"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${local.name}/backend"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${local.name}/frontend"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${local.name}"
  retention_in_days = 30

  tags = local.common_tags
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = local.private_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.name}-db-subnets"
  })
}

resource "aws_db_instance" "postgres" {
  identifier = "${local.name}-postgres"

  allocated_storage       = var.postgres_allocated_storage
  max_allocated_storage   = var.postgres_max_allocated_storage
  db_name                 = var.postgres_db
  db_subnet_group_name    = aws_db_subnet_group.this.name
  deletion_protection     = var.postgres_deletion_protection
  engine                  = "postgres"
  engine_version          = var.postgres_engine_version
  instance_class          = var.postgres_instance_class
  multi_az                = var.postgres_multi_az
  password                = random_password.postgres.result
  port                    = 5432
  publicly_accessible     = false
  skip_final_snapshot     = !var.postgres_deletion_protection
  storage_encrypted       = true
  storage_type            = "gp3"
  username                = var.postgres_user
  vpc_security_group_ids  = [aws_security_group.database.id]
  backup_retention_period = var.environment == "production" ? 7 : 1

  tags = merge(local.common_tags, {
    Name = "${local.name}-postgres"
  })
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${local.name}/app"
  recovery_window_in_days = var.environment == "production" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id

  secret_string = jsonencode({
    DOMAIN                   = var.domain_name
    FRONTEND_HOST            = local.frontend_origin
    ENVIRONMENT              = var.environment == "production" ? "production" : "staging"
    BACKEND_CORS_ORIGINS     = local.frontend_origin
    SECRET_KEY               = random_password.secret_key.result
    FIRST_SUPERUSER          = var.first_superuser
    FIRST_SUPERUSER_PASSWORD = random_password.first_superuser.result
    SMTP_HOST                = var.smtp_host
    SMTP_USER                = var.smtp_user
    SMTP_PASSWORD            = var.smtp_password
    EMAILS_FROM_EMAIL        = var.emails_from_email
    POSTGRES_SERVER          = aws_db_instance.postgres.address
    POSTGRES_PORT            = tostring(aws_db_instance.postgres.port)
    POSTGRES_DB              = var.postgres_db
    POSTGRES_USER            = var.postgres_user
    POSTGRES_PASSWORD        = random_password.postgres.result
    SENTRY_DSN               = var.sentry_dsn
  })
}

resource "aws_ecs_cluster" "this" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${local.name}-ecs-execution-secrets"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.app.arn
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json

  tags = local.common_tags
}

resource "aws_lb" "frontend" {
  name               = "${local.name}-frontend"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.frontend_alb.id]
  subnets            = local.public_subnet_ids

  tags = local.common_tags
}

resource "aws_lb" "backend" {
  name               = "${local.name}-backend"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend_alb.id]
  subnets            = local.private_subnet_ids

  tags = local.common_tags
}

resource "aws_lb_target_group" "frontend" {
  name        = "${local.name}-frontend"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "backend" {
  name        = "${local.name}-backend"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = local.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200-399"
    path                = "/api/v1/utils/health-check/"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  count = var.acm_certificate_arn == "" ? 1 : 0

  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.frontend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count = var.acm_certificate_arn != "" ? 1 : 0

  certificate_arn   = var.acm_certificate_arn
  load_balancer_arn = aws_lb.frontend.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener" "backend" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 8000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

resource "aws_apigatewayv2_vpc_link" "backend" {
  name               = "${local.name}-backend"
  security_group_ids = [aws_security_group.api_gateway_link.id]
  subnet_ids         = local.private_subnet_ids

  tags = local.common_tags
}

resource "aws_apigatewayv2_api" "backend" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["authorization", "content-type"]
    allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_origins     = [local.frontend_origin]
    max_age           = 3600
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "backend" {
  api_id             = aws_apigatewayv2_api.backend.id
  connection_id      = aws_apigatewayv2_vpc_link.backend.id
  connection_type    = "VPC_LINK"
  integration_method = "ANY"
  integration_type   = "HTTP_PROXY"
  integration_uri    = aws_lb_listener.backend.arn
}

resource "aws_apigatewayv2_route" "backend_default" {
  api_id    = aws_apigatewayv2_api.backend.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.backend.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.backend.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }

  tags = local.common_tags
}

resource "aws_wafv2_web_acl" "frontend" {
  name  = "${local.name}-frontend"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-frontend-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-frontend-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-frontend-sqli"
      sampled_requests_enabled   = true
    }
  }

  tags = local.common_tags

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-frontend"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl" "api" {
  name  = "${local.name}-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-api-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  tags = local.common_tags

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-api"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "frontend_alb" {
  resource_arn = aws_lb.frontend.arn
  web_acl_arn  = aws_wafv2_web_acl.frontend.arn
}

resource "aws_wafv2_web_acl_association" "api_gateway" {
  resource_arn = "arn:aws:apigateway:${var.aws_region}::/apis/${aws_apigatewayv2_api.backend.id}/stages/${aws_apigatewayv2_stage.default.name}"
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name}-backend"
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = var.backend_image
      essential = true

      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]

      secrets = [
        for key in local.backend_secret_keys : {
          name      = key
          valueFrom = "${aws_secretsmanager_secret.app.arn}:${key}::"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.backend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "backend"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name}-frontend"
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = var.frontend_image
      essential = true

      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.frontend.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "frontend"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "backend" {
  name            = "${local.name}-backend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 8000
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.backend.id]
    subnets          = local.private_subnet_ids
  }

  tags = local.common_tags

  depends_on = [
    aws_lb_listener.backend
  ]
}

resource "aws_ecs_service" "frontend" {
  name            = "${local.name}-frontend"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 80
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.frontend.id]
    subnets          = local.private_subnet_ids
  }

  tags = local.common_tags

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https
  ]
}

resource "aws_appautoscaling_target" "backend" {
  max_capacity       = var.backend_max_count
  min_capacity       = var.backend_min_count
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "backend_cpu" {
  name               = "${local.name}-backend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.ecs_cpu_target_value

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "frontend" {
  max_capacity       = var.frontend_max_count
  min_capacity       = var.frontend_min_count
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.frontend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "frontend_cpu" {
  name               = "${local.name}-frontend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.ecs_cpu_target_value

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

data "aws_iam_policy_document" "github_oidc_assume_role" {
  count = var.create_github_oidc_role && var.github_repository != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_branch}"]
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_role && var.github_repository != "" ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

resource "aws_iam_role" "github_deploy" {
  count = var.create_github_oidc_role && var.github_repository != "" ? 1 : 0

  name               = "${local.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume_role[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "github_deploy_admin" {
  count = var.create_github_oidc_role && var.github_repository != "" ? 1 : 0

  role       = aws_iam_role.github_deploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
