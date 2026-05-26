terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ==========================================
# DATOS DINÁMICOS / AUXILIARES
# ==========================================

# Generador de sufijo aleatorio para asegurar nombres únicos globales
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ==========================================
# GENERACIÓN DE CERTIFICADO SSL PARA EL ALB
# ==========================================

# 1. Crear una clave privada RSA interna
resource "tls_private_key" "alb_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# 2. Generar el certificado autofirmado
resource "tls_self_signed_cert" "alb_cert" {
  private_key_pem = tls_private_key.alb_key.private_key_pem

  subject {
    common_name  = "cyberguard.local"
    organization = "CyberGuard Academia"
  }

  validity_period_hours = 8760 # Válido por 1 año

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# 3. Importar dinámicamente el certificado en AWS ACM
resource "aws_acm_certificate" "alb_self_signed" {
  private_key      = tls_private_key.alb_key.private_key_pem
  certificate_body = tls_self_signed_cert.alb_cert.cert_pem

  tags = {
    Name = "cyberguard-self-signed-cert"
  }
}

# ==========================================
# PERFIL DE IAM (AWS ACADEMY LABROLE)
# ==========================================

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "cyberguard-ec2-instance-profile-${random_string.suffix.result}"
  role = "LabRole" # Utiliza el rol preconfigurado obligatorio en AWS Academy
}

# ==========================================
# 1. RED (VPC, SUBNETS, ROUTING)
# ==========================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "cyberguard-vpc" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "cyberguard-public-${count.index}" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "cyberguard-private-${count.index}" }
}

resource "aws_subnet" "database" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 20}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "cyberguard-db-${count.index}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "cyberguard-igw" }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "cyberguard-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "cyberguard-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "cyberguard-private-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ==========================================
# 2. GRUPOS DE SEGURIDAD (SECURITY GROUPS)
# ==========================================

resource "aws_security_group" "alb" {
  name   = "cyberguard-alb-sg"
  vpc_id = aws_vpc.main.id

  # Permitir HTTP (80) para realizar la redirección
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir HTTPS (443) para procesar el tráfico seguro de los usuarios
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  name   = "cyberguard-ec2-sg"
  vpc_id = aws_vpc.main.id

  # Las instancias EC2 se comunican por HTTPS seguro con el ALB
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name   = "cyberguard-rds-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# 3. ALMACENAMIENTO (S3 BUCKETS)
# ==========================================

resource "aws_s3_bucket" "restic_backups" {
  bucket        = "cyberguard-restic-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "waf_logs" {
  bucket        = "aws-waf-logs-cyberguard-${random_string.suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket" "nginx_logs" {
  bucket        = "cyberguard-nginx-logs-${random_string.suffix.result}"
  force_destroy = true
}

# ==========================================
# 4. BALANCEADOR DE CARGA (ALB) + REDIRECCIÓN
# ==========================================

resource "aws_lb" "web_alb" {
  name               = "cyberguard-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

# Target Group conectado al puerto SSL (443) de Nginx
resource "aws_lb_target_group" "web_tg_https" {
  name     = "cyberguard-tg-https"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/login.php"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    protocol            = "HTTPS"
    matcher             = "200"
  }
}

# REGLA CLAVE: Listener HTTP (80) redirige forzosamente a HTTPS (443)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
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

# Listener HTTPS (443) que descifra con el certificado autofirmado importado
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.alb_self_signed.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg_https.arn
  }
}

# ==========================================
# 5. AUTO SCALING GROUP (ASG)
# ==========================================

resource "aws_launch_template" "web_lt" {
  name_prefix   = "cyberguard-template-"
  image_id      = "ami-0236922087fa98b6e" # Amazon Linux 2023 en us-east-1
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2.id]
  }

  user_data = base64encode(templatefile("${path.module}/setup_nginx.sh", {
    github_repo = var.github_repo
    db_host     = split(":", aws_db_instance.db.endpoint)[0]
    db_port     = "5432"
    db_user     = var.db_user
    db_password = var.db_password
    db_name     = var.db_name
    turnstile_site_key   = var.turnstile_site_key
    turnstile_secret_key = var.turnstile_secret_key
  }))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  desired_capacity    = 2
  max_size            = 4
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.web_tg_https.arn]
  vpc_zone_identifier = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.web_lt.id 
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "cyberguard-web-server"
    propagate_at_launch = true
  }
}

# ==========================================
# 6. SEGURIDAD ADICIONAL (AWS WAFv2)
# ==========================================

resource "aws_wafv2_web_acl" "waf" {
  name        = "cyberguard-waf"
  scope       = "REGIONAL"
  description = "Filtros WAF para capas de aplicacion"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 1
    
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
      metric_name                = "WafIpReputationMetrics"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "cyberguardWafMetrics"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "waf_alb_assoc" {
  resource_arn = aws_lb.web_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}

resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  log_destination_configs = [aws_s3_bucket.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.waf.arn
}

# ==========================================
# 7. CAPA DE DATOS (RDS POSTGRESQL)
# ==========================================

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "cyberguard-rds-subnet-group"
  subnet_ids = aws_subnet.database[*].id
}

resource "aws_db_instance" "db" {
  allocated_storage      = 20
  max_allocated_storage  = 100
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
}

# ==========================================
# OUTPUTS
# ==========================================

output "url_https_directa" {
  description = "Petición cifrada HTTPS directa"
  value       = "https://${aws_lb.web_alb.dns_name}"
}

output "rds_endpoint" {
  description = "Dirección interna del motor RDS"
  value       = aws_db_instance.db.endpoint
}
