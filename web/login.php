<?php
ini_set('display_errors', 1);
error_reporting(E_ALL);
session_start();
include("conexion.php");

$mensaje = "";

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $email = trim($_POST['email']);
    $password = $_POST['password'];

    if (empty($email) || empty($password)) {
        $mensaje = "Debes completar todos los campos.";
    } else {
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
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Login | CyberGuard Solutions</title>
  <link rel="stylesheet" href="style.css">
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
        <?php echo htmlspecialchars($mensaje); ?>
      </div>
    <?php endif; ?>

    <form method="POST" action="">
      <div class="form-group">
        <label>Correo electrónico</label>
        <input type="email" name="email" class="form-control" required>
      </div>

      <div class="form-group">
        <label>Contraseña</label>
        <input type="password" name="password" class="form-control" required>
      </div>

      <button type="submit" class="btn btn-primary" style="width:100%;">Entrar</button>
    </form>

    <div class="form-footer">
      ¿No tienes cuenta? <a href="registro.php">Regístrate</a>
    </div>
  </div>
</div>

</body>
</html>

