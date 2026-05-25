<?php
session_start();

if (!isset($_SESSION['usuario_id'])) {
    header("Location: login.php");
    exit();
}
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Panel | CyberGuard Solutions</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>

<nav class="navbar">
  <div class="logo">CyberGuard Solutions</div>
  <div class="nav-links">
    <a href="index.php">Inicio</a>
    <a href="logout.php" class="btn btn-secondary">Cerrar sesión</a>
  </div>
</nav>

<section class="dashboard">
  <div class="dashboard-top">
    <div>
      <h1>Bienvenido, <?php echo htmlspecialchars($_SESSION['usuario_nombre']); ?></h1>
      <p>Empresa registrada: <?php echo htmlspecialchars($_SESSION['usuario_empresa']); ?></p>
    </div>
  </div>

  <div class="stats">
    <div class="glass-card stat-box">
      <h3>Estado del portal</h3>
      <div class="big">Activo</div>
      <small>La plataforma web está operativa</small>
    </div>

    <div class="glass-card stat-box">
      <h3>Infraestructura</h3>
      <div class="big">AWS</div>
      <small>Servidor web + base de datos separada</small>
    </div>

    <div class="glass-card stat-box">
      <h3>Seguridad</h3>
      <div class="big">Protegida</div>
      <small>Credenciales cifradas y acceso privado</small>
    </div>
  </div>
</section>

<footer>
  Panel privado de cliente | CyberGuard Solutions
</footer>

</body>
</html>