variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "db_name" {
  type    = string
  default = "cyberguard"
}

variable "db_user" {
  type        = string
  description = "Usuario administrador y dueño de la base de datos (reemplazará dinámicamente al del SQL)"
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "github_repo" {
  type    = string
  default = "https://github.com/MarcosPITB/ProjectoCyberGuardFinal.git"
}

variable "turnstile_site_key" {
  type        = string
  description = "Llave pública de Cloudflare Turnstile"
}

variable "turnstile_secret_key" {
  type        = string
  description = "Llave privada secreta de Cloudflare Turnstile"
  sensitive   = true
}
