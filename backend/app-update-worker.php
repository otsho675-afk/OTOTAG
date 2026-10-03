<?php
// Run every minute to recover interrupted or temporarily failed push requests.
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
$apiDirectory=is_file(__DIR__.'/app_updates.php') ? __DIR__ : __DIR__.'/../lib';
require_once $apiDirectory.'/server_configuration.php';
require_once $apiDirectory.'/api_runtime.php';
require_once $apiDirectory.'/app_updates.php';
try {
    $env=readServerEnvironment($apiDirectory.'/.env');
    if (serverConfig('ONESIGNAL_APP_ID')==='' || serverConfig('ONESIGNAL_REST_API_KEY')==='') exit(0);
    $pdo=new PDO('mysql:host='.serverConfig('DB_HOST','localhost').';dbname='.serverConfig('DB_NAME').';charset=utf8mb4',serverConfig('DB_USER'),serverConfig('DB_PASS'),
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
    appUpdateEnsureSchema($pdo);
    $stmt=$pdo->prepare("SELECT id FROM app_update_releases WHERE active=1 AND created_at>DATE_SUB(NOW(),INTERVAL 1 DAY)
        AND push_attempts<5 AND push_next_attempt<=? AND (push_status IN ('pending','failed','not_configured') OR (push_status='sending' AND push_locked_at<?)) ORDER BY id LIMIT 20");
    $stmt->execute([time(),time()-60]);
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $id) appUpdateSendPush($pdo,$id);
} catch (Throwable $e) { fwrite(STDERR,"Güncelleme bildirim kuyruğu çalıştırılamadı. Sunucu yapılandırmasını kontrol edin.\n"); exit(1); }
