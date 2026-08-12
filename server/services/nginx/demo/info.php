<?php
// Small proof-of-life page for the nginx + php-fpm part of the stack.
// Deliberately avoids a full phpinfo() dump (which leaks a lot of local
// path/environment detail onto a page reachable from the tailnet) — prints
// just enough to confirm PHP is actually executing behind nginx.
header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>on_server — PHP demo</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 640px; margin: 3rem auto; padding: 0 1.25rem; }
    table { border-collapse: collapse; width: 100%; }
    td, th { text-align: left; padding: 0.3rem 0.6rem; border-bottom: 1px solid #ddd; }
  </style>
</head>
<body>
  <h1>PHP is running behind nginx</h1>
  <table>
    <tr><th>PHP version</th><td><?php echo htmlspecialchars(phpversion()); ?></td></tr>
    <tr><th>Server time</th><td><?php echo date('c'); ?></td></tr>
    <tr><th>SAPI</th><td><?php echo htmlspecialchars(php_sapi_name()); ?></td></tr>
  </table>
  <p>For the full environment dump, run <code>php -i</code> from a Termux shell instead of exposing it here.</p>
</body>
</html>
