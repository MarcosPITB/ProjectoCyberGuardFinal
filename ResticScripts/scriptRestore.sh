#!/bin/bash

# ==============================================================================
# SCRIPT DE RESTAURACIÓN INTERACTIVA (RESTIC S3 -> POSTGRESQL RDS)
# ==============================================================================

ENV_FILE="/home/reestic/restic/.env"
RESTIC_BIN="/home/reestic/restic/restic_0.18.1_linux_amd64"
RESTORE_TEMP_DIR="/home/reestic/restic/restores"

# 1. Cargar y validar entorno
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ ERROR: No se encontró el archivo de entorno en $ENV_FILE"
    exit 1
fi

source "$ENV_FILE"
mkdir -p "$RESTORE_TEMP_DIR"

echo "======================================================="
echo "   MENÚ DE RESTAURACIÓN TOTAL (REEMPLAZAR BASE DATOS)  "
echo "======================================================="
echo "1) Usar el respaldo más reciente (latest)"
echo "2) Elegir un snapshot específico del historial"
read -p "Seleccione una opción [1-2]: " opcion

# 2. Determinar qué Snapshot descargar
if [ "$opcion" == "1" ]; then
    SNAPSHOT_ID="latest"
else
    echo "🔍 Consultando el historial de respaldos en S3..."
    $RESTIC_BIN -r "$RESTIC_REPOSITORY" snapshots
    echo ""
    read -p "👉 Introduce el ID del snapshot que deseas restaurar: " SNAPSHOT_ID
    
    if [ -z "$SNAPSHOT_ID" ]; then
        echo "❌ Operación cancelada: No especificaste un ID válido."
        exit 1
    fi
fi

# 3. Descargar el archivo desde AWS S3
echo "⏳ Descargando y descifrando archivos desde el repositorio..."
$RESTIC_BIN -r "$RESTIC_REPOSITORY" restore "$SNAPSHOT_ID" --target "$RESTORE_TEMP_DIR"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Restic no pudo descargar el snapshot seleccionado."
    exit 1
fi

# 4. Localizar el archivo SQL extraído en el directorio temporal
SQL_FILE=$(find "$RESTORE_TEMP_DIR" -name "backup_rds_*.sql" | head -n 1)

if [ -z "$SQL_FILE" ] || [ ! -f "$SQL_FILE" ]; then
    echo "❌ ERROR: No se encontró ningún archivo de volcado .sql dentro del backup descargado."
    exit 1
fi

echo "✅ Archivo preparado para inyección: $SQL_FILE"

# 5. Confirmación destructiva de seguridad
echo ""
echo "⚠️  ADVERTENCIA CRÍTICA: Se va a ELIMINAR todo el contenido actual"
echo "   de la base de datos '$DB_NAME' para reemplazarla con el backup."
read -p "¿Estás completamente seguro de continuar? (s/n): " confirmacion

if [ "$confirmacion" != "s" ] && [ "$confirmacion" != "S" ]; then
    echo "❌ Operación abortada por el usuario."
    rm -rf "${RESTORE_TEMP_DIR:?}/*"
    exit 0
fi

echo "⚡ Limpiando tablas previas e importando nuevos datos en RDS..."

# 6. Reemplazo del esquema en PostgreSQL
# Borra el esquema público para limpiar tablas viejas y lo vuelve a crear vacío
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Falló la purga del esquema de la base de datos."
    exit 1
fi

# Inyecta los datos del archivo descargado
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SQL_FILE"

if [ $? -eq 0 ]; then
    echo "========================================================="
    echo "✅ PROCESO COMPLETADO EN SU TOTALIDAD CON ÉXITO"
    echo " La base de datos ha sido restaurada al estado seleccionado."
    echo "========================================================="
else
    echo "❌ ERROR: Ocurrió un fallo durante la importación del archivo SQL."
fi

# 7. Limpieza del entorno de trabajo
rm -rf "${RESTORE_TEMP_DIR:?}/*"
