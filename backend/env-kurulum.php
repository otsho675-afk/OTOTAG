<?php
// Run once in aaPanel Terminal: php env-kurulum.php
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require_once __DIR__.'/server_configuration.php';
$path = __DIR__.'/.env';
if (!is_file($path)) {
    fwrite(STDERR, "Mevcut .env bulunamadı. Önce .env.example içindeki veritabanı değerlerini doldurup .env adıyla kaydedin.\n"); exit(1);
}
$handle = fopen($path, 'c+');
if (!$handle || !flock($handle, LOCK_EX)) { fwrite(STDERR, ".env yazılamıyor. Dosya izinlerini kontrol edin.\n"); exit(1); }
try {
    $source = stream_get_contents($handle);
    $env = parseServerEnvironment($source);
    if (!serverConfig('DB_NAME') || !serverConfig('DB_USER')) throw new RuntimeException('DB_NAME/DB_USER (veya DB_DATABASE/DB_USERNAME) eksik. Veritabanı ayarlarını doldurun.');
    $defaults = [
        'DB_HOST'=>'localhost',
        'JWT_SECRET'=>bin2hex(random_bytes(32)),
        'ALLOWED_ORIGINS'=>'https://eliteagency.sbs,https://www.eliteagency.sbs,http://localhost:*,http://127.0.0.1:*',
        'GOOGLE_OAUTH_CLIENT_IDS'=>'73273804842-vq4fqlr07t8rhlgpituoka7nvnqltfba.apps.googleusercontent.com,73273804842-u0lcirptug9aotm2m6gn27g92hftt5ud.apps.googleusercontent.com',
        'APPLE_OAUTH_CLIENT_IDS'=>'com.oto.tag',
        'APPLE_BUNDLE_ID'=>'com.oto.tag',
        'ANDROID_PACKAGE_NAME'=>'com.oto.tag',
        'PUSHER_APP_ID'=>'2048564',
        'PUSHER_KEY'=>'7197ebfa7d2e68b962dd',
        'PUSHER_CLUSTER'=>'eu',
        'ONESIGNAL_APP_ID'=>'c12cca1e-ad0b-4d18-8746-661dc4cbdad9',
    ];
    $added = [];
    $append = '';
    foreach ($defaults as $key=>$value) {
        $existing = serverConfig($key);
        $invalidJwt = $key === 'JWT_SECRET' && (strlen($existing)<32 || preg_match('/^(REPLACE_|CHANGE_)/', $existing));
        if ($existing !== '' && !$invalidJwt) continue;
        $append .= $key.'="'.$value.'"'.PHP_EOL;
        $added[] = $key;
    }
    if ($append !== '') {
        fseek($handle, 0, SEEK_END);
        $append = PHP_EOL.'# OTOTAG sunucu ayarları'.PHP_EOL.$append;
        if (fwrite($handle, $append) !== strlen($append) || !fflush($handle)) throw new RuntimeException('.env kaydedilemedi.');
    }
    @chmod($path, 0600);
    echo $added ? 'Eklendi: '.implode(', ', $added).PHP_EOL : 'Gerekli ayarlar zaten mevcut.'.PHP_EOL;
    echo "Veritabanı değerleri ve mevcut servis anahtarları korundu. JWT_SECRET ilk kez eklendiyse uygulamada yeniden giriş yapın.\n";
    foreach (['PUSHER_SECRET','ONESIGNAL_REST_API_KEY','APPLE_SHARED_SECRET'] as $key) {
        if (!serverConfig($key)) echo "İlgili servis için ayrıca doldurun: $key\n";
    }
} catch (Throwable $e) { fwrite(STDERR, $e->getMessage().PHP_EOL); exit(1); }
finally { flock($handle, LOCK_UN); fclose($handle); }
