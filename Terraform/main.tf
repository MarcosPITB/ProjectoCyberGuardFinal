# ==========================================
# PROVEEDOR Y VARIABLES
# ==========================================
provider "aws" {
  region = "us-east-1"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type    = string
  default = "cyberguard"
}

variable "db_user" {
  type    = string
  default = "postgres"
}

variable "db_port" {
  type    = string
  default = "5432"
}

variable "turnstile_site_key" {
  type        = string
  description = "Site Key de Cloudflare Turnstile"
  default     = "1x00000000000000000000AA"
}

variable "turnstile_secret_key" {
  type        = string
  description = "Secret Key de Cloudflare Turnstile"
  sensitive   = true
  default     = "1x0000000000000000000000000000000AA"
}

data "aws_availability_zones" "available" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# ==========================================
# INFRAESTRUCTURA DE RED (VPC, PUBLIC & PRIVATE SUBNETS)
# ==========================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "ciberguard-vpc" }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "ciberguard-igw" }
}

# Subredes Públicas (Para el ALB y NAT Gateway)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "ciberguard-public-sub-${count.index}" }
}

# Subredes Privadas (Para EC2 con Nginx y RDS)
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = { Name = "ciberguard-private-sub-${count.index}" }
}

# NAT Gateway (Permite a la red privada descargar de GitHub/Apt sin exponerse)
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "ciberguard-nat-gw" }
}

# Tablas de ruteo
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "ciberguard-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "ciberguard-private-rt" }
}

# Asociaciones de ruteo
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
# GRUPOS DE SEGURIDAD (SECURITY GROUPS)
# ==========================================
resource "aws_security_group" "alb_sg" {
  name        = "ciberguard-alb-sg"
  description = "Permitir HTTP y HTTPS desde Internet hacia el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

resource "aws_security_group" "ec2_sg" {
  name        = "ciberguard-ec2-sg"
  description = "Permitir trafico SSL unicamente desde el ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db_sg" {
  name        = "ciberguard-db-sg"
  description = "Permitir acceso a PostgreSQL unicamente desde las instancias EC2 privadas"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ==========================================
# ALMACENAMIENTO AMAZON S3
# ==========================================
# 1. Bucket para Copias de Seguridad de Restic
resource "aws_s3_bucket" "restic_backups" {
  bucket        = "ciberguard-restic-backups-${random_id.suffix.hex}"
  force_destroy = true
}

# 2. Bucket para Logs del WAF (Debe empezar obligatoriamente con este prefijo)
resource "aws_s3_bucket" "waf_logs" {
  bucket        = "aws-waf-logs-ciberguard-${random_id.suffix.hex}"
  force_destroy = true
}

# 3. Bucket para Logs de Nginx
resource "aws_s3_bucket" "nginx_logs" {
  bucket        = "ciberguard-nginx-logs-${random_id.suffix.hex}"
  force_destroy = true
}

# ================= Certificado Autogenerado para el ALB =================
resource "tls_private_key" "cert" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "cert" {
  private_key_pem = tls_private_key.cert.private_key_pem

  subject {
    common_name  = "ciberguard.local"
    organization = "CiberGuard"
  }

  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

resource "aws_acm_certificate" "alb_cert" {
  private_key      = tls_private_key.cert.private_key_pem
  certificate_body = tls_self_signed_cert.cert.cert_pem
}

# ==========================================
# APPLICATION LOAD BALANCER (ALB)
# ==========================================
resource "aws_lb" "alb" {
  name               = "ciberguard-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "tg" {
  name        = "ciberguard-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.alb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.alb.arn
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

# ==========================================
# SEGURIDAD PERIMETRAL: AWS WAFv2
# ==========================================
resource "aws_wafv2_web_acl" "waf" {
  name        = "ciberguard-waf"
  description = "Proteccion contra OWASP Top 10 y ataques comunes"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

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
      metric_name                = "WafCommonRules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CiberGuardWafMetrics"
    sampled_requests_enabled   = true
  }
}

# Vinculación del WAF al Balanceador de Carga
resource "aws_wafv2_web_acl_association" "waf_alb_assoc" {
  resource_arn = aws_lb.alb.arn
  web_acl_arn  = aws_wafv2_web_acl.waf.arn
}

# ==========================================
# AUTO SCALING GROUP (MÁQUINAS EC2 DINÁMICAS)
# ==========================================
resource "aws_launch_template" "web_lt" {
  name_prefix   = "ciberguard-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  network_interfaces {
    associate_public_ip_address = false # Forzado en FALSE: Máquinas 100% privadas
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  iam_instance_profile {
    name = "LabInstanceProfile" # Perfil autorizado por AWS Academy
  }

  user_data = base64encode(templatefile("setup_nginx.sh", {
    db_port              = var.db_port
    db_name              = var.db_name
    db_user              = var.db_user
    db_pass              = var.db_password
    turnstile_site_key   = var.turnstile_site_key
    turnstile_secret_key = var.turnstile_secret_key
  }))

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name                = "ciberguard-asg"
  vpc_zone_identifier = aws_subnet.private[*].id # Despliega solo en red privada
  target_group_arns   = [aws_lb_target_group.tg.arn]

  desired_capacity = 2 # Inicia con 2 instancias activas balanceando cargas
  min_size         = 1
  max_size         = 3

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ciberguard-private-nginx"
    propagate_at_launch = true
  }
}

# ==========================================
# BASE DE DATOS RDS SEGURA (POSTGRESQL)
# ==========================================
resource "aws_db_subnet_group" "s_sub" {
  name       = "db-sub-group-private-${random_id.suffix.hex}"
  subnet_ids = aws_subnet.private[*].id # Base de datos aislada en red privada
}

resource "aws_db_instance" "db" {
  identifier             = "ciberguard-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.db_user
  password               = var.db_password
  port                   = var.db_port
  publicly_accessible    = false # Forzado en FALSE por seguridad corporativa
  db_subnet_group_name   = aws_db_subnet_group.s_sub.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  skip_final_snapshot    = true
}

# ==========================================
# CONFIGURACIÓN DE OUTPUTS
# ==========================================
output "url_alb" {
  value       = "http://${aws_lb.alb.dns_name}"
  description = "URL protegida por WAF (Redirige a HTTPS de forma transparente)"
}

output "rds_endpoint" {
  value       = aws_db_instance.db.endpoint
  description = "Endpoint interno de la base de datos (Accesible solo por Nginx y Restic internamente)"
}
