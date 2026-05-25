<?php
session_start();
?>
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CyberGuard Solutions</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>

<nav class="navbar">
  <div class="logo">CyberGuard Solutions</div>
  <div class="nav-links">
    <?php if (isset($_SESSION['usuario_nombre'])): ?>
      <a href="panel.php">Panel</a>
      <a href="logout.php" class="btn btn-secondary">Cerrar sesión</a>
    <?php else: ?>
      <a href="login.php">Login</a>
      <a href="registro.php" class="btn btn-primary">Registrarse</a>
    <?php endif; ?>
  </div>
</nav>

<section class="hero">
  <div class="hero-text">
    <span class="badge">Infraestructura web segura sobre AWS</span>
    <h1>Protegemos empresas frente a amenazas digitales.</h1>
    <p>
      Plataforma corporativa de CyberGuard Solutions para gestión de clientes,
      acceso seguro, registro de usuarios y servicios de ciberseguridad con
      almacenamiento en base de datos MySQL desplegada en AWS.
    </p>
    <div class="hero-actions">
      <?php if (isset($_SESSION['usuario_nombre'])): ?>
        <a href="panel.php" class="btn btn-primary">Entrar al panel</a>
      <?php else: ?>
        <a href="registro.php" class="btn btn-primary">Crear cuenta</a>
        <a href="login.php" class="btn btn-secondary">Iniciar sesión</a>
      <?php endif; ?>
    </div>
  </div>

  <div class="glass-card info-card">
    <h3>Servicios incluidos</h3>
    <ul class="info-list">
      <li>Auditoría de seguridad y análisis de vulnerabilidades</li>
      <li>Monitorización de eventos e incidentes</li>
      <li>Backups y recuperación ante desastres</li>
      <li>Protección de red y control de accesos</li>
    </ul>
  </div>
</section>

<section class="section">
  <div class="section-title">
    <h2>Soluciones preparadas para PYMES</h2>
    <p>Un entorno profesional, modular y escalable para vuestro proyecto.</p>
  </div>

  <div class="cards">
    <div class="glass-card card">
      <h3>Auditoría técnica</h3>
      <p>Identificación de vulnerabilidades, revisión de exposición externa y pruebas controladas de seguridad.</p>
    </div>
    <div class="glass-card card">
      <h3>Monitorización</h3>
      <p>Detección de incidentes, control de eventos de seguridad y análisis continuo de la infraestructura.</p>
    </div>
    <div class="glass-card card">
      <h3>Recuperación</h3>
      <p>Protección de datos, copias de seguridad y planes de continuidad ante incidentes o pérdidas de información.</p>
    </div>
  </div>
</section>

<footer>
  © 2026 CyberGuard Solutions S.L. | Plataforma corporativa en AWS
</footer>

</body>
</html>