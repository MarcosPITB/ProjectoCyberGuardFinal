#!/bin/bash

# ==============================================================================
# SCRIPT DE RESPALDO AUTOMÁTICO (POSTGRESQL -> RESTIC S3)
# ==============================================================================

# Ruta al entorno y al ejecutable
ENV_FILE="/home/reestic/restic/.env"
RESTIC_BIN="/home/reestic/restic/restic_0.18.1_linux_amd64"

# 1. Validar la existencia del archivo de configuración
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ ERROR: No se encontró el archivo de entorno en $ENV_FILE"
    exit 1
fi

# 2. Cargar variables de AWS, Restic y Base de Datos
source "$ENV_FILE"

# 3. Validar que las variables esenciales de red existan
if [ -z "$DB_HOST" ] || [ -z "$RESTIC_REPOSITORY" ]; then
    echo "❌ ERROR: DB_HOST o RESTIC_REPOSITORY no están definidos en el .env"
    exit 1
fi

echo "🚀 Iniciando proceso de respaldo dinámico..."
echo "📅 Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo "🔗 Conectando a RDS: $DB_HOST"

# 4. Ejecución del pipeline (pg_dump -> sed -> Restic)
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" "$DB_NAME" | \
sed '/transaction_timeout/d' | \
$RESTIC_BIN -r "$RESTIC_REPOSITORY" backup \
    --stdin \
    --stdin-filename "backup_rds_$(date +%Y%m%d).sql" \
    --tag "automatic_rds"

# 🛑 GUARDAR LOS ESTADOS INMEDIATAMENTE (No tocar esta línea de orden)
ESTADOS=("${PIPESTATUS[@]}")

# 5. Comprobar los códigos de salida guardados
if [ "${ESTADOS[0]}" -ne 0 ]; then
    echo "❌ ERROR CRÍTICO: 'pg_dump' falló al extraer los datos de la BD."
    exit 1
elif [ "${ESTADOS[2]}" -ne 0 ]; then
    echo "❌ ERROR CRÍTICO: Restic falló al subir los datos a AWS S3."
    exit 1
else
    echo "========================================================="
    echo "✅ RESPALDO COMPLETADO Y CIFRADO EN S3 CON ÉXITO"
    echo "========================================================="
fi
