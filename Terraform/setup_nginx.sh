#!/bin/bash
# Actualizar el sistema e instalar dependencias básicas
dnf update -y
dnf install nginx git postgresql15 openssl -y

# Instalar PHP y la extensión oficial para PostgreSQL
dnf install php php-fpm php-pgsql php-json -y

# ========================================================
# CONFIGURACIÓN DE SEGURIDAD Y USUARIOS DE PHP-FPM
# ========================================================
# En Amazon Linux, PHP-FPM viene configurado para el usuario 'apache'. 
# Lo cambiamos a 'nginx' para que compartan los mismos permisos de sockets y archivos.
sed -i 's/user = apache/user = nginx/g' /etc/php-fpm.d/www.conf
sed -i 's/group = apache/group = nginx/g' /etc/php-fpm.d/www.conf

# ========================================================
# CONFIGURACIÓN DE VARIABLES DE ENTORNO EN PHP-FPM
# ========================================================
# Inyectamos dinámicamente las variables que requiere tu conexion.php de forma nativa
cat <<EOF >> /etc/php-fpm.d/www.conf
env[DB_HOST] = '${db_host}'
env[DB_PORT] = '${db_port}'
env[DB_NAME] = '${db_name}'
env[DB_USER] = '${db_user}'
env[DB_PASS] = '${db_password}'
env[TURNSTILE_SITE_KEY] = '${turnstile_site_key}'
env[TURNSTILE_SECRET_KEY] = '${turnstile_secret_key}'
EOF

# ========================================================
# SOLUCIÓN AL ERROR DE PERMISOS EN SESIONES DE PHP
# ========================================================
# Aseguramos que la carpeta de almacenamiento de sesiones pertenezca a nginx
mkdir -p /var/lib/php/session
chown -R nginx:nginx /var/lib/php/session
chmod 770 /var/lib/php/session

# Iniciar servicios con la configuración de usuarios y variables ya lista
systemctl daemon-reload
systemctl enable php-fpm nginx
systemctl start php-fpm nginx

# Limpiar el directorio web por defecto
rm -rf /usr/share/nginx/html/*

# Clonar tu repositorio en un directorio temporal
mkdir -p /tmp/cyberguard
git clone ${github_repo} /tmp/cyberguard

sed -i 's/.*transaction_timeout.*/-- &/g' /tmp/cyberguard/Web/cyberguard.sql

# ========================================================
# GENERACIÓN AUTOMÁTICA DEL CERTIFICADO AUTOFIRMADO (NUEVO)
# ========================================================
# Creamos un directorio dedicado para almacenar las llaves SSL
mkdir -p /etc/nginx/ssl

# Generamos llave privada y certificado válido por 1 año de forma silenciosa e interactiva
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/cyberguard.key \
  -out /etc/nginx/ssl/cyberguard.crt \
  -subj "/C=US/ST=State/L=City/O=CyberGuard/OU=IT/CN=localhost"

# Permisos seguros y estrictos para las credenciales SSL
chmod 600 /etc/nginx/ssl/cyberguard.key
chmod 644 /etc/nginx/ssl/cyberguard.crt

# ========================================================
# CONFIGURACIÓN DEL ENRUTADO DE NGINX PARA PHP CON HTTPS (NUEVO)
# ========================================================
# Creamos el bloque de servidor que le indica a Nginx cómo procesar PHP y usar login.php como índice
cat << 'EOF' > /etc/nginx/conf.d/cyberguard.conf
# 1. Servidor en Puerto 80 para atrapar tráfico HTTP y redirigir a HTTPS
server {
    listen       80;
    server_name  localhost;
    
    # Redirección nativa 301 conservando los parámetros de consulta originales
    return 301 https://$host$request_uri;
}

# 2. Servidor Seguro en Puerto 443 con SSL habilitado
server {
    listen       443 ssl;
    server_name  localhost;
    root         /usr/share/nginx/html;
    index        index.php;

    # Asignación de certificados autofirmados generados dinámicamente
    ssl_certificate      /etc/nginx/ssl/cyberguard.crt;
    ssl_certificate_key  /etc/nginx/ssl/cyberguard.key;

    # Ajustes estándar y seguros para transacciones SSL cifradas
    ssl_session_cache    shared:SSL:1m;
    ssl_session_timeout  5m;
    ssl_protocols        TLSv1.2 TLSv1.3;
    ssl_ciphers          HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers  on;

    location / {
        try_files $uri $uri/ /login.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass   unix:/run/php-fpm/www.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
        include        fastcgi_params;
    }
}
EOF

# Eliminar el archivo de bienvenida por defecto que estropea los ruteos
rm -f /etc/nginx/conf.d/default.conf

# ========================================================
# PROCESAMIENTO DINÁMICO DEL SQL (CERO HARDCODING)
# ========================================================
export PGPASSWORD='${db_password}'

# Verificar si la base de datos ya contiene tablas (evita sobreescritura en el ASG)
TABLAS_EXISTENTES=$(psql -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${db_name}" -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d ' ')

if [ "$${TABLAS_EXISTENTES:-0}" -eq 0 ]; then
    echo "Base de datos vacía. Procesando archivo SQL de forma dinámica..."

    # 1. Eliminar comandos de control meta-SQL (\restrict y \unrestrict)
    sed -i '/^\\restrict/d; /^\\unrestrict/d' /tmp/cyberguard/Web/cyberguard.sql

    # 2. Reemplazar privilegios y dueños para que coincidan con tu db_user de Terraform (postgres)
    sed -i -E 's/OWNER TO [a-zA-Z0-9_]+/OWNER TO ${db_user}/g' /tmp/cyberguard/Web/cyberguard.sql
    sed -i -E 's/TO [a-zA-Z0-9_]+;/TO ${db_user};/g' /tmp/cyberguard/Web/cyberguard.sql

    echo "Importando archivo SQL modificado..."
    psql -h "${db_host}" -p "${db_port}" -U "${db_user}" -d "${db_name}" -f /tmp/cyberguard/Web/cyberguard.sql
else
    echo "La base de datos ya cuenta con estructura. Saltando importación."
fi

# Limpieza total de contraseñas de la memoria de Bash
unset PGPASSWORD

# ELIMINACIÓN TOTAL Y SEGURA DEL ARCHIVO SQL
rm -f /tmp/cyberguard/Web/cyberguard.sql
rm -f /tmp/cyberguard/cyberguard.sql

# ========================================================
# DESPLIEGUE DE LA APLICACIÓN Y PERMISOS FINALES
# ========================================================
# Mover el contenido limpio de la carpeta "Web" al directorio de Nginx
cp -r /tmp/cyberguard/Web/* /usr/share/nginx/html/

# Asegurar la eliminación total si se copió por accidente en la ruta final
rm -f /usr/share/nginx/html/cyberguard.sql

# Limpieza final de directorios temporales
rm -rf /tmp/cyberguard

# Dar permisos correctos a Nginx sobre los archivos de la Web
chown -R nginx:nginx /usr/share/nginx/html
chmod -R 755 /usr/share/nginx/html

# Reiniciar Nginx para asegurar que aplique el nuevo archivo cyberguard.conf
systemctl restart nginx
