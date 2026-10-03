<?php
if (PHP_SAPI!=='cli') { http_response_code(404); exit; }
$root=is_file(__DIR__.'/notification_delivery.php') ? __DIR__ : __DIR__.'/../lib';
require_once $root.'/server_configuration.php';
require_once $root.'/notification_delivery.php';
try {
    $env=readServerEnvironment($root.'/.env');
    $pdo=new PDO('mysql:host='.serverConfig('DB_HOST','localhost').';dbname='.serverConfig('DB_NAME').';charset=utf8mb4',serverConfig('DB_USER'),serverConfig('DB_PASS'),
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
    notificationEnsureSchema($pdo);
    if ((int)$pdo->query("SELECT GET_LOCK(CONCAT(DATABASE(),':notifications'),0)")->fetchColumn()!==1) exit(0);
    try {
        $today=(new DateTimeImmutable('now',new DateTimeZone('Europe/Istanbul')));
        $previous=$pdo->query("SELECT setting_value FROM app_settings WHERE setting_key='vehicle_reminder_scan_at'")->fetchColumn();
        if (vehicleReminderScanDue($previous,$today)) {
            vehicleReminderQueue($pdo,$today);
            $pdo->prepare("INSERT INTO app_settings(setting_key,setting_value) VALUES ('vehicle_reminder_scan_at',?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)")->execute([(string)$today->getTimestamp()]);
            $pdo->prepare("INSERT INTO app_settings(setting_key,setting_value) VALUES ('vehicle_reminder_day',?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)")->execute([$today->format('Y-m-d')]);
        }
        notificationDrain($pdo,100);
        $pdo->prepare('DELETE FROM notification_outbox WHERE created_at<? LIMIT 1000')->execute([time()-30*86400]);
        $pdo->exec("INSERT INTO app_settings(setting_key,setting_value) VALUES ('notification_worker_at',UNIX_TIMESTAMP()) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)");
    } finally { $pdo->query("SELECT RELEASE_LOCK(CONCAT(DATABASE(),':notifications'))"); }
    echo "Bildirim kuyruğu işlendi.\n";
} catch (Throwable $e) { fwrite(STDERR,"Bildirim işçisi çalışamadı. PHP, veritabanı ve tablo kurulumunu kontrol edin.\n"); exit(1); }
