<?php
if (PHP_SAPI !== 'cli') {
    http_response_code(404);
    exit;
}

require_once __DIR__.'/server_configuration.php';
require_once __DIR__.'/api_runtime.php';

$env=readServerEnvironment(__DIR__.'/.env');
$dbHost=serverConfig('DB_HOST','localhost');
$dbName=serverConfig('DB_NAME');
$dbUser=serverConfig('DB_USER');
$dbPass=serverConfig('DB_PASS');
if ($dbName==='' || $dbUser==='') {
    fwrite(STDERR,"Database configuration missing.\n");
    exit(1);
}

$pdo=new PDO(
    "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4",
    $dbUser,
    $dbPass,
    [
        PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES=>false,
    ]
);
date_default_timezone_set('Europe/Istanbul');
$pdo->exec("SET time_zone = '+03:00'");

require_once __DIR__.'/notification_delivery.php';
require_once __DIR__.'/referral_rewards.php';
require_once __DIR__.'/growth_features.php';

function sendOneSignalPush($targetUsers,$title,$message,$data=[]) {
    global $pdo;
    return notificationQueue(
        $pdo,
        $targetUsers,
        $title,
        $message,
        $data,
        'growth:'.hash('sha256',json_encode([$targetUsers,$title,$message,$data,gmdate('Y-m-d-H')]))
    );
}

try {
    notificationEnsureSchema($pdo);
    ensureGrowthSchema($pdo);

    $last=0;
    $usersScanned=0;
    $alerts=0;
    do {
        $stmt=$pdo->prepare("SELECT id FROM users
            WHERE id>? AND user_type='customer' AND status='active'
            ORDER BY id LIMIT 200");
        $stmt->execute([$last]);
        $ids=$stmt->fetchAll(PDO::FETCH_COLUMN);
        foreach ($ids as $id) {
            $last=(int)$id;
            $result=growthSyncVehicleReminders($pdo,$last);
            $alerts+=count($result['alerts'] ?? []);
            $usersScanned++;
        }
    } while (count($ids)===200);

    notificationDrain($pdo,200);
    echo "OK users={$usersScanned} alerts={$alerts}\n";
} catch (Throwable $e) {
    fwrite(STDERR,'Growth reminder worker failed: '.$e->getMessage()."\n");
    exit(1);
}
