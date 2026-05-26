<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);
session_start();
include("conexion.php");

$mensaje = "";

// Leer las claves de seguridad directo del pool privado del servidor web
define('TURNSTILE_SITE_KEY', getenv('TURNSTILE_SITE_KEY')); 
define('TURNSTILE_SECRET_KEY', getenv('TURNSTILE_SECRET_KEY'));

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $email = trim($_POST['email'] ?? '');
    $password = $_POST['password'] ?? '';
    
    // Captura el token devuelto por el widget del lado del cliente
    $turnstile_response = $_POST['cf-turnstile-response'] ?? '';

    if (empty($email) || empty($password)) {
        $mensaje = "Debes completar todos los campos.";
    } elseif (!TURNSTILE_SITE_KEY || !TURNSTILE_SECRET_KEY) {
        $mensaje = "Error de sistema: Faltan las llaves de validación perimetral.";
    } elseif (empty($turnstile_response)) {
        $mensaje = "Por favor, completa la verificación de seguridad para continuar.";
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
        } else {
            // EL CAPTCHA ES VÁLIDO -> VALIDACIÓN DE CREDENCIALES
            $consulta = pg_query_params(
                $conn,
                "SELECT id, nombre, empresa, password FROM usuarios WHERE email = $1",
                array($email)
            );

            if ($consulta && pg_num_rows($consulta) === 1) {
                $usuario = pg_fetch_assoc($consulta);

                if (password_verify($password, $usuario['password'])) {
                    $_SESSION['usuario_id'] = $usuario['id'];
                    $_SESSION['usuario_nombre'] = $usuario['nombre'];
                    $_SESSION['usuario_empresa'] = $usuario['empresa'];

                    header("Location: panel.php");
                    exit();
                } else {
                    $mensaje = "Contraseña incorrecta.";
                }
            } else {
                $mensaje = "No existe ninguna cuenta con ese correo.";
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
  <title>Login | CyberGuard Solutions</title>
  <link rel="stylesheet" href="style.css">
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
</head>
<body>

<nav class="navbar">
  <div class="logo">CyberGuard Solutions</div>
  <div class="nav-links">
    <a href="index.php">Inicio</a>
    <a href="registro.php">Registro</a>
  </div>
</nav>

<div class="form-wrapper">
  <div class="glass-card form-card">
    <h2>Iniciar sesión</h2>
    <p>Accede a tu panel corporativo.</p>

    <?php if (!empty($mensaje)): ?>
      <div class="alert alert-error">
        <?php echo htmlspecialchars($mensaje, ENT_QUOTES, 'UTF-8'); ?>
      </div>
    <?php endif; ?>

    <form method="POST" action="">
      <div class="form-group">
        <label>Correo electrónico</label>
        <input type="email" name="email" class="form-control" required autocomplete="email">
      </div>

      <div class="form-group">
        <label>Contraseña</label>
        <input type="password" name="password" class="form-control" required autocomplete="current-password">
      </div>

      <?php if (TURNSTILE_SITE_KEY): ?>
      <div class="form-group" style="display: flex; justify-content: center; margin-top: 15px; margin-bottom: 15px;">
        <div class="cf-turnstile" data-sitekey="<?php echo htmlspecialchars(TURNSTILE_SITE_KEY, ENT_QUOTES, 'UTF-8'); ?>"></div>
      </div>
      <?php endif; ?>

      <button type="submit" class="btn btn-primary" style="width:100%;">Entrar</button>
    </form>

    <div class="form-footer">
      ¿No tienes cuenta? <a href="registro.php">Regístrate</a>
    </div>
  </div>
</div>

</body>
</html>
