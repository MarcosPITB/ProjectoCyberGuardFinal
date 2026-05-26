**Echo por Marcos Pérez  y Pau Cortés**

# Web

Web corporativa con inicio de sesión y área privada para clientes.

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

# Terraform

Configuración en Terraform y Bash para desplegar de forma automática la infraestructura y el servidor web de CiberGuard en AWS.

## 🏗️ Recursos Creados
* **Red:** VPC dedicada con dos subredes públicas en diferentes zonas de disponibilidad.
* **Balanceador (ALB):** Un Application Load Balancer que recibe el tráfico y redirige automáticamente de HTTP (puerto 80) a HTTPS (puerto 443).
* **Servidor Web:** Una instancia EC2 (`t3.small`) con Ubuntu 22.04 que descarga la aplicación desde GitHub y configura Nginx + PHP 8.1.
* **Base de Datos:** Una instancia RDS con PostgreSQL (`db.t3.micro`) de 20 GB.
* **Almacenamiento:** Un bucket S3 para guardar los logs de AWS WAF.

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


# Scripts de Restic

## scriptBackup.sh

Este script automatiza la extracción segura de datos de la base de datos. Está diseñado para poder ser programado mediante tareas Cron.

### Ejecución manual

```bash
   ./scriptBackup.sh
```

## scriptRestore.sh

Este script permite recuperar la base de datos de los backups hechos con el script de scriptBackup.sh

### Ejecución manual

```bash
   ./scriptRestore.sh
```


# Configuración Requerida

Antes de arrancar la infraestructura, debes crear un **terraform.tfvars** en el mismo directorio de Terraform con las siguientes **variables de entorno**:

* `aws_region` - Región de la infraestructura.
* `db_name` - Nombre de la base de datos.
* `db_user` - Nombre del usuario de la base de datos.
* `db_password` - Contraseña de la base de datos.
* `github_repo` - Repositorio de Github.
* `turnstile_site_key` - Clave pública de Cloudflare Turnstile.
* `turnstile_secret_key` - Clave privada de Cloudflare Turnstile.

Para que funcionen los scripts de Restic, debes crear un **.env** en el mismo directorio de ReesticScripts con las siguientes **variables de entorno**:

* `AWS_ACCESS_KEY_ID` - ID de tu clave de acceso de AWS.
* `AWS_SECRET_ACCESS_KEY` - Clave de acceso secreta de AWS.
* `AWS_SESSION_TOKEN` - Token de sesión temporal de AWS.
* `RESTIC_PASSWORD` - Contraseña del repositorio de Restic.
* `RESTIC_REPOSITORY` - Ubicación del repositorio de Restic.
* `DB_HOST` - URL de la instancia de RDS.
* `DB_PORT` - Puerto de la base de datos.
* `DB_NAME` - Nombre de la base de datos.
* `DB_USER` - Nombre del usuario de la base de datos.
* `PGPASSWORD` - Contraseña de la base de datos.
