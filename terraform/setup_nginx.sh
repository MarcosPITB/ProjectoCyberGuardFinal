#!/bin/bash

# ==============================================================================
# 1. CONTROL DE BLOQUEOS DE APT (Evita que el script falle por unattended-upgrades)
# ==============================================================================
echo "=== [1/5] Esperando a que el sistema libere los bloqueos de APT e IMDS ==="
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do sleep 5; done
while fuser /var/lib/apt/lists/lock >/dev/null 2>&1 ; do sleep 5; done

# Forzar modo no interactivo para evitar diálogos emergentes que pausen el script
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  nginx git php8.1-fpm php8.1-pgsql openssl awscli postgresql-client

# ==============================================================================
# 2. GENERACIÓN DE CERTIFICADO SSL AUTOFIRMADO
# ==============================================================================
echo "=== [2/5] Generando certificado SSL para Nginx ==="
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/nginx.key \
  -out /etc/nginx/ssl/nginx.crt \
  -subj "/C=ES/ST=BCN/L=BCN/O=CiberGuard/CN=ciberguard.interno"

# ==============================================================================
# 3. CONFIGURACIÓN EXCLUSIVA HTTPS (Puerto 443) EN NGINX Y DESPLIEGUE DESDE GITHUB
# ==============================================================================
echo "=== [3/5] Configurando bloque de servidor Nginx (Puerto 443) ==="
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.php index.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

echo "=== Descargando el código de la aplicación desde GitHub ==="
# Limpiar el directorio web por defecto
rm -rf /var/www/html/*

# Clonar el repositorio en un directorio temporal
git clone https://github.com/paucortesyuste/projectoweb.git /tmp/projectoweb

# Mover los archivos a la ruta web de producción
if [ -d "/tmp/projectoweb/projectoweb-main" ]; then
    cp -r /tmp/projectoweb/projectoweb-main/* /var/www/html/
else
    cp -r /tmp/projectoweb/* /var/www/html/
fi

# Limpiar temporales de clonación
rm -rf /tmp/projectoweb

# ==============================================================================
# 4. EXTRACCIÓN DE ENDPOINT, IMPORTACIÓN DE SQL Y CONFIGURACIÓN DE ENTORNO
# ==============================================================================
echo "=== [4/5] Configurando base de datos e inyectando entorno ==="

# Obtener dinámicamente el Endpoint del RDS Postgres
DB_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier ciberguard-db --query 'DBInstances[0].Endpoint.Address' --output text --region us-east-1)

# --- PROCESO DE IMPORTACIÓN Y LIMPIEZA DEL ARCHIVO .SQL ---
if [ -f "/var/www/html/cyberguard.sql" ]; then
    echo "Detectado archivo SQL. Preparando importación en RDS..."
    
    # Exportar temporalmente la contraseña para que psql la use de forma segura
    export PGPASSWORD="${db_pass}"
    
    # Comprobar si la tabla 'usuarios' ya existe (evita duplicados)
    TABLA_EXISTE=$(psql -h "$DB_ENDPOINT" -p "${db_port}" -U "${db_user}" -d "${db_name}" -tAc "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'usuarios');")
    
    if [ "$TABLA_EXISTE" = "f" ]; then
        echo "La base de datos está vacía. Importando estructura y datos de prueba..."
        psql -h "$DB_ENDPOINT" -p "${db_port}" -U "${db_user}" -d "${db_name}" -f /var/www/html/cyberguard.sql
        echo "Importación completada exitosamente."
    else
        echo "La tabla 'usuarios' ya existe en RDS. Saltando importación para evitar duplicados."
    fi
    
    # Destruir credencial temporal en memoria
    unset PGPASSWORD

    # ELIMINACIÓN DEL ARCHIVO SQL DE LA INSTANCIA (Tu requerimiento de limpieza)
    echo "Eliminando archivo cyberguard.sql de la instancia EC2 de manera permanente..."
    rm -f /var/www/html/cyberguard.sql
else
    echo "Aviso: No se encontró el archivo cyberguard.sql para importar."
fi
# ----------------------------------------------------------

# Asegurar permisos correctos para Nginx y PHP antes de configurar variables
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html/

# Limpiar inyecciones previas en el pool de PHP-FPM para evitar duplicados
sed -i '/env\[DB_/d' /etc/php/8.1/fpm/pool.d/www.conf
sed -i '/env\[TURNSTILE_/d' /etc/php/8.1/fpm/pool.d/www.conf

# Inyectar credenciales de la Base de Datos al entorno PHP
echo "env[DB_HOST] = \"$DB_ENDPOINT\"" >> /etc/php/8.1/fpm/pool.d/www.conf
echo "env[DB_PORT] = \"${db_port}\"" >> /etc/php/8.1/fpm/pool.d/www.conf
echo "env[DB_NAME] = \"${db_name}\"" >> /etc/php/8.1/fpm/pool.d/www.conf
echo "env[DB_USER] = \"${db_user}\"" >> /etc/php/8.1/fpm/pool.d/www.conf
echo "env[DB_PASS] = \"${db_pass}\"" >> /etc/php/8.1/fpm/pool.d/www.conf

# Inyectar credenciales de Cloudflare Turnstile al entorno PHP
echo "env[TURNSTILE_SITE_KEY] = \"${turnstile_site_key}\"" >> /etc/php/8.1/fpm/pool.d/www.conf
echo "env[TURNSTILE_SECRET_KEY] = \"${turnstile_secret_key}\"" >> /etc/php/8.1/fpm/pool.d/www.conf

# ==============================================================================
# 5. VERIFICACIÓN Y REINICIO DE SERVICIOS
# ==============================================================================
echo "=== [5/5] Reiniciando servicios y aplicando configuraciones ==="

systemctl enable nginx
systemctl enable php8.1-fpm

# Comprobar sintaxis de Nginx antes de aplicar cambios
nginx -t

if [ $? -eq 0 ]; then
    systemctl restart php8.1-fpm
    systemctl restart nginx
    echo "=== PROCESO COMPLETADO EXITOSAMENTE ==="
else
    echo "=== ERROR: La sintaxis de Nginx no es válida ==="
    exit 1
fi
