<?php
/**
 * Portal de Registro Seguro - CyberGuard Solutions
 * controles de seguridad implementados:
 * - Anti-SQLi: Consultas parametrizadas con pg_query_params.
 * - Anti-Automatización: Validación de Cloudflare Turnstile en Backend.
 * - Anti-XSS: Sanitización de datos impresos mediante htmlspecialchars.
 * - Confidencialidad: Uso de getenv() para variables de entorno (Sin claves hardcodeadas).
 */

session_start();
include("conexion.php");

$mensaje = "";
$tipo = "";

// Leer las claves de seguridad directo del pool privado del servidor web
define('TURNSTILE_SITE_KEY', getenv('TURNSTILE_SITE_KEY')); 
define('TURNSTILE_SECRET_KEY', getenv('TURNSTILE_SECRET_KEY'));

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $nombre   = trim($_POST['nombre'] ?? '');
    $empresa  = trim($_POST['empresa'] ?? '');
    $email    = trim($_POST['email'] ?? '');
    $password = $_POST['password'] ?? '';
    
    // Captura el token devuelto por el widget del lado del cliente
    $turnstile_response = $_POST['cf-turnstile-response'] ?? '';

    if (empty($nombre) || empty($empresa) || empty($email) || empty($password)) {
        $mensaje = "Todos los campos son obligatorios.";
        $tipo = "error";
    } elseif (!TURNSTILE_SITE_KEY || !TURNSTILE_SECRET_KEY) {
        $mensaje = "Error de sistema: Faltan las llaves de validación perimetral.";
        $tipo = "error";
    } elseif (empty($turnstile_response)) {
        $mensaje = "Por favor, completa la verificación de seguridad para continuar.";
        $tipo = "error";
    } else {
        // VALIDACIÓN DEL TOKEN EN EL BACKEND CONTRA LA API DE CLOUDFLARE
        $url = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
        $datos = [
            'secret'   => TURNSTILE_SECRET_KEY,
            'response' => $turnstile_response,
            'remoteip' => $_SERVER['REMOTE_ADDR']
        ];

        $opciones = [
            'http' => [
                'header'  => "Content-type: application/x-www-form-urlencoded\r\n",
                'method'  => 'POST',
                'content' => http_build_query($datos)
            ]
        ];

        $contexto  = stream_context_create($opciones);
        $resultado = @file_get_contents($url, false, $contexto);
        $respuesta_json = $resultado ? json_decode($resultado, true) : null;

        if (!$respuesta_json || !isset($respuesta_json['success']) || !$respuesta_json['success']) {
            $mensaje = "La verificación de seguridad ha fallado o el token ha expirado. Inténtalo de nuevo.";
            $tipo = "error";
        } else {
            // EL CAPTCHA ES VÁLIDO -> VALIDACIÓN DE EMAIL MEDIANTE CONSULTA PARAMETRIZADA
            $consulta = pg_query_params($conn, "SELECT id FROM usuarios WHERE email = $1", array($email));

            if ($consulta && pg_num_rows($consulta) > 0) {
                $mensaje = "Ese correo electrónico ya está registrado.";
                $tipo = "error";
            } else {
                // Hashing criptográfico robusto (Bcrypt nativo)
                $password_hash = password_hash($password, PASSWORD_DEFAULT);

                $insert = pg_query_params(
                    $conn,
                    "INSERT INTO usuarios (nombre, empresa, email, password) VALUES ($1, $2, $3, $4)",
                    array($nombre, $empresa, $email, $password_hash)
                );

                if ($insert) {
                    $mensaje = "Registro completado correctamente. Ya puedes iniciar sesión.";
                    $tipo = "success";
                } else {
                    $mensaje = "Error interno al procesar el alta del usuario.";
                    $tipo = "error";
                }
            }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Registro Seguro | CyberGuard Solutions</title>
  <link rel="stylesheet" href="style.css">
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
</head>
<body>

<nav class="navbar">
  <div class="logo">CyberGuard Solutions</div>
  <div class="nav-links">
    <a href="index.php">Inicio</a>
    <a href="login.php">Login</a>
  </div>
</nav>

<div class="form-wrapper">
  <div class="glass-card form-card">
    <h2>Crear cuenta</h2>
    <p>Registra tu organización en el portal seguro.</p>

    <?php if (!empty($mensaje)): ?>
      <div class="alert <?php echo $tipo === 'success' ? 'alert-success' : 'alert-error'; ?>">
        <?php echo htmlspecialchars($mensaje, ENT_QUOTES, 'UTF-8'); ?>
      </div>
    <?php endif; ?>

    <form method="POST" action="">
      <div class="form-group">
        <label for="nombre">Nombre Completo</label>
        <input type="text" id="nombre" name="nombre" class="form-control" required autocomplete="name">
      </div>

      <div class="form-group">
        <label for="empresa">Empresa</label>
        <input type="text" id="empresa" name="empresa" class="form-control" required>
      </div>

      <div class="form-group">
        <label for="email">Correo electrónico</label>
        <input type="email" id="email" name="email" class="form-control" required autocomplete="email">
      </div>

      <div class="form-group">
        <label for="password">Contraseña</label>
        <input type="password" id="password" name="password" class="form-control" required autocomplete="new-password">
      </div>

      <?php if (TURNSTILE_SITE_KEY): ?>
      <div class="form-group" style="display: flex; justify-content: center; margin-top: 15px; margin-bottom: 15px;">
        <div class="cf-turnstile" data-sitekey="<?php echo htmlspecialchars(TURNSTILE_SITE_KEY, ENT_QUOTES, 'UTF-8'); ?>"></div>
      </div>
      <?php endif; ?>

      <button type="submit" class="btn btn-primary" style="width:100%;">Registrarse</button>
    </form>

    <div class="form-footer">
      ¿Ya tienes cuenta? <a href="login.php">Inicia sesión</a>
    </div>
  </div>
</div>

</body>
</html>
