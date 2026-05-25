<?php
// Obtener las credenciales puras desde el entorno del sistema
$host     = getenv('DB_HOST');
$port     = getenv('DB_PORT');
$dbname   = getenv('DB_NAME');
$user     = getenv('DB_USER');
$password = getenv('DB_PASS');

// Construcción de la cadena de conexión utilizando estrictamente los valores del entorno
$connection_string = sprintf(
    "host=%s port=%s dbname=%s user=%s password=%s",
    $host, $port, $dbname, $user, $password
);

// Intento de conexión a PostgreSQL
$conn = pg_connect($connection_string);

if (!$conn) {
    die("Error de conexión a PostgreSQL");
}
?>
