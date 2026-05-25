# Web

Web corporativa de ciberseguridad con inicio de sesión y área privada para clientes.

## ✨ Características

* **Registro y Login:** Acceso seguro para usuarios y empresas.
* **Diseño moderno:** Interfaz oscura, elegante y adaptada a móviles.

## 🔒 Seguridad Implementada

* **Protección contra Inyecciones SQL:** Uso de consultas parametrizadas (`pg_query_params`).
* **Contraseñas seguras:** Encriptadas en la base de datos usando Bcrypt.
* **Anti-Bots:** Verificación mediante Cloudflare Turnstile en el registro.
* **Datos ocultos:** Las credenciales del sistema se leen desde variables de entorno (`getenv`).

## 📁 Archivos del Proyecto

* `index.php` - Página principal.
* `conexion.php` - Conexión a la base de datos (PostgreSQL).
* `registro.php` - Formulario de creación de cuentas.
* `login.php` - Formulario de inicio de sesión.
* `panel.php` - Área privada del cliente.
* `logout.php` - Cierre de sesión.
* `style.css` - Estil del sitio.

## ⚙️ Configuración Requerida

Antes de arrancar el proyecto, debes configurar las siguientes **variables de entorno** en tu servidor:

* `DB_HOST` - Servidor de la base de datos.
* `DB_PORT` - Puerto (ej: 5432).
* `DB_NAME` - Nombre de la base de datos.
* `DB_USER` - Usuario de la base de datos.
* `DB_PASS` - Contraseña.
* `TURNSTILE_SITE_KEY` - Clave pública de Cloudflare Turnstile.
* `TURNSTILE_SECRET_KEY` - Clave privada de Cloudflare Turnstile.

# Terraform

Configuración en Terraform y Bash para desplegar de forma automática la infraestructura y el servidor web de CiberGuard en AWS.

## 🏗️ Recursos Creados
* **Red:** VPC dedicada con dos subredes públicas en diferentes zonas de disponibilidad.
* **Balanceador (ALB):** Un Application Load Balancer que recibe el tráfico y redirige automáticamente de HTTP (puerto 80) a HTTPS (puerto 443).
* **Servidor Web:** Una instancia EC2 (`t3.small`) con Ubuntu 22.04 que descarga la aplicación desde GitHub y configura Nginx + PHP 8.1.
* **Base de Datos:** Una instancia RDS con PostgreSQL (`db.t3.micro`) de 20 GB.
* **Almacenamiento:** Un bucket S3 para guardar los logs de AWS WAF.

## ⚙️ Variables Principales
* `db_password`: Contraseña para la base de datos (Obligatoria).
* `db_name`: Nombre de la base de datos (Por defecto: `"cyberguard"`).
* `db_user`: Usuario administrador (Por defecto: `"postgres"`).
* `turnstile_site_key` / `turnstile_secret_key`: Credenciales para Cloudflare Turnstile.

## 🚀 Despliegue Rápido

1. **Inicializar Terraform:**
   ```bash
   terraform init
2. **Ver infraestructura**
   ```bash
   terraform plan
3. **Crear infraestructura**
   ```bash
   terraform apply
