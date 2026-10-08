<?php
error_reporting(0);
ini_set('display_errors', 0);

require_once __DIR__ . '/server_configuration.php';
require_once __DIR__ . '/api_runtime.php';
set_exception_handler('apiUnhandledError');
$envPath = __DIR__ . '/.env';
$configurationError = null;
try { $env = readServerEnvironment($envPath); }
catch (RuntimeException $e) { $env = []; $configurationError = $e->getMessage(); }
$origin = $_SERVER['HTTP_ORIGIN'] ?? '';
$allowedOrigins = array_filter(array_map('trim', explode(',', serverConfig('ALLOWED_ORIGINS',
    'https://eliteagency.sbs,https://www.eliteagency.sbs,http://localhost:*,http://127.0.0.1:*'))));
if (apiOriginAllowed($origin, $allowedOrigins)) header('Access-Control-Allow-Origin: '.$origin);
header('Vary: Origin');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Cache-Control, Pragma, Origin, Accept, X-API-KEY');
header('Access-Control-Max-Age: 86400');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') { http_response_code(204); exit; }
try { apiValidateInput($_GET,$_POST); }
catch (InvalidArgumentException $e) { http_response_code(422); header('Content-Type: application/json; charset=utf-8'); echo apiJson(['status'=>'error','message'=>$e->getMessage()]); exit; }
if ($configurationError) {
    http_response_code(503); header('Content-Type: application/json; charset=UTF-8');
    echo json_encode(['status'=>'error','message'=>$configurationError], JSON_UNESCAPED_UNICODE); exit;
}
require_once __DIR__ . '/purchase_verification.php';
define('PUSHER_CLUSTER', serverConfig('PUSHER_CLUSTER', 'eu'));
define('PUSHER_SECRET', serverConfig('PUSHER_SECRET'));
define('PUSHER_KEY', serverConfig('PUSHER_KEY'));
define('PUSHER_APP_ID', serverConfig('PUSHER_APP_ID'));
define('DB_PASS', serverConfig('DB_PASS'));
define('DB_USER', serverConfig('DB_USER'));
define('DB_NAME', serverConfig('DB_NAME'));
define('DB_HOST', serverConfig('DB_HOST', 'localhost'));


if (empty($_GET['action']) && $_SERVER['REQUEST_METHOD'] === 'GET') {
    header("Content-Type: text/html; charset=UTF-8");
    echo '<!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>API Durumu</title><style>body{font-family:system-ui,-apple-system,sans-serif;margin:0;padding:20px;background:#f8fafc;color:#0f172a;display:flex;justify-content:center;align-items:center;min-height:100vh;} .card{background:#fff;padding:2rem;border-radius:1rem;box-shadow:0 10px 15px -3px rgba(0,0,0,0.1);width:100%;max-width:400px;text-align:center;} h1{color:#10b981;font-size:1.5rem;margin-bottom:0.5rem;} p{color:#64748b;font-size:1rem;}</style></head><body><div class="card"><h1>API Çevrimiçi</h1><p>Sistem optimize modda sorunsuz çalışıyor.</p></div></body></html>';
    exit;
}

header("Content-Type: application/json; charset=UTF-8");
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");
header("X-Content-Type-Options: nosniff");
header("X-Frame-Options: SAMEORIGIN");
header("X-XSS-Protection: 1; mode=block");

// --- SİBER GÜVENLİK (ANTI-HACK & ANTI-DDOS) MODÜLÜ ---
$request_uri = $_SERVER['REQUEST_URI'] ?? '';
if (preg_match('/\.(json|lock|env|git|sql|bak|log)$/i', parse_url($request_uri, PHP_URL_PATH))) {
    http_response_code(403);
    die(json_encode(["status" => "error", "message" => "Bu dosyaya doğrudan erişim yasaklanmıştır!"]));
}

// Katman 7 (L7) Anti-DDoS ve Akıllı IP Ban Sistemi (Mobil/Web Burst İstek Uyumlu)
$client_ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$trustedProxies=array_filter(array_map('trim',explode(',',serverConfig('TRUSTED_PROXY_IPS'))));
if (in_array($client_ip,$trustedProxies,true)) {
    $forwarded=$_SERVER['HTTP_CF_CONNECTING_IP'] ?? explode(',',$_SERVER['HTTP_X_FORWARDED_FOR'] ?? '')[0];
    if (filter_var(trim($forwarded),FILTER_VALIDATE_IP)) $client_ip=trim($forwarded);
}
if (strpos($client_ip, ',') !== false) {
    $client_ip = trim(explode(',', $client_ip)[0]);
}

$is_local = in_array($client_ip, ['127.0.0.1', '::1', 'localhost']) || preg_match('#^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.#', $client_ip);

// --- YEREL REDIS (127.0.0.1) ULTRA HIZLI BELLEK BAĞLANTISI ---
$redis = null;
try {
    if (class_exists('Redis')) {
        $redis = new Redis();
        $redis->connect('127.0.0.1', 6379, 1.5);
    }
} catch (Exception $e) {
    $redis = null;
}

// --- REDIS TABANLI ANTI-DDOS SİSTEMİ ---
$ban_key = 'ddos_ban_' . md5($client_ip);
$rate_key = 'rate_limit_' . md5($client_ip);

if (!$is_local && $redis) {
    // IP banlı mı kontrol et
    if ($redis->exists($ban_key)) {
        http_response_code(429);
        die(json_encode(["status" => "error", "message" => "DDoS Kalkanı: Çok fazla istek yapıldı, lütfen birkaç saniye bekleyin."]));
    }
    
    // İstek sayacını güvenli şekilde artır (Önce artırıp değeri sonra alıyoruz)
    $req_count = $redis->incr($rate_key);
    
    // Uygulama saatlerce arka planda kalırsa hatalı birikimi önlemek için TTL(-1) kontrolü
    if ($req_count == 1 || $redis->ttl($rate_key) === -1) {
        $redis->expire($rate_key, 3);
    }
    
    if ($req_count > 80) { 
        $redis->setex($ban_key, 25, time()); // 25 saniye boyunca banla
        $redis->del($rate_key); // Sonsuz loop ban döngüsünü kırmak için sayacı sıfırla
        http_response_code(429);
        die(json_encode(["status" => "error", "message" => "Sistem Koruması: Aşırı istek gönderildi. Lütfen bekleyin."]));
    }
}

// -----------------------------------------------------

$DB_HOST = DB_HOST;
$DB_NAME = DB_NAME;
$DB_USER = DB_USER;
$DB_PASS = DB_PASS;
$charset = 'utf8mb4';

$SYSTEM_API_KEY = '';
$JWT_SECRET = serverConfig('JWT_SECRET');
$missingConfiguration = [];
foreach (['DB_HOST'=>$DB_HOST, 'DB_NAME'=>$DB_NAME, 'DB_USER'=>$DB_USER] as $key=>$value) {
    if ($value === '') $missingConfiguration[] = $key;
}
if (strlen($JWT_SECRET)<32 || preg_match('/^(REPLACE_|CHANGE_)/', $JWT_SECRET)) $missingConfiguration[] = 'JWT_SECRET (en az 32 karakter)';
if ($missingConfiguration) {
    http_response_code(503);
    echo json_encode(['status'=>'error','message'=>'.env ayarları eksik: '.implode(', ', $missingConfiguration).'. Sunucu dizininde php env-kurulum.php çalıştırın.'], JSON_UNESCAPED_UNICODE); exit;
}

// --- WEBSOCKET / PUSHER INTEGRATION ---

function triggerPusherEvent($channel, $event, $data, $timeout = 6) {
    if (PUSHER_APP_ID === '' || PUSHER_KEY === '' || PUSHER_SECRET === '') return false;
    $auth_timestamp = time();
    $auth_version = '1.0';
    $body = json_encode(['name'=>$event, 'channels'=>[$channel], 'data'=>json_encode($data)]);
    $body_md5 = md5($body);
    $string_to_sign = "POST\n/apps/" . PUSHER_APP_ID . "/events\nauth_key=" . PUSHER_KEY . "&auth_timestamp=$auth_timestamp&auth_version=$auth_version&body_md5=$body_md5";
    $auth_signature = hash_hmac('sha256', $string_to_sign, PUSHER_SECRET);
    
    $url = "https://api-" . PUSHER_CLUSTER . ".pusher.com/apps/" . PUSHER_APP_ID . "/events?body_md5=$body_md5&auth_version=$auth_version&auth_key=" . PUSHER_KEY . "&auth_timestamp=$auth_timestamp&auth_signature=$auth_signature";
    
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    // Eşleşme sırasında WebSocket sinyallerinin kopmaması için süreler artırıldı
    curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);
    curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, min(5,$timeout));
    curl_setopt($ch, CURLOPT_NOSIGNAL, 1);
    curl_exec($ch);
    curl_close($ch);
}
// -------------------------------------- 

$dsn = "mysql:host=$DB_HOST;dbname=$DB_NAME;charset=$charset";
$options = [
    PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES   => false,
    PDO::ATTR_PERSISTENT         => false, // İstekler arasında PDO oturum durumunu paylaşma.
    PDO::ATTR_TIMEOUT            => 15,   // Veritabanı gecikmelerinde bağlantı kopmasını önlemek için süre artırıldı
];

class SmartPDOStatement extends PDOStatement {
    protected $pdo;
    protected $boundParams = [];
    private $errorLog = __DIR__ . '/db_errors.log';
    private $slowLog = __DIR__ . '/slow_queries.log';

    protected function __construct($pdo) {
        $this->pdo = $pdo;
    }

    #[\ReturnTypeWillChange]
    public function execute($params = null) {
        $start = microtime(true);
        try {
            $result = parent::execute($params);
            $this->logPerformance($this->queryString, $params ?? $this->boundParams, microtime(true) - $start);
            return $result;
        } catch (\PDOException $e) {
            // A deadlocked transaction must be retried as a whole, never as a single statement.
            $this->logError($this->queryString, $params ?? $this->boundParams, $e->getMessage());
            throw $e;
        }
    }

    #[\ReturnTypeWillChange]
    public function bindValue($param, $value, $type = PDO::PARAM_STR) {
        $this->boundParams[$param] = $value;
        return parent::bindValue($param, $value, $type);
    }

    #[\ReturnTypeWillChange]
    public function bindParam($param, &$variable, $type = PDO::PARAM_STR, $maxLength = 0, $driverOptions = null) {
        $this->boundParams[$param] = $variable;
        return parent::bindParam($param, $variable, $type, $maxLength, $driverOptions);
    }

    private function isRetryable(\PDOException $e) {
        $msg = $e->getMessage();
        return strpos($msg, 'server has gone away') !== false || strpos($msg, 'Deadlock found') !== false || strpos($msg, 'Lock wait timeout') !== false;
    }

    private function logPerformance($query, $params, $duration) {
        if ($duration > 0.5) {
            $time = date('Y-m-d H:i:s');
            $cleanQuery = trim(preg_replace('/\s+/', ' ', $query));
        $paramStr = ""; // Credentials, tokens and message bodies never enter SQL logs.
            @file_put_contents($this->slowLog, "[{$time}] YAVAŞ SORGU (" . round($duration, 4) . " sn): {$cleanQuery}{$paramStr}" . PHP_EOL, FILE_APPEND);
        }
    }

    private function logError($query, $params, $error) {
        $time = date('Y-m-d H:i:s');
        $cleanQuery = trim(preg_replace('/\s+/', ' ', $query));
        $paramStr = ""; // Credentials, tokens and message bodies never enter SQL logs.
        @file_put_contents($this->errorLog, "[{$time}] DB HATASI: {$error} | Sorgu: {$cleanQuery}{$paramStr}" . PHP_EOL, FILE_APPEND);
    }
}

class SmartPDO extends PDO {
    private $errorLog = __DIR__ . '/db_errors.log';
    private $slowLog = __DIR__ . '/slow_queries.log';
    
    public function __construct($dsn, $username, $password, $options) {
        parent::__construct($dsn, $username, $password, $options);
        // Tüm hazırlanan sorgularda SmartPDOStatement kullanılmasını sağla
        $this->setAttribute(PDO::ATTR_STATEMENT_CLASS, ['SmartPDOStatement', [$this]]);
    }

    #[\ReturnTypeWillChange]
    public function query($query, ?int $fetchMode = null, ...$fetchModeArgs) {
        $start = microtime(true);
        try {
            $stmt = ($fetchMode !== null) ? parent::query($query, $fetchMode, ...$fetchModeArgs) : parent::query($query);
            $this->logPerformance($query, microtime(true) - $start);
            return $stmt;
        } catch (\PDOException $e) {
            $this->logError($query, $e->getMessage());
            throw $e;
        }
    }

    #[\ReturnTypeWillChange]
    public function exec($statement) {
        $start = microtime(true);
        try {
            $result = parent::exec($statement);
            $this->logPerformance($statement, microtime(true) - $start);
            return $result;
        } catch (\PDOException $e) {
            $this->logError($statement, $e->getMessage());
            throw $e;
        }
    }

    private function isRetryable(\PDOException $e) {
        $msg = $e->getMessage();
        return strpos($msg, 'server has gone away') !== false || strpos($msg, 'Deadlock found') !== false || strpos($msg, 'Lock wait timeout') !== false;
    }

    private function logPerformance($query, $duration) {
        if ($duration > 0.5) {
            $time = date('Y-m-d H:i:s');
            $cleanQuery = trim(preg_replace('/\s+/', ' ', $query));
            @file_put_contents($this->slowLog, "[{$time}] YAVAŞ SORGU (" . round($duration, 4) . " sn): {$cleanQuery}" . PHP_EOL, FILE_APPEND);
        }
    }

    private function logError($query, $error) {
        $time = date('Y-m-d H:i:s');
        $cleanQuery = trim(preg_replace('/\s+/', ' ', $query));
        @file_put_contents($this->errorLog, "[{$time}] DB HATASI: {$error} | Sorgu: {$cleanQuery}" . PHP_EOL, FILE_APPEND);
    }
}

try {
    $pdo = new SmartPDO($dsn, $DB_USER, $DB_PASS, $options);
    date_default_timezone_set('Europe/Istanbul');
    $pdo->exec("SET time_zone = '+03:00'");
    // Gap-Lock kilitlemelerini kaldırarak tekil UPDATE/INSERT işlemlerini mikrosaniyeye düşürür
    $pdo->exec("SET SESSION tx_isolation = 'READ-COMMITTED'");
    
    $schemaInitLock = __DIR__ . '/.db_schema_v3_perf.lock';
    if (!file_exists($schemaInitLock)) {
       try {
            $indexList = [
                ['jobs', 'idx_jobs_status', 'status'],
                ['jobs', 'idx_jobs_customer', 'customer_id'],
                ['jobs', 'idx_jobs_provider', 'provider_id'],
                ['bids', 'idx_bids_job', 'job_id'],
                ['messages', 'idx_messages_job', 'job_id'],
                ['ratings', 'idx_ratings_provider', 'provider_id'],
                ['jobs', 'idx_jobs_prov_stat', 'provider_id, status'],
                ['jobs', 'idx_jobs_cust_stat', 'customer_id, status'],
                ['bids', 'idx_bids_job_prov', 'job_id, provider_id'],
                ['bids', 'idx_bids_status', 'status'],
                ['messages', 'idx_messages_recv_read', 'receiver_id, is_read'],
                ['users', 'idx_users_type_status', 'user_type, status']
            ];
            
            foreach ($indexList as $idx) {
                if (!$pdo->query("SHOW INDEX FROM {$idx[0]} WHERE Key_name = '{$idx[1]}'")->fetch()) {
                    $pdo->exec("CREATE INDEX {$idx[1]} ON {$idx[0]}({$idx[2]})");
                }
            }
            
            // app_telemetry tablosu ve indeksleri (INSERT yavaşlığını çözer)
            $pdo->exec("CREATE TABLE IF NOT EXISTS app_telemetry (
                id BIGINT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NULL,
                user_type VARCHAR(20) DEFAULT 'customer',
                event_type VARCHAR(50) NOT NULL,
                event_name VARCHAR(100) NOT NULL,
                screen_name VARCHAR(100) NOT NULL,
                duration_seconds INT DEFAULT 0,
                metadata JSON NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_telemetry_event_created (event_type, created_at),
                INDEX idx_telemetry_created (created_at)
            ) ENGINE=InnoDB");
            
            if (!$pdo->query("SHOW INDEX FROM app_telemetry WHERE Key_name = 'idx_telemetry_event_created'")->fetch()) {
                $pdo->exec("CREATE INDEX idx_telemetry_event_created ON app_telemetry(event_type, created_at)");
            }
        } catch (\Exception $indexEx) {}

        $pdo->exec("CREATE TABLE IF NOT EXISTS app_settings (
            setting_key VARCHAR(50) PRIMARY KEY,
            setting_value TEXT
        )");
        
        $pdo->exec("INSERT IGNORE INTO app_settings (setting_key, setting_value) VALUES 
            ('android_version', '1.0.31'), 
            ('ios_version', '1.0.31'), 
            ('force_update', '1'), 
            ('update_message', 'Ototag\'ın daha hızlı ve güvenli yeni sürümü yayında! Devam etmek için lütfen güncelleyin.')
        ");

        $pdo->exec("CREATE TABLE IF NOT EXISTS in_app_purchases (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            user_type ENUM('customer', 'provider', 'rentacar') DEFAULT 'customer',
            platform ENUM('google', 'apple') NOT NULL,
            product_id VARCHAR(150) NOT NULL,
            order_id VARCHAR(255) NULL,
            purchase_token TEXT NOT NULL,
            token_hash VARCHAR(64) NOT NULL,
            purchase_type VARCHAR(50) NOT NULL,
            status VARCHAR(50) DEFAULT 'completed',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX (user_id),
            INDEX (token_hash)
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS ads (
            id INT AUTO_INCREMENT PRIMARY KEY,
            title VARCHAR(255) NOT NULL,
            description TEXT,
            image_url TEXT,
            priority INT DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS banned_ips (
            id INT AUTO_INCREMENT PRIMARY KEY,
            ip_address VARCHAR(45) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS part_listings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            customer_id INT,
            city VARCHAR(100),
            part_name VARCHAR(255),
            car_model VARCHAR(255),
            description TEXT,
            status VARCHAR(50) DEFAULT 'searching',
            seller_id INT NULL,
            seller_type VARCHAR(50) NULL,
            agreed_price DECIMAL(10,2) NULL,
            price DECIMAL(10,2) NULL,
            photo1 VARCHAR(255) NULL,
            photo2 VARCHAR(255) NULL,
            photo3 VARCHAR(255) NULL,
            customer_deleted TINYINT(1) DEFAULT 0,
            seller_deleted TINYINT(1) DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");
        
        $pdo->exec("CREATE TABLE IF NOT EXISTS rentacar_listings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            company_id INT,
            city VARCHAR(100),
            car_brand_model VARCHAR(255),
            daily_price DECIMAL(10,2),
            description TEXT,
            photo VARCHAR(255),
            status VARCHAR(50) DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");
        
        $pdo->exec("CREATE TABLE IF NOT EXISTS rentacar_bids (
            id INT AUTO_INCREMENT PRIMARY KEY,
            listing_id INT,
            customer_id INT,
            amount DECIMAL(10,2),
            rent_days INT,
            status VARCHAR(50) DEFAULT 'pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS part_bids (
            id INT AUTO_INCREMENT PRIMARY KEY,
            listing_id INT,
            seller_id INT,
            seller_type VARCHAR(50),
            amount DECIMAL(10,2),
            status VARCHAR(50) DEFAULT 'pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");

        $pdo->exec("CREATE TABLE IF NOT EXISTS feedbacks (
            id INT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");

        @file_put_contents($schemaInitLock, date('Y-m-d H:i:s'));
    }

    // Google ve Apple OAuth Kolonlarını Kesin Olarak Aç ve Doğrula
    try {
        $colCheckMap = $pdo->query("SHOW COLUMNS FROM users LIKE 'map_link'")->fetch();
        if (!$colCheckMap) {
            $pdo->exec("ALTER TABLE users ADD COLUMN map_link VARCHAR(500) NULL");
        }
        
        $pdo->exec("CREATE TABLE IF NOT EXISTS rentacar_listings (
            id INT AUTO_INCREMENT PRIMARY KEY,
            company_id INT,
            city VARCHAR(100),
            car_brand_model VARCHAR(255),
            daily_price DECIMAL(10,2),
            description TEXT,
            photo VARCHAR(255),
            status VARCHAR(50) DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");
        
        $pdo->exec("CREATE TABLE IF NOT EXISTS rentacar_bids (
            id INT AUTO_INCREMENT PRIMARY KEY,
            listing_id INT,
            customer_id INT,
            amount DECIMAL(10,2),
            rent_days INT,
            status VARCHAR(50) DEFAULT 'pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");

        $colCheckPlate = $pdo->query("SHOW COLUMNS FROM rentacar_listings LIKE 'plate'")->fetch();
        if (!$colCheckPlate) {
            $pdo->exec("ALTER TABLE rentacar_listings ADD COLUMN plate VARCHAR(50) NULL AFTER company_id");
        }

        $colCheckModelYear = $pdo->query("SHOW COLUMNS FROM rentacar_listings LIKE 'model_year'")->fetch();
        if (!$colCheckModelYear) {
            $pdo->exec("ALTER TABLE rentacar_listings ADD COLUMN model_year VARCHAR(10) NULL AFTER car_brand_model");
            $pdo->exec("ALTER TABLE rentacar_listings ADD COLUMN photo1 VARCHAR(255) NULL AFTER description");
            $pdo->exec("ALTER TABLE rentacar_listings ADD COLUMN photo2 VARCHAR(255) NULL AFTER photo1");
            $pdo->exec("ALTER TABLE rentacar_listings ADD COLUMN photo3 VARCHAR(255) NULL AFTER photo2");
        }

        $colCheck1 = $pdo->query("SHOW COLUMNS FROM users LIKE 'oauth_provider'")->fetch();
        if (!$colCheck1) {
            $pdo->exec("ALTER TABLE users ADD COLUMN oauth_provider VARCHAR(50) NULL DEFAULT NULL");
        }
        $colCheck2 = $pdo->query("SHOW COLUMNS FROM users LIKE 'oauth_id'")->fetch();
        if (!$colCheck2) {
            $pdo->exec("ALTER TABLE users ADD COLUMN oauth_id VARCHAR(255) NULL DEFAULT NULL");
        }
        $colCheck3 = $pdo->query("SHOW COLUMNS FROM users LIKE 'email'")->fetch();
        if (!$colCheck3) {
            $pdo->exec("ALTER TABLE users ADD COLUMN email VARCHAR(255) NULL DEFAULT NULL");
        }
        
        // Kurumsal Usta Künyesi Kolonları
        $colCheck4 = $pdo->query("SHOW COLUMNS FROM users LIKE 'tow_plate'")->fetch();
        if (!$colCheck4) {
            $pdo->exec("ALTER TABLE users ADD COLUMN tow_plate VARCHAR(50) NULL DEFAULT '42 TAG 001'");
            $pdo->exec("ALTER TABLE users ADD COLUMN shop_address TEXT NULL");
            $pdo->exec("ALTER TABLE users ADD COLUMN shop_photo VARCHAR(255) NULL DEFAULT 'uploads/shop_default.jpg'");
            $pdo->exec("ALTER TABLE users ADD COLUMN is_id_verified TINYINT(1) DEFAULT 1");
            $pdo->exec("ALTER TABLE users ADD COLUMN is_tax_verified TINYINT(1) DEFAULT 1");
            $pdo->exec("ALTER TABLE users ADD COLUMN has_guarantee TINYINT(1) DEFAULT 1");
        }

        // Kayıt sistemi için zorunlu users kolonlarını garanti et
        $registrationColumns = [
            'service_category' => "VARCHAR(50) NULL DEFAULT 'none'",
            'iban' => "VARCHAR(34) NULL DEFAULT NULL",
            'tax_plate' => "VARCHAR(255) NULL DEFAULT NULL",
            'driver_license' => "VARCHAR(255) NULL DEFAULT NULL",
            'vehicle_photo' => "VARCHAR(255) NULL DEFAULT NULL",
            'equipment_photo' => "VARCHAR(255) NULL DEFAULT NULL",
            'tracking_code' => "VARCHAR(20) NULL DEFAULT NULL",
            'ip_address' => "VARCHAR(45) NULL DEFAULT NULL"
        ];

        foreach ($registrationColumns as $columnName => $columnDefinition) {
            $columnCheck = $pdo->query("SHOW COLUMNS FROM users LIKE " . $pdo->quote($columnName))->fetch();

            if (!$columnCheck) {
                $pdo->exec(
                    "ALTER TABLE users ADD COLUMN `" .
                    $columnName .
                    "` " .
                    $columnDefinition
                );
            }
        }

        // Rent a Car kullanıcıları için enum kolonunu güncelle (Data truncated hatası için)
        $typeColumn = $pdo->query("SHOW COLUMNS FROM users LIKE 'user_type'")->fetch();
        if ($typeColumn && strpos($typeColumn['Type'], "'rentacar'") === false && stripos($typeColumn['Type'], 'enum(') === 0) {
            $pdo->exec("ALTER TABLE users MODIFY COLUMN user_type ENUM('customer', 'provider', 'admin', 'rentacar') DEFAULT 'customer'");
        }

        // Şeffaf Kanıt & Arıza Görsel/Ses Kolonları
        $jobCol1 = $pdo->query("SHOW COLUMNS FROM jobs LIKE 'before_photo'")->fetch();
        if (!$jobCol1) {
            $pdo->exec("ALTER TABLE jobs ADD COLUMN before_photo VARCHAR(255) NULL");
            $pdo->exec("ALTER TABLE jobs ADD COLUMN after_photo VARCHAR(255) NULL");
            $pdo->exec("ALTER TABLE jobs ADD COLUMN issue_photo VARCHAR(255) NULL");
            $pdo->exec("ALTER TABLE jobs ADD COLUMN issue_audio VARCHAR(255) NULL");
        }
        $jobColConf = $pdo->query("SHOW COLUMNS FROM jobs LIKE 'is_evidence_confirmed'")->fetch();
        if (!$jobColConf) {
            $pdo->exec("ALTER TABLE jobs ADD COLUMN is_evidence_confirmed TINYINT(1) DEFAULT 0");
        }

        // Geçmiş ve Silme Kolonları (jobs)
        $jobColDel1 = $pdo->query("SHOW COLUMNS FROM jobs LIKE 'customer_deleted'")->fetch();
        if (!$jobColDel1) {
            $pdo->exec("ALTER TABLE jobs ADD COLUMN customer_deleted TINYINT(1) DEFAULT 0");
        }
        $jobColDel2 = $pdo->query("SHOW COLUMNS FROM jobs LIKE 'provider_deleted'")->fetch();
        if (!$jobColDel2) {
            $pdo->exec("ALTER TABLE jobs ADD COLUMN provider_deleted TINYINT(1) DEFAULT 0");
        }

        // Değerlendirme türü kolonu (ratings)
        try {
            $rateColCheck = $pdo->query("SHOW COLUMNS FROM ratings LIKE 'rater_type'")->fetch();
            if (!$rateColCheck) {
                $pdo->exec("ALTER TABLE ratings ADD COLUMN IF NOT EXISTS rater_type VARCHAR(20) DEFAULT 'customer'");
            }
        } catch (\Throwable $e) {}

        // İnceleme İtiraz Tablosu
        $pdo->exec("CREATE TABLE IF NOT EXISTS rating_appeals (
            id INT AUTO_INCREMENT PRIMARY KEY,
            rating_id INT NOT NULL,
            provider_id INT NOT NULL,
            reason TEXT NOT NULL,
            status ENUM('pending', 'approved', 'rejected') DEFAULT 'pending',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )");
        
        $idxCheck = $pdo->query("SHOW INDEX FROM users WHERE Key_name = 'idx_users_oauth'")->fetch();
        if (!$idxCheck) {
            $pdo->exec("CREATE INDEX idx_users_oauth ON users(oauth_provider, oauth_id)");
        }
    } catch (\Exception $oauthColEx) {}

    $user_ip = $client_ip;

    if (!empty($user_ip)) {
        $redisBanKey = "banned_ip_" . md5($user_ip);
        if ($redis && $redis->exists($redisBanKey)) {
            http_response_code(403);
            die(json_encode(["status" => "error", "message" => "Bu cihaz veya ağın sisteme erişimi kalıcı olarak engellenmiştir."]));
        }

        $ipCheck = $pdo->prepare("SELECT id FROM banned_ips WHERE ip_address = ?");
        $ipCheck->execute([$user_ip]);
        if ($ipCheck->fetch()) {
            if ($redis) {
                $redis->setex($redisBanKey, 86400, "1");
            }
            http_response_code(403);
            die(json_encode(["status" => "error", "message" => "Bu cihaz veya ağın sisteme erişimi kalıcı olarak engellenmiştir."]));
        }
    }
    

} catch (\PDOException $e) {
    error_log('OTOTAG database initialization failed (SQLSTATE '.($e->errorInfo[0] ?? $e->getCode()).').');
    http_response_code(503);
    die(apiJson(["status" => "error", "message" => "Sunucu geçici olarak kullanılamıyor. Lütfen tekrar deneyin."]));
}

function sendResponse($statusCode, $data) {
    $data = apiPublicResponse($statusCode, $data);
    http_response_code($statusCode); 
    header('Content-Type: application/json; charset=utf-8');
    echo apiJson($data);
    
    // PHP-FPM kullanılıyorsa HTTP yanıtını tamamla; ardından bu isteği sonlandır.
    if (function_exists('fastcgi_finish_request')) {
        fastcgi_finish_request();
    }
    exit;
}

function generateJWT($userId, $userType) {
    global $JWT_SECRET;
    $header = json_encode(['typ' => 'JWT', 'alg' => 'HS256']);
    $payload = json_encode([
        'user_id' => $userId,
        'user_type' => $userType,
        'iat' => time(),
        'exp' => time() + (86400 * 30) 
    ]);
    
    $base64UrlHeader = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($header));
    $base64UrlPayload = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($payload));
    $signature = hash_hmac('sha256', $base64UrlHeader . "." . $base64UrlPayload, $JWT_SECRET, true);
    $base64UrlSignature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
    
    return $base64UrlHeader . "." . $base64UrlPayload . "." . $base64UrlSignature;
}

function authenticateRequest($requestedUserId = null, $requireAdmin = false) {
    global $JWT_SECRET;
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $authHeader = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    foreach ($headers as $name=>$value) if (strtolower($name)==='authorization') $authHeader=$value;
    if (!preg_match('/^Bearer\s+(\S+)$/D', $authHeader, $matches)) {
        sendResponse(401, ['status'=>'error', 'message'=>'Lütfen giriş yapın.']);
    }

    $token = $matches[1];
    $tokenParts = explode('.', $token);
    if (count($tokenParts) !== 3) {
        sendResponse(401, ["status" => "error", "message" => "Geçersiz token yapısı."]);
    }

    $jwtHeader = json_decode(base64_decode(strtr($tokenParts[0], '-_', '+/'), true), true);
    if (!is_array($jwtHeader) || ($jwtHeader['alg'] ?? '') !== 'HS256') {
        sendResponse(401, ['status'=>'error', 'message'=>'Geçersiz oturum.']);
    }
    $signature = hash_hmac('sha256', $tokenParts[0] . "." . $tokenParts[1], $JWT_SECRET, true);
    $base64UrlSignature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));

    if (!hash_equals($base64UrlSignature, $tokenParts[2])) {
        sendResponse(401, ["status" => "error", "message" => "İmza doğrulanamadı. Token sahte."]);
    }

    $payload = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $tokenParts[1])), true);

    if (!is_array($payload) || !isset($payload['exp'], $payload['user_id'], $payload['user_type']) || !is_numeric($payload['exp']) || $payload['exp'] <= time() || (int)$payload['user_id'] < 1 || !in_array($payload['user_type'], ['customer','provider','rentacar','admin'], true)) {
        sendResponse(401, ["status" => "error", "message" => "Oturum süresi doldu, lütfen tekrar giriş yapın."]);
    }

    if ($requireAdmin && ($payload['user_type'] ?? '') !== 'admin') {
        sendResponse(403, ["status" => "error", "message" => "Bu işlem için yönetici yetkisi gereklidir."]);
    }

    if ($requestedUserId !== null && (string)$payload['user_id'] !== (string)$requestedUserId && ($payload['user_type'] ?? '') !== 'admin') {
        sendResponse(403, ["status" => "error", "message" => "Bu hesap veya kayıt üzerinde işlem yapma yetkiniz yok."]);
    }

    return $payload;
}

function deletePhysicalFile($relativePath) {
    if (empty($relativePath)) return;
    $cleanPath = ltrim($relativePath, '/');
    $fullPath = realpath(__DIR__ . '/' . $cleanPath);
    $uploadsDir = realpath(__DIR__ . '/uploads/');
    // Dizin atlama saldırılarını (Path Traversal) önler; yalnızca uploads dizinindeki dosyaları siler
    if ($fullPath && $uploadsDir && strpos($fullPath, $uploadsDir . DIRECTORY_SEPARATOR) === 0 && is_file($fullPath)) {
        @unlink($fullPath);
    }
}

function deletePartListingFiles($listing) {
    if (!$listing) return;
    $photos = ['photo1', 'photo2', 'photo3'];
    foreach ($photos as $photoKey) {
        if (!empty($listing[$photoKey])) {
            deletePhysicalFile($listing[$photoKey]);
        }
    }
}

function deleteJobMediaFiles($job) {
    if (!$job) return;
    $fields = ['before_photo', 'after_photo', 'issue_photo', 'issue_audio'];
    foreach ($fields as $f) {
        if (!empty($job[$f])) {
            deletePhysicalFile($job[$f]);
        }
    }
}

function deleteUserFiles($user) {
    $fields = ['tax_plate', 'driver_license', 'vehicle_photo', 'equipment_photo'];
    foreach ($fields as $field) {
        if (!empty($user[$field])) {
            deletePhysicalFile($user[$field]);
        }
    }
}

function isSafeFile($tmpName, $allowedExts) {
    if (!file_exists($tmpName)) return false;
    
    $content = file_get_contents($tmpName);
    if (preg_match('/<\?php|<\?=|<script\s+language\s*=\s*["\']?php/i', $content)) {
        return false;
    }
    
    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime = finfo_file($finfo, $tmpName);
    finfo_close($finfo);

    $allowedMimes = [
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' => 'image/heic',
        'mp4' => 'video/mp4',
        'mov' => 'video/quicktime',
        'pdf' => 'application/pdf',
        'doc' => 'application/msword',
        'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ];

    $validMimes = [];
    foreach ($allowedExts as $ext) {
        if (isset($allowedMimes[$ext])) {
            $validMimes[] = $allowedMimes[$ext];
        }
    }

    return in_array($mime, $validMimes);
}

function getGoogleAccessToken($serviceAccountPath) {
    if (!file_exists($serviceAccountPath)) return null;
    $auth = json_decode(file_get_contents($serviceAccountPath), true);
    if (!is_array($auth) || empty($auth['client_email']) || empty($auth['private_key'])) return null;
    
    $header = json_encode(['alg' => 'RS256', 'typ' => 'JWT']);
    $now = time();
    $payload = json_encode([
        'iss'   => $auth['client_email'],
        'scope' => 'https://www.googleapis.com/auth/androidpublisher',
        'aud'   => 'https://oauth2.googleapis.com/token',
        'exp'   => $now + 3600,
        'iat'   => $now
    ]);

    $base64UrlHeader  = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($header));
    $base64UrlPayload = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($payload));
    $dataToSign       = $base64UrlHeader . "." . $base64UrlPayload;

    $signature = '';
    if (!@openssl_sign($dataToSign, $signature, $auth['private_key'], 'SHA256')) return null;
    $base64UrlSignature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
    $jwt = $dataToSign . "." . $base64UrlSignature;

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 8); // Google yanıt vermezse PHP işlemini kurtar
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion'  => $jwt
    ]));
    $res = curl_exec($ch);
    curl_close($ch);
    
    $tokenData = json_decode($res, true);
    return $tokenData['access_token'] ?? null;
}

function verifyApplePurchase($receiptData, $productId) {
    $sharedSecret = serverConfig('APPLE_SHARED_SECRET'); 
    if (!trim($sharedSecret)) sendResponse(503,['status'=>'error','error_code'=>'APPLE_PURCHASE_CONFIGURATION','message'=>'Sunucunun Apple ödeme doğrulaması hazır değil. Yönetici abonelik ayarlarını kontrol etmeli.']);
    $endpoint = 'https://buy.itunes.apple.com/verifyReceipt';
    
    $postData = json_encode([
        'receipt-data' => $receiptData,
        'password' => $sharedSecret,
        'exclude-old-transactions' => true
    ]);

    $ch = curl_init($endpoint);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 8); // Apple gecikirse PHP işlemini kurtar
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($httpCode===0 || $httpCode===429 || $httpCode>=500) sendResponse(503,['status'=>'error','error_code'=>'STORE_TEMPORARILY_UNAVAILABLE','message'=>'Mağaza doğrulaması geçici olarak yanıt vermiyor. Satın alımları geri yüklemeyi tekrar deneyin.']);

    $data = json_decode($response, true);
    if (($data['status'] ?? null)===21004) sendResponse(503,['status'=>'error','error_code'=>'APPLE_PURCHASE_CONFIGURATION','message'=>'Apple ödeme doğrulama ayarı hatalı. Yönetici abonelik ayarlarını kontrol etmeli.']);
    
    if (isset($data['status']) && $data['status'] == 21007) {
        $endpoint = 'https://sandbox.itunes.apple.com/verifyReceipt';
        $ch = curl_init($endpoint);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 8);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $postData);
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($httpCode===0 || $httpCode===429 || $httpCode>=500) sendResponse(503,['status'=>'error','error_code'=>'STORE_TEMPORARILY_UNAVAILABLE','message'=>'Mağaza doğrulaması geçici olarak yanıt vermiyor. Satın alımları geri yüklemeyi tekrar deneyin.']);
        $data = json_decode($response, true);
    }

    if (($data['status'] ?? null)===21004) sendResponse(503,['status'=>'error','error_code'=>'APPLE_PURCHASE_CONFIGURATION','message'=>'Apple ödeme doğrulama ayarı hatalı. Yönetici abonelik ayarlarını kontrol etmeli.']);
    if (in_array((int)($data['status'] ?? -1),[21005,21009,21100],true)) sendResponse(503,['status'=>'error','error_code'=>'STORE_TEMPORARILY_UNAVAILABLE','message'=>'Mağaza doğrulaması geçici olarak yanıt vermiyor. Satın alımları geri yüklemeyi tekrar deneyin.']);

    if (isset($data['status']) && $data['status'] == 0) {
        return normalizeAppleSubscription($data, $productId, serverConfig('APPLE_BUNDLE_ID','com.oto.tag'));
    }
    
    return false;
}

function verifyGooglePurchase($packageName, $productId, $token, $isSubscription = false) {
    $keyPath = serverConfig('GOOGLE_SERVICE_ACCOUNT_PATH', __DIR__ . '/thinking-league-508210-h4-5402aee1b450.json');
    if (!is_readable($keyPath)) sendResponse(503,['status'=>'error','error_code'=>'GOOGLE_PURCHASE_CONFIGURATION','message'=>'Sunucunun Google Play ödeme doğrulaması hazır değil. Yönetici mağaza bağlantısını kontrol etmeli.']);
    $accessToken = getGoogleAccessToken($keyPath);
    if (!$accessToken) sendResponse(503,['status'=>'error','error_code'=>'GOOGLE_PURCHASE_CONFIGURATION','message'=>'Sunucunun Google Play doğrulama bağlantısı kurulamadı. Yönetici mağaza bağlantısını kontrol etmeli.']);

    if ($packageName!==serverConfig('ANDROID_PACKAGE_NAME','com.oto.tag')) return false;
    $packageName=rawurlencode($packageName); $productId=rawurlencode($productId); $token=rawurlencode($token);
    if ($isSubscription) {
        $url = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{$packageName}/purchases/subscriptions/{$productId}/tokens/{$token}";
    } else {
        $url = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{$packageName}/purchases/products/{$productId}/tokens/{$token}";
    }

    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 8); // Google Play API yavaşlarsa sunucunun çökmesini engelle
    curl_setopt($ch, CURLOPT_HTTPHEADER, [
        'Authorization: Bearer ' . $accessToken,
        'Accept: application/json'
    ]);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if (in_array($httpCode,[401,403],true)) sendResponse(503,['status'=>'error','error_code'=>'GOOGLE_PURCHASE_CONFIGURATION','message'=>'Google Play doğrulama erişimi yok. Yönetici mağaza bağlantısının yetkilerini kontrol etmeli.']);
    if ($httpCode===0 || $httpCode===429 || $httpCode>=500) sendResponse(503,['status'=>'error','error_code'=>'STORE_TEMPORARILY_UNAVAILABLE','message'=>'Mağaza doğrulaması geçici olarak yanıt vermiyor. Satın alımları geri yüklemeyi tekrar deneyin.']);

    if ($httpCode === 200) {
        $data=json_decode($response,true);
        return $isSubscription ? normalizeGoogleSubscription($data) : (($data['purchaseState'] ?? -1)===0 ? $data : false);
    }
    return false;
}

function sendOneSignalPush($targetUsers, $title, $message, $data = []) {
    global $pdo;
    try {
        return notificationQueue($pdo,$targetUsers,$title,$message,$data);
    } catch (Throwable $e) { error_log('Notification could not be queued.'); return false; }
}

$input_data = json_decode(file_get_contents("php://input"), true);
if (is_array($input_data)) {
    $_POST = array_merge($_POST, $input_data);
}

$action = $_GET['action'] ?? '';
$method = $_SERVER['REQUEST_METHOD'];

require_once __DIR__.'/registration_rules.php';
require_once __DIR__.'/service_matching.php';
require_once __DIR__.'/referral_rewards.php';
require_once __DIR__.'/growth_features.php';
require_once __DIR__.'/map_routing.php';
require_once __DIR__ . '/oauth_verification.php';
require_once __DIR__ . '/api_authorization.php';
authorizeApiAction($pdo, $action, $method);
require_once __DIR__ . '/app_updates.php';
require_once __DIR__.'/notification_delivery.php';
notificationEnsureSchema($pdo);
register_shutdown_function(function() use($pdo) {
    if ($pdo->inTransaction() || empty($GLOBALS['notification_queued']) || !function_exists('fastcgi_finish_request')) return;
    fastcgi_finish_request();
    try { notificationDrain($pdo,5); } catch (Throwable $e) { error_log('Notification queue will retry via worker.'); }
});
handleAppUpdateAction($pdo, $action, $method);
require_once __DIR__ . '/rentacar_api.php';
handleRentalAction($pdo, $action, $method);

switch ($action) {
    case 'get_reward_catalog':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $actor=authenticateRequest();
        ensureGrowthSchema($pdo);
        $stmt=$pdo->prepare('SELECT reward_points FROM users WHERE id=?'); $stmt->execute([$actor['user_id']]);
        sendResponse(200,['status'=>'success','reward_points'=>(int)$stmt->fetchColumn(),'items'=>growthRewardCatalog($actor['user_type'])]);
        break;
    case 'redeem_reward':
        if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $actor=authenticateRequest();
        try { sendResponse(200,growthRedeemReward($pdo,(int)$actor['user_id'],trim($_POST['reward_code'] ?? ''))); }
        catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        break;
    case 'get_price_quote':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        authenticateRequest();
        $service=trim($_GET['service_type'] ?? 'mechanic');
        $distance=(float)($_GET['distance_km'] ?? 0);
        sendResponse(200,['status'=>'success','quote'=>growthPriceQuote($service,$distance,$_GET['hour'] ?? null)]);
        break;
    case 'get_favorite_providers':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $actor=authenticateRequest();
        if($actor['user_type']!=='customer') sendResponse(403,['status'=>'error','message'=>'Müşteri hesabı gereklidir.']);
        sendResponse(200,['status'=>'success','providers'=>growthFavoriteList($pdo,(int)$actor['user_id'])]);
        break;
    case 'toggle_favorite_provider':
        if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $actor=authenticateRequest();
        if($actor['user_type']!=='customer') sendResponse(403,['status'=>'error','message'=>'Müşteri hesabı gereklidir.']);
        try {
            $favorite=growthToggleFavorite($pdo,(int)$actor['user_id'],(int)($_POST['provider_id'] ?? 0));
            sendResponse(200,['status'=>'success','favorite'=>$favorite]);
        } catch(InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        break;
    case 'growth_analytics':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $actor=authenticateRequest();
        if($actor['user_type']!=='admin') sendResponse(403,['status'=>'error','message'=>'Yönetici yetkisi gereklidir.']);
        sendResponse(200,['status'=>'success','analytics'=>growthAnalytics($pdo)]);
        break;
    case 'get_referral_summary':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $userId=(int)($_GET['user_id'] ?? 0);
        if ($userId<=0) sendResponse(400,['status'=>'error','message'=>'Kullanıcı bilgisi eksik.']);
        sendResponse(200,referralSummary($pdo,$userId));
        break;
    case 'get_my_subscriptions':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        require_once __DIR__.'/subscription_summary.php';
        ensureBusinessSubscriptionSchema($pdo);
        $stmt=$pdo->prepare('SELECT * FROM users WHERE id=?'); $stmt->execute([$_GET['user_id']]);
        $user=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$user) sendResponse(404,['status'=>'error','message'=>'Hesap bulunamadı.']);
        sendResponse(200,subscriptionSummary($user));
        break;
    case 'get_ads':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        try {
            $adsCacheKey = "ads_list_cache";
            if ($redis) {
                $cachedAds = $redis->get($adsCacheKey);
                if ($cachedAds) {
                    sendResponse(200, ["status" => "success", "ads" => availableAdImages(json_decode($cachedAds, true) ?: [], __DIR__)]);
                }
            }

            $stmt = $pdo->query("SELECT * FROM ads ORDER BY priority ASC, id DESC");
            $ads = $stmt->fetchAll();
            $ads = availableAdImages($ads, __DIR__);
            if ($redis) {
                $redis->setex($adsCacheKey, 300, json_encode($ads));
            }
            sendResponse(200, ["status" => "success", "ads" => $ads]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Reklamlar alınamadı."]);
        }
        break;
        
    case 'get_directions':
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $actor=authenticateRequest();
        $job=apiJob($pdo,$_GET['job_id'] ?? 0,$actor);
        if (!in_array($job['status'],['matched','accepted','approved','in_progress','customer_paid'],true)) sendResponse(409,['status'=>'error','message'=>'Rota için aktif bir eşleşme gerekir.']);
        try {
            $origin=routeCoordinates($_GET['origin'] ?? '');
            // Pickup destination belongs to the authorized job, never a client-supplied third-party address.
            $destination=[serviceCoordinate($job['latitude']),serviceCoordinate($job['longitude'],false)];
        } catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        $mapProvider=($_GET['map_provider'] ?? 'google')==='apple' ? 'apple' : 'google';
        $cacheKey='road_route_'.hash('sha256',json_encode([$actor['user_id'],$job['id'],$origin,$destination,$mapProvider]));
        if ($redis && ($cached=$redis->get($cacheKey))) sendResponse(200,json_decode($cached,true));
        // Bound requests per account, independent of the requested coordinates.
        $rateFile=sys_get_temp_dir().'/ototag_route_'.hash('sha256',__DIR__.'|'.$actor['user_id']).'.lock';
        $handle=@fopen($rateFile,'c+');
        if (!$handle || !flock($handle,LOCK_EX|LOCK_NB)) sendResponse(429,['status'=>'error','message'=>'Rota hesaplanıyor. Biraz sonra tekrar deneyin.']);
        $last=(int)stream_get_contents($handle);
        if ($last && time()-$last<5) { flock($handle,LOCK_UN); fclose($handle); sendResponse(429,['status'=>'error','message'=>'Rota kısa süre önce güncellendi.']); }
        rewind($handle); ftruncate($handle,0); fwrite($handle,(string)time());
        try { $route=calculateServiceRoute($origin,$destination,$mapProvider); }
        finally { flock($handle,LOCK_UN); fclose($handle); }
        if (!$route) sendResponse(503,['status'=>'error','message'=>'Yol rotası alınamadı. Apple/Google Haritalar ile navigasyonu açabilir veya tekrar deneyebilirsiniz.']);
        if ($redis && $route['source']!=='google') $redis->setex($cacheKey,45,json_encode($route));
        sendResponse(200,$route);
        break;

    case 'add_ad':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $title = isset($_POST['title']) ? trim($_POST['title']) : null;
        $description = isset($_POST['description']) ? trim($_POST['description']) : null;
        $image_url = isset($_POST['image_url']) ? trim($_POST['image_url']) : null;
        $priority = isset($_POST['priority']) ? (int)$_POST['priority'] : 1;

        if (!$title) sendResponse(400, ["status" => "error", "message" => "Başlık gerekli."]);

        if (isset($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
            $upload_dir = __DIR__ . '/uploads/ads/';
            if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);

            $ext = strtolower(pathinfo($_FILES['image']['name'], PATHINFO_EXTENSION));
            $allowed_exts = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
            
            if (in_array($ext, $allowed_exts) && isSafeFile($_FILES['image']['tmp_name'], $allowed_exts)) {
                $filename = time() . '_ad_' . uniqid() . '.' . $ext;
                if (@move_uploaded_file($_FILES['image']['tmp_name'], $upload_dir . $filename)) {
                    $image_url = 'uploads/ads/' . $filename;
                }
            }
        }

        if (empty($image_url)) $image_url = null;

        try {
            $stmt = $pdo->prepare("INSERT INTO ads (title, description, image_url, priority) VALUES (?, ?, ?, ?)");
            $stmt->execute([$title, $description, $image_url, $priority]);
            if ($redis) { $redis->del("ads_list_cache"); }
            sendResponse(201, ["status" => "success", "message" => "Reklam başarıyla eklendi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Reklam eklenemedi."]);
        }
        break;

    case 'edit_ad':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $ad_id = $_POST['ad_id'] ?? null;
        $title = isset($_POST['title']) ? trim($_POST['title']) : null;
        $description = isset($_POST['description']) ? trim($_POST['description']) : null;
        $image_url = isset($_POST['image_url']) ? trim($_POST['image_url']) : null;
        $priority = isset($_POST['priority']) ? (int)$_POST['priority'] : 1;

        if (!$ad_id || !$title) sendResponse(400, ["status" => "error", "message" => "ID ve başlık gerekli."]);

        if (isset($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
            $upload_dir = __DIR__ . '/uploads/ads/';
            if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);

            $ext = strtolower(pathinfo($_FILES['image']['name'], PATHINFO_EXTENSION));
            $allowed_exts = ['jpg', 'jpeg', 'png', 'webp', 'gif'];
            if (in_array($ext, $allowed_exts) && isSafeFile($_FILES['image']['tmp_name'], $allowed_exts)) {
                $filename = time() . '_ad_' . uniqid() . '.' . $ext;
                if (@move_uploaded_file($_FILES['image']['tmp_name'], $upload_dir . $filename)) {
                    $image_url = 'uploads/ads/' . $filename;
                }
            }
        }

        try {
            $stmt = $pdo->prepare("UPDATE ads SET title = ?, description = ?, image_url = ?, priority = ? WHERE id = ?");
            $stmt->execute([$title, $description, $image_url, $priority, $ad_id]);
            if ($redis) { $redis->del("ads_list_cache"); }
            sendResponse(200, ["status" => "success", "message" => "Reklam başarıyla güncellendi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Reklam güncellenemedi."]);
        }
        break;

    case 'delete_ad':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $ad_id = $_POST['ad_id'] ?? null;
        if (!$ad_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $stmtImg = $pdo->prepare("SELECT image_url FROM ads WHERE id = ?");
            $stmtImg->execute([$ad_id]);
            $adData = $stmtImg->fetch();
            if ($adData && !empty($adData['image_url'])) {
                $normalizedPath = realpath(__DIR__ . '/' . ltrim($adData['image_url'], '/'));
                $uploadsDir = realpath(__DIR__ . '/uploads/');
                if ($normalizedPath && $uploadsDir && strpos($normalizedPath, $uploadsDir) === 0 && is_file($normalizedPath)) {
                    @unlink($normalizedPath);
                }
            }
            $stmt = $pdo->prepare("DELETE FROM ads WHERE id = ?");
            $stmt->execute([$ad_id]);
            if ($redis) { $redis->del("ads_list_cache"); }
            sendResponse(200, ["status" => "success", "message" => "Reklam silindi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Reklam silinemedi."]);
        }
        break;

    case 'create_part_listing':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $customer_id = $_POST['customer_id'] ?? null;
        $city = $_POST['city'] ?? null;
        $part_name = $_POST['part_name'] ?? null;
        $car_model = $_POST['car_model'] ?? null;
        $description = $_POST['description'] ?? '';
        $price = isset($_POST['price']) ? (float)str_replace(',', '.', $_POST['price']) : null;
        $is_selling = strpos($part_name, '[SATILIK]') !== false;

        if (!$customer_id || !$city || !$part_name || !$car_model) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $photo1 = null; $photo2 = null; $photo3 = null;
        
        if ($is_selling) {
            if (!$price || $price <= 0) sendResponse(400, ["status" => "error", "message" => "Satılık ilanlar için geçerli bir fiyat girmelisiniz."]);
            
            $upload_dir = __DIR__ . '/uploads/parts/';
            if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);

            $uploadPartFile = function($fileKey, $dir) {
                if (isset($_FILES[$fileKey]) && $_FILES[$fileKey]['error'] === UPLOAD_ERR_OK) {
                    $ext = strtolower(pathinfo($_FILES[$fileKey]['name'], PATHINFO_EXTENSION));
                    if (empty($ext)) $ext = 'jpg'; 
                    
                    $allowed_exts = ['jpg', 'jpeg', 'png', 'webp', 'heic'];
                    if (in_array($ext, $allowed_exts) && isSafeFile($_FILES[$fileKey]['tmp_name'], $allowed_exts)) {
                        $filename = time() . '_' . $fileKey . '_' . uniqid() . '.' . $ext;
                        if (@move_uploaded_file($_FILES[$fileKey]['tmp_name'], $dir . $filename)) {
                            return 'uploads/parts/' . $filename;
                        }
                    }
                }
                return null;
            };

            $photo1 = $uploadPartFile('photo1', $upload_dir);
            $photo2 = $uploadPartFile('photo2', $upload_dir);
            $photo3 = $uploadPartFile('photo3', $upload_dir);

            if (!$photo1 || !$photo2) {
                sendResponse(400, ["status" => "error", "message" => "Satılık ilanlar için en az 2 fotoğraf yüklemelisiniz."]);
            }
        }
        
        try {
            $stmt = $pdo->prepare("INSERT INTO part_listings (customer_id, city, part_name, car_model, description, status, price, photo1, photo2, photo3) VALUES (?, ?, ?, ?, ?, 'searching', ?, ?, ?, ?)");
            $stmt->execute([$customer_id, $city, $part_name, $car_model, $description, $price, $photo1, $photo2, $photo3]);
            sendResponse(201, ["status" => "success", "message" => "İlan oluşturuldu."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "İlan oluşturulamadı."]);
        }
        break;

    case 'get_part_listings':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        if (authenticateRequest()['user_type']==='admin') {
            require_once __DIR__.'/admin_management.php';
            try { sendResponse(200,adminPartListings($pdo,$_GET)); }
            catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        }
        $user_id = isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0;
        $city = $_GET['city'] ?? null;
        
        try {
            $cityCond = empty($city) ? "" : "AND p.city = :city";
            $sqlMarket = "SELECT p.*, u.name as customer_name, u.phone as customer_phone, 
                          (SELECT status FROM part_bids WHERE listing_id = p.id AND seller_id = :uid1 ORDER BY id DESC LIMIT 1) as my_bid_status 
                          FROM part_listings p LEFT JOIN users u ON p.customer_id = u.id WHERE p.status = 'searching' AND p.customer_id != :uid2 AND p.customer_deleted = 0 $cityCond ORDER BY p.id DESC LIMIT 100";
            
            $stmtMarket = $pdo->prepare($sqlMarket);
            $stmtMarket->bindValue(':uid1', $user_id);
            $stmtMarket->bindValue(':uid2', $user_id);
            if (!empty($city)) $stmtMarket->bindValue(':city', $city);
            $stmtMarket->execute();
            $market = $stmtMarket->fetchAll();

            $stmtMy = $pdo->prepare("SELECT p.*, u.name as seller_name, u.phone as seller_phone FROM part_listings p LEFT JOIN users u ON p.seller_id = u.id WHERE p.customer_id = ? AND p.customer_deleted = 0 ORDER BY p.id DESC");
            $stmtMy->execute([$user_id]);
            $myListings = $stmtMy->fetchAll();
            
            foreach ($myListings as &$listing) {
                if ($listing['status'] === 'searching') {
                    $stmtBids = $pdo->prepare("SELECT b.*, u.name as seller_name FROM part_bids b LEFT JOIN users u ON b.seller_id = u.id WHERE b.listing_id = ? AND b.status = 'pending'");
                    $stmtBids->execute([$listing['id']]);
                    $listing['bids'] = $stmtBids->fetchAll();
                }
            }

            $stmtSales = $pdo->prepare("
                SELECT p.*, u.name as customer_name, u.phone as customer_phone, 
                       (SELECT status FROM part_bids WHERE listing_id = p.id AND seller_id = ? ORDER BY id DESC LIMIT 1) as my_bid_status
                FROM part_listings p 
                LEFT JOIN users u ON p.customer_id = u.id 
                WHERE p.id IN (SELECT listing_id FROM part_bids WHERE seller_id = ?) 
                AND p.seller_deleted = 0 
                ORDER BY p.id DESC
            ");
            $stmtSales->execute([$user_id, $user_id]);
            $mySales = $stmtSales->fetchAll();

            sendResponse(200, [
                "status" => "success", 
                "market" => $market,
                "my_listings" => $myListings,
                "my_sales" => $mySales
            ]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Veriler alınamadı."]);
        }
        break;

    case 'place_part_bid':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $listing_id = $_POST['listing_id'] ?? null;
        $seller_id = $_POST['seller_id'] ?? null;
        $seller_type = $_POST['seller_type'] ?? null;
        $amount = isset($_POST['amount']) ? (float)str_replace(',', '.', $_POST['amount']) : 0;
        
        if (!$listing_id || !$seller_id || $amount <= 0) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        $checkPending = $pdo->prepare("SELECT id FROM part_bids WHERE listing_id = ? AND seller_id = ? AND status = 'pending'");
        $checkPending->execute([$listing_id, $seller_id]);
        if ($checkPending->fetch()) {
            sendResponse(400, ["status" => "error", "message" => "Bu ilana zaten bekleyen bir teklifiniz var. Lütfen yanıt bekleyin."]);
        }

        try {
            $stmt = $pdo->prepare("INSERT INTO part_bids (listing_id, seller_id, seller_type, amount, status) VALUES (?, ?, ?, ?, 'pending')");
            $stmt->execute([$listing_id, $seller_id, $seller_type, $amount]);
            
            try {
                $listInfo = $pdo->prepare("SELECT customer_id, seller_id FROM part_listings WHERE id = ?");
                $listInfo->execute([$listing_id]);
                $listData = $listInfo->fetch();
                if ($listData) {
                    $target_user = null;
                    if (!empty($listData['customer_id']) && $listData['customer_id'] != $seller_id) {
                        $target_user = $listData['customer_id'];
                    } elseif (!empty($listData['seller_id']) && $listData['seller_id'] != $seller_id) {
                        $target_user = $listData['seller_id'];
                    }

                    if ($target_user) {
                        $pdo->prepare("INSERT INTO notifications (user_id, title, message) VALUES (?, ?, ?)")
                            ->execute([(int)$target_user, "Pazarda Yeni Teklif", "İlanınıza ".$amount." ₺ teklif geldi!"]);

                        triggerPusherEvent("private-user_".$target_user, "new_part_bid", [
                            "listing_id" => $listing_id,
                            "amount" => $amount,
                            "message" => "İlanınıza ".$amount." ₺ teklif geldi!"
                        ]);
                        sendOneSignalPush($target_user,'Pazarda Yeni Teklif',
                            'Yedek parça ilanınıza '.$amount.' ₺ tutarında yeni bir teklif geldi!',
                            ['type'=>'new_part_bid','listing_id'=>(string)$listing_id]);
                    }
                }
            } catch (Exception $e) {}

            sendResponse(201, ["status" => "success", "message" => "Teklif verildi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Teklif oluşturulamadı."]);
        }
        break;

    case 'accept_part_bid':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $listing_id = $_POST['listing_id'] ?? null;
        $bid_id = $_POST['bid_id'] ?? null;
        $amount = $_POST['amount'] ?? null;
        
        if (!$listing_id || !$bid_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        try {
            $pdo->beginTransaction();
            $stmtBid = $pdo->prepare("SELECT seller_id, seller_type, amount FROM part_bids WHERE id = ?");
            $stmtBid->execute([$bid_id]);
            $bid = $stmtBid->fetch();

            if ($bid) {
                if (empty($amount)) $amount = $bid['amount'];

                $pdo->prepare("UPDATE part_listings SET status = 'matched', seller_id = ?, seller_type = ?, agreed_price = ? WHERE id = ?")
                    ->execute([$bid['seller_id'], $bid['seller_type'], $amount, $listing_id]);
                
                $pdo->prepare("UPDATE part_bids SET status = 'accepted' WHERE id = ?")->execute([$bid_id]);
                $pdo->prepare("UPDATE part_bids SET status = 'rejected' WHERE listing_id = ? AND id != ?")->execute([$listing_id, $bid_id]);

                // İlan bilgisini ve ilan sahibinin adını al
                $listStmt = $pdo->prepare("SELECT p.part_name, p.customer_id, u.name as customer_name FROM part_listings p LEFT JOIN users u ON p.customer_id = u.id WHERE p.id = ?");
                $listStmt->execute([$listing_id]);
                $listInfo = $listStmt->fetch();

                $bidder_id = (string)$bid['seller_id'];
                $cleanTitle = "Teklifiniz Kabul Edildi! 🎉";
                $cleanMsg = ($listInfo['part_name'] ?? 'İlan') . " için verdiğiniz " . $amount . " ₺ tutarındaki teklif kabul edildi. İletişim bilgileri açıldı!";

                // 1. Kullanıcının Bildirimler Tablosuna Kaydet
                $pdo->prepare("INSERT INTO notifications (user_id, title, message) VALUES (?, ?, ?)")
                    ->execute([(int)$bidder_id, $cleanTitle, $cleanMsg]);

                // Tablo kilitlerini dış ağ cURL çağrılarından ÖNCE serbest bırak
                $pdo->commit();

                // 2. Pusher Anlık Canlı Soket Bildirimi
                triggerPusherEvent("user_" . $bidder_id, "part_bid_accepted", [
                    "listing_id" => $listing_id,
                    "amount" => $amount,
                    "message" => $cleanMsg
                ]);

                // 3. OneSignal Arka Plan Push Bildirimi
                sendOneSignalPush(
                    $bidder_id,
                    $cleanTitle,
                    $cleanMsg,
                    ['type' => 'part_bid_accepted', 'listing_id' => (string)$listing_id]
                );
            } else {
                $pdo->commit();
            }

            sendResponse(200, ["status" => "success", "message" => "Teklif kabul edildi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız oldu."]);
        }
        break;

    case 'reject_part_bid':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $bid_id = $_POST['bid_id'] ?? null;
        if (!$bid_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $pdo->prepare("UPDATE part_bids SET status = 'rejected' WHERE id = ?")->execute([$bid_id]);
            
            $bidInfo = $pdo->prepare("SELECT b.seller_id, b.amount, p.part_name, p.id as listing_id FROM part_bids b JOIN part_listings p ON b.listing_id = p.id WHERE b.id = ?");
            $bidInfo->execute([$bid_id]);
            $bidData = $bidInfo->fetch();
            
            if ($bidData) {
                $bidder_id = (string)$bidData['seller_id'];
                $msgTitle = "Teklifiniz Reddedildi";
                $msgBody = $bidData['part_name'] . " ilanı için verdiğiniz " . $bidData['amount'] . " ₺ tutarındaki teklif maalesef reddedildi.";
                
                $pdo->prepare("INSERT INTO notifications (user_id, title, message) VALUES (?, ?, ?)")->execute([(int)$bidder_id, $msgTitle, $msgBody]);
                
                triggerPusherEvent("private-user_" . $bidder_id, "part_bid_rejected", [
                    "listing_id" => $bidData['listing_id'],
                    "message" => $msgBody
                ]);
                
                sendOneSignalPush($bidder_id, $msgTitle, $msgBody, ['type' => 'part_bid_rejected', 'listing_id' => (string)$bidData['listing_id']]);
            }

            sendResponse(200, ["status" => "success", "message" => "Teklif reddedildi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız oldu."]);
        }
        break;

    case 'complete_part_trade':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $listing_id = $_POST['listing_id'] ?? null;
        if (!$listing_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $pdo->prepare("UPDATE part_listings SET status = 'completed' WHERE id = ?")->execute([$listing_id]);
            sendResponse(200, ["status" => "success", "message" => "İşlem başarıyla tamamlandı."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Güncelleme başarısız."]);
        }
        break;

    case 'delete_part_record':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $listing_id = $_POST['listing_id'] ?? null;
        $user_id = $_POST['user_id'] ?? null;

        if (!$listing_id || !$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $stmt = $pdo->prepare("SELECT customer_id, seller_id, status, photo1, photo2, photo3, seller_deleted FROM part_listings WHERE id = ?");
            $stmt->execute([$listing_id]);
            $listing = $stmt->fetch();

            if ($listing) {
                if ($listing['customer_id'] == $user_id) {
                    if ($listing['status'] === 'searching') {
                        // İlan aranırken silindiyse fotoğrafları anında sunucudan kaldır ve kaydı sil
                        deletePartListingFiles($listing);
                        $pdo->prepare("DELETE FROM part_bids WHERE listing_id = ?")->execute([$listing_id]);
                        $pdo->prepare("DELETE FROM part_listings WHERE id = ?")->execute([$listing_id]);
                    } else {
                        // Satıcı da silmişse veya satıcı atanmamışsa dosyaları diskten sil ve kaydı kaldır
                        if ((int)($listing['seller_deleted'] ?? 0) === 1 || empty($listing['seller_id'])) {
                            deletePartListingFiles($listing);
                            $pdo->prepare("DELETE FROM part_bids WHERE listing_id = ?")->execute([$listing_id]);
                            $pdo->prepare("DELETE FROM part_listings WHERE id = ?")->execute([$listing_id]);
                        } else {
                            $pdo->prepare("UPDATE part_listings SET customer_deleted = 1 WHERE id = ?")->execute([$listing_id]);
                        }
                    }
                    sendResponse(200, ["status" => "success", "message" => "İlan ve fotoğrafları sunucudan temizlendi."]);
                } elseif ($listing['seller_id'] == $user_id) {
                    // Satıcı sildiğinde müşteri zaten silmişse fotoğrafları sunucudan tamamen kaldır
                    $custDelStmt = $pdo->prepare("SELECT customer_deleted FROM part_listings WHERE id = ?");
                    $custDelStmt->execute([$listing_id]);
                    if ((int)$custDelStmt->fetchColumn() === 1) {
                        deletePartListingFiles($listing);
                        $pdo->prepare("DELETE FROM part_bids WHERE listing_id = ?")->execute([$listing_id]);
                        $pdo->prepare("DELETE FROM part_listings WHERE id = ?")->execute([$listing_id]);
                    } else {
                        $pdo->prepare("UPDATE part_listings SET seller_deleted = 1 WHERE id = ?")->execute([$listing_id]);
                    }
                    sendResponse(200, ["status" => "success", "message" => "Kayıt silindi."]);
                } else {
                    sendResponse(403, ["status" => "error", "message" => "Yetkisiz işlem."]);
                }
            } else {
                sendResponse(404, ["status" => "error", "message" => "Kayıt bulunamadı."]);
            }
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız."]);
        }
        break;

    case 'login':
    case 'auth_user': 
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        
        $phone = $_POST['phone'] ?? null;
        $password = $_POST['password'] ?? null;
        $user_type = $_POST['user_type'] ?? null;
        
        if (!$phone || !$password || !$user_type) sendResponse(400, ["status" => "error", "message" => "Lütfen tüm bilgileri girin."]);
        
        try { $clean_phone=registrationPhone($phone); }
        catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        $phone=$clean_phone;
        $phone_with_zero = (strpos($clean_phone, '0') === 0) ? $clean_phone : '0' . $clean_phone;
        $phone_without_zero = (strpos($clean_phone, '0') === 0) ? substr($clean_phone, 1) : $clean_phone;
        
        try {
            if ($user_type === 'provider') {
                // Usta ve Rent A Car aynı panelden giriş yapabilsin
                $stmt = $pdo->prepare("SELECT id, user_type, status, password, is_premium, is_suspended, suspension_end_date, city, iban FROM users WHERE (phone = ? OR phone = ? OR phone = ?) AND user_type IN ('provider', 'rentacar') LIMIT 1");
                $stmt->execute([$phone, $phone_with_zero, $phone_without_zero]);
            } else {
                $stmt = $pdo->prepare("SELECT id, user_type, status, password, is_premium, is_suspended, suspension_end_date, city, iban FROM users WHERE (phone = ? OR phone = ? OR phone = ?) AND user_type = ? LIMIT 1");
                $stmt->execute([$phone, $phone_with_zero, $phone_without_zero, $user_type]);
            }
            $user = $stmt->fetch();
            
            if ($user) {
                expirePremiumEntitlement($pdo,$user['id']);
                $premiumState=$pdo->prepare('SELECT is_premium FROM users WHERE id=?'); $premiumState->execute([$user['id']]);
                $user['is_premium']=(int)$premiumState->fetchColumn();
                if ($user['status'] === 'banned') sendResponse(403, ["status" => "error", "message" => "Hesabınız kalıcı olarak kapatılmıştır."]);
                if (!password_verify($password, $user['password'])) sendResponse(401, ["status" => "error", "message" => "Hatalı şifre."]);
                if ($user['status'] === 'pending') sendResponse(403, ["status" => "error", "message" => "Hesabınız yönetici onayı bekliyor."]);
                
                if (!empty($user_ip)) {
                    $ipCheck = $pdo->prepare("SELECT id FROM banned_ips WHERE ip_address = ?");
                    $ipCheck->execute([$user_ip]);
                    if ($ipCheck->fetch()) {
                        sendResponse(403, ["status" => "error", "message" => "Bu IP adresi kalıcı olarak engellenmiştir."]);
                    }
                    $pdo->prepare("UPDATE users SET ip_address = ? WHERE id = ?")->execute([$user_ip, $user['id']]);
                }

                $jwtToken = generateJWT($user['id'], $user['user_type']);
                sendResponse(200, [
                    "status" => "success", 
                    "user_id" => $user['id'], 
                    "user_type" => $user['user_type'], 
                    "token" => $jwtToken,
                    "city" => $user['city'] ?? 'Bilinmiyor',
                    "iban" => $user['iban'] ?? '',
                    "is_premium" => (int)($user['is_premium'] ?? 0),
                    "is_suspended" => (bool)($user['is_suspended'] ?? 0),
                    "suspension_end_date" => $user['suspension_end_date']
                ]);
            } else {
                sendResponse(401, ["status" => "error", "message" => "Kullanıcı bulunamadı veya şifre hatalı."]);
            }
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Giriş işlemi sırasında veritabanı hatası."]);
        }
        break;

    case 'check_active_job':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_GET['user_id'] ?? null;
        $user_type = $_GET['user_type'] ?? null;

        try {
            $cacheKey = "active_job_{$user_type}_{$user_id}";
            if ($redis) {
                $cached = $redis->get($cacheKey);
                if ($cached) {
                    sendResponse(200, json_decode($cached, true));
                }
            }

            if ($user_type === 'customer') {
                $stmt = $pdo->prepare("SELECT id, status, service_type FROM jobs WHERE customer_id = ? AND status IN ('searching', 'matched', 'accepted', 'approved', 'in_progress', 'customer_paid') ORDER BY id DESC LIMIT 1");
                $stmt->execute([$user_id]);
            } else {
                $stmt = $pdo->prepare("
                    SELECT id, status, service_type FROM jobs WHERE provider_id = ? AND status IN ('matched', 'accepted', 'approved', 'in_progress', 'customer_paid')
                    LIMIT 1
                ");
                $stmt->execute([$user_id]);
            }
            $job = $stmt->fetch();

            $resPayload = ["status" => "success", "has_active" => false];
            if ($job) {
                $s = strtolower($job['status']);
                $normalizedStatus = ($s === 'accepted' || $s === 'approved') ? 'matched' : $job['status'];
                $resPayload = [
                    "status" => "success", 
                    "has_active" => true, 
                    "job_id" => $job['id'], 
                    "job_status" => $normalizedStatus, "service_type" => $job['service_type']
                ];
            }
            if ($redis) {
                $redis->setex($cacheKey, 4, json_encode($resPayload));
            }
            sendResponse(200, $resPayload);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Veritabanı hatası."]);
        }
        break;

    case 'update_location':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $lat = isset($_POST['lat']) ? (float)str_replace(',', '.', $_POST['lat']) : 0;
        $lng = isset($_POST['lng']) ? (float)str_replace(',', '.', $_POST['lng']) : 0;
        $heading = isset($_POST['heading']) ? (float)$_POST['heading'] : 0;
        
        try { $lat=serviceCoordinate($_POST['lat'] ?? null); $lng=serviceCoordinate($_POST['lng'] ?? null,false); }
        catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        if (!is_finite($heading)) sendResponse(422,['status'=>'error','message'=>'Geçersiz yön bilgisi.']);
        $heading=fmod(($heading+360),360);

        $save_db = isset($_POST['save_db']) ? (int)$_POST['save_db'] : 0;

        if ($user_id) {
            // Canlı koordinatları önce doğrudan soket ile alıcıya fırlatıyoruz
            triggerPusherEvent("user_location_".$user_id, "location_update", ["lat" => $lat, "lng" => $lng, "heading" => $heading]);
            
            // Sadece seyrek aralıklarla (Flutter'dan save_db=1 geldiğinde) veya iş bitiminde MySQL'e yazarız.
            if ($save_db === 1) {
                try {
                    $pdo->prepare("UPDATE users SET lat = ?, lng = ?, heading = ? WHERE id = ?")->execute([$lat, $lng, $heading, $user_id]);
                } catch (Exception $e) {
                    if ($e->getCode() == '42S22') {
                        $pdo->exec("ALTER TABLE users ADD COLUMN heading DECIMAL(10,2) DEFAULT 0");
                        $pdo->prepare("UPDATE users SET lat = ?, lng = ?, heading = ? WHERE id = ?")->execute([$lat, $lng, $heading, $user_id]);
                    }
                }
            }
            sendResponse(200, ["status" => "success"]);
        } else {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        }
        break;

    case 'create_job':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $customer_id = $_POST['customer_id'] ?? null;
        authenticateRequest($customer_id); // JWT Güvenlik Kontrolü
        $service_type = $_POST['service_type'] ?? null;
        $lat = isset($_POST['latitude']) ? (float)str_replace(',', '.', $_POST['latitude']) : 0;
        $lng = isset($_POST['longitude']) ? (float)str_replace(',', '.', $_POST['longitude']) : 0;
        $problem_description = $_POST['problem_description'] ?? null;
        $city = $_POST['city'] ?? null;
        $match_code = rand(1000, 9999);
        
        if (!$customer_id || !$service_type || !$lat || !$lng || !$city) sendResponse(400, ["status" => "error", "message" => "Eksik parametreler var."]);

        try {
            $lat=serviceCoordinate($_POST['lat'] ?? $_POST['latitude'] ?? null); $lng=serviceCoordinate($_POST['lng'] ?? $_POST['longitude'] ?? null,false);
            if (!in_array($service_type,['mechanic','tow','tire','wash'],true)) throw new InvalidArgumentException('Geçerli bir hizmet seçin.');
            $customerCity=$pdo->prepare('SELECT city FROM users WHERE id=?'); $customerCity->execute([$customer_id]);
            $city=registrationCity($customerCity->fetchColumn());
        } catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }

        $issue_photo = null;
        $issue_audio = null;
        $upload_dir = __DIR__ . '/uploads/issues/';
        if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);

        if (isset($_FILES['issue_photo']) && $_FILES['issue_photo']['error'] === UPLOAD_ERR_OK) {
            $ext = strtolower(pathinfo($_FILES['issue_photo']['name'], PATHINFO_EXTENSION));
            $allowed = ['jpg', 'jpeg', 'png', 'webp'];
            if (in_array($ext, $allowed) && isSafeFile($_FILES['issue_photo']['tmp_name'], $allowed)) {
                $pName = time() . '_fault_' . uniqid() . '.' . $ext;
                if (@move_uploaded_file($_FILES['issue_photo']['tmp_name'], $upload_dir . $pName)) {
                    $issue_photo = 'uploads/issues/' . $pName;
                }
            }
        }

        if (isset($_FILES['issue_audio']) && $_FILES['issue_audio']['error'] === UPLOAD_ERR_OK) {
            $ext = strtolower(pathinfo($_FILES['issue_audio']['name'], PATHINFO_EXTENSION));
            $allowed_audio = ['m4a', 'aac', 'mp3', 'wav', 'ogg'];
            if (in_array($ext, $allowed_audio)) {
                $aName = time() . '_audio_' . uniqid() . '.' . $ext;
                if (@move_uploaded_file($_FILES['issue_audio']['tmp_name'], $upload_dir . $aName)) {
                    $issue_audio = 'uploads/issues/' . $aName;
                }
            }
        }

        try {
            $pdo->prepare("UPDATE jobs SET status = 'cancelled' WHERE customer_id = ? AND status = 'searching'")->execute([$customer_id]);

            $checkStmt = $pdo->prepare("SELECT id FROM jobs WHERE customer_id = ? AND status IN ('matched', 'accepted', 'approved', 'in_progress', 'customer_paid')");
            $checkStmt->execute([$customer_id]);
            if ($checkStmt->fetch()) {
                sendResponse(403, ["status" => "error", "message" => "Devam eden bir işiniz mevcut."]);
            }

            ensureGrowthSchema($pdo);
            $favoriteStmt=$pdo->prepare("SELECT u.id
                FROM favorite_providers f
                JOIN users u ON u.id=f.provider_id
                WHERE f.customer_id=?
                AND u.user_type='provider' AND u.status='active'
                AND COALESCE(u.is_suspended,0)=0
                AND u.service_category=?
                AND TRIM(u.city)=TRIM(?)
                AND (u.subscription_end_date>NOW() OR DATE_ADD(u.created_at,INTERVAL 30 DAY)>NOW())
                ORDER BY u.rating DESC,u.id ASC LIMIT 1");
            $favoriteStmt->execute([$customer_id,$service_type,$city]);
            $preferredProviderId=$favoriteStmt->fetchColumn();
            if(!$preferredProviderId) $preferredProviderId=null;

            $stmt = $pdo->prepare("INSERT INTO jobs (customer_id, service_type, latitude, longitude, match_code, problem_description, city, search_radius, status, issue_photo, issue_audio, preferred_provider_id) VALUES (?, ?, ?, ?, ?, ?, ?, 50, 'searching', ?, ?, ?)");
            $stmt->execute([$customer_id, $service_type, $lat, $lng, $match_code, $problem_description, $city, $issue_photo, $issue_audio, $preferredProviderId]);
            $new_job_id = $pdo->lastInsertId();

            try {
                // Akıllı Algoritma: En yakın mesafedeki ve en yüksek puanlı 50 ustayı önceliklendir
                $nearbyStmt = $pdo->prepare("
                    SELECT id 
                    FROM users 
                    WHERE user_type = 'provider' AND is_suspended = 0 AND status = 'active' 
                    AND service_category = ? AND TRIM(city)=TRIM(?) AND (subscription_end_date>NOW() OR DATE_ADD(created_at,INTERVAL 30 DAY)>NOW())
                    AND (ST_Distance_Sphere(point(lng, lat), point(?, ?)) / 1000) <= 50 
                    ORDER BY (ST_Distance_Sphere(point(lng, lat), point(?, ?))) ASC, rating DESC 
                    LIMIT 50
                ");
                $nearbyStmt->execute([$service_type, $city, $lng, $lat, $lng, $lat]);
                $nearbyProviders = $nearbyStmt->fetchAll(PDO::FETCH_COLUMN);

                if (!empty($nearbyProviders)) {
                    $title = "Bölgenizde Yeni İş!";
                    $message = "Yakınınızda yeni bir " . strtoupper($service_type) . " talebi var. Hemen teklif verin!";
                    if($preferredProviderId) {
                        sendOneSignalPush([(string)$preferredProviderId],
                            "Favori Müşterinizden Talep!",
                            "Favorinizdeki müşteri size öncelikli bir talep gönderdi.",
                            ['type'=>'favorite_job','job_id'=>(string)$new_job_id]);
                        $nearbyProviders=array_values(array_filter($nearbyProviders,
                            fn($id)=>(int)$id!==(int)$preferredProviderId));
                    }
                    if(!empty($nearbyProviders)) {
                        sendOneSignalPush($nearbyProviders, $title, $message, ['type' => 'new_job', 'job_id' => (string)$new_job_id]);
                    }
                }
            } catch (Exception $pushEx) {}

            triggerPusherEvent("global_jobs", "new_job_created", ["job_id" => $new_job_id]);
            sendResponse(201, ["status" => "success", "job_id" => $new_job_id, "match_code" => (string)$match_code]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Talep kaydedilemedi."]);
        }
        break;

    case 'place_bid':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $provider_id = $_POST['provider_id'] ?? null;
        authenticateRequest($provider_id); // JWT Güvenlik Kontrolü

        // Usta Abonelik / 30 Günlük Deneme Kontrolü
        $subCheckStmt = $pdo->prepare("SELECT created_at, subscription_end_date FROM users WHERE id = ? AND user_type = 'provider'");
        $subCheckStmt->execute([$provider_id]);
        $provUser = $subCheckStmt->fetch();
        if ($provUser) {
            $now = new DateTime();
            $trialEnd = (new DateTime($provUser['created_at']))->modify("+30 days");
            $subEnd = !empty($provUser['subscription_end_date']) ? new DateTime($provUser['subscription_end_date']) : null;
            
            $canWork = ($now < $trialEnd) || ($subEnd && $now < $subEnd);
            if (!$canWork) {
                sendResponse(403, [
                    "status" => "subscription_required", 
                    "message" => "30 günlük ücretsiz deneme süreniz dolmuştur. Teklif verebilmek için usta aboneliğinizi başlatmalısınız."
                ]);
            }
        }
        
        $amount = isset($_POST['amount']) ? (float)str_replace(',', '.', $_POST['amount']) : 0;
        $estimated_time = isset($_POST['estimated_time']) ? (int)$_POST['estimated_time'] : 30;
        $provider_note = trim($_POST['provider_note'] ?? '');
        
        if (!$job_id || !$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        if (!is_finite($amount) || $amount<0 || $amount>99999999) sendResponse(422,['status'=>'error','message'=>'Geçerli bir teklif tutarı girin.']);
        $estimated_time=max(1,min(1440,$estimated_time));
        if ($amount <= 0 && empty($provider_note)) sendResponse(400, ["status" => "error", "message" => "Lütfen teklif tutarı veya bir not girin."]);
        
        try {
            // EŞLEŞME GÜVENLİĞİ: İş hala aktif mi kontrolü (Kusursuz Eşleşme Kalkanı)
            $pdo->beginTransaction();
            $jobCheck = $pdo->prepare("SELECT * FROM jobs WHERE id = ? FOR UPDATE");
            $jobCheck->execute([$job_id]);
            $jData = $jobCheck->fetch();
            if (!$jData || $jData['status'] !== 'searching') {
                $pdo->rollBack();
                sendResponse(400, ["status" => "error", "message" => "Geç kaldınız, bu iş talebi iptal edilmiş veya başka bir usta ile eşleşmiş."]);
            }

            $candidate=$pdo->prepare('SELECT * FROM users WHERE id=? FOR UPDATE'); $candidate->execute([$provider_id]);
            try { serviceCandidate($pdo,$candidate->fetch(),$jData); }
            catch (DomainException $e) { $pdo->rollBack(); sendResponse(403,['status'=>'error','message'=>$e->getMessage()]); }
            $checkStmt = $pdo->prepare("SELECT id, negotiation_count, status FROM bids WHERE job_id = ? AND provider_id = ?");
            $checkStmt->execute([$job_id, $provider_id]);
            $existingBid = $checkStmt->fetch();

            if ($existingBid) {
                if ($existingBid['status'] === 'rejected' || $existingBid['status'] === 'cancelled') { $pdo->rollBack(); sendResponse(403, ["status" => "error", "message" => "Bu iş için teklifiniz sonlandırılmış."]); }
                if ($existingBid['negotiation_count'] >= 2) { $pdo->rollBack(); sendResponse(403, ["status" => "error", "message" => "Maksimum karşı teklif sınırına ulaştınız."]); }
                
                if (isset($_POST['estimated_time'])) {
                    $stmt = $pdo->prepare("UPDATE bids SET amount = ?, estimated_time = ?, provider_note = ?, negotiation_count = negotiation_count + 1, last_bidder = 'provider', status = 'negotiating' WHERE id = ?");
                    $stmt->execute([$amount, $estimated_time, $provider_note, $existingBid['id']]);
                } else {
                    $stmt = $pdo->prepare("UPDATE bids SET amount = ?, provider_note = ?, negotiation_count = negotiation_count + 1, last_bidder = 'provider', status = 'negotiating' WHERE id = ?");
                    $stmt->execute([$amount, $provider_note, $existingBid['id']]);
                }
            } else {
                $stmt = $pdo->prepare("INSERT INTO bids (job_id, provider_id, amount, estimated_time, provider_note, last_bidder, status) VALUES (?, ?, ?, ?, ?, 'provider', 'pending')");
                $stmt->execute([$job_id, $provider_id, $amount, $estimated_time, $provider_note]);
            }

            $bid_id = $existingBid ? $existingBid['id'] : $pdo->lastInsertId();
            $pdo->commit();

            try {
                $jobInfo = $pdo->prepare("SELECT customer_id FROM jobs WHERE id = ?");
                $jobInfo->execute([$job_id]);
                $jobData = $jobInfo->fetch();
                if ($jobData && !empty($jobData['customer_id'])) {
                    $notifTitle = $existingBid ? "Ustanız Karşı Teklif Verdi!" : "Yeni Teklif Geldi!";
                    $notifBody = $existingBid 
                        ? "Ustanız yeni bir fiyat (" . $amount . " ₺) önerdi. İncelemek için dokunun." 
                        : "Talebinize " . $amount . " ₺ tutarında yeni bir teklif geldi. Hemen inceleyin!";
                    
                    sendOneSignalPush(
                        (string)$jobData['customer_id'], 
                        $notifTitle, 
                        $notifBody, 
                        ['type' => 'bid_update', 'job_id' => (string)$job_id]
                    );
                }
            } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();}

            // Sağlayıcı detaylarını tek sorguda al ve Payload'a ekle (Mobil uygulama HTTP GET atmayacak)
            $provQuery = $pdo->prepare("SELECT name, IFNULL((SELECT ROUND(AVG(rating), 1) FROM ratings WHERE provider_id = u.id), 0) as average_rating FROM users u WHERE id = ?");
            $provQuery->execute([$provider_id]);
            $provInfo = $provQuery->fetch();

            $payload = [
                "status" => "new_bid",
                "bid" => [
                    "bid_id" => $bid_id,
                    "provider_id" => $provider_id,
                    "amount" => $amount,
                    "estimated_time" => $estimated_time,
                    "provider_note" => $provider_note,
                    "negotiation_count" => $existingBid ? ($existingBid['negotiation_count'] + 1) : 0,
                    "last_bidder" => "provider",
                    "provider_name" => $provInfo['name'] ?? 'Bilinmeyen Usta',
                    "average_rating" => $provInfo['average_rating'] ?? 5.0
                ]
            ];
            triggerPusherEvent("job_".$job_id, "bid_update", $payload);
            sendResponse(201, ["status" => "success"]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Teklif veritabanına kaydedilemedi."]);
        }
        break;

    case 'accept_bid':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $bid_id = $_POST['bid_id'] ?? null;
        $provider_id = $_POST['provider_id'] ?? null;
        $amount = $_POST['amount'] ?? null;
        $caller_user_type = $_POST['user_type'] ?? 'customer';
        
        if (!$job_id || !$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        try {
            $accepted=serviceAcceptOffer($pdo,authenticateRequest(),$_POST);
            $currentJob=$accepted['job'];
            $amount=$accepted['bid']['amount'];
            $matchCode=$currentJob['match_code'];
            if ($accepted['repeated']) sendResponse(200,['status'=>'success','job_status'=>$currentJob['status'],'match_code'=>(string)$matchCode]);

            try {
                if ($caller_user_type === 'provider') {
                    $target_user = (string)$currentJob['customer_id'];
                    $title = "Ustanız Eşleşmeyi Onayladı!";
                    $msg = "Usta teklifinizi kabul etti ve yola çıkıyor. Canlı konumunu takip edebilirsiniz.";
                } else {
                    $target_user = (string)$provider_id;
                    $title = "Tebrikler, İş Sizde!";
                    $msg = "Müşteri teklifinizi onayladı. Hemen işe koyulun!";
                }

                if (!empty($target_user)) {
                    sendOneSignalPush($target_user, $title, $msg, ['type' => 'job_matched', 'job_id' => (string)$job_id]);
                }
            } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();}

            // 1. İlgili İş Odasına Bildir
            triggerPusherEvent("job_".$job_id, "status_update", [
                "job_status" => "matched",
                "job_id" => (int)$job_id,
                "provider_id" => (int)$provider_id
            ]);

            // 2. Ustanın Şahsi Kanalına Anında Geçiş Bildirimi Gönder (Kritik Düzeltme)
            triggerPusherEvent("user_".$provider_id, "job_matched", [
                "job_id" => (int)$job_id,
                "customer_id" => (int)$currentJob['customer_id'],
                "agreed_price" => $amount
            ]);

            sendResponse(200, [
                "status" => "success", 
                "message" => "Teklif başarıyla kabul edildi. Eşleşme sağlandı.",
                "job_status" => "matched",
                "match_code" => (string)$matchCode
            ]);
        } catch (DomainException $e) {
            sendResponse(409,['status'=>'error','message'=>$e->getMessage()]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız oldu: " . $e->getMessage()]);
        }
        break;

    case 'get_job_status':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_GET['job_id'] ?? null;
        if (!$job_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmt = $pdo->prepare("
            SELECT j.status, j.match_code, j.agreed_price, j.latitude, j.longitude, j.customer_id, j.provider_id, j.service_type,
            j.before_photo, j.after_photo, j.issue_photo, j.issue_audio, IFNULL(j.is_evidence_confirmed, 0) as is_evidence_confirmed,
            p.name as provider_name, p.iban as provider_iban, p.phone as provider_phone, p.lat as provider_lat, p.lng as provider_lng, p.heading as provider_heading,
            p.tow_plate as provider_tow_plate,
            IFNULL(p.is_id_verified, 1) as provider_is_id_verified,
            IFNULL(p.has_guarantee, 1) as provider_has_guarantee,
            c.name as customer_name, c.phone as customer_phone, c.lat as customer_live_lat, c.lng as customer_live_lng,
            (SELECT COUNT(*) FROM jobs WHERE customer_id = c.id AND status = 'completed') as customer_completed_count,
            (SELECT COUNT(*) FROM jobs WHERE customer_id = c.id AND status = 'cancelled') as customer_cancelled_count
        FROM jobs j 
        LEFT JOIN users p ON j.provider_id = p.id 
        LEFT JOIN users c ON j.customer_id = c.id 
        WHERE j.id = ?
        ");
        $stmt->execute([$job_id]);
        $result = $stmt->fetch();
        if ($result) {
            $comp = (int)$result['customer_completed_count'];
            $canc = (int)$result['customer_cancelled_count'];
            $tot = $comp + $canc;
            $result['customer_cancel_rate'] = $tot > 0 ? round(($canc / $tot) * 100) : 0;
        }
        
        if ($result) {
            $rawStatus = strtolower($result['status']);
            if (in_array($rawStatus, ['matched', 'accepted', 'approved'])) {
                $result['status'] = 'matched';
            }
            if ($result['status'] === 'completed') {
                $checkRating = $pdo->prepare("SELECT id FROM ratings WHERE job_id = ?");
                $checkRating->execute([$job_id]);
                $result['is_rated'] = $checkRating->fetch() ? true : false;
            }
            sendResponse(200, $result);
        } else {
            sendResponse(404, ["status" => "error", "message" => "İş bulunamadı."]);
        }
        break;

    case 'upload_job_evidence':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $evidence_type = $_POST['evidence_type'] ?? ''; // 'before' veya 'after'
        
        if (!$job_id || !in_array($evidence_type, ['before', 'after'])) {
            sendResponse(400, ["status" => "error", "message" => "Geçersiz işlem veya kanıt türü."]);
        }

        $upload_dir = __DIR__ . '/uploads/evidences/';
        if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);

        $savedUrl = null;

        // 1. Multipart Dosya Yüklemesi
        if (isset($_FILES['photo']) && $_FILES['photo']['error'] === UPLOAD_ERR_OK) {
            $ext = strtolower(pathinfo($_FILES['photo']['name'], PATHINFO_EXTENSION));
            if (empty($ext)) $ext = 'jpg';
            $allowed = ['jpg', 'jpeg', 'png', 'webp'];
            
            // PHP Enjeksiyon Koruması
            $rawContent = file_get_contents($_FILES['photo']['tmp_name']);
            if (preg_match('/<\?php|<\?=|<script\b/i', $rawContent)) {
                sendResponse(400, ["status" => "error", "message" => "Zararlı dosya içeriği engellendi."]);
            }

            $fileName = time() . "_{$evidence_type}_" . uniqid() . '.' . $ext;
            if (@move_uploaded_file($_FILES['photo']['tmp_name'], $upload_dir . $fileName)) {
                $savedUrl = 'uploads/evidences/' . $fileName;
            }
        } 
        // 2. Base64 veya Metin Formatında Yükleme Desteği
        elseif (!empty($_POST['photo_base64'])) {
            $base64Data = $_POST['photo_base64'];
            if (preg_match('/^data:image\/(\w+);base64,/', $base64Data, $type)) {
                $base64Data = substr($base64Data, strpos($base64Data, ',') + 1);
            }
            $decodedImage = base64_decode($base64Data);
            if ($decodedImage !== false) {
                $fileName = time() . "_{$evidence_type}_" . uniqid() . '.jpg';
                file_put_contents($upload_dir . $fileName, $decodedImage);
                $savedUrl = 'uploads/evidences/' . $fileName;
            }
        }

        if ($savedUrl) {
            $col = ($evidence_type === 'before') ? 'before_photo' : 'after_photo';
            $pdo->prepare("UPDATE jobs SET $col = ? WHERE id = ?")->execute([$savedUrl, $job_id]);
            triggerPusherEvent("job_".$job_id, "evidence_uploaded", ["type" => $evidence_type, "url" => $savedUrl]);
            sendResponse(200, ["status" => "success", "message" => "Fotoğraf kanıtı başarıyla yüklendi.", "url" => $savedUrl]);
        } else {
            sendResponse(400, ["status" => "error", "message" => "Fotoğraf dosyası alınamadı veya kaydedilemedi."]);
        }
        break;

    case 'confirm_job_evidence':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $customer_id = $_POST['customer_id'] ?? null;
        
        if (!$job_id) {
            sendResponse(400, ["status" => "error", "message" => "İş ID parametresi zorunludur."]);
        }

        try {
            $pdo->prepare("UPDATE jobs SET is_evidence_confirmed = 1 WHERE id = ?")->execute([$job_id]);
            
            // Ustanın ekranına ve odaya kanıtın doğrulandığı bilgisini soket ile fırlat
            triggerPusherEvent("job_".$job_id, "evidence_confirmed", ["job_id" => $job_id]);
            
            // Ustaya bildirim gönder
            $jobInfo = $pdo->prepare("SELECT provider_id FROM jobs WHERE id = ?");
            $jobInfo->execute([$job_id]);
            $jobRow = $jobInfo->fetch();
            if ($jobRow && !empty($jobRow['provider_id'])) {
                sendOneSignalPush(
                    (string)$jobRow['provider_id'],
                    "Müşteri İşi Onayladı! ✓",
                    "Müşteri yüklediğiniz bitmiş iş fotoğrafını inceledi ve onayladı.",
                    ['type' => 'evidence_confirmed', 'job_id' => (string)$job_id]
                );
            }

            sendResponse(200, ["status" => "success", "message" => "İş bitimi fotoğrafı müşteri tarafından başarıyla onaylandı."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Onay işlemi kaydedilemedi: " . $e->getMessage()]);
        }
        break;

    case 'verify_code':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $code = $_POST['code'] ?? null;
        if (!$job_id || !$code) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmt = $pdo->prepare("SELECT match_code, status, before_photo FROM jobs WHERE id = ?");
        $stmt->execute([$job_id]);
        $job = $stmt->fetch();
        
        if ($job && trim((string)$job['match_code']) === trim((string)$code)) {
            if (empty($job['before_photo'])) {
                sendResponse(400, ["status" => "error", "message" => "İşe başlamadan önce lütfen hasarlı/arızalı bölgenin fotoğrafını sisteme yükleyin."]);
            }
            if (strtolower($job['status']) !== 'matched') {
                sendResponse(400, ["status" => "error", "message" => "Bu işlem durumu başlatılmaya uygun değil (İptal edilmiş veya çoktan bitmiş olabilir)."]);
            }
            $pdo->prepare("UPDATE jobs SET status = 'in_progress' WHERE id = ?")->execute([$job_id]);

            try {
                $jobInfo = $pdo->prepare("SELECT customer_id FROM jobs WHERE id = ?");
                $jobInfo->execute([$job_id]);
                $jobData = $jobInfo->fetch();
                if ($jobData && !empty($jobData['customer_id'])) {
                    sendOneSignalPush(
                        (string)$jobData['customer_id'],
                        "İşlem Başladı!",
                        "Ustanız onay kodunu girdi ve işleme başladı.",
                        ['type' => 'job_started', 'job_id' => (string)$job_id]
                    );
                }
            } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();}

            sendResponse(200, ["status" => "success", "message" => "Kod doğrulandı, iş başlatıldı."]);
        } else {
            sendResponse(401, ["status" => "error", "message" => "Hatalı veya eksik onay kodu."]);
        }
        break;

    case 'send_message':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $sender_id = $_POST['sender_id'] ?? null;
        authenticateRequest($sender_id); // JWT Güvenlik Kontrolü
        $sender_type = $_POST['sender_type'] ?? null;
        $receiver_id = $_POST['receiver_id'] ?? null;
        $message_text = $_POST['message_text'] ?? null;
        $media_type = $_POST['media_type'] ?? 'text';
        
        if (!$job_id || !$sender_id || !$receiver_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        if (empty($message_text) && empty($_FILES['media'])) sendResponse(400, ["status" => "error", "message" => "Mesaj veya dosya eksik."]);

        $media_url = null;
        $upload_dir = __DIR__ . '/uploads/chat/';
        if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);
        
        if (isset($_FILES['media']) && $_FILES['media']['error'] === UPLOAD_ERR_OK) {
            $fileSize = $_FILES['media']['size'];
            $maxSize = ($media_type === 'video') ? 30 * 1024 * 1024 : 10 * 1024 * 1024;
            if ($fileSize > $maxSize) {
                sendResponse(400, ["status" => "error", "message" => "Dosya boyutu çok büyük."]);
            }
            $ext = strtolower(pathinfo($_FILES['media']['name'], PATHINFO_EXTENSION));
            $allowed_media = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'mp4', 'mov', 'pdf'];
            if (in_array($ext, $allowed_media) && isSafeFile($_FILES['media']['tmp_name'], $allowed_media)) {
                $filename = time() . '_chat_' . uniqid() . '.' . $ext;
                if(@move_uploaded_file($_FILES['media']['tmp_name'], $upload_dir . $filename)) {
                    $media_url = 'uploads/chat/' . $filename;
                }
            }
        }
        if (trim((string)$message_text)==='' && $media_url===null) {
            sendResponse(422,['status'=>'error','message'=>'Dosya yüklenemedi. Yeniden deneyin.']);
        }

        try {
            $stmt = $pdo->prepare("INSERT INTO messages (job_id, sender_id, sender_type, receiver_id, message_text, media_url, media_type) VALUES (?, ?, ?, ?, ?, ?, ?)");
            $stmt->execute([$job_id, $sender_id, $sender_type, $receiver_id, $message_text, $media_url, $media_type]);

            $senderQuery = $pdo->prepare("SELECT name FROM users WHERE id = ?");
            $senderQuery->execute([$sender_id]);
            $senderData = $senderQuery->fetch();
            $senderName = $senderData ? $senderData['name'] : "Karşı taraf";

            $notifTitle = "Yeni Mesaj (" . $senderName . ")";
            $notifMsg = ($media_type === 'text' && !empty($message_text)) ? $message_text : "Size bir medya gönderdi.";
            
            try {
                $notifInsert = $pdo->prepare("INSERT INTO notifications (user_id, title, message) VALUES (?, ?, ?)");
                $notifInsert->execute([$receiver_id, $notifTitle, $notifMsg]);
            } catch (Throwable $e) { error_log('Chat inbox notification failed.'); }

            // A notification failure must not turn an already saved message
            // into a client error and cause the sender to retry it twice.
            sendOneSignalPush((string)$receiver_id, $notifTitle, $notifMsg,
                ['type' => 'chat', 'job_id' => (string)$job_id]);

            if ($redis && !empty($receiver_id)) {
                $redis->del("unread_msg_" . $receiver_id);
            }

            $payload = [
                "status" => "new_message_added",
                "message" => [
                    "sender_id" => $sender_id,
                    "sender_name" => $senderName,
                    "receiver_id" => $receiver_id,
                    "message_text" => $message_text,
                    "media_url" => $media_url,
                    "media_type" => $media_type,
                    "created_at" => date('Y-m-d H:i:s')
                ]
            ];
            try { triggerPusherEvent("private-chat_".$job_id, "new_message", $payload); }
            catch (Throwable $e) { error_log('Chat realtime event failed.'); }
            sendResponse(201, ["status" => "success", "message" => "Mesaj iletildi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Mesaj kaydedilemedi."]);
        }
        break;

    case 'get_messages':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_GET['job_id'] ?? null;
        $user_id = $_GET['user_id'] ?? null;
        $receiver_id = $_GET['receiver_id'] ?? null;

        if (!$job_id || !$user_id || !$receiver_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $stmt = $pdo->prepare("SELECT * FROM messages WHERE job_id = ? AND ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)) ORDER BY created_at ASC");
            $stmt->execute([$job_id, $user_id, $receiver_id, $receiver_id, $user_id]);
            $messages = $stmt->fetchAll();

            // 350K Optimizasyonu: Her mesaj okumada gereksiz DB yazmasını (Write-Lock) engelle. Sadece okunmamış varsa güncelle.
            $readUpdate=$pdo->prepare("UPDATE messages SET is_read = 1 WHERE job_id = ? AND receiver_id = ? AND is_read = 0");
            $readUpdate->execute([$job_id, $user_id]);
            if ($redis && $readUpdate->rowCount()>0) $redis->del('unread_msg_'.$user_id);

            sendResponse(200, ["status" => "success", "messages" => $messages]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Mesajlar alınamadı."]);
        }
        break;

    case 'check_unread_messages':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_GET['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $cacheKey = "unread_msg_{$user_id}";
            if ($redis) {
                $cached = $redis->get($cacheKey);
                if ($cached) {
                    sendResponse(200, json_decode($cached, true));
                }
            }

            $stmt = $pdo->prepare("SELECT COUNT(*) FROM messages WHERE receiver_id = ? AND is_read = 0");
            $stmt->execute([$user_id]);
            $unreadCount = $stmt->fetchColumn();

            $jobId = null;
            $senderId = null;
            $senderName = "";
            if ($unreadCount > 0) {
                $lastMsgStmt = $pdo->prepare("SELECT m.job_id, m.sender_id, u.name as sender_name FROM messages m LEFT JOIN users u ON m.sender_id = u.id WHERE m.receiver_id = ? AND m.is_read = 0 ORDER BY m.id DESC LIMIT 1");
                $lastMsgStmt->execute([$user_id]);
                $lastMsg = $lastMsgStmt->fetch();
                if ($lastMsg) {
                    $jobId = $lastMsg['job_id'];
                    $senderId = $lastMsg['sender_id'];
                    $senderName = $lastMsg['sender_name'];
                }
            }

            $resData = [
                "status" => "success", 
                "unread_messages" => (int)$unreadCount,
                "last_job_id" => $jobId,
                "last_sender_id" => $senderId,
                "last_sender_name" => $senderName
            ];
            if ($redis) {
                $redis->setex($cacheKey, 3, json_encode($resData));
            }
            sendResponse(200, $resData);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Mesaj kontrolü başarısız."]);
        }
        break;

    case 'mark_read':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $job_id = $_POST['job_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        try {
            if ($redis) {
                $redis->del("unread_msg_" . $user_id);
            }
            if ($job_id) {
                $stmt = $pdo->prepare("UPDATE messages SET is_read = 1 WHERE receiver_id = ? AND job_id = ?");
                $stmt->execute([$user_id, $job_id]);
            } else {
                $stmt = $pdo->prepare("UPDATE messages SET is_read = 1 WHERE receiver_id = ?");
                $stmt->execute([$user_id]);
            }
            sendResponse(200, ["status" => "success"]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem güncellenemedi."]);
        }
        break;

    case 'oauth_login':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $oauth_provider = trim($_POST['oauth_provider'] ?? '');
        $oauth_id = trim($_POST['oauth_id'] ?? '');
        $email = trim($_POST['email'] ?? '');
        if ($oauth_provider !== '' || $oauth_id !== '') {
            $identity=verifyOAuthIdentity($oauth_provider, $_POST['oauth_token'] ?? '');
            $oauth_id=$identity['sub']; $email=$identity['email'];
        }
        $user_type = trim($_POST['user_type'] ?? '');
        if (!in_array($user_type,['customer','provider','rentacar'],true)) sendResponse(422,['status'=>'error','message'=>'Geçersiz hesap türü.']);

        if (empty($oauth_provider) || empty($oauth_id) || empty($user_type)) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre gönderildi."]);
        }

        try {
            if ($user_type === 'provider') {
                $stmt = $pdo->prepare("SELECT * FROM users WHERE (oauth_provider = ? AND oauth_id = ?) AND user_type IN ('provider', 'rentacar') LIMIT 1");
                $stmt->execute([$oauth_provider, $oauth_id]);
            } else {
                $stmt = $pdo->prepare("SELECT * FROM users WHERE (oauth_provider = ? AND oauth_id = ?) AND user_type = ? LIMIT 1");
                $stmt->execute([$oauth_provider, $oauth_id, $user_type]);
            }
            $user = $stmt->fetch();

            if ($user) {
                expirePremiumEntitlement($pdo,$user['id']);
                $premiumState=$pdo->prepare('SELECT is_premium FROM users WHERE id=?'); $premiumState->execute([$user['id']]);
                $user['is_premium']=(int)$premiumState->fetchColumn();
                if ($user['status'] === 'banned') sendResponse(403, ["status" => "error", "message" => "Hesabınız kalıcı olarak kapatılmıştır."]);
                if ($user['status'] === 'pending') sendResponse(403, ["status" => "error", "message" => "Hesabınız henüz onaylanmadı. Yönetici onayı bekleniyor."]);

                $missing=registrationMissingFields($user);
                if ($missing) sendResponse(200,['status'=>'needs_completion','user_id'=>$user['id'],'user_type'=>$user['user_type'],'missing_fields'=>$missing,'message'=>'Hesabınıza gerekli bilgileri tamamlayın.']);

                $pdo->prepare("UPDATE users SET oauth_provider = ?, oauth_id = ? WHERE id = ?")->execute([$oauth_provider, $oauth_id, $user['id']]);

                $jwtToken = generateJWT($user['id'], $user['user_type']);
                sendResponse(200, [
                    "status" => "success",
                    "user_id" => $user['id'],
                    "user_type" => $user['user_type'],
                    "token" => $jwtToken,
                    "city" => $user['city'] ?? 'Bilinmiyor',
                    "iban" => $user['iban'] ?? '',
                    "is_premium" => (int)($user['is_premium'] ?? 0),
                    "is_suspended" => (bool)($user['is_suspended'] ?? 0),
                    "suspension_end_date" => $user['suspension_end_date']
                ]);
            } else {
                sendResponse(200, [
                    "status" => "not_registered",
                    "message" => "Hesap bulunamadı, kayıt tamamlama adımına yönlendiriliyorsunuz."
                ]);
            }
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Giriş işlemi gerçekleştirilemedi. Tekrar deneyin."]);
        }
        break;

    case 'register':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $name = trim($_POST['name'] ?? '');
        $phone = trim($_POST['phone'] ?? '');
        $password = trim($_POST['password'] ?? '');
        $user_type = trim($_POST['user_type'] ?? '');
        if (!in_array($user_type,['customer','provider','rentacar'],true)) sendResponse(422,['status'=>'error','message'=>'Geçersiz hesap türü.']);
        $service_category = trim($_POST['service_category'] ?? 'none');
        $iban = trim($_POST['iban'] ?? '');
        $tow_plate = strtoupper(trim($_POST['tow_plate'] ?? ''));
        $map_link = trim($_POST['map_link'] ?? '');
        if ($user_type==='rentacar') {
            try { $map_link=rentalMapLink($map_link); }
            catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        }
        $city = trim($_POST['city'] ?? '');
        $oauth_provider = trim($_POST['oauth_provider'] ?? '');
        $oauth_id = trim($_POST['oauth_id'] ?? '');
        $email = trim($_POST['email'] ?? '');
        $referral_code = strtoupper(trim($_POST['referral_code'] ?? ''));
        $inviterId = null;
        $hasRegistrationPassword=$password!=='';

@file_put_contents(
    __DIR__ . '/register_request.log',
    '[' . date('Y-m-d H:i:s') . '] ' .
    'PHONE=' . $phone .
    ' | USER_TYPE=' . $user_type .
    ' | SERVICE=' . $service_category .
    ' | CITY=' . $city .
    ' | OAUTH=' . $oauth_provider .
    PHP_EOL,
    FILE_APPEND
);
        if ($oauth_provider !== '' || $oauth_id !== '') {
            $identity=verifyOAuthIdentity($oauth_provider, $_POST['oauth_token'] ?? '');
            $oauth_id=$identity['sub']; $email=$identity['email'];
        }

        try {
            if (strlen($name)<2 || strlen($name)>160) throw new InvalidArgumentException('Ad veya firma ismi 2–160 karakter olmalı.');
            $clean_phone=registrationPhone($phone); $city=registrationCity($city);
            if ($user_type!=='customer') {
                $iban=strtoupper(preg_replace('/\s+/','',$iban));
                if (!preg_match('/^TR[0-9]{24}$/D',$iban)) throw new InvalidArgumentException('Geçerli bir TR IBAN girin.');
                if ($user_type==='rentacar') {
                    $service_category='rentacar';
                    if ($map_link==='') throw new InvalidArgumentException('Firma konum bağlantısı zorunludur.');
                } elseif (!in_array($service_category,['mechanic','tow','tire','wash'],true) || !preg_match('/^[0-9]{2}\s*[A-Z]{1,3}\s*[0-9]{2,4}$/D',$tow_plate)) throw new InvalidArgumentException('Hizmet kategorisi ve geçerli hizmet aracı plakası zorunludur.');
            }
            if ($password!=='' && strlen($password)<6) throw new InvalidArgumentException('Şifre en az 6 karakter olmalı.');
        } catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }

        try {
            $inviterId = referralResolveInviter($pdo,$referral_code);
        } catch (InvalidArgumentException $e) {
            sendResponse(422,['status'=>'error','message'=>$e->getMessage()]);
        }

        @file_put_contents(
            __DIR__ . '/register_request.log',
            '[' . date('Y-m-d H:i:s') . '] STEP=VALIDATION_OK | PHONE=' . $clean_phone . PHP_EOL,
            FILE_APPEND
        );

        if (empty($password) && empty($oauth_id)) {
            sendResponse(400, ["status" => "error", "message" => "Şifre alanı zorunludur."]);
        }

        if (empty($password)) {
            $password = bin2hex(random_bytes(10));
        }

        $upload_dir = __DIR__ . '/uploads/';
        if (!is_dir($upload_dir)) @mkdir($upload_dir, 0777, true);
        
        $tax_plate = null;
        $driver_license = null;
        $vehicle_photo = null;
        $equipment_photo = null;

        $uploadFile = function($fileKey, $dir) {

    $logFile = __DIR__ . '/register_request.log';

    if (!isset($_FILES[$fileKey])) {

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=FILES_ALANINDA_YOK' .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }

    $file = $_FILES[$fileKey];

    $uploadError = $file['error'] ?? -1;

    @file_put_contents(
        $logFile,
        '[' . date('Y-m-d H:i:s') . '] FILE_RECEIVED=' . $fileKey .
        ' | NAME=' . ($file['name'] ?? '') .
        ' | TYPE=' . ($file['type'] ?? '') .
        ' | SIZE=' . ($file['size'] ?? 0) .
        ' | ERROR=' . $uploadError .
        PHP_EOL,
        FILE_APPEND
    );


    if ($uploadError !== UPLOAD_ERR_OK) {

        $errorNames = [
            UPLOAD_ERR_INI_SIZE   => 'UPLOAD_ERR_INI_SIZE',
            UPLOAD_ERR_FORM_SIZE  => 'UPLOAD_ERR_FORM_SIZE',
            UPLOAD_ERR_PARTIAL    => 'UPLOAD_ERR_PARTIAL',
            UPLOAD_ERR_NO_FILE    => 'UPLOAD_ERR_NO_FILE',
            UPLOAD_ERR_NO_TMP_DIR => 'UPLOAD_ERR_NO_TMP_DIR',
            UPLOAD_ERR_CANT_WRITE => 'UPLOAD_ERR_CANT_WRITE',
            UPLOAD_ERR_EXTENSION  => 'UPLOAD_ERR_EXTENSION',
        ];

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=' . ($errorNames[$uploadError] ?? 'UNKNOWN_UPLOAD_ERROR') .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }


    $tmp_name = $file['tmp_name'] ?? '';
    $originalName = $file['name'] ?? '';

    if (
        $tmp_name === '' ||
        !file_exists($tmp_name)
    ) {

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=TMP_FILE_YOK' .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }


    $ext = strtolower(
        pathinfo(
            $originalName,
            PATHINFO_EXTENSION
        )
    );


    /*
     * Flutter / Android / iPhone / Web için
     * desteklenen resim formatları
     */
    $allowed_exts = [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'pdf'
    ];


    /*
     * Dosya isminin uzantısı gelmediyse MIME'dan belirle
     */
    if ($ext === '') {

        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $mime = finfo_file($finfo, $tmp_name);
        finfo_close($finfo);

        switch ($mime) {

            case 'image/jpeg':
                $ext = 'jpg';
                break;

            case 'image/png':
                $ext = 'png';
                break;

            case 'image/webp':
                $ext = 'webp';
                break;

            case 'image/heic':
            case 'image/heif':
                $ext = 'heic';
                break;

            case 'application/pdf':
                $ext = 'pdf';
                break;

            default:
                $ext = '';
                break;
        }
    }


    if (
        $ext === '' ||
        !in_array(
            $ext,
            $allowed_exts,
            true
        )
    ) {

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=UZANTI_DESTEKLENMIYOR' .
            ' | EXT=' . $ext .
            ' | NAME=' . $originalName .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }


    if (
        !isSafeFile(
            $tmp_name,
            $allowed_exts
        )
    ) {

        $finfo = finfo_open(FILEINFO_MIME_TYPE);
        $detectedMime = finfo_file($finfo, $tmp_name);
        finfo_close($finfo);

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=MIME_GUVENLIK_REDDETTI' .
            ' | MIME=' . $detectedMime .
            ' | EXT=' . $ext .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }


    if (!is_dir($dir)) {

        if (!@mkdir($dir, 0775, true)) {

            @file_put_contents(
                $logFile,
                '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
                ' | REASON=UPLOAD_KLASORU_OLUSTURULAMADI' .
                ' | DIR=' . $dir .
                PHP_EOL,
                FILE_APPEND
            );

            return null;
        }
    }


    if (!is_writable($dir)) {

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=UPLOAD_KLASORU_YAZILABILIR_DEGIL' .
            ' | DIR=' . $dir .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }


    $filename =
        date('YmdHis') .
        '_' .
        $fileKey .
        '_' .
        bin2hex(random_bytes(8)) .
        '.' .
        $ext;


    $destination =
        rtrim($dir, '/') .
        '/' .
        $filename;


    if (
        !@move_uploaded_file(
            $tmp_name,
            $destination
        )
    ) {

        @file_put_contents(
            $logFile,
            '[' . date('Y-m-d H:i:s') . '] FILE_ERROR=' . $fileKey .
            ' | REASON=MOVE_UPLOADED_FILE_BASARISIZ' .
            ' | DEST=' . $destination .
            PHP_EOL,
            FILE_APPEND
        );

        return null;
    }


    @file_put_contents(
        $logFile,
        '[' . date('Y-m-d H:i:s') . '] FILE_OK=' . $fileKey .
        ' | PATH=uploads/' . $filename .
        PHP_EOL,
        FILE_APPEND
    );


    return 'uploads/' . $filename;
};
        if ($user_type === 'provider') {
            if (empty($service_category) || $service_category === 'none') {
                sendResponse(400, ["status" => "error", "message" => "Usta kaydı için hizmet kategorisi seçimi zorunludur."]);
            }

            $cleanIban = strtoupper(preg_replace('/[^A-Z0-9]/', '', $iban));
            if (empty($cleanIban) || strlen($cleanIban) !== 26 || strpos($cleanIban, 'TR') !== 0) {
                sendResponse(400, ["status" => "error", "message" => "Usta kaydı için 26 haneli geçerli bir TR IBAN numarası zorunludur."]);
            }
            $iban = $cleanIban;

            if ($service_category === 'wash') {
                $driver_license = $uploadFile('driver_license', $upload_dir);
                $vehicle_photo = $uploadFile('vehicle_photo', $upload_dir);
                $equipment_photo = $uploadFile('equipment_photo', $upload_dir);

                if (empty($driver_license) || empty($vehicle_photo) || empty($equipment_photo)) {
                    sendResponse(400, ["status" => "error", "message" => "Oto yıkama ustaları için ehliyet, araç ve ekipman fotoğraflarının tamamı zorunludur."]);
                }
            } else {
                $tax_plate = $uploadFile('tax_plate', $upload_dir);
                if (empty($tax_plate)) {
                    sendResponse(400, ["status" => "error", "message" => "Usta kaydı için vergi levhası belgesinin yüklenmesi zorunludur."]);
                }
            }

            @file_put_contents(
                __DIR__ . '/register_request.log',
                '[' . date('Y-m-d H:i:s') . '] STEP=PROVIDER_FILES_OK | TAX=' . ($tax_plate ?: 'NONE') . PHP_EOL,
                FILE_APPEND
            );
        }

        if ($user_type==='rentacar') {
            $tax_plate=$uploadFile('tax_plate',$upload_dir);
            if (!$tax_plate) sendResponse(422,['status'=>'error','message'=>'Firma kaydı için vergi levhası zorunludur.']);
        }
        $phoneRole=$user_type==='customer' ? 'customer' : 'business';
        $locks=['reg_phone_'.substr(hash('sha256',$phoneRole.'|'.$clean_phone),0,54)];
        if ($oauth_id!=='') $locks[]='reg_oauth_'.substr(hash('sha256',$phoneRole.'|'.$oauth_provider.'|'.$oauth_id),0,54);
        sort($locks);
        foreach ($locks as $lockName) {
            $lock=$pdo->prepare('SELECT GET_LOCK(?,10)'); $lock->execute([$lockName]);
            if ((int)$lock->fetchColumn()!==1) sendResponse(409,['status'=>'error','message'=>'Kayıt işlemi sürüyor. Tekrar deneyin.']);
        }
        $completionUser=null;
        if ($oauth_id!=='') {
            $proofAccount=$pdo->prepare('SELECT * FROM users WHERE oauth_provider=? AND oauth_id=? AND user_type=? LIMIT 1');
            $proofAccount->execute([$oauth_provider,$oauth_id,$user_type]); $completionUser=$proofAccount->fetch();
            if ($completionUser && ($completionUser['status']==='banned' || !registrationMissingFields($completionUser))) sendResponse(409,['status'=>'error','message'=>'Bu sosyal hesap zaten kayıtlı. Giriş ekranını kullanın.']);
        }
        $phone_with_zero = (strpos($clean_phone, '0') === 0) ? $clean_phone : '0' . $clean_phone;
        $phone_without_zero = (strpos($clean_phone, '0') === 0) ? substr($clean_phone, 1) : $clean_phone;

        // Customers and businesses have separate accounts; provider/rentacar phone logins share one business namespace.
        if ($user_type==='customer') {
            $existingCheck=$pdo->prepare("SELECT id,user_type,status FROM users WHERE phone IN (?,?,?) AND user_type='customer' LIMIT 1");
        } else {
            $existingCheck=$pdo->prepare("SELECT id,user_type,status FROM users WHERE phone IN (?,?,?) AND user_type IN ('provider','rentacar') LIMIT 1");
        }
        $existingCheck->execute([$clean_phone,$phone_with_zero,$phone_without_zero]);
        $existingUser = $existingCheck->fetch();

        if ($existingUser && (!$completionUser || (int)$existingUser['id']!==(int)$completionUser['id'])) {
            sendResponse(409,['status'=>'error','message'=>'Bu telefon zaten kayıtlı. Mevcut hesabınıza giriş yapıp sosyal hesabı profilinizden bağlayın.']);
        }

        @file_put_contents(
            __DIR__ . '/register_request.log',
            '[' . date('Y-m-d H:i:s') . '] STEP=PHONE_CHECK_OK | PHONE=' . $clean_phone . PHP_EOL,
            FILE_APPEND
        );

        try {
            $firebaseIdentity=growthVerifyFirebasePhoneToken(
                $_POST['firebase_id_token'] ?? '',
                $clean_phone
            );
            $firebaseUid=$firebaseIdentity['uid'];
            $phoneVerified=true;
        } catch (InvalidArgumentException $e) {
            sendResponse(422,['status'=>'error','message'=>$e->getMessage()]);
        } catch (Throwable $e) {
            error_log('Firebase phone verification failed: '.$e->getMessage());
            sendResponse(503,['status'=>'error','message'=>'Telefon doğrulama servisine ulaşılamadı. Tekrar deneyin.']);
        }

        $firebaseUidCheck=$pdo->prepare('SELECT id FROM users WHERE firebase_uid=? LIMIT 1');
        $firebaseUidCheck->execute([$firebaseUid]);
        $firebaseUidOwner=$firebaseUidCheck->fetchColumn();
        if ($firebaseUidOwner &&
            (!$completionUser || (int)$firebaseUidOwner!==(int)$completionUser['id'])) {
            sendResponse(409,['status'=>'error','message'=>'Bu Firebase telefon hesabı başka bir OTO TAG hesabına bağlı.']);
        }

        if ($oauth_id !== '' && !$completionUser) {
            $oauthCheck=$pdo->prepare('SELECT id FROM users WHERE oauth_provider=? AND oauth_id=? AND user_type=? LIMIT 1');
            $oauthCheck->execute([$oauth_provider,$oauth_id,$user_type]);
            if ($oauthCheck->fetch()) sendResponse(409,['status'=>'error','message'=>'Bu sosyal hesap zaten kayıtlı. Giriş ekranını kullanın.']);
        }
        if ($completionUser) {
            $status=$user_type==='customer' ? 'active':'pending';
            $hash=$hasRegistrationPassword ? password_hash($password,PASSWORD_DEFAULT) : $completionUser['password'];
            $update=$pdo->prepare('UPDATE users SET name=?,email=?,phone=?,password=?,city=?,service_category=?,iban=?,tow_plate=?,map_link=?,tax_plate=?,driver_license=?,vehicle_photo=?,equipment_photo=?,status=?,phone_verified=1,firebase_uid=? WHERE id=? AND oauth_provider=? AND oauth_id=?');
            $update->execute([$name,$email ?: null,$clean_phone,$hash,$city,$service_category,$iban,$tow_plate ?: null,$map_link ?: null,$tax_plate,$driver_license,$vehicle_photo,$equipment_photo,$status,$firebaseUid,$completionUser['id'],$oauth_provider,$oauth_id]);
            sendResponse(200,['status'=>'success','user_id'=>$completionUser['id'],'user_type'=>$user_type,'account_status'=>$status,'token'=>generateJWT($completionUser['id'],$user_type),'tracking_code'=>$completionUser['tracking_code'] ?? null]);
        }
        $hashed_password = password_hash($password, PASSWORD_DEFAULT);
        $status = ($user_type === 'provider' || $user_type === 'rentacar') ? 'pending' : 'active';
        $tracking_code = ($user_type === 'provider' || $user_type === 'rentacar') ? rand(10000000, 99999999) : null;

        @file_put_contents(
            __DIR__ . '/register_request.log',
            '[' . date('Y-m-d H:i:s') . '] STEP=BEFORE_INSERT | PHONE=' . $clean_phone . PHP_EOL,
            FILE_APPEND
        );

        try {
            $pdo->beginTransaction();
            $stmt = $pdo->prepare("INSERT INTO users (name, email, phone, password, user_type, service_category, iban, tow_plate, map_link, city, status, is_premium, tax_plate, driver_license, vehicle_photo, equipment_photo, tracking_code, ip_address, oauth_provider, oauth_id, phone_verified, firebase_uid) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?)");
            $stmt->execute([$name, !empty($email) ? $email : null, $clean_phone, $hashed_password, $user_type, $service_category, $iban, $tow_plate ?: null, !empty($map_link) ? $map_link : null, $city, $status, $tax_plate, $driver_license, $vehicle_photo, $equipment_photo, $tracking_code, $user_ip, !empty($oauth_provider) ? $oauth_provider : null, !empty($oauth_id) ? $oauth_id : null, $firebaseUid]);
            $newUserId = $pdo->lastInsertId();
            referralAttachNewUser($pdo,(int)$newUserId,$inviterId);
            $pdo->commit();
            $jwtToken = generateJWT($newUserId, $user_type);
            sendResponse(201, [
                "status" => "success", 
                "user_id" => $newUserId, 
                "user_type" => $user_type, 
                "token" => $jwtToken, 
                "account_status" => $status, 
                "tracking_code" => $tracking_code
            ]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }

            @file_put_contents(
                __DIR__ . '/register_error.log',
                '[' . date('Y-m-d H:i:s') . '] REGISTER ERROR: ' .
                $e->getMessage() .
                ' | FILE: ' . $e->getFile() .
                ' | LINE: ' . $e->getLine() .
                PHP_EOL,
                FILE_APPEND
            );

            sendResponse(500, [
                "status" => "error",
                "message" => "Kayıt hatası: " . $e->getMessage()
            ]);
        }
        break;

    case 'check_provider_subscription':
        if ($method !== 'GET') sendResponse(405, ['status'=>'error','message'=>'Geçersiz metod.']);
        $stmt=$pdo->prepare("SELECT id,user_type,created_at,subscription_end_date FROM users WHERE id=? AND user_type IN ('provider','rentacar')");
        $stmt->execute([$_GET['provider_id'] ?? 0]); $business=$stmt->fetch();
        if (!$business) sendResponse(404,['status'=>'error','message'=>'Firma veya usta bulunamadı.']);
        sendResponse(200,['status'=>'success']+businessSubscriptionStatus($business));
        break;
    case 'renew_provider_subscription':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $provider_id = $_POST['provider_id'] ?? null;
        $purchase_token = $_POST['purchase_token'] ?? null;
        $platform = strtolower($_POST['platform'] ?? '');
        $product_id = $_POST['product_id'] ?? 'provider_monthly_subscription';
        $package_name = $_POST['package_name'] ?? 'com.oto.tag';
        $order_id = $_POST['order_id'] ?? null;

        if (!$provider_id || !$purchase_token) {
            sendResponse(400, ["status" => "error", "message" => "Usta ID ve satın alma token bilgisi gereklidir."]);
        }

        if (!in_array($platform, ['apple', 'google'])) {
            $platform = (isset($_SERVER['HTTP_USER_AGENT']) && stripos($_SERVER['HTTP_USER_AGENT'], 'iPhone') !== false) ? 'apple' : 'google';
        }

        if ($platform === 'google') {
            $verification = verifyGooglePurchase($package_name, $product_id, $purchase_token, true);
            if (!$verification) {
                sendResponse(400, ["status" => "error", "message" => "Abonelik Google Play tarafından doğrulanamadı! Sahte makbuz."]);
            }
            $order_id = $verification['orderId'] ?? $order_id;
        } elseif ($platform === 'apple') {
            $verification = verifyApplePurchase($purchase_token, $product_id);
            if (!$verification) {
                sendResponse(400, ["status" => "error", "message" => "Abonelik Apple tarafından doğrulanamadı! Sahte makbuz."]);
            }
            if (isset($verification['latest_receipt_info'][0]['transaction_id'])) {
                $order_id = $verification['latest_receipt_info'][0]['transaction_id'];
            }
        }

        try {
            sendResponse(200,applyVerifiedBusinessPurchase($pdo,$provider_id,$platform,$product_id,$purchase_token,$verification));
        } catch (PurchaseOwnershipException $e) {
            sendResponse(409,['status'=>'error','message'=>$e->getMessage()]);
        } catch (InvalidArgumentException $e) {
            sendResponse(422,['status'=>'error','message'=>$e->getMessage()]);
        } catch (Throwable $e) {
            error_log('Business subscription update failed: '.$e->getMessage());
            sendResponse(500,['status'=>'error','message'=>'Abonelik güncellenemedi. Satın alımları geri yükleyin.']);
        }
        break;
    case 'activate_obd_subscription':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $user_type = $_POST['user_type'] ?? 'customer';
        $purchase_token = $_POST['purchase_token'] ?? null;
        $platform = strtolower($_POST['platform'] ?? '');
        $product_id = $_POST['product_id'] ?? 'diagnostic_monthly_100tl';
        $package_name = $_POST['package_name'] ?? 'com.oto.tag';
        $order_id = $_POST['order_id'] ?? null;

        if (!$user_id || !$purchase_token) {
            sendResponse(400, ["status" => "error", "message" => "Kullanıcı ID ve satın alma token bilgisi gereklidir."]);
        }

        if (!in_array($platform, ['apple', 'google'])) {
            $platform = (isset($_SERVER['HTTP_USER_AGENT']) && stripos($_SERVER['HTTP_USER_AGENT'], 'iPhone') !== false) ? 'apple' : 'google';
        }

        if ($platform === 'google') {
            $verification = verifyGooglePurchase($package_name, $product_id, $purchase_token, true);
            if (!$verification) {
                sendResponse(400, ["status" => "error", "message" => "Abonelik Google Play tarafından doğrulanamadı! Sahte makbuz."]);
            }
            $order_id = $verification['orderId'] ?? $order_id;
        } elseif ($platform === 'apple') {
            $verification = verifyApplePurchase($purchase_token, $product_id);
            if (!$verification) {
                sendResponse(400, ["status" => "error", "message" => "Abonelik Apple tarafından doğrulanamadı! Sahte makbuz."]);
            }
            if (isset($verification['latest_receipt_info'][0]['transaction_id'])) {
                $order_id = $verification['latest_receipt_info'][0]['transaction_id'];
            }
        }

        $order_id=$verification['verified_transaction_id'];
        $token_hash=hash('sha256',$platform.'|'.$product_id.'|'.$order_id);
        $purchaseLock=$pdo->prepare('SELECT GET_LOCK(?,10)'); $purchaseLock->execute(['purchase_'.substr($token_hash,0,55)]);
        if ((int)$purchaseLock->fetchColumn()!==1) sendResponse(409,['status'=>'error','message'=>'Satın alma doğrulanıyor. Biraz sonra geri yüklemeyi deneyin.']);

        try {
            $pdo->beginTransaction();

            $tokenCheck = $pdo->prepare("SELECT id, user_id FROM in_app_purchases WHERE token_hash = ? OR (platform = ? AND order_id = ?)");
            $tokenCheck->execute([$token_hash,$platform,$order_id]);
            $existingPurchase=$tokenCheck->fetch();
            if ($existingPurchase) {
                if ((int)$existingPurchase['user_id']!==(int)$user_id) { $pdo->rollBack(); sendResponse(409,['status'=>'error','message'=>'Bu satın alma başka bir hesaba ait.']); }
                $pdo->prepare('UPDATE users SET obd_subscription_end_date=? WHERE id=?')->execute([$verification['verified_expiry'],$user_id]);
                $pdo->commit(); sendResponse(200,['status'=>'success','obd_subscription_end_date'=>$verification['verified_expiry'],'message'=>'Aboneliğiniz geri yüklendi.']);
            }
            // users tablosuna obd_subscription_end_date sütunu yoksa dinamik ekle
            try {
                $colCheck = $pdo->query("SHOW COLUMNS FROM users LIKE 'obd_subscription_end_date'")->fetch();
                if (!$colCheck) {
                    $pdo->exec("ALTER TABLE users ADD COLUMN obd_subscription_end_date DATETIME NULL DEFAULT NULL");
                }
            } catch (\Exception $colEx) {}

            $stmt = $pdo->prepare("SELECT user_type,created_at,subscription_end_date,obd_subscription_end_date FROM users WHERE id = ?");
            $stmt->execute([$user_id]);
            $user = $stmt->fetch();
            if (!$user) {
                $pdo->rollBack();
                sendResponse(404, ["status" => "error", "message" => "Kullanıcı bulunamadı."]);
            }

            $now = new DateTime();
            $baseDate = $now;
            if (!empty($user['obd_subscription_end_date'])) {
                $existingEnd = new DateTime($user['obd_subscription_end_date']);
                if ($existingEnd > $now) {
                    $baseDate = $existingEnd;
                }
            }

            $newEndDate = $verification['verified_expiry'];

            $updateStmt = $pdo->prepare("UPDATE users SET obd_subscription_end_date = ? WHERE id = ?");
            $updateStmt->execute([$newEndDate, $user_id]);

            $logStmt = $pdo->prepare("INSERT INTO in_app_purchases (user_id, user_type, platform, product_id, order_id, purchase_token, token_hash, purchase_type, status) VALUES (?, ?, ?, ?, ?, ?, ?, 'obd_subscription', 'completed')");
            $logStmt->execute([$user_id, $user_type, $platform, $product_id, $order_id, $purchase_token, $token_hash]);

            $pdo->commit();

            sendResponse(200, [
                "status" => "success",
                "message" => "OBD Arıza Teşhis Aboneliğiniz 30 gün boyunca aktif edildi.",
                "obd_subscription_end_date" => $newEndDate,
                "platform" => $platform
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "OBD Aboneliği güncellenemedi: " . $e->getMessage()]);
        }
        break;

    case 'check_obd_subscription':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_GET['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $stmt = $pdo->prepare("SELECT user_type,created_at,subscription_end_date,obd_subscription_end_date FROM users WHERE id = ?");
            $stmt->execute([$user_id]);
            $user = $stmt->fetch();

            if (!$user) {
                sendResponse(404, ["status" => "error", "message" => "Kullanıcı bulunamadı."]);
            }

            if ($user['user_type']==='rentacar') {
                $entitlement=businessSubscriptionStatus($user);
                if ($entitlement['can_work']) sendResponse(200,['status'=>'success','is_subscribed'=>true,'included_in_business'=>true,'subscription_end'=>$entitlement['access_end'],'message'=>'Arıza tespit erişimi Rent A Car üyeliğinize dahil.']);
            }
            $subEndDate = !empty($user['obd_subscription_end_date']) ? new DateTime($user['obd_subscription_end_date']) : null;
            $now = new DateTime();

            if ($subEndDate && $now < $subEndDate) {
                sendResponse(200, [
                    "status" => "success",
                    "is_subscribed" => true,
                    "subscription_end" => $subEndDate->format('Y-m-d H:i:s'),
                    "message" => "OBD aboneliği aktif."
                ]);
            }

            sendResponse(200, [
                "status" => "success",
                "is_subscribed" => false,
                "message" => "Abonelik süresi dolmuş veya hiç başlatılmamış."
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Abonelik sorgulanamadı."]);
        }
        break;

    case 'activate_premium':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $purchase_token = $_POST['purchase_token'] ?? null;
        $platform = strtolower($_POST['platform'] ?? '');
        $product_id = $_POST['product_id'] ?? 'customer_premium_subscription';
        $package_name = $_POST['package_name'] ?? 'com.oto.tag';
        $order_id = $_POST['order_id'] ?? null;

        if (!$user_id || !$purchase_token) {
            sendResponse(400, ["status" => "error", "message" => "Kullanıcı ID ve satın alma token bilgisi gereklidir."]);
        }

        if (!in_array($platform, ['apple', 'google'])) {
            $platform = (isset($_SERVER['HTTP_USER_AGENT']) && stripos($_SERVER['HTTP_USER_AGENT'], 'iPhone') !== false) ? 'apple' : 'google';
        }

        if ($platform === 'google') {
            $verification = verifyGooglePurchase($package_name, $product_id, $purchase_token, true);
            if (!$verification) {
                sendResponse(400, ["status" => "error", "message" => "Google Play abonelik doğrulaması başarısız!"]);
            }
            $order_id = $verification['orderId'] ?? $order_id;
        } elseif ($platform === 'apple') {
            $verification = verifyApplePurchase($purchase_token, $product_id);
            if (!$verification) {
                sendResponse(400, ["status" => "error", "message" => "Apple satın alma doğrulaması başarısız! Sahte makbuz."]);
            }
            if (isset($verification['receipt']['in_app'][0]['transaction_id'])) {
                $order_id = $verification['receipt']['in_app'][0]['transaction_id'];
            }
        }

        $order_id=$verification['verified_transaction_id'];
        $token_hash=hash('sha256',$platform.'|'.$product_id.'|'.$order_id);
        $purchaseLock=$pdo->prepare('SELECT GET_LOCK(?,10)'); $purchaseLock->execute(['purchase_'.substr($token_hash,0,55)]);
        if ((int)$purchaseLock->fetchColumn()!==1) sendResponse(409,['status'=>'error','message'=>'Satın alma doğrulanıyor. Biraz sonra geri yüklemeyi deneyin.']);

        try {
            $pdo->beginTransaction();

            $tokenCheck = $pdo->prepare("SELECT id, user_id FROM in_app_purchases WHERE token_hash = ? OR (platform = ? AND order_id = ?)");
            $tokenCheck->execute([$token_hash,$platform,$order_id]);
            $existingPurchase = $tokenCheck->fetch();

            if ($existingPurchase) {
                // Aynı müşteri geri yüklüyorsa (Restore) 409 vermek yerine Premium'u aktif et
                if ((string)$existingPurchase['user_id'] === (string)$user_id) {
                    $pdo->prepare("UPDATE users SET is_premium = 1, premium_end_date = ? WHERE id = ?")->execute([$verification['verified_expiry'],$user_id]);
                    $pdo->commit();
                    sendResponse(200, [
                        "status" => "success",
                        "message" => "OTOTAG Premium üyeliğiniz başarıyla geri yüklendi.",
                        "platform" => $platform
                    ]);
                } else {
                    $pdo->rollBack();
                    sendResponse(409, ["status" => "error", "message" => "Bu satın alma makbuzu başka bir kullanıcıya aittir."]);
                }
            }

            $updateStmt = $pdo->prepare("UPDATE users SET is_premium = 1, premium_end_date = ? WHERE id = ?");
            $updateStmt->execute([$verification['verified_expiry'],$user_id]);

            $logStmt = $pdo->prepare("INSERT INTO in_app_purchases (user_id, user_type, platform, product_id, order_id, purchase_token, token_hash, purchase_type, status) VALUES (?, 'customer', ?, ?, ?, ?, ?, 'premium', 'completed')");
            $logStmt->execute([$user_id, $platform, $product_id, $order_id, $purchase_token, $token_hash]);

            $pdo->commit();

            sendResponse(200, [
                "status" => "success", 
                "message" => "OTOTAG Premium üyeliğiniz aktif edildi.",
                "platform" => $platform
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem tamamlanamadı: " . $e->getMessage()]);
        }
        break;

    case 'get_user_purchases':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_GET['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Kullanıcı ID gerekli."]);

        try {
            $stmt = $pdo->prepare("SELECT id, platform, product_id, order_id, purchase_type, status, created_at FROM in_app_purchases WHERE user_id = ? ORDER BY created_at DESC");
            $stmt->execute([$user_id]);
            sendResponse(200, ["status" => "success", "purchases" => $stmt->fetchAll()]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Kayıtlar alınamadı."]);
        }
        break;

    case 'admin_get_purchases':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        try {
            $stmt = $pdo->query("SELECT p.id, p.user_id, p.platform, p.product_id, p.order_id, p.purchase_type, p.status, p.created_at, u.name as user_name, u.phone as user_phone, u.user_type FROM in_app_purchases p LEFT JOIN users u ON p.user_id = u.id ORDER BY p.created_at DESC LIMIT 500");
            $purchases = $stmt->fetchAll();

            $stats = $pdo->query("SELECT 
                COUNT(*) as total_sales,
                SUM(CASE WHEN platform = 'google' THEN 1 ELSE 0 END) as google_sales,
                SUM(CASE WHEN platform = 'apple' THEN 1 ELSE 0 END) as apple_sales,
                SUM(CASE WHEN purchase_type = 'subscription' THEN 1 ELSE 0 END) as subscriptions_count,
                SUM(CASE WHEN purchase_type = 'premium' THEN 1 ELSE 0 END) as premium_count
            FROM in_app_purchases WHERE status = 'completed'")->fetch();

            sendResponse(200, [
                "status" => "success",
                "stats" => $stats,
                "purchases" => $purchases
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Satın alma kayıtları alınamadı."]);
        }
        break;

    case 'send_notification':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        
        $target = $_POST['target'] ?? $_POST['user_id'] ?? 'all';
        $title = $_POST['title'] ?? null;
        $message = $_POST['message'] ?? null;
        
        if (!$title || !$message) sendResponse(400, ["status" => "error", "message" => "Başlık ve mesaj zorunludur."]);
        try {
            $pdo->beginTransaction();
            $insert = $pdo->prepare("INSERT INTO notifications (user_id, title, message) VALUES (?, ?, ?)");

            if ($target === 'all') {
                // 350K Optimizasyonu: PHP RAM limitini korumak için 350 binlik döngüyü tek satır DB işlemine çevirdik.
                $pdo->prepare("INSERT INTO notifications (user_id, title, message) SELECT id, ?, ? FROM users")->execute([$title, $message]);

                
            } elseif ($target === 'customer' || $target === 'provider') {
                // 350K Optimizasyonu: Yüz binlerce döngü yerine Mass Insert.
                $pdo->prepare("INSERT INTO notifications (user_id, title, message) SELECT id, ?, ? FROM users WHERE user_type = ?")->execute([$title, $message, $target]);
                
            } elseif (is_numeric($target) || (!empty($_POST['job_id']) && (empty($target) || $target == '0'))) {
                if (empty($target) || $target == '0') {
                    $jobFind = $pdo->prepare("SELECT customer_id FROM jobs WHERE id = ?");
                    $jobFind->execute([$_POST['job_id']]);
                    $target = (string)($jobFind->fetchColumn() ?: '');
                }

                if (!empty($target)) {
                    $insert->execute([(int)$target, $title, $message]);
                    sendOneSignalPush((string)$target, $title, $message, ['type' => 'arrival', 'job_id' => (string)($_POST['job_id'] ?? '')]);
                }
            }

            if (in_array($target,['all','customer','provider'],true)) {
                $cursor=0; $campaign=appUpdateUuid();
                do {
                    $stmt=$pdo->prepare('SELECT id FROM users WHERE id>?'.($target==='all'?'':' AND user_type=?').' ORDER BY id LIMIT 2000');
                    $stmt->execute($target==='all'?[$cursor]:[$cursor,$target]); $users=$stmt->fetchAll(PDO::FETCH_COLUMN);
                    if ($users) {
                        notificationQueue($pdo,$users,$title,$message,['type'=>'general'],$campaign.':'.$cursor);
                        $cursor=(int)end($users);
                    }
                } while (count($users)===2000);
            }
            $pdo->commit();
            sendResponse(200, ['status'=>'success','message'=>'Bildirim kaydedildi ve gönderim kuyruğuna alındı.','push_status'=>'queued']);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Bildirim kaydedilemedi."]);
        }
        break;

    case 'get_notifications':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_GET['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmt = $pdo->prepare("SELECT * FROM notifications WHERE user_id = ? ORDER BY id DESC LIMIT 50");
        $stmt->execute([$user_id]);
        $notifications = $stmt->fetchAll();
        
        $unreadStmt = $pdo->prepare("SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0");
        $unreadStmt->execute([$user_id]);
        $unread_count = $unreadStmt->fetchColumn();
        
        sendResponse(200, ["status" => "success", "notifications" => $notifications, "unread_count" => (int)$unread_count]);
        break;

    case 'mark_notif_read':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $pdo->prepare("UPDATE notifications SET is_read = 1 WHERE user_id = ?")->execute([$user_id]);
        sendResponse(200, ["status" => "success"]);
        break;

    case 'delete_notification':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $notification_id = $_POST['notification_id'] ?? null;
        $user_id = $_POST['user_id'] ?? null;
        if (!$notification_id || !$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        try {
            $stmt = $pdo->prepare("DELETE FROM notifications WHERE id = ? AND user_id = ?");
            $stmt->execute([$notification_id, $user_id]);
            sendResponse(200, ["status" => "success", "message" => "Bildirim başarıyla silindi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Bildirim silinemedi."]);
        }
        break;

    case 'clear_all_notifications':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        try {
            $stmt = $pdo->prepare("DELETE FROM notifications WHERE user_id = ?");
            $stmt->execute([$user_id]);
            sendResponse(200, ["status" => "success", "message" => "Tüm bildirimler temizlendi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Bildirimler temizlenemedi."]);
        }
        break;

    case 'admin_login':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $username = trim($_POST['username'] ?? '');
        $password = trim($_POST['password'] ?? '');
        
        if (empty($username) || empty($password)) sendResponse(400, ["status" => "error", "message" => "Kullanıcı adı ve şifre gerekli."]);
        
        $stmtAdmin = $pdo->prepare("SELECT id, password FROM admins WHERE username = ?");
        $stmtAdmin->execute([$username]);
        $admin = $stmtAdmin->fetch();
        
        $loginSuccess = $admin && password_verify($password, $admin['password']);
        $adminId = $admin ? (int)$admin['id'] : 0;
        if ($loginSuccess) {
            $adminToken = generateJWT($adminId, 'admin');
            sendResponse(200, [
                "status" => "success", 
                "admin_id" => $adminId, 
                "user_type" => "admin",
                "token" => $adminToken
            ]);
        } else {
            sendResponse(401, ["status" => "error", "message" => "Hatalı kullanıcı adı veya şifre."]);
        }
        break;
        
    case 'admin_change_password':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $adminTokenData = authenticateRequest(null, true);
        $admin_id = $adminTokenData['user_id'] ?? ($_POST['admin_id'] ?? 1);
        $old_password = $_POST['old_password'] ?? null;
        $new_password = $_POST['new_password'] ?? null;
        
        if (!$old_password || !$new_password) sendResponse(400, ["status" => "error", "message" => "Mevcut şifre ve yeni şifre eksik."]);
        
        $stmt = $pdo->prepare("SELECT password FROM admins WHERE id = ?");
        $stmt->execute([$admin_id]);
        $admin = $stmt->fetch();
        
        if (!$admin || !password_verify($old_password, $admin['password'])) {
            sendResponse(403, ["status" => "error", "message" => "Mevcut şifrenizi yanlış girdiniz."]);
        }
        
        $hashed = password_hash($new_password, PASSWORD_DEFAULT);
        
        try {
            $pdo->prepare("UPDATE admins SET password = ? WHERE id = ?")->execute([$hashed, $admin_id]);
            sendResponse(200, ["status" => "success", "message" => "Şifre güncellendi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Şifre güncellenemedi."]);
        }
        break;

    case 'admin_backup_db':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        try {
            $tables = ['users', 'jobs', 'bids', 'ratings', 'vehicles', 'vehicle_records', 'tickets', 'ads', 'part_listings', 'part_bids', 'in_app_purchases'];
            $backup = [];
            foreach($tables as $table) {
                $stmt = $pdo->query("SELECT * FROM $table");
                $backup[$table] = $stmt->fetchAll();
            }
            sendResponse(200, ["status" => "success", "backup_data" => $backup]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Yedek alınırken hata oluştu."]);
        }
        break;

    case 'admin_optimize_system':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        
        try {
            $pdo->beginTransaction();
            $deletedRecords = 0;

            $stmt = $pdo->query("UPDATE users SET is_suspended = 0, suspension_end_date = NULL WHERE is_suspended = 1 AND suspension_end_date < NOW()");
            $deletedRecords += $stmt->rowCount();

            $stmt = $pdo->query("DELETE FROM jobs WHERE status = 'cancelled' AND created_at < NOW() - INTERVAL 30 DAY");
            $deletedRecords += $stmt->rowCount();

            $queries = [
                "DELETE FROM bids WHERE job_id NOT IN (SELECT id FROM jobs)",
                "DELETE FROM part_bids WHERE listing_id NOT IN (SELECT id FROM part_listings)",
                "DELETE FROM ratings WHERE job_id NOT IN (SELECT id FROM jobs)",
                "DELETE FROM messages WHERE job_id NOT IN (SELECT id FROM jobs)",
                "DELETE FROM tickets WHERE job_id NOT IN (SELECT id FROM jobs)",
                "DELETE FROM notifications WHERE is_read = 1 AND created_at < NOW() - INTERVAL 30 DAY"
            ];

            foreach ($queries as $q) {
                try {
                    $stmt = $pdo->query($q);
                    $deletedRecords += $stmt->rowCount();
                } catch (\Throwable $e) {}
            }

            $pdo->commit();

            $tables = ['users', 'jobs', 'bids', 'ratings', 'vehicles', 'vehicle_records', 'tickets', 'ads', 'part_listings', 'part_bids', 'messages', 'notifications', 'banned_ips', 'in_app_purchases'];
            foreach ($tables as $table) {
                try {
                    $pdo->exec("OPTIMIZE TABLE $table");
                } catch (\Throwable $e) {}
            }

            $deletedFiles = 0;
            $clearedSpaceBytes = 0;
            
            $junkExtensions = ['tmp', 'log', 'bak', 'cache', 'session'];
            $dirsToClean = [
                __DIR__ . '/',
                __DIR__ . '/uploads/',
                __DIR__ . '/uploads/ads/',
                __DIR__ . '/uploads/parts/',
                __DIR__ . '/uploads/chat/'
            ];

            foreach ($dirsToClean as $dir) {
                if (is_dir($dir)) {
                    $files = array_diff(scandir($dir), array('.', '..'));
                    foreach ($files as $file) {
                        $filePath = $dir . $file;
                        if (is_file($filePath)) {
                            $ext = strtolower(pathinfo($filePath, PATHINFO_EXTENSION));
                            
                            if (in_array($ext, $junkExtensions) || $file === 'error_log') {
                                $clearedSpaceBytes += filesize($filePath);
                                @unlink($filePath);
                                $deletedFiles++;
                            }
                        }
                    }
                }
            }
            
            $clearedMb = round($clearedSpaceBytes / 1048576, 2);

            sendResponse(200, [
                "status" => "success", 
                "message" => "Sistem hızlandırıldı! $deletedRecords çöp veri, $clearedMb MB önbellek temizlendi. Fotoğraflar korundu."
            ]);

        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Optimizasyon sırasında hata oluştu: " . $e->getMessage()]);
        }
        break;

    case 'check_status':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $tracking_code = $_GET['tracking_code'] ?? null;
        if (!$tracking_code) sendResponse(400, ["status" => "error", "message" => "Sorgu numarası gerekli."]);
        
        $stmt = $pdo->prepare("SELECT name, status FROM users WHERE tracking_code = ? AND user_type = 'provider'");
        $stmt->execute([$tracking_code]);
        $user = $stmt->fetch();
        
        if ($user) {
            sendResponse(200, ["status" => "success", "account_status" => $user['status'], "name" => $user['name']]);
        } else {
            sendResponse(400, ["status" => "error", "message" => "Kayıt bulunamadı veya başvurunuz reddedildi."]);
        }
        break;

    case 'admin_dashboard':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        // Ciro hesaplaması COALESCE ile güvenli hale getirildi, limit optimize edildi
        // 350K Optimizasyonu: Tüm milyonlarca satırı saymak sunucuyu kilitler. Sadece son 30 günün istatistiklerini hızlıca getir.
        $stmtJobs = $pdo->query("SELECT COUNT(id) as total_jobs, COALESCE(SUM(agreed_price), 0) as total_revenue FROM jobs WHERE status = 'completed' AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)");
        $stmtUsers = $pdo->query("SELECT user_type, COUNT(*) as count FROM users GROUP BY user_type");
        
        $stmtRecent = $pdo->query("SELECT j.id, j.service_type, j.agreed_price, j.status, j.latitude, j.longitude, c.name as customer_name, p.name as provider_name, j.created_at FROM jobs j LEFT JOIN users c ON j.customer_id = c.id LEFT JOIN users p ON j.provider_id = p.id ORDER BY j.id DESC LIMIT 100");
        
        $stmtPendingProviders = $pdo->query("SELECT id, name, phone, user_type, service_category, tax_plate, driver_license, vehicle_photo, equipment_photo FROM users WHERE user_type IN ('provider', 'rentacar') AND status = 'pending' ORDER BY id DESC");
        $stmtLowPerf = $pdo->query("SELECT id, name, rating, reviews_count FROM users WHERE user_type = 'provider' AND rating > 0 AND rating < 3.5 AND is_suspended = 0 AND status != 'banned' AND created_at <= DATE_SUB(NOW(), INTERVAL 3 MONTH)");
        
        sendResponse(200, [
            "status" => "success", 
            "jobs_data" => $stmtJobs->fetch(), 
            "users_data" => $stmtUsers->fetchAll(), 
            "recent_jobs" => $stmtRecent->fetchAll(),
            "pending_providers" => $stmtPendingProviders->fetchAll(),
            "low_performing_providers" => $stmtLowPerf->fetchAll()
        ]);
        break;

    case 'suspend_provider':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $provider_id = $_POST['provider_id'] ?? null;
        $duration_days = (int)($_POST['duration_days'] ?? 15);
        if (!$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmtCheck = $pdo->prepare("SELECT created_at FROM users WHERE id = ?");
        $stmtCheck->execute([$provider_id]);
        $uData = $stmtCheck->fetch();
        if ($uData) {
            $createdAt = new DateTime($uData['created_at']);
            $now = new DateTime();
            $months = ($now->diff($createdAt)->y * 12) + $now->diff($createdAt)->m;
            
            if ($months < 3) {
                sendResponse(403, ["status" => "error", "message" => "Usta henüz 3 aylık gözetim süresini doldurmamıştır. Performans nedeniyle askıya alınamaz."]);
            }
        }
        
        try {
            $stmt = $pdo->prepare("UPDATE users SET is_suspended = 1, suspension_end_date = DATE_ADD(NOW(), INTERVAL ? DAY) WHERE id = ?");
            $stmt->execute([$duration_days, $provider_id]);
            sendResponse(200, ["status" => "success", "message" => "Usta $duration_days gün süreyle askıya alındı."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız."]);
        }
        break;

    case 'ban_user':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $pdo->prepare("UPDATE users SET status = 'banned' WHERE id = ?")->execute([$user_id]);
            sendResponse(200, ["status" => "success", "message" => "Kullanıcı kalıcı olarak engellendi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız."]);
        }
        break;

    case 'ban_ip':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $stmt = $pdo->prepare("SELECT ip_address FROM users WHERE id = ?");
            $stmt->execute([$user_id]);
            $u = $stmt->fetch();
            if ($u && !empty($u['ip_address'])) {
                $pdo->prepare("INSERT IGNORE INTO banned_ips (ip_address) VALUES (?)")->execute([$u['ip_address']]);
            }
            $pdo->prepare("UPDATE users SET status = 'banned' WHERE id = ?")->execute([$user_id]);
            sendResponse(200, ["status" => "success", "message" => "Kullanıcıya IP ve hesap engeli atıldı."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem başarısız."]);
        }
        break;

    case 'get_all_users':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $stmt = $pdo->query("SELECT id, user_type, name, phone, service_category, iban, status, is_premium, is_suspended, suspension_end_date, tax_plate, driver_license, vehicle_photo, equipment_photo, created_at, rating, reviews_count FROM users ORDER BY created_at DESC LIMIT 1500");
        sendResponse(200, ["status" => "success", "users" => $stmt->fetchAll()]);
        break;

    case 'admin_delete_user':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $pdo->beginTransaction();
            rentalGuardAccountDeletion($pdo,$user_id);

            $stmtFile = $pdo->prepare("SELECT tax_plate, driver_license, vehicle_photo, equipment_photo FROM users WHERE id = ?");
            $stmtFile->execute([$user_id]);
            $userData = $stmtFile->fetch();
            if ($userData) {
                deleteUserFiles($userData);
            }

            $stmtChatFiles = $pdo->prepare("SELECT media_url FROM messages WHERE (sender_id = ? OR receiver_id = ?) AND media_url IS NOT NULL");
            $stmtChatFiles->execute([$user_id, $user_id]);
            $chatFiles = $stmtChatFiles->fetchAll(PDO::FETCH_COLUMN);
            foreach ($chatFiles as $fileUrl) {
                $localChatFile = __DIR__ . '/' . ltrim($fileUrl, '/');
                if (file_exists($localChatFile) && is_file($localChatFile)) {
                    @unlink($localChatFile);
                }
            }

            $pdo->prepare("DELETE FROM notifications WHERE user_id = ?")->execute([$user_id]);
            $pdo->prepare("DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?")->execute([$user_id, $user_id]);
            $pdo->prepare("DELETE FROM ratings WHERE customer_id = ? OR provider_id = ?")->execute([$user_id, $user_id]);
            $pdo->prepare("DELETE FROM tickets WHERE customer_id = ? OR provider_id = ?")->execute([$user_id, $user_id]);
            $pdo->prepare("DELETE FROM in_app_purchases WHERE user_id = ?")->execute([$user_id]);
            
            $pdo->prepare("DELETE FROM part_bids WHERE seller_id = ?")->execute([$user_id]);
            $pdo->prepare("DELETE FROM part_bids WHERE listing_id IN (SELECT id FROM part_listings WHERE customer_id = ?)")->execute([$user_id]);
            $pdo->prepare("DELETE FROM part_listings WHERE customer_id = ? OR seller_id = ?")->execute([$user_id, $user_id]);
            
            $pdo->prepare("DELETE FROM vehicle_records WHERE vehicle_id IN (SELECT id FROM vehicles WHERE customer_id = ?)")->execute([$user_id]);
            $pdo->prepare("DELETE FROM vehicles WHERE customer_id = ?")->execute([$user_id]);
            
            $pdo->prepare("DELETE FROM bids WHERE provider_id = ?")->execute([$user_id]);
            $pdo->prepare("DELETE FROM bids WHERE job_id IN (SELECT id FROM jobs WHERE customer_id = ?)")->execute([$user_id]);
            $pdo->prepare("DELETE FROM jobs WHERE customer_id = ?")->execute([$user_id]);
            
            $pdo->prepare("UPDATE jobs SET provider_id = NULL WHERE provider_id = ?")->execute([$user_id]);
            
            $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$user_id]);
            
            $pdo->commit();
            sendResponse(200, ["status" => "success", "message" => "Kullanıcı ve yüklenen dosyaları başarıyla silindi."]);
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Kullanıcı silinemedi."]);
        }
        break;

    case 'admin_delete_job':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $job_id = $_POST['job_id'] ?? null;
        if (!$job_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $rentalCheck=$pdo->prepare("SELECT service_type FROM jobs WHERE id=?"); $rentalCheck->execute([$job_id]);
            if ($rentalCheck->fetchColumn()==='rentacar') sendResponse(409,['status'=>'error','message'=>'Kiralama geçmişini silmek yerine şikayet detayından rezervasyonu iptal edin.']);
            $pdo->beginTransaction();
            $jobMediaStmt = $pdo->prepare("SELECT before_photo, after_photo, issue_photo, issue_audio FROM jobs WHERE id = ?");
            $jobMediaStmt->execute([$job_id]);
            $jobMedia = $jobMediaStmt->fetch();
            if ($jobMedia) {
                deleteJobMediaFiles($jobMedia);
            }
            $pdo->prepare("DELETE FROM ratings WHERE job_id = ?")->execute([$job_id]);
            $pdo->prepare("DELETE FROM bids WHERE job_id = ?")->execute([$job_id]);
            $pdo->prepare("DELETE FROM tickets WHERE job_id = ?")->execute([$job_id]);
            $pdo->prepare("DELETE FROM jobs WHERE id = ?")->execute([$job_id]);
            $pdo->commit();
            sendResponse(200, ["status" => "success", "message" => "İşlem ve tüm fotoğrafları sunucudan silindi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem silinemedi."]);
        }
        break;

    case 'approve_provider':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $provider_id = $_POST['provider_id'] ?? null;
        if (!$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        $pdo->prepare("UPDATE users SET status = 'active' WHERE id = ?")->execute([$provider_id]);
        sendResponse(200, ["status" => "success", "message" => "Usta onaylandı."]);
        break;
        
    case 'reject_provider':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $provider_id = $_POST['provider_id'] ?? null;
        if (!$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        try {
            $stmtFile = $pdo->prepare("SELECT tax_plate, driver_license, vehicle_photo, equipment_photo FROM users WHERE id = ? AND status = 'pending'");
            $stmtFile->execute([$provider_id]);
            $userData = $stmtFile->fetch();
            if ($userData) {
                deleteUserFiles($userData);
                $pdo->prepare("DELETE FROM users WHERE id = ? AND status = 'pending'")->execute([$provider_id]);
                sendResponse(200, ["status" => "success", "message" => "Usta başvurusu reddedildi ve yüklenen belgeleri silindi."]);
            } else {
                sendResponse(404, ["status" => "error", "message" => "Bekleyen başvuru bulunamadı."]);
            }
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem gerçekleştirilemedi."]);
        }
        break;

    case 'get_profile':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_GET['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        $premiumColumn=$pdo->query("SHOW COLUMNS FROM users LIKE 'premium_end_date'")->fetch() ? 'premium_end_date' : 'NULL AS premium_end_date';
        $stmt = $pdo->prepare("SELECT name, phone, service_category, iban, map_link, user_type, is_premium, $premiumColumn, city, email, oauth_provider, oauth_id FROM users WHERE id = ?");
        $stmt->execute([$user_id]);
        $user = $stmt->fetch();
        if ($user) sendResponse(200, ["status" => "success", "profile" => $user]);
        else sendResponse(404, ["status" => "error", "message" => "Kullanıcı bulunamadı."]);
        break;

    case 'link_oauth':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $oauth_provider = strtolower(trim($_POST['oauth_provider'] ?? ''));
        $oauth_id = trim($_POST['oauth_id'] ?? '');
        $email = trim($_POST['email'] ?? '');
        if ($oauth_provider !== '' || $oauth_id !== '') {
            $identity=verifyOAuthIdentity($oauth_provider, $_POST['oauth_token'] ?? '');
            $oauth_id=$identity['sub']; $email=$identity['email'];
        }

        if (!$user_id || empty($oauth_provider) || empty($oauth_id)) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre gönderildi."]);
        }
        authenticateRequest($user_id);

        try {
            // Bu Google veya Apple hesabı başka bir kullanıcıya bağlı mı kontrol et
            $checkStmt = $pdo->prepare("SELECT id FROM users WHERE oauth_provider = ? AND oauth_id = ? AND id != ? LIMIT 1");
            $checkStmt->execute([$oauth_provider, $oauth_id, $user_id]);
            if ($checkStmt->fetch()) {
                sendResponse(409, ["status" => "error", "message" => "Bu " . ucfirst($oauth_provider) . " hesabı zaten başka bir kullanıcıya bağlı!"]);
            }

            $stmt = $pdo->prepare("UPDATE users SET oauth_provider = ?, oauth_id = ?, email = IFNULL(NULLIF(?, ''), email) WHERE id = ?");
            $stmt->execute([$oauth_provider, $oauth_id, $email, $user_id]);

            sendResponse(200, [
                "status" => "success",
                "message" => ucfirst($oauth_provider) . " hesabınız başarıyla bağlandı.",
                "oauth_provider" => $oauth_provider,
                "email" => $email
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Hesap bağlanırken hata oluştu: " . $e->getMessage()]);
        }
        break;

    case 'unlink_oauth':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        authenticateRequest($user_id);

        try {
            $stmt = $pdo->prepare("UPDATE users SET oauth_provider = NULL, oauth_id = NULL WHERE id = ?");
            $stmt->execute([$user_id]);
            sendResponse(200, [
                "status" => "success",
                "message" => "Hesap bağlantısı başarıyla kaldırıldı."
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Bağlantı kaldırılamadı."]);
        }
        break;

    case 'update_profile':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        authenticateRequest($user_id); // JWT Güvenlik Kontrolü
        
        $name = $_POST['name'] ?? null;
        $phone = $_POST['phone'] ?? null;
        $service_category = $_POST['service_category'] ?? 'none';
        $iban = $_POST['iban'] ?? '';
        
        if (!$user_id || !$name) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $mapSql=''; $mapParams=[];
            if (array_key_exists('map_link',$_POST)) {
                $owner=$pdo->prepare('SELECT user_type FROM users WHERE id=?'); $owner->execute([$user_id]);
                if ($owner->fetchColumn()!=='rentacar') sendResponse(403,['status'=>'error','message'=>'Konum linki yalnızca Rent A Car firma profilinden değiştirilebilir.']);
                $mapParams=[rentalMapLink($_POST['map_link'])]; $mapSql=', map_link = ?';
            }
            if (!empty($phone)) {
                $clean_phone = preg_replace('/[^0-9]/', '', (string)$phone);
                if (strlen($clean_phone) == 10 && strpos($clean_phone, '5') === 0) {
                    $clean_phone = '0' . $clean_phone;
                }
                $stmt = $pdo->prepare("UPDATE users SET name = ?, phone = ?, service_category = ?, iban = ?$mapSql WHERE id = ?");
                $stmt->execute(array_merge([$name, $clean_phone, $service_category, $iban],$mapParams,[$user_id]));
            } else {
                $stmt = $pdo->prepare("UPDATE users SET name = ?, service_category = ?, iban = ?$mapSql WHERE id = ?");
                $stmt->execute(array_merge([$name, $service_category, $iban],$mapParams,[$user_id]));
            }
            sendResponse(200, ["status" => "success", "message" => "Profil başarıyla güncellendi."]);
        } catch (InvalidArgumentException $e) {
            sendResponse(422,['status'=>'error','message'=>$e->getMessage()]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Profil güncellenirken hata oluştu. (Bu numara zaten kullanılıyor olabilir)"]);
        }
        break;

    case 'delete_account':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        if (!$user_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        authenticateRequest($user_id); // JWT Güvenlik Kontrolü
        
        try {
            $pdo->beginTransaction();
            rentalGuardAccountDeletion($pdo,$user_id);
            
            $stmtFile = $pdo->prepare("SELECT tax_plate, driver_license, vehicle_photo, equipment_photo FROM users WHERE id = ?");
            $stmtFile->execute([$user_id]);
            $userData = $stmtFile->fetch();
            if ($userData) {
                deleteUserFiles($userData);
            }
            
            $stmtChatFiles = $pdo->prepare("SELECT media_url FROM messages WHERE (sender_id = ? OR receiver_id = ?) AND media_url IS NOT NULL");
            $stmtChatFiles->execute([$user_id, $user_id]);
            $chatFiles = $stmtChatFiles->fetchAll(PDO::FETCH_COLUMN);
            foreach ($chatFiles as $fileUrl) {
                $localChatFile = __DIR__ . '/' . ltrim($fileUrl, '/');
                if (file_exists($localChatFile) && is_file($localChatFile)) {
                    @unlink($localChatFile);
                }
            }
            
            $pdo->prepare("DELETE FROM notifications WHERE user_id = ?")->execute([$user_id]);
            $pdo->prepare("DELETE FROM messages WHERE sender_id = ? OR receiver_id = ?")->execute([$user_id, $user_id]);
            $pdo->prepare("DELETE FROM ratings WHERE customer_id = ? OR provider_id = ?")->execute([$user_id, $user_id]);
            $pdo->prepare("DELETE FROM tickets WHERE customer_id = ? OR provider_id = ?")->execute([$user_id, $user_id]);
            $pdo->prepare("DELETE FROM in_app_purchases WHERE user_id = ?")->execute([$user_id]);
            
            $pdo->prepare("DELETE FROM part_bids WHERE seller_id = ?")->execute([$user_id]);
            $pdo->prepare("DELETE FROM part_bids WHERE listing_id IN (SELECT id FROM part_listings WHERE customer_id = ?)")->execute([$user_id]);
            $pdo->prepare("DELETE FROM part_listings WHERE customer_id = ? OR seller_id = ?")->execute([$user_id, $user_id]);
            
            $pdo->prepare("DELETE FROM vehicle_records WHERE vehicle_id IN (SELECT id FROM vehicles WHERE customer_id = ?)")->execute([$user_id]);
            $pdo->prepare("DELETE FROM vehicles WHERE customer_id = ?")->execute([$user_id]);
            
            $pdo->prepare("DELETE FROM bids WHERE provider_id = ?")->execute([$user_id]);
            $pdo->prepare("DELETE FROM bids WHERE job_id IN (SELECT id FROM jobs WHERE customer_id = ?)")->execute([$user_id]);
            $pdo->prepare("DELETE FROM jobs WHERE customer_id = ?")->execute([$user_id]);
            
            $pdo->prepare("UPDATE jobs SET provider_id = NULL WHERE provider_id = ?")->execute([$user_id]);
            
            $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$user_id]);
            
            $pdo->commit();
            sendResponse(200, ["status" => "success", "message" => "Hesabınız başarıyla silindi."]);
        } catch (\Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Hesap silinemedi. Detay: " . $e->getMessage()]);
        }
        break;

    case 'get_history':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0;
        $user_type = $_GET['user_type'] ?? null;
        if ($user_id <= 0 || !$user_type) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            // Kolonların varlığını anında garantiye al
            try {
                $checkCustDel = $pdo->query("SHOW COLUMNS FROM jobs LIKE 'customer_deleted'")->fetch();
                if (!$checkCustDel) {
                    $pdo->exec("ALTER TABLE jobs ADD COLUMN customer_deleted TINYINT(1) DEFAULT 0");
                    $pdo->exec("ALTER TABLE jobs ADD COLUMN provider_deleted TINYINT(1) DEFAULT 0");
                }
                // rater_type kontrolü tamamlandı
            } catch (\Exception $colEx) {}

            if ($user_type === 'customer') {
                $stmt = $pdo->prepare("SELECT j.id as job_id, j.customer_id, j.service_type, j.agreed_price, j.status, j.created_at, j.latitude, j.longitude, j.before_photo, j.after_photo, j.city, u.name as provider_name, j.provider_id, u.lat as p_start_lat, u.lng as p_start_lng, (SELECT rating FROM ratings WHERE job_id = j.id AND (rater_type = 'customer' OR rater_type IS NULL) LIMIT 1) as given_rating FROM jobs j LEFT JOIN users u ON j.provider_id = u.id WHERE j.customer_id = ? AND (j.status = 'completed' OR (j.service_type='rentacar' AND j.status='cancelled')) AND (j.customer_deleted = 0 OR j.customer_deleted IS NULL) ORDER BY j.id DESC LIMIT 50");
            } else {
                $stmt = $pdo->prepare("SELECT j.id as job_id, j.customer_id, j.service_type, j.agreed_price, j.status, j.created_at, j.latitude, j.longitude, j.before_photo, j.after_photo, j.city, u.name as customer_name, j.provider_id, p.lat as p_start_lat, p.lng as p_start_lng, (SELECT rating FROM ratings WHERE job_id = j.id AND rater_type = 'provider' LIMIT 1) as given_rating FROM jobs j LEFT JOIN users u ON j.customer_id = u.id LEFT JOIN users p ON j.provider_id = p.id WHERE j.provider_id = ? AND j.status IN ('completed', 'cancelled') AND (j.provider_deleted = 0 OR j.provider_deleted IS NULL) ORDER BY j.id DESC LIMIT 50");
            }
            $stmt->execute([$user_id]);
            $result = $stmt->fetchAll();
            sendResponse(200, ["status" => "success", "history" => rentalEnrichHistory($pdo,$result ?: [])]);
        } catch (\PDOException $e) {
            // Güvenlik Ağı: Beklenmeyen bir SQL kısıtı durumunda 500 hatası vermek yerine güvenli temel sorgu ile 200 dön
            try {
                if ($user_type === 'customer') {
                    $fallbackStmt = $pdo->prepare("SELECT j.id as job_id, j.customer_id, j.service_type, j.agreed_price, j.status, j.created_at, j.latitude, j.longitude, j.city, u.name as provider_name, j.provider_id FROM jobs j LEFT JOIN users u ON j.provider_id = u.id WHERE j.customer_id = ? AND (j.status = 'completed' OR (j.service_type='rentacar' AND j.status='cancelled')) ORDER BY j.id DESC LIMIT 50");
                } else {
                    $fallbackStmt = $pdo->prepare("SELECT j.id as job_id, j.customer_id, j.service_type, j.agreed_price, j.status, j.created_at, j.latitude, j.longitude, j.city, u.name as customer_name, j.provider_id FROM jobs j LEFT JOIN users u ON j.customer_id = u.id WHERE j.provider_id = ? AND j.status IN ('completed', 'cancelled') ORDER BY j.id DESC LIMIT 50");
                }
                $fallbackStmt->execute([$user_id]);
                $fbResult = $fallbackStmt->fetchAll();
                sendResponse(200, ["status" => "success", "history" => rentalEnrichHistory($pdo,$fbResult ?: [])]);
            } catch (\Exception $fallbackEx) {
                sendResponse(200, ["status" => "success", "history" => []]);
            }
        }
        break;

    case 'delete_history':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $user_type = $_GET['user_type'] ?? $_POST['user_type'] ?? 'provider';
        $raw_job_ids = $_POST['job_ids'] ?? '';
        
        $job_ids = [];
        if (is_array($raw_job_ids)) {
            $job_ids = $raw_job_ids;
        } else {
            $decoded = json_decode($raw_job_ids, true);
            if (is_array($decoded)) {
                $job_ids = $decoded;
            } elseif (!empty($raw_job_ids)) {
                $job_ids = explode(',', $raw_job_ids);
            }
        }

        if (!$user_id || empty($job_ids)) {
            sendResponse(400, ["status" => "error", "message" => "Eksik veya hatalı parametre."]);
        }

        if (count($job_ids) > 100) {
            sendResponse(422, ["status" => "error", "message" => "Tek seferde en fazla 100 işlem seçebilirsiniz."]);
        }
        foreach ($job_ids as $job_id) {
            if (!is_scalar($job_id) || !preg_match('/^[1-9][0-9]{0,9}$/D', (string)$job_id)) {
                sendResponse(422, ["status" => "error", "message" => "Geçersiz işlem seçimi."]);
            }
        }

        try {
            $safe_job_ids = array_values(array_unique(array_map('intval', $job_ids)));
            if (empty($safe_job_ids)) {
                 sendResponse(400, ["status" => "error", "message" => "Geçerli işlem ID bulunamadı."]);
            }
            $placeholders = implode(',', array_fill(0, count($safe_job_ids), '?'));
            
            if ($user_type === 'customer') {
                $stmt = $pdo->prepare("UPDATE jobs SET customer_deleted = 1 WHERE customer_id = ? AND id IN ($placeholders)");
            } else {
                $stmt = $pdo->prepare("UPDATE jobs SET provider_deleted = 1 WHERE provider_id = ? AND id IN ($placeholders)");
            }
            
            $params = array_merge([$user_id], $safe_job_ids);
            $stmt->execute($params);

            sendResponse(200, ["status" => "success", "message" => "İşlemler başarıyla silindi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "İşlem sırasında bir hata oluştu: " . $e->getMessage()]);
        }
        break;

    case 'get_earnings':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $provider_id = $_GET['provider_id'] ?? null;
        if (!$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            // Haftalık Ciro ve İş Sayısı (Son 7 Gün)
            $stmtWeek = $pdo->prepare("SELECT COALESCE(SUM(agreed_price), 0) as rev, COUNT(id) as cnt FROM jobs WHERE provider_id = ? AND status = 'completed' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)");
            $stmtWeek->execute([$provider_id]);
            $weekData = $stmtWeek->fetch();
            $weekly = $weekData['rev'];
            $weeklyJobs = (int)$weekData['cnt'];

            // Aylık Ciro ve İş Sayısı (İçinde Bulunulan Ay)
            $stmtMonth = $pdo->prepare("SELECT COALESCE(SUM(agreed_price), 0) as rev, COUNT(id) as cnt FROM jobs WHERE provider_id = ? AND status = 'completed' AND MONTH(created_at) = MONTH(CURRENT_DATE()) AND YEAR(created_at) = YEAR(CURRENT_DATE())");
            $stmtMonth->execute([$provider_id]);
            $monthData = $stmtMonth->fetch();
            $monthly = $monthData['rev'];
            $monthlyJobs = (int)$monthData['cnt'];

            // Yıllık Ciro ve İş Sayısı (İçinde Bulunulan Yıl)
            $stmtYear = $pdo->prepare("SELECT COALESCE(SUM(agreed_price), 0) as rev, COUNT(id) as cnt FROM jobs WHERE provider_id = ? AND status = 'completed' AND YEAR(created_at) = YEAR(CURRENT_DATE())");
            $stmtYear->execute([$provider_id]);
            $yearData = $stmtYear->fetch();
            $yearly = $yearData['rev'];
            $yearlyJobs = (int)$yearData['cnt'];

            // Toplam Tamamlanan İş Sayısı
            $stmtTotal = $pdo->prepare("SELECT COUNT(id) as total_jobs FROM jobs WHERE provider_id = ? AND status = 'completed'");
            $stmtTotal->execute([$provider_id]);
            $totalJobs = $stmtTotal->fetchColumn();

            $stmtPerf = $pdo->prepare("SELECT lat, lng, rating, reviews_count, is_suspended, suspension_end_date, created_at FROM users WHERE id = ?");
            $stmtPerf->execute([$provider_id]);
            $perf = $stmtPerf->fetch();

            // Ustanın bugün tamamladığı iş sayısı
            $dailyStmt = $pdo->prepare("SELECT COUNT(*) FROM jobs WHERE provider_id = ? AND DATE(created_at) = CURRENT_DATE() AND status = 'completed'");
            $dailyStmt->execute([$provider_id]);
            $dailyJobsCount = (int)$dailyStmt->fetchColumn();

            $currentRating = $perf ? (float)$perf['rating'] : 5.0;
            if ($currentRating <= 0.0) $currentRating = 5.0; // Yeni üye başlangıç puanı 5.0
            $reviewsCount = $perf ? (int)$perf['reviews_count'] : 0;

            // 1.5 Ay (45 Gün) Yeni Üye Gözlem ve Koruma Süresi Kontrolü
            $createdAt = ($perf && !empty($perf['created_at'])) ? new DateTime($perf['created_at']) : new DateTime();
            $now = new DateTime();
            $daysSinceRegistered = $now->diff($createdAt)->days;
            $isGracePeriod = ($daysSinceRegistered < 45 || $reviewsCount < 3);

            // Kademeli Değerlendirme Algoritması Kotası
            $maxDailyJobs = 999;
            $penaltyDelaySec = 0;
            $algorithmTier = "vip";

            if ($isGracePeriod) {
                // 1.5 ay boyunca ceza ve kısıtlama uygulanmaz
                $algorithmTier = "observation";
                $maxDailyJobs = 999;
                $penaltyDelaySec = 0;
            } elseif ($reviewsCount >= 3) {
                if ($currentRating < 2.0) {
                    $maxDailyJobs = 1;
                    $penaltyDelaySec = 90;
                    $algorithmTier = "critical";
                } elseif ($currentRating < 3.0) {
                    $maxDailyJobs = 2;
                    $penaltyDelaySec = 45;
                    $algorithmTier = "restricted";
                } elseif ($currentRating < 3.5) {
                    $maxDailyJobs = 5;
                    $penaltyDelaySec = 15;
                    $algorithmTier = "warning";
                }
            }

            $ratingsStmt = $pdo->prepare("SELECT r.rating, r.comment, DATE_FORMAT(r.created_at, '%Y-%m-%d') as date, u.name as customer_name FROM ratings r JOIN users u ON r.customer_id = u.id WHERE r.provider_id = ? AND r.comment IS NOT NULL AND TRIM(r.comment) != '' ORDER BY r.created_at DESC");
            $ratingsStmt->execute([$provider_id]);
            $reviews = $ratingsStmt->fetchAll();

            sendResponse(200, [
                "status" => "success",
                "earnings" => [
                    "weekly" => $weekly ? round((float)$weekly, 2) : 0,
                    "weekly_jobs" => $weeklyJobs,
                    "monthly" => $monthly ? round((float)$monthly, 2) : 0,
                    "monthly_jobs" => $monthlyJobs,
                    "yearly" => $yearly ? round((float)$yearly, 2) : 0,
                    "yearly_jobs" => $yearlyJobs,
                    "total_jobs" => $totalJobs ? (int)$totalJobs : 0
                ],
                "performance" => [
                    "rating" => $currentRating,
                    "reviews_count" => $reviewsCount,
                    "daily_jobs_count" => $dailyJobsCount,
                    "max_daily_jobs" => $maxDailyJobs,
                    "penalty_delay_sec" => $penaltyDelaySec,
                    "algorithm_tier" => $algorithmTier,
                    "is_grace_period" => $isGracePeriod,
                    "grace_days_left" => max(0, 45 - $daysSinceRegistered),
                    "is_suspended" => $perf ? (bool)$perf['is_suspended'] : false,
                    "suspension_end_date" => $perf ? $perf['suspension_end_date'] : null,
                    "reviews" => $reviews 
                ]
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Veri çekilemedi."]);
        }
        break;

    case 'get_pending_jobs':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        
        $provider_lat = isset($_GET['lat']) ? (float)str_replace(',', '.', $_GET['lat']) : 0.0;
        $provider_lng = isset($_GET['lng']) ? (float)str_replace(',', '.', $_GET['lng']) : 0.0;
        $provider_id = isset($_GET['provider_id']) ? (int)$_GET['provider_id'] : 0; 
        $requested_radius = isset($_GET['radius']) ? (float)$_GET['radius'] : 50.0; 
        
        try {
            if ($provider_lat == 0.0 || $provider_lng == 0.0) {
                sendResponse(200, ["status" => "success", "jobs" => []]);
            }

            // Ustanın puanını, yorum sayısını ve kayıt tarihini denetle
            $provStmt = $pdo->prepare("SELECT rating, reviews_count, created_at, service_category, city, subscription_end_date FROM users WHERE id = ? AND user_type = 'provider'");
            $provStmt->execute([$provider_id]);
            $provData = $provStmt->fetch();

            if (!$provData || !businessSubscriptionStatus($provData)['can_work']) sendResponse(200,['status'=>'success','jobs'=>[],'subscription_required'=>true,'message'=>'Usta üyeliğinizi yenileyin.']);
            $requested_radius=max(1,min(50,$requested_radius));
            $pRating = $provData ? (float)$provData['rating'] : 5.0;
            if ($pRating <= 0.0) $pRating = 5.0;
            $pReviews = $provData ? (int)$provData['reviews_count'] : 0;
            $pCreatedAt = ($provData && !empty($provData['created_at'])) ? new DateTime($provData['created_at']) : new DateTime();
            $now = new DateTime();
            $pDays = $now->diff($pCreatedAt)->days;
            $isGrace = ($pDays < 45 || $pReviews < 3); // 1.5 ay gözlem dönemi

            // Günlük yapılan iş sayısını say
            $dailyDoneStmt = $pdo->prepare("SELECT COUNT(*) FROM jobs WHERE provider_id = ? AND DATE(created_at) = CURRENT_DATE() AND status = 'completed'");
            $dailyDoneStmt->execute([$provider_id]);
            $todayDoneCount = (int)$dailyDoneStmt->fetchColumn();

            $delaySeconds = 0;
            $allowedMaxDaily = 999;

            if (!$isGrace && $pReviews >= 3) {
                if ($pRating < 2.0) {
                    $allowedMaxDaily = 1;
                    $delaySeconds = 90;
                } elseif ($pRating < 3.0) {
                    $allowedMaxDaily = 2;
                    $delaySeconds = 45;
                } elseif ($pRating < 3.5) {
                    $allowedMaxDaily = 5;
                    $delaySeconds = 15;
                }
            }

            // Eğer usta düşük puandan dolayı günlük kotasını doldurduysa yeni iş gösterilmez
            if ($todayDoneCount >= $allowedMaxDaily) {
                sendResponse(200, [
                    "status" => "success", 
                    "jobs" => [], 
                    "quota_reached" => true,
                    "message" => "Düşük puan sebebiyle günlük maksimum iş kotanıza ulaştınız."
                ]);
            }
            
            ensureGrowthSchema($pdo);
            // 350K Optimizasyonu: Haritayı karelere bölen Bounding Box. Geometri hesaplama yükünü %99 azaltır.
            $lat_range = $requested_radius / 111.045;
            $lng_range = $requested_radius / (111.045 * max(0.01,abs(cos(deg2rad($provider_lat)))));
            // Ustanın hizmet kategorisini al
            $provCategory = $provData['service_category'] ?? 'mechanic';

            $sql = "
                SELECT j.id, j.service_type, j.latitude, j.longitude, j.problem_description, j.search_radius, j.created_at,
                j.issue_photo, j.issue_audio,
                u.name as customer_name,
                (SELECT COUNT(*) FROM jobs WHERE customer_id = u.id AND status = 'completed') as customer_completed_count,
                (SELECT COUNT(*) FROM jobs WHERE customer_id = u.id AND status = 'cancelled') as customer_cancelled_count,
                (ST_Distance_Sphere(point(j.longitude, j.latitude), point(:lng1, :lat1)) / 1000) as distance
                FROM jobs j
                LEFT JOIN users u ON j.customer_id = u.id
                WHERE j.status = 'searching' AND TRIM(j.city)=TRIM(:provider_city) AND u.status='active' AND u.is_suspended=0 
                AND j.service_type = :service_type
                AND j.latitude BETWEEN (:lat2 - :lat_range1) AND (:lat3 + :lat_range2)
                AND j.longitude BETWEEN (:lng2 - :lng_range1) AND (:lng3 + :lng_range2)
                AND j.created_at <= (NOW() - INTERVAL :delay SECOND)
                AND (
                    j.preferred_provider_id IS NULL
                    OR j.preferred_provider_id = :pid_pref
                    OR j.created_at <= (NOW() - INTERVAL 15 SECOND)
                )
                AND NOT EXISTS (SELECT 1 FROM bids WHERE bids.job_id = j.id AND bids.provider_id = :pid)
                HAVING distance <= search_radius AND distance <= :req_rad
                ORDER BY (j.preferred_provider_id = :pid_order) DESC, distance ASC
                LIMIT 50
            ";
            $stmt = $pdo->prepare($sql);
            $stmt->bindValue(':service_type', $provCategory, PDO::PARAM_STR);
            $stmt->bindValue(':provider_city',$provData['city']);
            $stmt->bindValue(':pid_pref',$provider_id,PDO::PARAM_INT);
            $stmt->bindValue(':pid_order',$provider_id,PDO::PARAM_INT);
            $stmt->bindValue(':lng1', $provider_lng);
            $stmt->bindValue(':lat1', $provider_lat);
            $stmt->bindValue(':lat2', $provider_lat);
            $stmt->bindValue(':lat3', $provider_lat);
            $stmt->bindValue(':lng2', $provider_lng);
            $stmt->bindValue(':lng3', $provider_lng);
            $stmt->bindValue(':lat_range1', $lat_range);
            $stmt->bindValue(':lat_range2', $lat_range);
            $stmt->bindValue(':lng_range1', $lng_range);
            $stmt->bindValue(':lng_range2', $lng_range);
            $stmt->bindValue(':delay', (int)$delaySeconds, PDO::PARAM_INT);
            $stmt->bindValue(':pid', $provider_id, PDO::PARAM_INT);
            $stmt->bindValue(':req_rad', $requested_radius);
            $stmt->execute();
            $matched_jobs = $stmt->fetchAll();
            
            foreach ($matched_jobs as &$job) {
                $job['distance'] = round($job['distance'], 2);
            }
            
            sendResponse(200, [
                "status" => "success", 
                "jobs" => $matched_jobs,
                "delay_applied" => $delaySeconds,
                "daily_jobs" => $todayDoneCount,
                "max_daily_jobs" => $allowedMaxDaily
            ]);

        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Veritabanı hatası!"]);
        }
        break;

    case 'expand_search_radius':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        if (!$job_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmt = $pdo->prepare("SELECT search_radius FROM jobs WHERE id = ?");
        $stmt->execute([$job_id]);
        $job = $stmt->fetch();
        
        if ($job) {
            $current_radius = (int)$job['search_radius'];
            $new_radius = $current_radius;
            if ($current_radius < 20) $new_radius = 20;
            else if ($current_radius < 35) $new_radius = 35;
            else if ($current_radius < 50) $new_radius = 50;
            
            if ($new_radius != $current_radius && $new_radius <= 50) {
                $pdo->prepare("UPDATE jobs SET search_radius = ? WHERE id = ?")->execute([$new_radius, $job_id]);
            }
            sendResponse(200, ["status" => "success", "new_radius" => $new_radius]);
        } else {
            sendResponse(404, ["status" => "error", "message" => "İş bulunamadı."]);
        }
        break;

    case 'get_provider_active_bids': 
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $provider_id = $_GET['provider_id'] ?? null;
        if (!$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        $stmt = $pdo->prepare("SELECT b.id as bid_id, b.amount, b.status as bid_status, b.last_bidder, b.negotiation_count, j.id as job_id, j.service_type, j.status as job_status, c.name as customer_name FROM bids b JOIN jobs j ON b.job_id = j.id LEFT JOIN users c ON j.customer_id = c.id WHERE b.provider_id = ? AND j.status = 'searching' AND b.status IN ('pending', 'negotiating') ORDER BY b.id DESC");
        $stmt->execute([$provider_id]);
        sendResponse(200, ["status" => "success", "active_bids" => $stmt->fetchAll()]);
        break;

    case 'get_bids':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_GET['job_id'] ?? null;
        $user_type = $_GET['user_type'] ?? 'customer'; 
        $provider_id = $_GET['provider_id'] ?? null; 
        if (!$job_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            if ($user_type === 'provider' && $provider_id) {
                $stmt = $pdo->prepare("SELECT b.id as bid_id, b.amount, IFNULL(b.estimated_time, 30) as estimated_time, b.provider_note, b.negotiation_count, b.last_bidder, b.status, c.name as customer_name, j.problem_description, j.issue_photo, j.issue_audio FROM bids b JOIN jobs j ON b.job_id = j.id LEFT JOIN users c ON j.customer_id = c.id WHERE b.job_id = ? AND b.provider_id = ? AND b.status IN ('pending', 'negotiating', 'accepted')");
                $stmt->execute([$job_id, $provider_id]);
                $bids = $stmt->fetchAll();
            } else {
                // Yüksek performanslı ve kilitlenmeyen sorgu (Tabloyu kilitleyen HOUR fonksiyonlu alt sorgular kaldırıldı)
                $stmt = $pdo->prepare("
                    SELECT b.id as bid_id, b.amount, IFNULL(b.estimated_time, 30) as estimated_time, b.provider_note, b.negotiation_count, b.last_bidder, b.status, 
                    u.name as provider_name, u.id as provider_id, u.rating as average_rating, u.reviews_count as review_count,
                    u.created_at as provider_created_at,
                    IFNULL(u.service_category, 'mechanic') as provider_service_category,
                    IFNULL(u.is_id_verified, 1) as is_id_verified,
                    IFNULL(u.is_tax_verified, 1) as is_tax_verified,
                    IFNULL(u.has_guarantee, 1) as has_guarantee,
                    u.tow_plate as tow_plate,
                    (SELECT COUNT(*) FROM jobs WHERE provider_id = u.id AND status = 'completed') as completed_jobs_count,
                    0 as monthly_jobs_count,
                    0 as monthly_cancelled_count,
                    0 as night_jobs_count
                    FROM bids b 
                    LEFT JOIN users u ON b.provider_id = u.id 
                    WHERE b.job_id = ? AND b.status IN ('pending', 'negotiating')
                ");
                $stmt->execute([$job_id]);
                $bids = $stmt->fetchAll();

                // 20 Adet Dinamik Rozeti Hesapla
                foreach ($bids as &$provider) {
                    $badges = [];
                    $createdAt = !empty($provider['provider_created_at']) ? new DateTime($provider['provider_created_at']) : new DateTime();
                    $now = new DateTime();
                    $daysActive = $now->diff($createdAt)->days;
                    $monthsActive = floor($daysActive / 30);

                    $rating = isset($provider['average_rating']) ? (float)$provider['average_rating'] : 5.0;
                    $reviewCount = isset($provider['review_count']) ? (int)$provider['review_count'] : 0;
                    $totalJobs = isset($provider['completed_jobs_count']) ? (int)$provider['completed_jobs_count'] : 0;
                    $monthlyJobs = isset($provider['monthly_jobs_count']) ? (int)$provider['monthly_jobs_count'] : 0;
                    $monthlyCancelled = isset($provider['monthly_cancelled_count']) ? (int)$provider['monthly_cancelled_count'] : 0;
                    $nightJobs = isset($provider['night_jobs_count']) ? (int)$provider['night_jobs_count'] : 0;
                    $estimatedTime = isset($provider['estimated_time']) ? (int)$provider['estimated_time'] : 30;
                    $serviceCategory = strtolower(trim($provider['provider_service_category'] ?? 'mechanic'));

                    // Grup 1: Süre ve Kıdem
                    if ($daysActive <= 30) {
                        $badges[] = ['id' => 'tenure_1m', 'title' => 'Çaylak Usta', 'icon' => 'fiber_new_rounded', 'color' => '0xFF38BDF8'];
                    } elseif ($monthsActive >= 3 && $monthsActive < 12) {
                        $badges[] = ['id' => 'tenure_3m', 'title' => 'Kıdemli Esnaf', 'icon' => 'verified_rounded', 'color' => '0xFF10B981'];
                    } elseif ($monthsActive >= 12 && $monthsActive < 24) {
                        $badges[] = ['id' => 'tenure_1y', 'title' => 'Yılların Tecrübesi', 'icon' => 'military_tech_rounded', 'color' => '0xFFF59E0B'];
                    } elseif ($monthsActive >= 24 && $totalJobs >= 50) {
                        $badges[] = ['id' => 'tenure_2y', 'title' => 'Sanayi Duayeni', 'icon' => 'workspace_premium_rounded', 'color' => '0xFFA855F7'];
                    }

                    // Grup 2: Puan
                    if ($rating >= 4.90 && $reviewCount >= 5) {
                        $badges[] = ['id' => 'rating_perfect', 'title' => '5 Yıldız Şampiyonu', 'icon' => 'star_rounded', 'color' => '0xFFF59E0B'];
                    } elseif ($rating >= 4.70 && $rating < 4.90) {
                        $badges[] = ['id' => 'rating_gold', 'title' => 'Altın Statü', 'icon' => 'auto_awesome_rounded', 'color' => '0xFFEAB308'];
                    } elseif ($rating >= 4.40 && $rating < 4.70) {
                        $badges[] = ['id' => 'rating_silver', 'title' => 'Gümüş Statü', 'icon' => 'shield_rounded', 'color' => '0xFF94A3B8'];
                    }
                    if ($monthlyCancelled === 0 && $rating >= 4.80 && $monthlyJobs >= 3) {
                        $badges[] = ['id' => 'rating_zero_error', 'title' => 'Kusursuz İşçilik', 'icon' => 'fact_check_rounded', 'color' => '0xFF059669'];
                    }

                    // Grup 3: Aktiflik
                    if ($monthlyJobs >= 10) {
                        $badges[] = ['id' => 'activity_star', 'title' => 'Ayın Yıldız Ustası', 'icon' => 'local_fire_department_rounded', 'color' => '0xFFFF5722'];
                    }
                    if ($estimatedTime <= 15) {
                        $badges[] = ['id' => 'activity_jet', 'title' => 'Jet Varış (' . $estimatedTime . ' Dk)', 'icon' => 'bolt_rounded', 'color' => '0xFF00E5FF'];
                    }
                    if ($nightJobs >= 1) {
                        $badges[] = ['id' => 'activity_night', 'title' => '7/24 Nöbetçi Usta', 'icon' => 'nightlight_round', 'color' => '0xFF6366F1'];
                    }
                    if ($monthlyCancelled === 0 && $monthlyJobs >= 5) {
                        $badges[] = ['id' => 'activity_reliable', 'title' => 'Sıfır İptal (%100 Güven)', 'icon' => 'check_circle_rounded', 'color' => '0xFF00FFA3'];
                    }

                    // Grup 4-7: Kategoriye Özel
                    if ($serviceCategory === 'tow') {
                        $badges[] = ['id' => 'tow_heavy', 'title' => 'Ahtapot & Ağır Kurtarma', 'icon' => 'car_repair_rounded', 'color' => '0xFFF59E0B'];
                        if ($monthlyJobs >= 5 && $rating >= 4.60) {
                            $badges[] = ['id' => 'tow_express', 'title' => 'Otoyol Kaplanı', 'icon' => 'local_shipping_rounded', 'color' => '0xFF00FFA3'];
                        }
                    } elseif ($serviceCategory === 'tire') {
                        $badges[] = ['id' => 'tire_mobile', 'title' => 'Mobil Hızır Lastik', 'icon' => 'tire_repair_rounded', 'color' => '0xFF38BDF8'];
                        if ($rating >= 4.70) {
                            $badges[] = ['id' => 'tire_master', 'title' => 'Dört Mevsim Uzmanı', 'icon' => 'sync_problem_rounded', 'color' => '0xFF10B981'];
                        }
                    } elseif ($serviceCategory === 'wash') {
                        $badges[] = ['id' => 'wash_detail', 'title' => 'Detailing & Pasta Cila', 'icon' => 'local_car_wash_rounded', 'color' => '0xFFA855F7'];
                        $badges[] = ['id' => 'wash_eco', 'title' => 'Mobil Buharlı Hijyen', 'icon' => 'water_drop_rounded', 'color' => '0xFF06B6D4'];
                    } elseif ($serviceCategory === 'mechanic') {
                        $badges[] = ['id' => 'mechanic_engine', 'title' => 'Motor & Mekanik Doktoru', 'icon' => 'build_rounded', 'color' => '0xFFEF4444'];
                        $badges[] = ['id' => 'mechanic_electric', 'title' => 'Oto Beyin & Elektronik', 'icon' => 'settings_suggest_rounded', 'color' => '0xFFF59E0B'];
                    }

                    $provider['badges'] = $badges;
                }
            }
            $jobStatusCheck = $pdo->prepare("SELECT * FROM jobs WHERE id = ?");
            $jobStatusCheck->execute([$job_id]);
            $currentJob = $jobStatusCheck->fetch(PDO::FETCH_ASSOC);
            $currentJobStatus = $currentJob['status'] ?? null;
            $simulationFallback = null;
            $providerScan = null;
            if ($user_type !== 'provider' && $currentJobStatus === 'searching') {
                $eligibleProviders = serviceEligibleRealProviders($pdo, $currentJob, 100);
                $providerScan = [
                    'eligible_count' => count($eligibleProviders),
                    'search_radius' => (float)($currentJob['search_radius'] ?? 50),
                    'real_provider_available' => !empty($eligibleProviders),
                ];
                if (empty($bids)) {
                    $simulationFallback = serviceSimulationFallback($pdo, $currentJob);
                }
            }
            
            sendResponse(200, [
                "status" => "success",
                "job_status" => $currentJobStatus,
                "bids" => $bids,
                "provider_scan" => $providerScan,
                "simulation_fallback" => $simulationFallback
            ]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Teklifler çekilirken hata: " . $e->getMessage()]);
        }
        break;

    case 'counter_bid': 
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $bid_id = $_POST['bid_id'] ?? null;
        $user_type = $_POST['user_type'] ?? 'customer';
        // Gelen değer JSON kaynaklı integer olabilir, str_replace hatasını engellemek için (string) kullanıyoruz
        $amount = isset($_POST['amount']) ? (float)str_replace(',', '.', (string)$_POST['amount']) : 0;
        
        if (!$bid_id || !$amount) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        if (!is_finite($amount) || $amount <= 0 || $amount>99999999) sendResponse(400, ["status" => "error", "message" => "Lütfen geçerli bir tutar girin."]);
        
        $lookup=$pdo->prepare('SELECT job_id FROM bids WHERE id=?'); $lookup->execute([$bid_id]); $jobId=$lookup->fetchColumn();
        if (!$jobId) sendResponse(404,['status'=>'error','message'=>'Teklif bulunamadı.']);
        try {
            $pdo->beginTransaction();
            $lockJob=$pdo->prepare('SELECT status FROM jobs WHERE id=? FOR UPDATE'); $lockJob->execute([$jobId]);
            $lockedStatus=$lockJob->fetchColumn();
            $lockBid=$pdo->prepare('SELECT * FROM bids WHERE id=? FOR UPDATE'); $lockBid->execute([$bid_id]); $bid=$lockBid->fetch();
            if ($lockedStatus!=='searching' || !$bid || !in_array($bid['status'],['pending','negotiating'],true)) { $pdo->rollBack(); sendResponse(409,['status'=>'error','message'=>'Bu teklif artık pazarlığa açık değil.']); }
            if ($bid['last_bidder']===$user_type || (isset($_POST['offer_version']) &&
                (filter_var($_POST['offer_version'],FILTER_VALIDATE_INT)===false || (int)$_POST['offer_version']!==(int)$bid['negotiation_count']))) {
                $pdo->rollBack(); sendResponse(409,['status'=>'error','message'=>'Teklif değişti veya yanıt sırası karşı tarafta. Listeyi yenileyin.']);
            }
            if ($bid['negotiation_count']>=2) { $pdo->rollBack(); sendResponse(403,['status'=>'error','message'=>'Maksimum karşı teklif sınırına ulaştınız.']); }
            $stmt=$pdo->prepare("UPDATE bids SET amount=?,negotiation_count=negotiation_count+1,last_bidder=?,status='negotiating' WHERE id=?");
            $stmt->execute([$amount,$user_type,$bid_id]); $pdo->commit();
        } catch (Exception $e) { if ($pdo->inTransaction()) $pdo->rollBack(); sendResponse(500,['status'=>'error','message'=>'Karşı teklif kaydedilemedi.']); }

        try {
            // Müşteri ekranı için ustanın adını ve puanını da çekecek şekilde sorguyu genişletiyoruz
            $provInfo = $pdo->prepare("
                SELECT b.provider_id, b.job_id, b.estimated_time, b.provider_note, j.customer_id,
                       u.name as provider_name,
                       IFNULL((SELECT ROUND(AVG(rating), 1) FROM ratings WHERE provider_id = u.id), 5.0) as average_rating
                FROM bids b 
                LEFT JOIN jobs j ON b.job_id = j.id 
                LEFT JOIN users u ON b.provider_id = u.id
                WHERE b.id = ?
            ");
            $provInfo->execute([$bid_id]);
            $provData = $provInfo->fetch();
            
            if ($provData && !empty($provData['provider_id'])) {
                // Müşteri ekranındaki listenin çökmemesi için payload eksiksiz olmalı
                $payload = [
                    "status" => "counter_bid",
                    "bid" => [
                        "bid_id" => $bid_id,
                        "provider_id" => $provData['provider_id'],
                        "amount" => $amount,
                        "estimated_time" => $provData['estimated_time'] ?? 30,
                        "provider_note" => $provData['provider_note'] ?? '',
                        "negotiation_count" => $bid['negotiation_count'] + 1,
                        "last_bidder" => $user_type,
                        "provider_name" => $provData['provider_name'] ?? 'Usta',
                        "average_rating" => $provData['average_rating']
                    ]
                ];
                // Odadaki herkese (özellikle müşteriye) bildirimi yolla
                triggerPusherEvent("job_".$provData['job_id'], "bid_update", $payload);
                
                $target_id = ($user_type === 'provider') ? (string)$provData['customer_id'] : (string)$provData['provider_id'];
                $msg_title = "Yeni Pazarlık Teklifi Geldi!";
                $msg_body = ($user_type === 'provider') 
                    ? "Usta teklifinize karşılık " . $amount . " ₺ önerdi. İncelemek için dokunun." 
                    : "Müşteri teklifinize karşılık " . $amount . " ₺ önerdi. İncelemek için dokunun.";

                if (!empty($target_id)) {
                    sendOneSignalPush(
                        $target_id, 
                        $msg_title, 
                        $msg_body, 
                        ['type' => 'counter_bid', 'job_id' => (string)$provData['job_id']]
                    );
                }
            }
        } catch (Exception $e) {}

        sendResponse(200, ["status" => "success", "amount" => $amount]);
        break;

    case 'reject_bid':
        if ($method !== 'POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        try {
            $bid=serviceRejectOffer($pdo,(int)($_POST['bid_id'] ?? 0));
            triggerPusherEvent('job_'.$bid['job_id'],'bid_update',['status'=>'rejected']);
            sendOneSignalPush((string)$bid['provider_id'],'Teklif reddedildi','Teklif kapatıldı. Diğer talepleri inceleyebilirsiniz.',['type'=>'bid_update','job_id'=>(string)$bid['job_id']]);
            sendResponse(200,['status'=>'success']);
        } catch (DomainException $e) { sendResponse(409,['status'=>'error','message'=>$e->getMessage()]); }
        break;

    case 'cancel_job':
        if ($method !== 'POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        try {
            $jobId=(int)($_POST['job_id'] ?? 0);
            $actor=authenticateRequest();
            $owner=$pdo->prepare('SELECT customer_id, provider_id FROM jobs WHERE id=?');
            $owner->execute([$jobId]);
            $owner=$owner->fetch(PDO::FETCH_ASSOC);
            if (!$owner || (($actor['user_type'] ?? '') !== 'admin' &&
                (int)$actor['user_id'] !== (int)$owner['customer_id'] &&
                (int)$actor['user_id'] !== (int)($owner['provider_id'] ?? 0))) {
                sendResponse(403,['status'=>'error','message'=>'Bu talebi iptal etme yetkiniz yok.']);
            }
            $job=serviceCancelJob($pdo,$jobId,$_POST['expected_status'] ?? null);
            if ($job['status']!=='cancelled') {
                $targets=array_values(array_filter([(string)$job['customer_id'],(string)($job['provider_id'] ?? '')]));
                sendOneSignalPush($targets,'İşlem iptal edildi','Servis talebi iptal edilmiştir.',['type'=>'job_cancelled','job_id'=>(string)$jobId]);
                triggerPusherEvent('job_'.$jobId,'status_update',['job_status'=>'cancelled','job_id'=>$jobId]);
                triggerPusherEvent('global_jobs','job_cancelled',['job_id'=>$jobId]);
            }
            sendResponse(200,['status'=>'success','message'=>'Talep iptal edildi.']);
        } catch (DomainException $e) { sendResponse(409,['status'=>'error','message'=>$e->getMessage()]); }
        break;

    case 'expire_unanswered_service_job':
        if ($method !== 'POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $jobId=(int)($_POST['job_id'] ?? 0);
        $customerId=(int)($_POST['customer_id'] ?? 0);
        if ($jobId<=0 || $customerId<=0) sendResponse(400,['status'=>'error','message'=>'Geçersiz talep bilgisi.']);
        authenticateRequest($customerId);
        try {
            $pdo->beginTransaction();
            $jobStmt=$pdo->prepare('SELECT * FROM jobs WHERE id=? AND customer_id=? FOR UPDATE');
            $jobStmt->execute([$jobId,$customerId]);
            $job=$jobStmt->fetch(PDO::FETCH_ASSOC);
            if (!$job || $job['service_type']==='rentacar') {
                throw new DomainException('Açık servis talebi bulunamadı.');
            }
            if ($job['status'] !== 'searching') {
                $pdo->commit();
                sendResponse(200,['status'=>'success','job_status'=>$job['status'],'expired'=>false]);
            }
            $bidStmt=$pdo->prepare("SELECT COUNT(*) FROM bids WHERE job_id=? AND status IN ('pending','negotiating','accepted')");
            $bidStmt->execute([$jobId]);
            if ((int)$bidStmt->fetchColumn() > 0) {
                $pdo->commit();
                sendResponse(200,['status'=>'success','job_status'=>'searching','expired'=>false]);
            }
            $createdAt=!empty($job['created_at']) ? strtotime((string)$job['created_at']) : false;
            if ($createdAt!==false) {
                $elapsed=max(0,time()-$createdAt);
                if ($elapsed<60) {
                    $pdo->commit();
                    sendResponse(200,[
                        'status'=>'success',
                        'job_status'=>'searching',
                        'expired'=>false,
                        'retry_after'=>60-$elapsed
                    ]);
                }
            }
            $pdo->prepare("UPDATE jobs SET status='cancelled' WHERE id=? AND status='searching'")->execute([$jobId]);
            $pdo->commit();
            try {
                triggerPusherEvent('job_'.$jobId,'status_update',['job_status'=>'cancelled','job_id'=>$jobId,'reason'=>'no_provider_response']);
                triggerPusherEvent('global_jobs','job_cancelled',['job_id'=>$jobId]);
            } catch (Throwable $e) { error_log('Timed-out job realtime update failed.'); }
            sendResponse(200,['status'=>'success','job_status'=>'cancelled','expired'=>true]);
        } catch (DomainException $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(409,['status'=>'error','message'=>$e->getMessage()]);
        } catch (Throwable $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            error_log('Unanswered service job expiry failed: '.$e->getMessage());
            sendResponse(500,['status'=>'error','message'=>'Talep süresi güncellenemedi.']);
        }
        break;

    case 'customer_payment':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        if (!$job_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $jobStmt = $pdo->prepare("SELECT customer_id, provider_id, status FROM jobs WHERE id = ?");
        $jobStmt->execute([$job_id]);
        $jobData = $jobStmt->fetch();

        if (!$jobData || strtolower($jobData['status']) !== 'in_progress') {
            sendResponse(400, ["status" => "error", "message" => "İşlem durumu ödeme bildirimi için uygun değil."]);
        }

        $pdo->prepare("UPDATE jobs SET status = 'customer_paid' WHERE id = ? AND status = 'in_progress'")->execute([$job_id]);

        try {
            if (!empty($jobData['provider_id'])) {
                sendOneSignalPush(
                    (string)$jobData['provider_id'],
                    "Ödeme Bildirimi Geldi!",
                    "Müşteri ödemeyi gönderdiğini onayladı. Hesabınızı kontrol edip işi bitirin.",
                    ['type' => 'payment_sent', 'job_id' => (string)$job_id]
                );
            }
        } catch (Exception $e) {}

        sendResponse(200, ["status" => "success"]);
        break;

    case 'provider_payment':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        if (!$job_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmt = $pdo->prepare("SELECT customer_id, provider_id, status, after_photo FROM jobs WHERE id = ?");
        $stmt->execute([$job_id]);
        $job = $stmt->fetch();

        if (empty($job['after_photo'])) {
            sendResponse(400, ["status" => "error", "message" => "İşi bitirmeden önce onarılan parçanın/aracın bitmiş halinin fotoğrafını yüklemelisiniz."]);
        }
        
        if ($job && strtolower($job['status']) === 'customer_paid') {
            $pdo->prepare("UPDATE jobs SET status = 'completed' WHERE id = ?")->execute([$job_id]);
            referralRewardForCompletedJob($pdo,(int)$job_id);

            try {
                if (!empty($job['customer_id'])) {
                    sendOneSignalPush(
                        (string)$job['customer_id'],
                        "İşlem Tamamlandı!",
                        "Ustanız ödemeyi onayladı ve işlemi tamamladı. Lütfen hizmeti değerlendirin!",
                        ['type' => 'job_completed', 'job_id' => (string)$job_id]
                    );
                }
            } catch (Exception $e) {}

            sendResponse(200, ["status" => "success"]);
        } else {
            sendResponse(403, ["status" => "error", "message" => "Müşteri henüz ödeme onayı vermedi veya işlem tamamlanmış."]);
        }
        break;

    case 'add_rating':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $provider_id = $_POST['provider_id'] ?? null;
        $customer_id = $_POST['customer_id'] ?? null;
        $rating = $_POST['rating'] ?? null;
        $comment = $_POST['comment'] ?? '';
        $rater_type = $_POST['rater_type'] ?? 'customer';
        
        if (!$job_id || !$provider_id || !$customer_id || !$rating) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            // rater_type kontrolü tamamlandı

            $pdo->beginTransaction();
            $stmt = $pdo->prepare("INSERT INTO ratings (job_id, provider_id, customer_id, rating, comment, rater_type) VALUES (?, ?, ?, ?, ?, ?)");
            $stmt->execute([$job_id, $provider_id, $customer_id, $rating, $comment, $rater_type]);

            if ($rater_type === 'provider') {
                $updatePerf = $pdo->prepare("UPDATE users SET rating = (SELECT ROUND(AVG(rating), 1) FROM ratings WHERE customer_id = ? AND rater_type = 'provider'), reviews_count = (SELECT COUNT(*) FROM ratings WHERE customer_id = ? AND rater_type = 'provider') WHERE id = ?");
                $updatePerf->execute([$customer_id, $customer_id, $customer_id]);
            } else {
                $updatePerf = $pdo->prepare("UPDATE users SET rating = (SELECT ROUND(AVG(rating), 1) FROM ratings WHERE provider_id = ? AND (rater_type = 'customer' OR rater_type IS NULL)), reviews_count = (SELECT COUNT(*) FROM ratings WHERE provider_id = ? AND (rater_type = 'customer' OR rater_type IS NULL)) WHERE id = ?");
                $updatePerf->execute([$provider_id, $provider_id, $provider_id]);
            }

            $pdo->commit();
            if ($redis && !empty($provider_id)) {
                $redis->del("prov_profile_" . $provider_id);
            }
            sendResponse(201, ["status" => "success", "message" => "Değerlendirme kaydedildi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Değerlendirme kaydedilemedi."]);
        }
        break;

    case 'appeal_rating':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $provider_id = $_POST['provider_id'] ?? null;
        $reason = trim($_POST['reason'] ?? '');
        
        if (!$job_id || !$provider_id || empty($reason)) {
            sendResponse(400, ["status" => "error", "message" => "İtiraz gerekçesi belirtmelisiniz."]);
        }
        
        $rateStmt = $pdo->prepare("SELECT id FROM ratings WHERE job_id = ? AND provider_id = ?");
        $rateStmt->execute([$job_id, $provider_id]);
        $rating = $rateStmt->fetch();
        if (!$rating) {
            sendResponse(404, ["status" => "error", "message" => "Bu işe ait müşteri değerlendirmesi bulunamadı."]);
        }

        try {
            $pdo->prepare("INSERT INTO rating_appeals (rating_id, provider_id, reason) VALUES (?, ?, ?)")
                ->execute([$rating['id'], $provider_id, $reason]);
            sendResponse(200, ["status" => "success", "message" => "İtirazınız hakem heyetine iletildi. İnceleme sonrası algoritma puanınız revize edilecektir."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "İtiraz kaydedilemedi."]);
        }
        break;

    case 'get_provider_profile':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $provider_id = $_GET['provider_id'] ?? null;
        if (!$provider_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        $cacheKey = "prov_profile_{$provider_id}";
        if ($redis) {
            $cached = $redis->get($cacheKey);
            if ($cached) {
                sendResponse(200, json_decode($cached, true));
            }
        }

        ensureGrowthSchema($pdo);
        $stmt = $pdo->prepare("SELECT id,name,service_category,user_type,status,is_suspended,tax_plate,driver_license,tow_plate,map_link FROM users WHERE id = ? AND user_type = 'provider'");
        $stmt->execute([$provider_id]);
        $provider = $stmt->fetch();
        if ($provider) {
            $provider['verified'] = growthProviderVerification($provider);
            unset($provider['status'],$provider['is_suspended'],$provider['tax_plate'],$provider['driver_license'],$provider['tow_plate'],$provider['map_link']);
        }
        if (!$provider) sendResponse(404, ["status" => "error", "message" => "Usta bulunamadı."]);

        $ratingsStmt = $pdo->prepare("SELECT r.rating, r.comment, DATE_FORMAT(r.created_at, '%d.%m.%Y') AS date, u.name as customer_name FROM ratings r JOIN users u ON r.customer_id = u.id WHERE r.provider_id = ? AND r.comment IS NOT NULL AND TRIM(r.comment) != '' ORDER BY r.created_at DESC LIMIT 50");
        $ratingsStmt->execute([$provider_id]);
        $ratings = $ratingsStmt->fetchAll();

        $avgStmt = $pdo->prepare("SELECT rating as avg_rating, reviews_count as total_reviews FROM users WHERE id = ?");
        $avgStmt->execute([$provider_id]);
        $stats = $avgStmt->fetch();

        $completedStmt = $pdo->prepare("SELECT COUNT(*) FROM jobs WHERE provider_id=? AND status='completed'");
        $completedStmt->execute([$provider_id]);
        $completedJobs=(int)$completedStmt->fetchColumn();

        $assignedStmt=$pdo->prepare("SELECT COUNT(*) total,
            SUM(status='cancelled') cancelled,
            MAX(created_at) last_job_at
            FROM jobs WHERE provider_id=?");
        $assignedStmt->execute([$provider_id]);
        $assigned=$assignedStmt->fetch(PDO::FETCH_ASSOC) ?: [];
        $assignedTotal=(int)($assigned['total'] ?? 0);
        $cancelled=(int)($assigned['cancelled'] ?? 0);

        $responseStmt=$pdo->prepare("SELECT AVG(TIMESTAMPDIFF(MINUTE,j.created_at,b.created_at)) avg_response_min,
            MAX(b.created_at) last_bid_at
            FROM bids b JOIN jobs j ON j.id=b.job_id
            WHERE b.provider_id=? AND b.created_at>=DATE_SUB(NOW(),INTERVAL 90 DAY)");
        $responseStmt->execute([$provider_id]);
        $responseStats=$responseStmt->fetch(PDO::FETCH_ASSOC) ?: [];

        $profilePayload = [
            "status" => "success", 
            "provider" => $provider, 
            "stats" => [
                "average" => $stats['avg_rating'] ?? "0.0",
                "total" => $stats['total_reviews'] ?? 0,
                "completed_jobs" => $completedJobs,
                "avg_response_min" => round((float)($responseStats['avg_response_min'] ?? 0),1),
                "cancellation_rate" => $assignedTotal>0 ? round($cancelled*100/$assignedTotal,1) : 0,
                "last_active" => $responseStats['last_bid_at'] ?? ($assigned['last_job_at'] ?? null)
            ],
            "reviews" => $ratings
        ];
        if ($redis) {
            $redis->setex($cacheKey, 120, json_encode($profilePayload));
        }
        sendResponse(200, $profilePayload);
        break;

    case 'get_vehicles':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $customer_id = $_GET['customer_id'] ?? null;
        if (!$customer_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $cacheKey = "cust_vehicles_{$customer_id}";
        if ($redis) {
            $cached = $redis->get($cacheKey);
            if ($cached) {
                sendResponse(200, ["status" => "success", "vehicles" => json_decode($cached, true)]);
            }
        }

        $stmt = $pdo->prepare("SELECT * FROM vehicles WHERE customer_id = ? ORDER BY id DESC");
        $stmt->execute([$customer_id]);
        $vehicles = $stmt->fetchAll();
        if ($redis) {
            $redis->setex($cacheKey, 120, json_encode($vehicles));
        }
        sendResponse(200, ["status" => "success", "vehicles" => $vehicles]);
        break;

    case 'add_vehicle':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $customer_id = $_POST['customer_id'] ?? null;
        authenticateRequest($customer_id); 
        
        $plate = $_POST['plate'] ?? null;
        $brand_model = $_POST['brand_model'] ?? null;
        $engine_type = $_POST['engine_type'] ?? null; 
        $model_year = $_POST['model_year'] ?? null;   
        $insurance_date = $_POST['insurance_date'] ?? null;
        $inspection_date = $_POST['inspection_date'] ?? null;
        $mtv_date = $_POST['mtv_date'] ?? null;
        $current_km = $_POST['current_km'] ?? 0;
        $maintenance_km = $_POST['maintenance_km'] ?? 10000;

        if (!$customer_id || !$plate || !$brand_model) {
            sendResponse(400, ["status" => "error", "message" => "Müşteri ID, plaka ve marka/model zorunludur."]);
        }

        $countStmt = $pdo->prepare("SELECT COUNT(*) FROM vehicles WHERE customer_id = ?");
        $countStmt->execute([$customer_id]);
        $vehicleCount = (int)$countStmt->fetchColumn();

        if ($vehicleCount >= 1) {
            $userCheck = $pdo->prepare("SELECT is_premium FROM users WHERE id = ?");
            $userCheck->execute([$customer_id]);
            $isPremium = (int)($userCheck->fetchColumn() ?? 0);

            if (!$isPremium) {
                sendResponse(429, [
                    "status" => "limit_reached", 
                    "message" => "Ücretsiz araç ekleme sınırına (1 araç) ulaştınız. Sınırsız araç eklemek için OTOTAG Premium paketine geçiş yapın."
                ]);
            }
        }

        try {
            $stmt = $pdo->prepare("INSERT INTO vehicles (customer_id, plate, brand_model, engine_type, model_year, insurance_date, inspection_date, mtv_date, current_km, maintenance_km) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
            $stmt->execute([$customer_id, strtoupper($plate), $brand_model, $engine_type, $model_year, $insurance_date, $inspection_date, $mtv_date, $current_km, $maintenance_km]);
            if ($redis) { $redis->del("cust_vehicles_" . $customer_id); }
            sendResponse(201, ["status" => "success", "message" => "Araç başarıyla eklendi.", "vehicle_id" => $pdo->lastInsertId()]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Araç eklenirken bir hata oluştu."]);
        }
        break;

    case 'update_vehicle':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $vehicle_id = $_POST['vehicle_id'] ?? null;
        $customer_id = $_POST['customer_id'] ?? null;
        $plate = $_POST['plate'] ?? null;
        $brand_model = $_POST['brand_model'] ?? null;
        $engine_type = $_POST['engine_type'] ?? null; 
        $model_year = $_POST['model_year'] ?? null;   
        $insurance_date = $_POST['insurance_date'] ?? null;
        $inspection_date = $_POST['inspection_date'] ?? null;
        $mtv_date = $_POST['mtv_date'] ?? null;
        $current_km = $_POST['current_km'] ?? 0;
        $maintenance_km = $_POST['maintenance_km'] ?? 10000;

        if (!$vehicle_id || !$customer_id || !$plate || !$brand_model) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        }

        try {
            $stmt = $pdo->prepare("UPDATE vehicles SET plate = ?, brand_model = ?, engine_type = ?, model_year = ?, insurance_date = ?, inspection_date = ?, mtv_date = ?, current_km = ?, maintenance_km = ? WHERE id = ? AND customer_id = ?");
            $stmt->execute([strtoupper($plate), $brand_model, $engine_type, $model_year, $insurance_date, $inspection_date, $mtv_date, $current_km, $maintenance_km, $vehicle_id, $customer_id]);
            if ($redis) { $redis->del("cust_vehicles_" . $customer_id); }
            sendResponse(200, ["status" => "success", "message" => "Araç bilgileri güncellendi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Güncelleme sırasında hata oluştu."]);
        }
        break;

    case 'delete_vehicle':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $vehicle_id = $_POST['vehicle_id'] ?? null;
        $customer_id = $_POST['customer_id'] ?? null;

        if (!$vehicle_id || !$customer_id) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        }
        authenticateRequest($customer_id); 

        try {
            $checkStmt = $pdo->prepare("SELECT id FROM vehicles WHERE id = ? AND customer_id = ?");
            $checkStmt->execute([$vehicle_id, $customer_id]);
            if (!$checkStmt->fetch()) {
                sendResponse(403, ["status" => "error", "message" => "Yetkisiz silme işlemi."]);
            }

            $recStmt = $pdo->prepare("SELECT document_url, image_url FROM vehicle_records WHERE vehicle_id = ?");
            $recStmt->execute([$vehicle_id]);
            $records = $recStmt->fetchAll();
            foreach ($records as $r) {
                if (!empty($r['document_url']) && file_exists(__DIR__ . '/' . $r['document_url'])) {
                    @unlink(__DIR__ . '/' . $r['document_url']);
                }
                if (!empty($r['image_url']) && file_exists(__DIR__ . '/' . $r['image_url'])) {
                    @unlink(__DIR__ . '/' . $r['image_url']);
                }
            }
            $pdo->prepare("DELETE FROM vehicle_records WHERE vehicle_id = ?")->execute([$vehicle_id]);
            $stmt = $pdo->prepare("DELETE FROM vehicles WHERE id = ? AND customer_id = ?");
            $stmt->execute([$vehicle_id, $customer_id]);
            if ($redis) { $redis->del("cust_vehicles_" . $customer_id); }
            sendResponse(200, ["status" => "success", "message" => "Araç ve tüm kayıtları başarıyla silindi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Araç silinemedi."]);
        }
        break;

    case 'get_vehicle_records':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $vehicle_id = $_GET['vehicle_id'] ?? null;
        if (!$vehicle_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $stmt = $pdo->prepare("SELECT * FROM vehicle_records WHERE vehicle_id = ? ORDER BY id DESC");
        $stmt->execute([$vehicle_id]);
        sendResponse(200, ["status" => "success", "records" => $stmt->fetchAll()]);
        break;

    case 'add_vehicle_record':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        
        $vehicle_id = $_POST['vehicle_id'] ?? null;
        $record_type = $_POST['record_type'] ?? null;
        $description = $_POST['description'] ?? '';
        $next_date = $_POST['next_date'] ?? null;
        $current_km = $_POST['current_km'] ?? null;
        $maintenance_km = $_POST['maintenance_km'] ?? null;
        $created_at = $_POST['created_at'] ?? null;
        $cost = isset($_POST['cost']) ? (float)str_replace(',', '.', $_POST['cost']) : 0;
        
        if (!$vehicle_id || !$record_type) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        
        $doc_url = null;
        $image_url = null;
        
        $upload_dir = __DIR__ . '/uploads/';
        if (!is_dir($upload_dir)) {
            @mkdir($upload_dir, 0777, true);
        }
        
        if (isset($_FILES['document']) && $_FILES['document']['error'] === UPLOAD_ERR_OK) {
            if ($_FILES['document']['size'] > 10 * 1024 * 1024) sendResponse(400, ["status" => "error", "message" => "Belge boyutu 10MB'ı geçemez."]);
            $ext = strtolower(pathinfo($_FILES['document']['name'], PATHINFO_EXTENSION));
            $allowed_doc = ['pdf', 'doc', 'docx'];
            if (in_array($ext, $allowed_doc) && isSafeFile($_FILES['document']['tmp_name'], $allowed_doc)) {
                $doc_name = time() . '_doc_' . uniqid() . '.' . $ext;
                if (move_uploaded_file($_FILES['document']['tmp_name'], $upload_dir . $doc_name)) {
                    $doc_url = 'uploads/' . $doc_name;
                }
            }
        }
        
        if (isset($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
            if ($_FILES['image']['size'] > 10 * 1024 * 1024) sendResponse(400, ["status" => "error", "message" => "Resim boyutu 10MB'ı geçemez."]);
            $ext = strtolower(pathinfo($_FILES['image']['name'], PATHINFO_EXTENSION));
            $allowed_img = ['jpg', 'jpeg', 'png', 'webp'];
            if (in_array($ext, $allowed_img) && isSafeFile($_FILES['image']['tmp_name'], $allowed_img)) {
                $img_name = time() . '_img_' . uniqid() . '.' . $ext;
                if (move_uploaded_file($_FILES['image']['tmp_name'], $upload_dir . $img_name)) {
                    $image_url = 'uploads/' . $img_name;
                }
            }
        }
        
        try {
            $pdo->beginTransaction();

            if ($created_at) {
                $stmt = $pdo->prepare("INSERT INTO vehicle_records (vehicle_id, record_type, description, cost, document_url, image_url, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)");
                $stmt->execute([$vehicle_id, $record_type, $description, $cost, $doc_url, $image_url, $created_at]);
            } else {
                $stmt = $pdo->prepare("INSERT INTO vehicle_records (vehicle_id, record_type, description, cost, document_url, image_url) VALUES (?, ?, ?, ?, ?, ?)");
                $stmt->execute([$vehicle_id, $record_type, $description, $cost, $doc_url, $image_url]);
            }
            
            if ($record_type === 'Muayene' && $next_date) {
                $pdo->prepare("UPDATE vehicles SET inspection_date = ? WHERE id = ?")->execute([$next_date, $vehicle_id]);
            } elseif ($record_type === 'Sigorta' && $next_date) {
                $pdo->prepare("UPDATE vehicles SET insurance_date = ? WHERE id = ?")->execute([$next_date, $vehicle_id]);
            }
            
            if ($current_km !== null && $current_km !== '') {
                $pdo->prepare("UPDATE vehicles SET current_km = ? WHERE id = ?")->execute([$current_km, $vehicle_id]);
            }
            if ($record_type === 'Periyodik Bakım' && $maintenance_km !== null && $maintenance_km !== '') {
                $pdo->prepare("UPDATE vehicles SET maintenance_km = ? WHERE id = ?")->execute([$maintenance_km, $vehicle_id]);
            }

            $pdo->commit();
            sendResponse(201, ["status" => "success", "message" => "İşlem başarıyla eklendi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Veritabanına kaydedilemedi."]);
        }
        break;

    case 'update_vehicle_record':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $record_id = $_POST['record_id'] ?? null;
        $vehicle_id = $_POST['vehicle_id'] ?? null;
        $record_type = $_POST['record_type'] ?? null;
        $description = $_POST['description'] ?? '';
        $next_date = $_POST['next_date'] ?? null;
        $current_km = $_POST['current_km'] ?? null;
        $maintenance_km = $_POST['maintenance_km'] ?? null;
        $created_at = $_POST['created_at'] ?? null;
        $cost = isset($_POST['cost']) ? (float)str_replace(',', '.', $_POST['cost']) : 0;

        if (!$record_id || !$vehicle_id || !$record_type) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        }

        $upload_dir = __DIR__ . '/uploads/';
        if (!is_dir($upload_dir)) {
            @mkdir($upload_dir, 0777, true);
        }

        try {
            $pdo->beginTransaction();

            $existingStmt = $pdo->prepare("SELECT document_url, image_url FROM vehicle_records WHERE id = ? AND vehicle_id = ?");
            $existingStmt->execute([$record_id, $vehicle_id]);
            $existing = $existingStmt->fetch();

            if (!$existing) {
                $pdo->rollBack();
                sendResponse(404, ["status" => "error", "message" => "Kayıt bulunamadı veya yetkiniz yok."]);
            }

            $doc_url = $existing['document_url'] ?? null;
            $image_url = $existing['image_url'] ?? null;

            if (isset($_FILES['document']) && $_FILES['document']['error'] === UPLOAD_ERR_OK) {
                $ext = strtolower(pathinfo($_FILES['document']['name'], PATHINFO_EXTENSION));
                $allowed_doc = ['pdf', 'doc', 'docx'];
                if (in_array($ext, $allowed_doc) && isSafeFile($_FILES['document']['tmp_name'], $allowed_doc)) {
                    if (!empty($doc_url) && file_exists(__DIR__ . '/' . $doc_url)) {
                        @unlink(__DIR__ . '/' . $doc_url);
                    }
                    $doc_name = time() . '_doc_' . uniqid() . '.' . $ext;
                    if (move_uploaded_file($_FILES['document']['tmp_name'], $upload_dir . $doc_name)) {
                        $doc_url = 'uploads/' . $doc_name;
                    }
                }
            }

            if (isset($_FILES['image']) && $_FILES['image']['error'] === UPLOAD_ERR_OK) {
                $ext = strtolower(pathinfo($_FILES['image']['name'], PATHINFO_EXTENSION));
                $allowed_img = ['jpg', 'jpeg', 'png', 'webp'];
                if (in_array($ext, $allowed_img) && isSafeFile($_FILES['image']['tmp_name'], $allowed_img)) {
                    if (!empty($image_url) && file_exists(__DIR__ . '/' . $image_url)) {
                        @unlink(__DIR__ . '/' . $image_url);
                    }
                    $img_name = time() . '_img_' . uniqid() . '.' . $ext;
                    if (move_uploaded_file($_FILES['image']['tmp_name'], $upload_dir . $img_name)) {
                        $image_url = 'uploads/' . $img_name;
                    }
                }
            }

            if ($created_at) {
                $stmt = $pdo->prepare("UPDATE vehicle_records SET record_type = ?, description = ?, cost = ?, document_url = ?, image_url = ?, created_at = ? WHERE id = ? AND vehicle_id = ?");
                $stmt->execute([$record_type, $description, $cost, $doc_url, $image_url, $created_at, $record_id, $vehicle_id]);
            } else {
                $stmt = $pdo->prepare("UPDATE vehicle_records SET record_type = ?, description = ?, cost = ?, document_url = ?, image_url = ? WHERE id = ? AND vehicle_id = ?");
                $stmt->execute([$record_type, $description, $cost, $doc_url, $image_url, $record_id, $vehicle_id]);
            }

            if ($record_type === 'Muayene' && $next_date) {
                $pdo->prepare("UPDATE vehicles SET inspection_date = ? WHERE id = ?")->execute([$next_date, $vehicle_id]);
            } elseif ($record_type === 'Sigorta' && $next_date) {
                $pdo->prepare("UPDATE vehicles SET insurance_date = ? WHERE id = ?")->execute([$next_date, $vehicle_id]);
            }

            if ($current_km !== null && $current_km !== '') {
                $pdo->prepare("UPDATE vehicles SET current_km = ? WHERE id = ?")->execute([$current_km, $vehicle_id]);
            }
            if ($record_type === 'Periyodik Bakım' && $maintenance_km !== null && $maintenance_km !== '') {
                $pdo->prepare("UPDATE vehicles SET maintenance_km = ? WHERE id = ?")->execute([$maintenance_km, $vehicle_id]);
            }

            $pdo->commit();
            sendResponse(200, ["status" => "success", "message" => "İşlem başarıyla güncellendi."]);
        } catch (Exception $e) {
            if ($pdo->inTransaction()) $pdo->rollBack();
            sendResponse(500, ["status" => "error", "message" => "Güncelleme sırasında hata oluştu."]);
        }
        break;

    case 'delete_vehicle_record':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $record_id = $_POST['record_id'] ?? null;
        $vehicle_id = $_POST['vehicle_id'] ?? null;

        if (!$record_id || !$vehicle_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $stmt = $pdo->prepare("SELECT document_url, image_url FROM vehicle_records WHERE id = ? AND vehicle_id = ?");
            $stmt->execute([$record_id, $vehicle_id]);
            $rec = $stmt->fetch();
            
            if ($rec) {
                if (!empty($rec['document_url']) && file_exists(__DIR__ . '/' . $rec['document_url'])) {
                    @unlink(__DIR__ . '/' . $rec['document_url']);
                }
                if (!empty($rec['image_url']) && file_exists(__DIR__ . '/' . $rec['image_url'])) {
                    @unlink(__DIR__ . '/' . $rec['image_url']);
                }
                $delStmt = $pdo->prepare("DELETE FROM vehicle_records WHERE id = ? AND vehicle_id = ?");
                $delStmt->execute([$record_id, $vehicle_id]);
                sendResponse(200, ["status" => "success", "message" => "Kayıt başarıyla silindi."]);
            } else {
                sendResponse(404, ["status" => "error", "message" => "Kayıt bulunamadı veya yetkisiz işlem."]);
            }
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Kayıt silinemedi."]);
        }
        break;

    case 'create_ticket':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $customer_id = $_POST['customer_id'] ?? null;
        $provider_id = $_POST['provider_id'] ?? null;
        $subject = $_POST['subject'] ?? null;
        $message = $_POST['message'] ?? null;

        if (!$job_id || !$customer_id || !$provider_id || !$subject || !$message) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        }

        try {
            rentalEnsureSchema($pdo);
            $ticketAuth=authenticateRequest();
            $stmt = $pdo->prepare("INSERT INTO tickets (job_id, customer_id, provider_id, reporter_id, subject, message, status) VALUES (?, ?, ?, ?, ?, ?, 'open')");
            $stmt->execute([$job_id, $customer_id, $provider_id, $ticketAuth['user_id'], $subject, $message]);
            sendResponse(200, ["status" => "success", "message" => "Şikayet oluşturuldu."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Şikayet kaydedilemedi."]);
        }
        break;

    case 'get_tickets':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        try {
            rentalEnsureSchema($pdo);
            $stmt = $pdo->query("SELECT t.*, c.name as customer_name, c.phone AS customer_phone, p.name as provider_name,
                                 COALESCE(r.user_type,'customer') AS creator_type, COALESCE(r.name,c.name) AS reporter_name,
                                 CASE WHEN t.reporter_id=t.provider_id THEN c.name ELSE p.name END AS reported_name
                                 FROM tickets t 
                                 LEFT JOIN users c ON t.customer_id = c.id 
                                 LEFT JOIN users p ON t.provider_id = p.id 
                                 LEFT JOIN users r ON t.reporter_id = r.id
                                 ORDER BY t.created_at DESC LIMIT 500");
            sendResponse(200, ["status" => "success", "tickets" => $stmt->fetchAll()]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Şikayetler getirilemedi."]);
        }
        break;

    case 'update_ticket_status':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $ticket_id = $_POST['ticket_id'] ?? null;
        $status = $_POST['status'] ?? null;

        if (!$ticket_id || !$status) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);

        try {
            $stmt = $pdo->prepare("UPDATE tickets SET status = ? WHERE id = ?");
            $stmt->execute([$status, $ticket_id]);
            sendResponse(200, ["status" => "success", "message" => "Durum güncellendi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Durum güncellenemedi."]);
        }
        break;

    case 'admin_delete_ticket':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);
        $ticket_id = $_POST['ticket_id'] ?? null;
        if (!$ticket_id) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        try {
            $pdo->prepare("DELETE FROM tickets WHERE id = ?")->execute([$ticket_id]);
            sendResponse(200, ["status" => "success", "message" => "Şikayet kaydı silindi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "İşlem silinemedi."]);
        }
        break;

    case 'trigger_sos':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $job_id = $_POST['job_id'] ?? null;
        $user_id = $_POST['user_id'] ?? null;
        $lat = $_POST['lat'] ?? "0.0";
        $lng = $_POST['lng'] ?? "0.0";

        try {
            $pdo->prepare("INSERT INTO notifications (user_id, title, message) VALUES (?, 'ACİL DURUM (SOS)', ?)")
                ->execute([$user_id, "Acil durum sinyali alındı. Konum: $lat, $lng"]);

            sendResponse(200, ["status" => "success", "message" => "SOS sinyali kaydedildi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "SOS kaydedilemedi."]);
        }
        break;

    case 'change_password':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $old_password = $_POST['old_password'] ?? null;
        $new_password = $_POST['new_password'] ?? null;

        if (!$user_id || !$old_password || !$new_password) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        authenticateRequest($user_id);

        $stmt = $pdo->prepare("SELECT password FROM users WHERE id = ?");
        $stmt->execute([$user_id]);
        $user = $stmt->fetch();

        if ($user && password_verify($old_password, $user['password'])) {
            $hashed = password_hash($new_password, PASSWORD_DEFAULT);
            $pdo->prepare("UPDATE users SET password = ? WHERE id = ?")->execute([$hashed, $user_id]);
            sendResponse(200, ["status" => "success", "message" => "Şifre güncellendi."]);
        } else {
            sendResponse(403, ["status" => "error", "message" => "Mevcut şifre hatalı."]);
        }
        break;

   case 'send_feedback':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = $_POST['user_id'] ?? null;
        $message = $_POST['message'] ?? null;

        if (!$user_id || !$message) sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        authenticateRequest($user_id);

        try {
            $pdo->prepare("INSERT INTO feedbacks (user_id, message) VALUES (?, ?)")->execute([$user_id, $message]);
            sendResponse(200, ["status" => "success", "message" => "Geri bildirim gönderildi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Geri bildirim kaydedilemedi."]);
        }
        break;

    case 'get_feedbacks':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        try {
            $stmt = $pdo->query("SELECT f.*, u.name as user_name FROM feedbacks f LEFT JOIN users u ON f.user_id = u.id ORDER BY f.created_at DESC LIMIT 200");
            sendResponse(200, ["status" => "success", "feedbacks" => $stmt->fetchAll()]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Geri bildirimler alınamadı."]);
        }
        break;

    case 'log_telemetry':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        $user_id = !empty($_POST['user_id']) ? (int)$_POST['user_id'] : null;
        $user_type = $_POST['user_type'] ?? 'customer';
        $event_type = trim($_POST['event_type'] ?? 'button_click'); 
        $event_name = trim($_POST['event_name'] ?? '');
        $screen_name = trim($_POST['screen_name'] ?? '');
        $duration_seconds = isset($_POST['duration_seconds']) ? (int)$_POST['duration_seconds'] : 0;
        $metadata = $_POST['metadata'] ?? null;

        if (empty($event_name) || empty($screen_name)) {
            sendResponse(400, ["status" => "error", "message" => "event_name ve screen_name zorunludur."]);
        }

        try {
            $stmt = $pdo->prepare("
                INSERT INTO app_telemetry 
                (user_id, user_type, event_type, event_name, screen_name, duration_seconds, metadata) 
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ");
            $stmt->execute([
                $user_id, 
                $user_type, 
                $event_type, 
                $event_name, 
                $screen_name, 
                $duration_seconds, 
                is_array($metadata) ? json_encode($metadata, JSON_UNESCAPED_UNICODE) : $metadata
            ]);

            sendResponse(201, ["status" => "success", "message" => "Telemetri kaydedildi."]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Telemetri kaydedilemedi: " . $e->getMessage()]);
        }
        break;

    case 'admin_get_telemetry_stats':
        if ($method !== 'GET') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        authenticateRequest(null, true);

        try {
            // 1. Tıklamalar
            $topButtonsStmt = $pdo->query("
                SELECT event_name, screen_name, COUNT(*) as click_count 
                FROM app_telemetry 
                WHERE event_type = 'button_click' 
                AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                GROUP BY event_name, screen_name 
                ORDER BY click_count DESC 
                LIMIT 15
            ");
            $topButtons = $topButtonsStmt->fetchAll();

            // 2. Bekleme Süreleri (Darboğazlar)
            $longestWaitsStmt = $pdo->query("
                SELECT screen_name, event_name, 
                       ROUND(AVG(duration_seconds), 1) as avg_duration_sec,
                       MAX(duration_seconds) as max_duration_sec,
                       COUNT(*) as total_samples
                FROM app_telemetry 
                WHERE event_type = 'wait_time' AND duration_seconds > 0
                AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                GROUP BY screen_name, event_name 
                ORDER BY avg_duration_sec DESC 
                LIMIT 15
            ");
            $longestWaits = $longestWaitsStmt->fetchAll();

            // 3. Kullanıcı Vazgeçmeleri ve Terk Noktaları (User Drops)
            $userDropsStmt = $pdo->query("
                SELECT screen_name, event_name, metadata, COUNT(*) as drop_count,
                       ROUND(AVG(duration_seconds), 1) as avg_wait_before_drop,
                       MAX(created_at) as last_seen
                FROM app_telemetry 
                WHERE event_type = 'user_drop'
                AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                GROUP BY screen_name, event_name, metadata
                ORDER BY drop_count DESC 
                LIMIT 15
            ");
            $userDrops = $userDropsStmt->fetchAll();

            // 4. Gerçek Yazılımsal Hatalar & Çökmeler (Crash/Bug)
            $topErrorsStmt = $pdo->query("
                SELECT screen_name, event_name, metadata, COUNT(*) as error_count, MAX(created_at) as last_seen
                FROM app_telemetry 
                WHERE event_type = 'app_error'
                AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
                GROUP BY screen_name, event_name, metadata
                ORDER BY error_count DESC 
                LIMIT 15
            ");
            $topErrors = $topErrorsStmt->fetchAll();

            // 5. Canlı Telemetri Akışı (Son 25 Etkinlik)
            $recentStreamStmt = $pdo->query("
                SELECT user_id, user_type, event_type, event_name, screen_name, duration_seconds, metadata, created_at
                FROM app_telemetry 
                ORDER BY id DESC 
                LIMIT 25
            ");
            $recentStream = $recentStreamStmt->fetchAll();

            // 6. Özet Sayaçları (Hata ve Vazgeçme Ayrılmış Olarak)
            $summaryStmt = $pdo->query("
                SELECT 
                    COUNT(*) as total_events,
                    SUM(CASE WHEN event_type = 'button_click' THEN 1 ELSE 0 END) as total_clicks,
                    SUM(CASE WHEN event_type = 'user_drop' THEN 1 ELSE 0 END) as total_drops,
                    SUM(CASE WHEN event_type = 'app_error' THEN 1 ELSE 0 END) as total_errors,
                    ROUND(AVG(CASE WHEN event_type = 'wait_time' AND duration_seconds > 0 THEN duration_seconds ELSE NULL END), 1) as overall_avg_wait_sec
                FROM app_telemetry
                WHERE created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
            ");
            $summary = $summaryStmt->fetch();

            sendResponse(200, [
                "status" => "success",
                "summary" => $summary,
                "top_buttons" => $topButtons,
                "longest_waits" => $longestWaits,
                "user_drops" => $userDrops,
                "top_errors" => $topErrors,
                "recent_stream" => $recentStream
            ]);
        } catch (Exception $e) {
            sendResponse(500, ["status" => "error", "message" => "Telemetri verileri alınamadı: " . $e->getMessage()]);
        }
        break;

    case 'pusher_auth':
        if ($method !== 'POST') sendResponse(405, ["status" => "error", "message" => "Geçersiz metod."]);
        
        // Pusher Private/Presence Kanalları için JWT Güvenlik Kontrolü
        authenticateRequest(); 
        
        $socket_id = $_POST['socket_id'] ?? null;
        $channel_name = $_POST['channel_name'] ?? null;

        if (!$socket_id || !$channel_name) {
            sendResponse(400, ["status" => "error", "message" => "Eksik parametre."]);
        }

        $auth = authenticateRequest();
        if (!preg_match('/^\d+\.\d+$/D', $socket_id)) sendResponse(400,['status'=>'error','message'=>'Geçersiz soket.']);
        if ($channel_name==='private-admin_rental') {
            if ($auth['user_type']!=='admin') sendResponse(403,['status'=>'error','message'=>'Yönetici kanalı için yetkiniz yok.']);
        } elseif (preg_match('/^private-chat_(\d+)$/D', $channel_name, $m)) {
            $stmt=$pdo->prepare('SELECT customer_id,provider_id FROM jobs WHERE id=?'); $stmt->execute([$m[1]]);
            $job=$stmt->fetch();
            if (!$job || !in_array((int)$auth['user_id'], [(int)$job['customer_id'],(int)$job['provider_id']],true)) sendResponse(403,['status'=>'error','message'=>'Sohbete erişemezsiniz.']);
        } elseif (!preg_match('/^private-user_(\d+)$/D', $channel_name, $m) || (int)$m[1] !== (int)$auth['user_id']) {
            sendResponse(403,['status'=>'error','message'=>'Kanala erişemezsiniz.']);
        }
        $string_to_sign = $socket_id . ':' . $channel_name;
        $signature = hash_hmac('sha256', $string_to_sign, PUSHER_SECRET);
        
        $response_data = [
            'auth' => PUSHER_KEY . ':' . $signature
        ];

        header('Content-Type: application/json');
        echo json_encode($response_data);
        exit;
        break;

    default:
        sendResponse(400, ["status" => "error", "message" => "Geçersiz işlem (Action bulunamadı)."]);
        break;
}
?>
