<?php
require_once __DIR__ . '/rental_rules.php';
require_once __DIR__ . '/rental_reputation.php';
require_once __DIR__ . '/purchase_verification.php';
require_once __DIR__ . '/api_runtime.php';

function rentalFail($code, $message) { sendResponse($code, ['status'=>'error', 'message'=>$message]); }
class RentalServerException extends RuntimeException {
    public $errorCode;
    public function __construct($errorCode,$message) { parent::__construct($message); $this->errorCode=$errorCode; }
}
function rentalUser($pdo, $id, $role, $requireCity=true) {
    $stmt = $pdo->prepare('SELECT * FROM users WHERE id = ?');
    $stmt->execute([$id]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user || $user['user_type'] !== $role || $user['status'] !== 'active' || !empty($user['is_suspended'])) {
        rentalFail(403, 'Bu işlem için onaylı ve aktif bir hesap gereklidir.');
    }
    if ($requireCity && !rentalSameCity($user['city'], $user['city'])) rentalFail(422, 'Önce profilinizden şehrinizi güncelleyin.');
    return $user;
}
// Idempotent migration. DDL happens before any booking transaction.
function rentalEnsureSchema($pdo) {
    apiSchemaMigration($pdo,'rental_schema_v2',function() use($pdo) {
    $pdo->exec("CREATE TABLE IF NOT EXISTS tickets (
        id INT AUTO_INCREMENT PRIMARY KEY,
        job_id INT NULL,
        customer_id INT NULL,
        provider_id INT NULL,
        reporter_id INT NULL,
        subject VARCHAR(255) NULL,
        message TEXT NULL,
        status VARCHAR(30) DEFAULT 'open',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $pdo->exec("CREATE TABLE IF NOT EXISTS rentacar_listings (
        id INT AUTO_INCREMENT PRIMARY KEY,
        company_id INT NULL,
        city VARCHAR(100) NULL,
        car_brand_model VARCHAR(255) NULL,
        daily_price DECIMAL(10,2) NULL,
        description TEXT NULL,
        photo VARCHAR(255) NULL,
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $pdo->exec("CREATE TABLE IF NOT EXISTS rentacar_bids (
        id INT AUTO_INCREMENT PRIMARY KEY,
        listing_id INT NULL,
        customer_id INT NULL,
        amount DECIMAL(10,2) NULL,
        rent_days INT NULL,
        status VARCHAR(50) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $definitions = [
        'users'=>['created_at'=>'DATETIME NULL','subscription_end_date'=>'DATETIME NULL','map_link'=>'VARCHAR(500) NULL','rental_lat'=>'DECIMAL(10,7) NULL','rental_lng'=>'DECIMAL(10,7) NULL','rental_address'=>'VARCHAR(500) NULL','rating'=>'DECIMAL(3,2) NOT NULL DEFAULT 0','reviews_count'=>'INT NOT NULL DEFAULT 0'],
        'tickets'=>['reporter_id'=>'INT NULL'],
        'rentacar_listings'=>['brand'=>'VARCHAR(100) NULL', 'model'=>'VARCHAR(150) NULL',
            'plate'=>'VARCHAR(50) NULL', 'model_year'=>'VARCHAR(10) NULL',
            'plate'=>'VARCHAR(50) NULL','model_year'=>'VARCHAR(10) NULL','photo'=>'VARCHAR(255) NULL',
            'photo1'=>'VARCHAR(255) NULL', 'photo2'=>'VARCHAR(255) NULL', 'photo3'=>'VARCHAR(255) NULL',
            'listing_version'=>'INT NOT NULL DEFAULT 1'],
        'rentacar_bids'=>['quoted_daily_price'=>'DECIMAL(10,2) NULL',
            'last_offer_by'=>"VARCHAR(20) NOT NULL DEFAULT 'customer'", 'offer_version'=>'INT NOT NULL DEFAULT 1',
            'job_id'=>'INT NULL', 'updated_at'=>'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
            'customer_budget'=>'DECIMAL(10,2) NULL', 'vehicle_label'=>'VARCHAR(255) NULL', 'quoted_plate'=>'VARCHAR(50) NULL',
            'customer_hidden'=>'TINYINT NOT NULL DEFAULT 0','pickup_map_link'=>'VARCHAR(500) NULL','pickup_lat'=>'DECIMAL(10,7) NULL','pickup_lng'=>'DECIMAL(10,7) NULL','pickup_address'=>'VARCHAR(500) NULL',
            'reserved_at'=>'DATETIME NULL','expected_return_at'=>'DATETIME NULL']
    ];
    // A database advisory lock also coordinates concurrent PHP workers/servers.
    $locked = $pdo->query("SELECT GET_LOCK('ototag_rental_schema_v1', 10)")->fetchColumn();
    if ((int)$locked !== 1) throw new RuntimeException('Şema kilidi alınamadı.');
    try {
        rentalReputationSchema($pdo);
        foreach ($definitions as $table=>$columns) {
            $existing = $pdo->query("SHOW COLUMNS FROM `$table`")->fetchAll(PDO::FETCH_COLUMN);
            foreach ($columns as $column=>$definition) {
                if (!in_array($column, $existing, true)) $pdo->exec("ALTER TABLE `$table` ADD COLUMN `$column` $definition");
            }
        }
        $engines=$pdo->query("SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE()
            AND TABLE_NAME IN ('users','jobs','rentacar_listings','rentacar_bids','notifications','tickets','rental_reviews','rental_events')")->fetchAll(PDO::FETCH_ASSOC);
        foreach ($engines as $table) if (strcasecmp($table['ENGINE'],'InnoDB')!==0) throw new RuntimeException('Kiralama tabloları InnoDB olmalıdır.');
        foreach (['rentacar_listings'=>['rental_company_status'=>'(company_id, status)', 'rental_city_status'=>'(city, status)'],
            'rentacar_bids'=>['rental_listing_status'=>'(listing_id, status)', 'rental_customer_status'=>'(customer_id, status)'],
            'tickets'=>['rental_ticket_reporter'=>'(job_id, reporter_id, status)'],
            'jobs'=>['rental_active_customer'=>'(customer_id, status)']] as $table=>$indexes) {
            $existing = $pdo->query("SHOW INDEX FROM `$table`")->fetchAll(PDO::FETCH_ASSOC);
            $names = array_column($existing, 'Key_name');
            foreach ($indexes as $name=>$columns) if (!in_array($name, $names, true)) $pdo->exec("CREATE INDEX `$name` ON `$table` $columns");
        }
    } finally { $pdo->query("SELECT RELEASE_LOCK('ototag_rental_schema_v1')"); }
    });
    apiSchemaMigration($pdo,'rental_agreement_v1',function() use($pdo) {
        $columns=$pdo->query('SHOW COLUMNS FROM rentacar_bids')->fetchAll(PDO::FETCH_COLUMN);
        if (!in_array('agreement_at',$columns,true)) $pdo->exec('ALTER TABLE rentacar_bids ADD COLUMN agreement_at DATETIME NULL');
        // Preserve existing bookings made before the separate agreement step.
        $pdo->exec("UPDATE rentacar_bids SET agreement_at=COALESCE(reserved_at,UTC_TIMESTAMP()) WHERE status IN ('accepted','completed') AND agreement_at IS NULL");
    });
    // Storage engines can be changed by an operator after migration. Validate
    // transaction safety on every request without rescanning columns/indexes.
    $engines=$pdo->query("SELECT TABLE_NAME,ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE()
        AND TABLE_NAME IN ('users','jobs','rentacar_listings','rentacar_bids','notifications','tickets','rental_reviews','rental_events')")->fetchAll(PDO::FETCH_ASSOC);
    foreach ($engines as $table) if (strcasecmp($table['ENGINE'],'InnoDB')!==0) throw new RuntimeException('Kiralama tabloları InnoDB olmalıdır.');
}
function rentalIniBytes($value) {
    if (!preg_match('/^\s*(\d+(?:\.\d+)?)\s*([KMG]?)\s*$/i', (string)$value, $parts)) return 0;
    return (int)((float)$parts[1] * pow(1024, strpos(' KMG',strtoupper($parts[2]))));
}
function rentalImageExtension($path) {
    // Both checks inspect server-side file contents, never the supplied name/MIME.
    // getimagesize is in core PHP and also validates JPEG/PNG/WebP image headers.
    $image=@getimagesize($path);
    $extensions=['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp'];
    $mime=$image['mime'] ?? '';
    if (!$image || empty($image[0]) || empty($image[1]) || !isset($extensions[$mime])) throw new InvalidArgumentException('JPEG, PNG veya WebP görsel kullanın.');
    $contents=@file_get_contents($path);
    if ($contents===false || preg_match('/<\?php|<\?=|<script\s+language\s*=\s*["\']?php/i',$contents)) throw new InvalidArgumentException('Görsel içeriği güvenli değil. Farklı bir fotoğraf seçin.');
    if (class_exists('finfo')) {
        $detected=(new finfo(FILEINFO_MIME_TYPE))->file($path);
        if ($detected!==$mime) throw new InvalidArgumentException('JPEG, PNG veya WebP görsel kullanın.');
    }
    return $extensions[$mime];
}
function rentalUploadDirectory($dir) {
    if (!is_dir($dir) && !@mkdir($dir,0755,true) && !is_dir($dir)) {
        throw new RentalServerException('RENTAL_UPLOAD_DIRECTORY','Araç fotoğrafı klasörü oluşturulamıyor. Yönetici uploads/rentacar klasörünün PHP yazma izinlerini kontrol etmeli.');
    }
    if (!is_writable($dir)) throw new RentalServerException('RENTAL_UPLOAD_DIRECTORY','Araç fotoğrafı klasörü yazılabilir değil. Yönetici uploads/rentacar klasörünün PHP yazma izinlerini kontrol etmeli.');
}
function rentalUploadError($code) {
    if (in_array($code,[UPLOAD_ERR_INI_SIZE,UPLOAD_ERR_FORM_SIZE],true)) throw new InvalidArgumentException('Fotoğraf sunucunun yükleme sınırını aşıyor. Daha küçük bir fotoğraf seçin; yönetici PHP upload_max_filesize ayarını kontrol edebilir.');
    if (in_array($code,[UPLOAD_ERR_NO_TMP_DIR,UPLOAD_ERR_CANT_WRITE],true)) throw new RentalServerException('RENTAL_UPLOAD_TEMP','Sunucu geçici yükleme alanına yazamıyor. Yönetici PHP upload_tmp_dir ayarını ve disk alanını kontrol etmeli.');
    if ($code===UPLOAD_ERR_EXTENSION) throw new RentalServerException('RENTAL_UPLOAD_EXTENSION','Sunucudaki bir PHP uzantısı fotoğraf yüklemesini durdurdu. Yönetici PHP hata günlüğünü kontrol etmeli.');
    if ($code!==UPLOAD_ERR_OK) throw new InvalidArgumentException('Fotoğraf yüklemesi tamamlanmadı. Görseli yeniden seçip deneyin.');
}
function rentalPhoto($key) {
    if (!isset($_FILES[$key]) || $_FILES[$key]['error'] === UPLOAD_ERR_NO_FILE) return null;
    $file = $_FILES[$key];
    rentalUploadError($file['error']);
    if ($file['size'] > 5 * 1024 * 1024) throw new InvalidArgumentException('Görsel en fazla 5 MB olabilir.');
    if (!is_uploaded_file($file['tmp_name'])) throw new InvalidArgumentException('Geçersiz fotoğraf yüklemesi. Görseli yeniden seçin.');
    $extension=rentalImageExtension($file['tmp_name']);
    $dir = __DIR__ . '/uploads/rentacar/';
    rentalUploadDirectory($dir);
    $path = 'uploads/rentacar/' . bin2hex(random_bytes(16)) . '.' . $extension;
    if (!@move_uploaded_file($file['tmp_name'], __DIR__ . '/' . $path)) throw new RentalServerException('RENTAL_UPLOAD_WRITE','Araç fotoğrafı kaydedilemedi. Yönetici fotoğraf klasörü izinlerini ve sunucu disk alanını kontrol etmeli.');
    return $path;
}
function rentalQueryBids($pdo, $clause, $params, $limit=null) {
    $limitSql=$limit===null ? '' : ' LIMIT '.max(1,min(100,(int)$limit));
    $stmt = $pdo->prepare("SELECT b.*, l.company_id, COALESCE(b.vehicle_label,l.car_brand_model) AS car_brand_model, COALESCE(j.city,l.city) AS city, l.daily_price,
        c.name AS customer_name, f.name AS company_name FROM rentacar_bids b
        JOIN rentacar_listings l ON l.id=b.listing_id LEFT JOIN users c ON c.id=b.customer_id
        LEFT JOIN users f ON f.id=l.company_id LEFT JOIN jobs j ON j.id=b.job_id WHERE $clause ORDER BY b.id DESC$limitSql");
    $stmt->execute($params);
    return $stmt->fetchAll(PDO::FETCH_ASSOC);
}
function rentalHideUnagreedPickup(&$bids) {
    foreach ($bids as &$bid) {
        if (!empty($bid['agreement_at'])) continue;
        foreach (['pickup_map_link','pickup_lat','pickup_lng','pickup_address'] as $field) $bid[$field]=null;
    }
    unset($bid);
}
function rentalClosePending($pdo, $listingId, $message) {
    $stmt=$pdo->prepare("SELECT b.id AS bid_id,b.customer_id,l.company_id,l.city FROM rentacar_bids b JOIN rentacar_listings l ON l.id=b.listing_id WHERE b.listing_id=? AND b.status='pending'");
    $stmt->execute([$listingId]);
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) rentalEvent($pdo,'offer_closed',$row+['listing_id'=>$listingId],['reason'=>$message]);
    $stmt=$pdo->prepare("SELECT DISTINCT customer_id FROM rentacar_bids WHERE listing_id=? AND status='pending'");
    $stmt->execute([$listingId]);
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $customer) {
        $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Kiralama teklifi kapatıldı',?)")->execute([$customer,$message]);
    }
    $pdo->prepare("UPDATE rentacar_bids SET status='rejected',offer_version=offer_version+1 WHERE listing_id=? AND status='pending'")->execute([$listingId]);
}
function rentalCleanupPhotos($pdo, $paths) {
    foreach (array_unique(array_filter($paths)) as $path) {
        if (!preg_match('#^uploads/rentacar/[A-Za-z0-9_.-]+$#D',$path)) continue;
        try {
            $stmt=$pdo->prepare('SELECT COUNT(*) FROM rentacar_listings WHERE photo=? OR photo1=? OR photo2=? OR photo3=?');
            $stmt->execute([$path,$path,$path,$path]);
            if (!(int)$stmt->fetchColumn()) deletePhysicalFile($path);
        } catch (Throwable $e) { error_log('Rental photo cleanup failed.'); }
    }
}
function rentalEnrichHistory($pdo,$history) {
    $ids=[];
    foreach ($history as $row) if ($row['service_type']==='rentacar') $ids[]=(int)$row['job_id'];
    if (!$ids) return $history;
    rentalEnsureSchema($pdo);
    $stmt=$pdo->prepare('SELECT b.job_id,b.rent_days,b.quoted_daily_price,b.customer_budget,
        COALESCE(b.vehicle_label,l.car_brand_model) AS rental_car_model,COALESCE(b.quoted_plate,l.plate) AS rental_plate
        FROM rentacar_bids b JOIN rentacar_listings l ON l.id=b.listing_id WHERE b.job_id IN ('.implode(',',array_fill(0,count($ids),'?')).')');
    $stmt->execute($ids); $details=[];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) $details[$row['job_id']]=$row;
    foreach ($history as &$row) $row=array_merge($row,$details[$row['job_id']] ?? []);
    unset($row); return $history;
}
function rentalGuardAccountDeletion($pdo,$userId) {
    $pdo->prepare('SELECT id FROM users WHERE id=? FOR UPDATE')->execute([$userId]);
    $stmt=$pdo->prepare("SELECT id FROM jobs WHERE service_type='rentacar' AND status='matched' AND (customer_id=? OR provider_id=?) LIMIT 1 FOR UPDATE");
    $stmt->execute([$userId,$userId]);
    if ($stmt->fetch()) { $pdo->rollBack(); rentalFail(409,'Aktif kiralama rezervasyonu var. Önce iade veya yönetici iptali tamamlanmalıdır.'); }
}
function rentalReserve($pdo,$listing,$bid,$company) {
    rentalRequireSubscription($pdo,$company);
    $stmt=$pdo->prepare('SELECT map_link,rental_lat,rental_lng,rental_address FROM users WHERE id=? FOR UPDATE'); $stmt->execute([$listing['company_id']]); $pickup=$stmt->fetch(PDO::FETCH_ASSOC);
    $mapLink=trim($pickup['map_link'] ?? '');
    if ($mapLink!=='') $mapLink=rentalMapLink($mapLink);
    if ($mapLink==='' && ($pickup['rental_lat']===null || $pickup['rental_lng']===null || !trim($pickup['rental_address'] ?? ''))) throw new InvalidArgumentException('Firma profilinden geçerli konum linkini kaydetmelidir.');
    $stmt=$pdo->prepare("SELECT id FROM jobs WHERE customer_id=? AND status IN ('searching','matched','accepted','approved','in_progress','customer_paid') LIMIT 1 FOR UPDATE");
    $stmt->execute([$bid['customer_id']]);
    if ($stmt->fetch()) throw new InvalidArgumentException('Devam eden bir işleminiz var. Önce bu işlem tamamlanmalıdır.');
    $jobLat=is_numeric($pickup['rental_lat'] ?? null) ? (float)$pickup['rental_lat'] : 0.0;
    $jobLng=is_numeric($pickup['rental_lng'] ?? null) ? (float)$pickup['rental_lng'] : 0.0;
    $matchCode=(string)random_int(100000,999999);
    $pdo->prepare("INSERT INTO jobs (customer_id,provider_id,service_type,status,city,agreed_price,latitude,longitude,match_code) VALUES (?,?,'rentacar','matched',?,?,?,?,?)")
        ->execute([$bid['customer_id'],$listing['company_id'],trim($company['city']),$bid['amount'],$jobLat,$jobLng,$matchCode]);
    $jobId=(int)$pdo->lastInsertId();
    $pdo->prepare("UPDATE rentacar_bids SET status='accepted',job_id=?,offer_version=offer_version+1,pickup_map_link=?,pickup_lat=?,pickup_lng=?,pickup_address=?,reserved_at=UTC_TIMESTAMP(),expected_return_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? DAY) WHERE id=?")
        ->execute([$jobId,$mapLink ?: null,$pickup['rental_lat'],$pickup['rental_lng'],$pickup['rental_address'],$bid['rent_days'],$bid['id']]);
    $pdo->prepare("UPDATE rentacar_listings SET status='rented',city=?,listing_version=listing_version+1 WHERE id=?")->execute([trim($company['city']),$listing['id']]);
    rentalClosePending($pdo,$listing['id'],'Araç başka bir rezervasyon için ayrıldı. Diğer uygun araçlara bakabilirsiniz.');
    rentalEvent($pdo,'reserved',['company_id'=>$listing['company_id'],'customer_id'=>$bid['customer_id'],'listing_id'=>$listing['id'],'bid_id'=>$bid['id'],'job_id'=>$jobId,'city'=>$company['city']],['amount'=>$bid['amount'],'days'=>(int)$bid['rent_days']]);
    $message=$listing['car_brand_model'].' / '.$bid['rent_days'].' gün / '.$bid['amount'].' TL. Rezervasyon detayından teslim konumunu görebilirsiniz.';
    $pdo->prepare("INSERT INTO notifications (user_id,title,message) VALUES (?,'Kiralama Rezerve Edildi',?),(?,'Araç Rezerve Edildi',?)")->execute([$bid['customer_id'],$message,$listing['company_id'],$message]);
    return ['status'=>'success','job_id'=>$jobId,'amount'=>$bid['amount'],'rent_days'=>(int)$bid['rent_days']];
}
function rentalRequireSubscription($pdo,$company) {
    if (!businessSubscriptionStatus($company)['can_work']) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        sendResponse(402,['status'=>'error','error_code'=>'RENTAL_SUBSCRIPTION_REQUIRED','message'=>'Firmanın abonelik süresi doldu. Yeni ilan ve eşleşmeler için abonelik yenilenmelidir.']);
    }
}
function handleRentalAction($pdo, $action, $method) {
    $actions = ['get_rentacar_listings', 'create_rentacar_listing', 'place_rentacar_bid', 'get_rentacar_bids',
        'counter_rentacar_bid', 'accept_rentacar_bid', 'reject_rentacar_bid', 'agree_rentacar_booking', 'complete_rentacar_booking',
        'update_rentacar_listing','delete_rentacar_listing','reserve_rentacar_listing','get_rentacar_booking',
        'update_rentacar_location','report_rentacar_booking','admin_cancel_rentacar_booking',
        'get_rentacar_company_profile','add_rentacar_review','admin_get_rental_activity','admin_get_rental_detail','delete_rentacar_bid','get_rentacar_history'];
    if (!in_array($action, $actions, true)) return;
    $read = in_array($action, ['get_rentacar_listings', 'get_rentacar_bids','get_rentacar_booking','get_rentacar_company_profile','admin_get_rental_activity','admin_get_rental_detail','get_rentacar_history'], true);
    if ($method !== ($read ? 'GET' : 'POST')) rentalFail(405, 'Geçersiz metod.');
    $auth = authenticateRequest();
    handleRentalReputationAction($pdo,$action,$method,$auth);
    if ($action==='admin_cancel_rentacar_booking') {
        if ($auth['user_type']!=='admin') rentalFail(403,'Yönetici yetkisi gereklidir.');
        try {
            rentalEnsureSchema($pdo);
            $jobId=filter_var($_POST['job_id'] ?? null,FILTER_VALIDATE_INT);
            $stmt=$pdo->prepare('SELECT listing_id FROM rentacar_bids WHERE job_id=?'); $stmt->execute([$jobId]); $listingId=$stmt->fetchColumn();
            if (!$listingId) rentalFail(404,'Rezervasyon bulunamadı.');
            $pdo->beginTransaction();
            $pdo->prepare('SELECT id FROM rentacar_listings WHERE id=? FOR UPDATE')->execute([$listingId]);
            $stmt=$pdo->prepare('SELECT * FROM rentacar_bids WHERE job_id=? FOR UPDATE'); $stmt->execute([$jobId]); $bid=$stmt->fetch(PDO::FETCH_ASSOC);
            if ($bid['status']==='cancelled') { $pdo->commit(); sendResponse(200,['status'=>'success']); }
            if ($bid['status']!=='accepted') { $pdo->rollBack(); rentalFail(409,'Bu rezervasyon artık iptal edilemez.'); }
            $stmt=$pdo->prepare("SELECT * FROM jobs WHERE id=? AND service_type='rentacar' FOR UPDATE"); $stmt->execute([$jobId]); $job=$stmt->fetch(PDO::FETCH_ASSOC);
            if (!$job || $job['status']!=='matched') { $pdo->rollBack(); rentalFail(409,'Rezervasyon durumu değişti.'); }
            $pdo->prepare("UPDATE jobs SET status='cancelled' WHERE id=?")->execute([$jobId]);
            $pdo->prepare("UPDATE rentacar_bids SET status='cancelled',offer_version=offer_version+1 WHERE id=?")->execute([$bid['id']]);
            $pdo->prepare("UPDATE rentacar_listings SET status='active',listing_version=listing_version+1 WHERE id=?")->execute([$listingId]);
            rentalEvent($pdo,'admin_cancelled',['company_id'=>$job['provider_id'],'customer_id'=>$job['customer_id'],'listing_id'=>$listingId,'bid_id'=>$bid['id'],'job_id'=>$jobId,'city'=>$job['city']]);
            $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Kiralama iptal edildi',?),(?,'Kiralama iptal edildi',?)")
                ->execute([$job['customer_id'],'Yönetici rezervasyon #'.$jobId.' kaydını iptal etti.',$job['provider_id'],'Yönetici rezervasyon #'.$jobId.' kaydını iptal etti.']);
            $pdo->commit(); sendResponse(200,['status'=>'success','message'=>'Rezervasyon iptal edildi; araç yeniden müsait.']);
        } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); error_log('Rental cancellation failed.'); rentalFail(500,'Rezervasyon iptal edilemedi.'); }
    }
    $id = (int)$auth['user_id'];
    $role = $auth['user_type'];
    $adminBooking=$role==='admin' && $action==='get_rentacar_booking';
    if (!$adminBooking && !in_array($role, ['customer', 'rentacar'], true)) rentalFail(403, 'Bu işlem için müşteri veya rent a car hesabı gereklidir.');
    if (in_array($action,['create_rentacar_listing','update_rentacar_listing'],true)) {
        $bodyLimit=rentalIniBytes(ini_get('post_max_size'));
        if ($bodyLimit>0 && (float)($_SERVER['CONTENT_LENGTH'] ?? 0)>$bodyLimit) rentalFail(413,'Fotoğrafların toplam boyutu sunucunun yükleme sınırını aşıyor. Daha küçük görseller seçin; yönetici PHP post_max_size ayarını kontrol edebilir.');
    }
    $user = $adminBooking ? ['city'=>''] : rentalUser($pdo, $id, $role, !in_array($action,['get_rentacar_history','get_rentacar_booking','report_rentacar_booking','delete_rentacar_bid'],true));
    $actor = $adminBooking ? 'admin' : ($role === 'customer' ? 'customer' : 'company');
    $uploaded = [];
    $plateLock = null;
    $completedReferralJobId = null;
    $stage='schema';
    try {
        if (!function_exists('mb_substr') || !function_exists('mb_strlen')) throw new RentalServerException('RENTAL_PHP_MBSTRING','Sunucuda PHP mbstring uzantısı etkin değil. Yönetici aaPanel üzerinden sitenin PHP sürümünde mbstring uzantısını etkinleştirmeli.');
        rentalEnsureSchema($pdo);
        if ($actor==='company') $user=rentalUser($pdo,$id,$role,false);
        if ($action==='create_rentacar_listing') rentalRequireSubscription($pdo,$user);
        if ($action==='update_rentacar_location') {
            if ($actor!=='company') rentalFail(403,'Firma hesabı gereklidir.');
            $lat=filter_var($_POST['latitude'] ?? null,FILTER_VALIDATE_FLOAT);
            $lng=filter_var($_POST['longitude'] ?? null,FILTER_VALIDATE_FLOAT);
            $address=trim($_POST['address'] ?? '');
            if ($lat===false || $lng===false || abs($lat)>90 || abs($lng)>180 || ($lat==0 && $lng==0) || mb_strlen($address)<8 || mb_strlen($address)>500) throw new InvalidArgumentException('Geçerli teslim konumu ve açık adres girin.');
            $pdo->beginTransaction();
            $pdo->prepare('UPDATE users SET rental_lat=?,rental_lng=?,rental_address=? WHERE id=?')->execute([$lat,$lng,$address,$id]);
            rentalEvent($pdo,'pickup_updated',['company_id'=>$id,'city'=>$user['city']]); $pdo->commit();
            sendResponse(200,['status'=>'success','message'=>'Firma teslim konumu kaydedildi.']);
        }
        if (in_array($action,['get_rentacar_booking','report_rentacar_booking'],true)) {
            $jobId=filter_var(($read?$_GET:$_POST)['job_id'] ?? null,FILTER_VALIDATE_INT);
            $stmt=$pdo->prepare("SELECT b.*,j.status AS job_status,j.customer_id,j.provider_id AS company_id,j.city,
                COALESCE(b.vehicle_label,l.car_brand_model) AS car_brand_model,COALESCE(b.quoted_plate,l.plate) AS plate,
                c.name AS customer_name,c.phone AS customer_phone,f.name AS company_name,f.phone AS company_phone,f.map_link AS company_map_link
                FROM jobs j JOIN rentacar_bids b ON b.job_id=j.id JOIN rentacar_listings l ON l.id=b.listing_id
                LEFT JOIN users c ON c.id=j.customer_id LEFT JOIN users f ON f.id=j.provider_id WHERE j.id=? AND j.service_type='rentacar'");
            $stmt->execute([$jobId]); $booking=$stmt->fetch(PDO::FETCH_ASSOC);
            if (!$booking) rentalFail(404,'Rezervasyon bulunamadı.');
            if ($actor!=='admin' && (int)$booking[$actor==='customer'?'customer_id':'company_id']!==$id) rentalFail(403,'Bu rezervasyona erişemezsiniz.');
            if ($read) {
                if ($actor==='customer' && empty($booking['agreement_at'])) {
                    $booking['pickup_map_link']=null;
                    $booking['pickup_lat']=null;
                    $booking['pickup_lng']=null;
                    $booking['pickup_address']=null;
                    $booking['company_map_link']=null;
                }
                $stmt=$pdo->prepare('SELECT id,rating,comment,created_at FROM rental_reviews WHERE job_id=?'); $stmt->execute([$jobId]);
                $booking['review']=$stmt->fetch(PDO::FETCH_ASSOC) ?: null;
                $booking['can_review']=$actor==='customer' && $booking['job_status']==='completed' && !$booking['review'];
                $response=['status'=>'success','booking'=>$booking];
                if ($actor==='admin') {
                    $response+=rentalEvents($pdo,'(e.bid_id=? OR e.job_id=?)',[$booking['id'],$jobId],max(0,(int)($_GET['before_event_id'] ?? 0)));
                    $stmt=$pdo->prepare('SELECT id,reporter_id,subject,message,status,created_at FROM tickets WHERE job_id=? ORDER BY id DESC LIMIT 50');
                    $stmt->execute([$jobId]); $response['complaints']=$stmt->fetchAll(PDO::FETCH_ASSOC);
                }
                sendResponse(200,$response);
            }
            if (!in_array($booking['job_status'],['completed','cancelled'],true)) rentalFail(409,'Şikâyet iş tamamlandıktan veya iptal edildikten sonra açılabilir.');
            $subject=trim($_POST['subject'] ?? ''); $message=trim($_POST['message'] ?? '');
            if (!in_array($subject,['Rezervasyona uyulmadı','Araç teslim edilmedi','Araç iade edilmedi','Hasar / eksik teslim','Ödeme anlaşmazlığı','Diğer'],true) || mb_strlen($message)<10 || mb_strlen($message)>4000) throw new InvalidArgumentException('Şikayet nedenini seçin ve en az 10 karakter açıklayın.');
            $pdo->beginTransaction();
            $pdo->prepare('SELECT id FROM jobs WHERE id=? FOR UPDATE')->execute([$jobId]);
            $stmt=$pdo->prepare("SELECT id FROM tickets WHERE job_id=? AND reporter_id=? AND status='open' LIMIT 1"); $stmt->execute([$jobId,$id]);
            $ticketId=$stmt->fetchColumn();
            if (!$ticketId) {
                $pdo->prepare("INSERT INTO tickets(job_id,customer_id,provider_id,reporter_id,subject,message,status) VALUES (?,?,?,?,?,?,'open')")
                    ->execute([$jobId,$booking['customer_id'],$booking['company_id'],$id,'[KİRALAMA] '.$subject,$message]);
                $ticketId=$pdo->lastInsertId();
                rentalEvent($pdo,'complaint_opened',['company_id'=>$booking['company_id'],'customer_id'=>$booking['customer_id'],'bid_id'=>$booking['id'],'listing_id'=>$booking['listing_id'],'job_id'=>$jobId,'city'=>$booking['city']],['ticket_id'=>(int)$ticketId,'subject'=>$subject]);
            }
            $pdo->commit(); sendResponse(200,['status'=>'success','ticket_id'=>(int)$ticketId,'message'=>'Şikayet yönetici paneline iletildi.']);
        }
        if ($action === 'get_rentacar_listings') {
            if ($actor === 'company') {
                if (isset($_GET['company_id']) && (int)$_GET['company_id'] !== $id) rentalFail(403, 'Başka firmanın ilanlarını göremezsiniz.');
                $stmt = $pdo->prepare("SELECT * FROM rentacar_listings WHERE company_id=? AND status<>'deleted' ORDER BY id DESC");
                $stmt->execute([$id]);
                $listings = $stmt->fetchAll(PDO::FETCH_ASSOC);
                $bids = rentalQueryBids($pdo, "l.company_id=? AND b.status IN ('pending','accepted')", [$id]);
                $byListing = [];
                foreach ($bids as $bid) $byListing[$bid['listing_id']][] = $bid;
                foreach ($listings as &$listing) $listing['bids'] = $byListing[$listing['id']] ?? [];
                unset($listing);
            } else {
                if (isset($_GET['company_id'])) rentalFail(403, 'Firma ekranına erişemezsiniz.');
                // City comes from both verified profiles, never from caller input.
                $sql = "SELECT l.*, f.name AS company_name, f.city AS company_city,f.rating AS company_rating,f.reviews_count AS company_review_count FROM rentacar_listings l
                    JOIN users f ON f.id=l.company_id WHERE l.status='active' AND f.user_type='rentacar'
                    AND f.status='active' AND COALESCE(f.is_suspended,0)=0 AND TRIM(f.city)=?
                    AND (f.subscription_end_date>NOW() OR DATE_ADD(f.created_at,INTERVAL 30 DAY)>NOW())
                    ";
                $params = [trim($user['city'])];
                $brand = trim($_GET['brand'] ?? ''); $model = trim($_GET['model'] ?? '');
                if ($brand !== '') {
                    $sql .= ' AND (l.brand=? OR (l.brand IS NULL AND l.car_brand_model LIKE ?))';
                    $params[]=$brand; $params[]=strtr($brand, ['\\'=>'\\\\','%'=>'\\%','_'=>'\\_']) . ' %';
                }
                if ($model !== '') {
                    if ($brand === '') throw new InvalidArgumentException('Model için marka seçin.');
                    $sql .= ' AND (l.model=? OR (l.model IS NULL AND l.car_brand_model=?))';
                    $params[]=$model; $params[]=$brand . ' ' . $model;
                }
                if (!empty($_GET['max_budget'])) { $sql .= ' AND l.daily_price<=?'; $params[]=rentalMoneyText(rentalMoneyCents($_GET['max_budget'])); }
                $orderSql = ' ORDER BY l.daily_price ASC,l.id DESC';
                $orderParams = [];
                if (isset($_GET['total_budget']) && $_GET['total_budget']!=='') {
                    $searchDays = rentalDays($_GET['rent_days'] ?? null);
                    $searchBudget = rentalMoneyText(rentalMoneyCents($_GET['total_budget']));
                    $orderSql = ' ORDER BY CASE WHEN l.daily_price * ? <= ? THEN 0 ELSE 1 END, ABS((l.daily_price * ?) - ?) ASC, l.daily_price ASC,l.id DESC';
                    $orderParams = [$searchDays, $searchBudget, $searchDays, $searchBudget];
                }
                $page=filter_var($_GET['page'] ?? 1,FILTER_VALIDATE_INT);
                $pageSize=filter_var($_GET['page_size'] ?? 12,FILTER_VALIDATE_INT);
                if (!$page || $page<1 || $page>100000 || !$pageSize || $pageSize<1 || $pageSize>50) throw new InvalidArgumentException('Sayfa numarası ve sayfa başına araç sayısı geçersiz.');
                $from=substr($sql,strpos($sql,' FROM rentacar_listings'));
                $count=$pdo->prepare('SELECT COUNT(*)'.$from); $count->execute($params); $total=(int)$count->fetchColumn();
                $pages=max(1,(int)ceil($total/$pageSize)); $page=min($page,$pages);
                $stmt = $pdo->prepare($sql . $orderSql . ' LIMIT '.$pageSize.' OFFSET '.(($page-1)*$pageSize));
                $stmt->execute(array_merge($params, $orderParams));
                $listings = array_values(array_filter($stmt->fetchAll(PDO::FETCH_ASSOC), function($listing) use ($user) {
                    return rentalSameCity($listing['company_city'], $user['city']);
                }));
                foreach ($listings as &$listing) $listing['city']=$listing['company_city'];
                unset($listing);
            }
            $stmt=$pdo->prepare('SELECT rental_lat AS latitude,rental_lng AS longitude,rental_address AS address FROM users WHERE id=?'); $stmt->execute([$id]);
            sendResponse(200, ['status'=>'success', 'city'=>$user['city'], 'listings'=>$listings,'pickup'=>$actor==='company'?$stmt->fetch(PDO::FETCH_ASSOC):null]
                +($actor==='company' ? ['subscription'=>businessSubscriptionStatus($user)] : ['page'=>$page,'page_size'=>$pageSize,'total'=>$total,'total_pages'=>$pages]));
        }
        if ($action === 'get_rentacar_bids') {
            $bids = rentalQueryBids($pdo, $actor === 'customer' ? 'b.customer_id=? AND b.customer_hidden=0' : 'l.company_id=?', [$id]);
            if ($actor==='customer') rentalHideUnagreedPickup($bids);
            sendResponse(200, ['status'=>'success', 'city'=>$user['city'], 'bids'=>$bids]);
        }
        if ($action==='get_rentacar_history') {
            $before=max(0,(int)($_GET['before_id'] ?? 0));
            $clause=($actor==='customer' ? 'b.customer_id=?' : 'l.company_id=?')." AND b.status IN ('completed','cancelled') AND b.job_id IS NOT NULL";
            $params=[$id];
            if ($before) { $clause.=' AND b.id<?'; $params[]=$before; }
            // History remains accessible even if a closed offer was removed from the offer list.
            $history=rentalQueryBids($pdo,$clause,$params,51);
            if ($actor==='customer') rentalHideUnagreedPickup($history);
            $hasMore=count($history)>50; $history=array_slice($history,0,50);
            sendResponse(200,['status'=>'success','history'=>$history,'next_before_id'=>$hasMore?(int)end($history)['id']:null]);
        }
        if (in_array($action,['create_rentacar_listing','update_rentacar_listing','delete_rentacar_listing'],true)) {
            $stage='listing_validation';
            if ($actor !== 'company' || (int)($_POST['company_id'] ?? $id) !== $id) rentalFail(403, 'Yalnızca kendi firmanız için ilan açabilirsiniz.');
            $editing=$action!=='create_rentacar_listing'; $listing=null; $oldPhotos=[];
            if ($action!=='delete_rentacar_listing') {
                [$brand,$model,$plate,$year,$price,$description]=rentalListingFields($_POST);
                $plateLock='rental_plate_'.substr(hash('sha256',$id.'|'.$plate),0,48);
                $stmt=$pdo->prepare('SELECT GET_LOCK(?,10)'); $stmt->execute([$plateLock]);
                if ((int)$stmt->fetchColumn()!==1) throw new RuntimeException('Araç kilidi alınamadı.');
            }
            $pdo->beginTransaction();
            if ($editing) {
                $listingId=filter_var($_POST['listing_id'] ?? null,FILTER_VALIDATE_INT);
                $stmt=$pdo->prepare('SELECT * FROM rentacar_listings WHERE id=? FOR UPDATE'); $stmt->execute([$listingId]);
                $listing=$stmt->fetch(PDO::FETCH_ASSOC);
                if (!$listing) { $pdo->rollBack(); rentalFail(404,'Araç bulunamadı.'); }
                if ((int)$listing['company_id']!==$id) { $pdo->rollBack(); rentalFail(403,'Başka firmanın aracını değiştiremezsiniz.'); }
                if ($action==='delete_rentacar_listing' && $listing['status']==='deleted') { $pdo->commit(); sendResponse(200,['status'=>'success','message'=>'Araç zaten silinmiş.']); }
                if ((int)($_POST['listing_version'] ?? 0)!==(int)$listing['listing_version']) { $pdo->rollBack(); rentalFail(409,'Araç bilgileri değişti. Listeyi yenileyip tekrar deneyin.'); }
                $stmt=$pdo->prepare("SELECT id FROM rentacar_bids WHERE listing_id=? AND status='accepted' LIMIT 1"); $stmt->execute([$listingId]);
                if ($listing['status']!=='active' || $stmt->fetch()) { $pdo->rollBack(); rentalFail(409,'Kiradaki araç teslim alınmadan düzenlenemez veya silinemez.'); }
                $oldPhotos=[$listing['photo1'] ?: $listing['photo'], $listing['photo2'], $listing['photo3']];
            }
            if ($action==='delete_rentacar_listing') {
                rentalClosePending($pdo,$listingId,'Firma bu aracı ilandan kaldırdı. Diğer uygun araçlara teklif verebilirsiniz.');
                $pdo->prepare("UPDATE rentacar_listings SET status='deleted',photo=NULL,photo1=NULL,photo2=NULL,photo3=NULL,listing_version=listing_version+1 WHERE id=?")->execute([$listingId]);
                rentalEvent($pdo,'listing_deleted',['company_id'=>$id,'listing_id'=>$listingId,'city'=>$user['city']],['vehicle'=>$listing['car_brand_model']]);
                $pdo->commit(); rentalCleanupPhotos($pdo,$oldPhotos);
                sendResponse(200,['status'=>'success','message'=>'Araç ilanı kaldırıldı.']);
            }
            $stmt=$pdo->prepare("SELECT id FROM rentacar_listings WHERE company_id=? AND REPLACE(plate,' ','')=? AND status<>'deleted' AND id<>? LIMIT 1");
            $stmt->execute([$id,$plate,$listing['id'] ?? 0]);
            if ($stmt->fetch()) { $pdo->rollBack(); rentalFail(409,'Bu plakayla zaten bir araç ilanınız var.'); }
            $stage='photo_upload'; $photos=[];
            for ($i=1;$i<=3;$i++) {
                $photo=rentalPhoto('image_'.$i); if ($photo) $uploaded[]=$photo;
                $photos[]=$photo ?? (($_POST['remove_photo_'.$i] ?? '')==='1' ? null : ($oldPhotos[$i-1] ?? null));
            }
            $stage='listing_save';
            if ($editing) {
                $changed=$listing['daily_price']!==$price || $listing['car_brand_model']!=="$brand $model"
                    || preg_replace('/\s+/','',$listing['plate'] ?? '')!==$plate || (int)$listing['model_year']!==$year;
                if ($changed) rentalClosePending($pdo,$listingId,'Firma araç veya fiyat bilgisini güncelledi. Yeni fiyatla tekrar teklif verebilirsiniz.');
                $pdo->prepare('UPDATE rentacar_listings SET city=?,brand=?,model=?,car_brand_model=?,plate=?,model_year=?,daily_price=?,description=?,photo=?,photo1=?,photo2=?,photo3=?,listing_version=listing_version+1 WHERE id=?')
                    ->execute([trim($user['city']),$brand,$model,"$brand $model",$plate,$year,$price,$description,$photos[0],...$photos,$listingId]);
            } else {
                $pdo->prepare("INSERT INTO rentacar_listings(company_id,city,brand,model,car_brand_model,plate,model_year,daily_price,description,photo,photo1,photo2,photo3,status,listing_version) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,'active',1)")
                    ->execute([$id,trim($user['city']),$brand,$model,"$brand $model",$plate,$year,$price,$description,$photos[0],...$photos]);
                $listingId=(int)$pdo->lastInsertId();
            }
            $stage='audit';
            rentalEvent($pdo,$editing?'listing_updated':'listing_created',['company_id'=>$id,'listing_id'=>$listingId,'city'=>$user['city']],['vehicle'=>"$brand $model",'daily_price'=>$price]);
            $stage='commit';
            $pdo->commit(); rentalCleanupPhotos($pdo,$oldPhotos);
            sendResponse($editing?200:201,['status'=>'success','listing_id'=>$listingId,'message'=>$editing?'Araç bilgileri güncellendi.':'Araç ilana eklendi.']);
        }
        // Lock order is always listing -> bid -> customer, across all mutations.
        $bidId = filter_var($_POST['bid_id'] ?? null, FILTER_VALIDATE_INT);
        $listingId = filter_var($_POST['listing_id'] ?? null, FILTER_VALIDATE_INT);
        if (!in_array($action,['place_rentacar_bid','reserve_rentacar_listing'],true)) {
            if (!$bidId || $bidId<1) throw new InvalidArgumentException('Teklif seçin.');
            $stmt=$pdo->prepare('SELECT listing_id FROM rentacar_bids WHERE id=?'); $stmt->execute([$bidId]);
            $listingId=(int)$stmt->fetchColumn();
        }
        if (!$listingId || $listingId<1) rentalFail(404, 'Araç bulunamadı.');
        $pdo->beginTransaction();
        $stmt=$pdo->prepare('SELECT * FROM rentacar_listings WHERE id=? FOR UPDATE'); $stmt->execute([$listingId]);
        $listing=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$listing) { $pdo->rollBack(); rentalFail(404, 'Araç bulunamadı.'); }
        if (in_array($action,['place_rentacar_bid','reserve_rentacar_listing'],true)) {
            if ($actor !== 'customer') { $pdo->rollBack(); rentalFail(403, 'Kiralama talebini müşteri oluşturabilir.'); }
            $pdo->prepare('SELECT id FROM users WHERE id IN (?,?) ORDER BY id FOR UPDATE')->execute([$id,$listing['company_id']]);
            $customer=rentalUser($pdo,$id,'customer');
            $company=rentalUser($pdo, $listing['company_id'], 'rentacar');
            rentalRequireSubscription($pdo,$company);
            if (!rentalSameCity($customer['city'], $company['city'])) { $pdo->rollBack(); rentalFail(403, 'Yalnızca aynı şehirdeki firmayla eşleşebilirsiniz.'); }
            $quote=rentalQuote($listing['daily_price'],$_POST['rent_days'] ?? null,$_POST['total_budget'] ?? '');
            $days=$quote['days'];
            if ($action==='reserve_rentacar_listing' && rentalMoneyCents($quote['amount']) > rentalMoneyCents($quote['budget'])) {
                throw new InvalidArgumentException('Araç bu süre için toplam bütçenizi aşıyor.');
            }
            if ($action==='reserve_rentacar_listing' && $listing['status']==='rented') {
                $stmt=$pdo->prepare("SELECT * FROM rentacar_bids WHERE listing_id=? AND customer_id=? AND status='accepted' AND rent_days=? AND customer_budget=? LIMIT 1");
                $stmt->execute([$listingId,$id,$days,$quote['budget']]); $reserved=$stmt->fetch(PDO::FETCH_ASSOC);
                if ($reserved) { $pdo->commit(); sendResponse(200,['status'=>'success','job_id'=>(int)$reserved['job_id'],'amount'=>$reserved['amount'],'rent_days'=>$days]); }
            }
            if ($listing['status'] !== 'active') { $pdo->rollBack(); rentalFail(409, 'Bu araç şu anda kiralamaya uygun değil.'); }
            if ($action==='reserve_rentacar_listing' && !filter_var($_POST['listing_version'] ?? null,FILTER_VALIDATE_INT)) throw new InvalidArgumentException('Güncel ilanı seçip rezervasyonu onaylayın.');
            if (isset($_POST['listing_version']) && (int)$_POST['listing_version']!==(int)$listing['listing_version']) { $pdo->rollBack(); rentalFail(409,'İlan değişti. Güncel araç fiyatını kontrol edin.'); }
            $stmt=$pdo->prepare("SELECT * FROM rentacar_bids WHERE listing_id=? AND customer_id=? AND status IN ('pending','accepted') ORDER BY id DESC LIMIT 1 FOR UPDATE");
            $stmt->execute([$listingId,$id]); $existing=$stmt->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                if ($action==='reserve_rentacar_listing') { $pdo->rollBack(); rentalFail(409,'Bu araç için bekleyen teklifiniz var. Önce teklifi kabul edin veya iptal edin.'); }
                if ((int)$existing['rent_days']!==$days) { $pdo->rollBack(); rentalFail(409,'Gün sayısını değiştirmek için önce mevcut teklifinizi iptal edin.'); }
                if ($existing['customer_budget']!==null && $existing['customer_budget']!==$quote['budget']) { $pdo->rollBack(); rentalFail(409,'Bütçeyi değiştirmek için önce mevcut teklifinizi iptal edin.'); }
                $pdo->commit(); sendResponse(200,['status'=>'success','bid'=>$existing,'message'=>'Mevcut teklifiniz görüntülendi.']);
            }
            $daily=rentalMoneyCents($listing['daily_price']);
            $total=$action==='place_rentacar_bid' ? $quote['budget'] : $quote['amount'];
            $stmt=$pdo->prepare("INSERT INTO rentacar_bids (listing_id,customer_id,amount,rent_days,quoted_daily_price,customer_budget,vehicle_label,quoted_plate,last_offer_by) VALUES (?,?,?,?,?,?,?,?,'customer')");
            $stmt->execute([$listingId,$id,$total,$days,rentalMoneyText($daily),$quote['budget'],$listing['car_brand_model'],$listing['plate']]);
            $newId=(int)$pdo->lastInsertId();
            if ($action==='reserve_rentacar_listing') {
                $result=rentalReserve($pdo,$listing,['id'=>$newId,'customer_id'=>$id,'amount'=>$total,'rent_days'=>$days],$company);
                // Older approved app versions use the direct booking path.
                $pdo->prepare('UPDATE rentacar_bids SET agreement_at=UTC_TIMESTAMP() WHERE id=?')->execute([$newId]);
                $pdo->commit(); sendResponse(201,$result);
            }
            $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Yeni kiralama teklifi',?)")->execute([$listing['company_id'],$listing['car_brand_model'].' / '.$days.' gün / bütçe '.$quote['budget'].' TL']);
            rentalEvent($pdo,'offer_placed',['company_id'=>$listing['company_id'],'customer_id'=>$id,'listing_id'=>$listingId,'bid_id'=>$newId,'city'=>$company['city']],['amount'=>$total,'days'=>$days]);
            $pdo->commit();
            sendResponse(201,['status'=>'success','bid_id'=>$newId,'amount'=>$total,'rent_days'=>$days,'offer_version'=>1]);
        }
        $stmt=$pdo->prepare('SELECT * FROM rentacar_bids WHERE id=? FOR UPDATE'); $stmt->execute([$bidId]);
        $bid=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$bid || ($actor === 'customer' ? (int)$bid['customer_id']!==$id : (int)$listing['company_id']!==$id)) {
            $pdo->rollBack(); rentalFail(403, 'Bu teklif üzerinde işlem yapamazsınız.');
        }
        if ($action==='delete_rentacar_bid') {
            if ($actor!=='customer') { $pdo->rollBack(); rentalFail(403,'Teklifi yalnızca sahibi olan müşteri silebilir.'); }
            if ($bid['status']==='accepted') { $pdo->rollBack(); rentalFail(409,'Aktif rezervasyon silinemez. Sorun varsa rezervasyon detayından yöneticiye şikâyet bildirin.'); }
            if (!empty($bid['customer_hidden'])) { $pdo->commit(); sendResponse(200,['status'=>'success','message'=>'Teklif zaten kaldırılmış.']); }
            $version=filter_var($_POST['offer_version'] ?? null,FILTER_VALIDATE_INT);
            if (!$version || (int)$bid['offer_version']!==$version) { $pdo->rollBack(); rentalFail(409,'Teklif değişti. Listeyi yenileyip tekrar deneyin.'); }
            if ($bid['status']==='pending') {
                $pdo->prepare("UPDATE rentacar_bids SET status='rejected',customer_hidden=1,offer_version=offer_version+1 WHERE id=?")->execute([$bidId]);
                $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Kiralama teklifi iptal edildi',?)")->execute([$listing['company_id'],'Müşteri '.$bid['vehicle_label'].' için teklifini geri çekti.']);
            } else {
                $pdo->prepare('UPDATE rentacar_bids SET customer_hidden=1,offer_version=offer_version+1 WHERE id=?')->execute([$bidId]);
            }
            rentalEvent($pdo,'offer_removed',['company_id'=>$listing['company_id'],'customer_id'=>$id,'listing_id'=>$listingId,'bid_id'=>$bidId,'job_id'=>$bid['job_id'],'city'=>$listing['city']],['previous_status'=>$bid['status']]);
            $pdo->commit(); sendResponse(200,['status'=>'success','message'=>'Teklif listenizden kaldırıldı.']);
        }
        if ($action === 'accept_rentacar_bid' && $bid['status']==='accepted' && $bid['job_id']) {
            $pdo->commit(); sendResponse(200,['status'=>'success','job_id'=>(int)$bid['job_id']]);
        }
        $version=filter_var($_POST['offer_version'] ?? null,FILTER_VALIDATE_INT);
        if (!$version || (int)$bid['offer_version']!==$version) { $pdo->rollBack(); rentalFail(409, 'Teklif değişti. Güncel teklifi kontrol edin.'); }
        if ($action === 'agree_rentacar_booking') {
            if ($actor!=='company' || $bid['status']!=='accepted' || !$bid['job_id']) { $pdo->rollBack(); rentalFail(409,'Anlaşma için önce teklifi kabul edin.'); }
            $stmt=$pdo->prepare("SELECT status FROM jobs WHERE id=? AND service_type='rentacar' FOR UPDATE"); $stmt->execute([$bid['job_id']]);
            if ($stmt->fetchColumn()!=='matched') { $pdo->rollBack(); rentalFail(409,'Bu kiralama artık anlaşmaya açık değil.'); }
            if (empty($bid['agreement_at'])) {
                $pdo->prepare('UPDATE rentacar_bids SET agreement_at=UTC_TIMESTAMP(),offer_version=offer_version+1 WHERE id=?')->execute([$bidId]);
                rentalEvent($pdo,'agreed',['company_id'=>$listing['company_id'],'customer_id'=>$bid['customer_id'],'listing_id'=>$listingId,'bid_id'=>$bidId,'job_id'=>$bid['job_id'],'city'=>$listing['city']]);
            }
            $pdo->commit(); sendResponse(200,['status'=>'success','job_id'=>(int)$bid['job_id'],'message'=>'Anlaşma kaydedildi. Müşteri yol tarifi alabilir.']);
        }
        if ($action === 'complete_rentacar_booking') {
            if ($actor!=='company' || $bid['status']!=='accepted' || !$bid['job_id']) { $pdo->rollBack(); rentalFail(409,'Tamamlanabilecek bir kiralama bulunamadı.'); }
            if (empty($bid['agreement_at'])) { $pdo->rollBack(); rentalFail(409,'Önce Anlaştık adımını onaylayın.'); }
            $pdo->prepare("UPDATE jobs SET status='completed' WHERE id=? AND service_type='rentacar'")->execute([$bid['job_id']]);
            $completedReferralJobId=(int)$bid['job_id'];
            $pdo->prepare("UPDATE rentacar_bids SET status='completed',offer_version=offer_version+1 WHERE id=?")->execute([$bidId]);
            $pdo->prepare("UPDATE rentacar_listings SET status='active',listing_version=listing_version+1 WHERE id=?")->execute([$listingId]);
            rentalEvent($pdo,'completed',['company_id'=>$listing['company_id'],'customer_id'=>$bid['customer_id'],'listing_id'=>$listingId,'bid_id'=>$bidId,'job_id'=>$bid['job_id'],'city'=>$listing['city']]);
            $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Kiralamayı değerlendir',?)")->execute([$bid['customer_id'],'Kiralaman tamamlandı. Rezervasyon detayından firmaya puan ve yorum bırakabilirsin.']);
        } elseif ($action === 'reject_rentacar_bid') {
            if ($bid['status']!=='pending') { $pdo->rollBack(); rentalFail(409,'Bu teklif artık kapatılamaz.'); }
            $pdo->prepare("UPDATE rentacar_bids SET status='rejected',offer_version=offer_version+1 WHERE id=?")->execute([$bidId]);
            rentalEvent($pdo,'offer_rejected',['company_id'=>$listing['company_id'],'customer_id'=>$bid['customer_id'],'listing_id'=>$listingId,'bid_id'=>$bidId,'city'=>$listing['city']]);
        } else {
            if ($listing['status']!=='active' || !rentalCanRespond($bid,$actor,$version)) {
                $pdo->rollBack(); rentalFail(409, 'Kendi teklifinizi kabul edemezsiniz. Karşı tarafın yanıtını bekleyin.');
            }
            $pdo->prepare('SELECT id FROM users WHERE id IN (?,?) ORDER BY id FOR UPDATE')->execute([$bid['customer_id'],$listing['company_id']]);
            $customer=rentalUser($pdo,$bid['customer_id'],'customer');
            $company=rentalUser($pdo,$listing['company_id'],'rentacar');
            rentalRequireSubscription($pdo,$company);
            if (!rentalSameCity($customer['city'],$company['city'])) { $pdo->rollBack(); rentalFail(403,'Hesapların şehirleri eşleşmiyor. Profilleri kontrol edin.'); }
            if ($action==='counter_rentacar_bid') {
                $amount=rentalMoneyText(rentalMoneyCents($_POST['amount'] ?? ''));
                if ($bid['customer_budget']!==null && rentalMoneyCents($amount)>rentalMoneyCents($bid['customer_budget'])) throw new InvalidArgumentException('Karşı teklif müşterinin toplam bütçesini aşamaz.');
                $pdo->prepare('UPDATE rentacar_bids SET amount=?,last_offer_by=?,offer_version=offer_version+1 WHERE id=?')->execute([$amount,$actor,$bidId]);
                rentalEvent($pdo,'counter_offer',['company_id'=>$listing['company_id'],'customer_id'=>$bid['customer_id'],'listing_id'=>$listingId,'bid_id'=>$bidId,'city'=>$company['city']],['amount'=>$amount,'offer_version'=>$version+1]);
            } else {
                if ($bid['customer_budget']!==null && rentalMoneyCents($bid['amount'])>rentalMoneyCents($bid['customer_budget'])) throw new InvalidArgumentException('Kabul edilen tutar müşterinin toplam bütçesini aşıyor.');
                $result=rentalReserve($pdo,$listing,$bid,$company);
                $pdo->commit(); sendResponse(200,$result);
            }
        }
        $pdo->commit();
        if ($completedReferralJobId) referralRewardForCompletedJob($pdo,$completedReferralJobId);
        sendResponse(200,['status'=>'success','message'=>'İşlem tamamlandı.']);
    } catch (InvalidArgumentException $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        foreach ($uploaded as $path) if ($path) deletePhysicalFile($path);
        rentalFail(422,$e->getMessage());
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        foreach ($uploaded as $path) if ($path) deletePhysicalFile($path);
        $reference=bin2hex(random_bytes(6));
        $code='RENTAL_SERVER_ERROR'; $http=500; $message='Kiralama işlemi tamamlanamadı. Yöneticiye destek kodunu iletin: '.$reference;
        if ($e instanceof RentalServerException) { $code=$e->errorCode; $http=503; $message=$e->getMessage(); }
        elseif ($stage==='schema') { $code='RENTAL_DATABASE_SCHEMA'; $http=503; $message='Kiralama veritabanı hazırlanamadı. Yönetici tablo yapısını, CREATE/ALTER izinlerini ve InnoDB kullanımını kontrol etmeli.'; }
        elseif ($e instanceof PDOException) {
            $number=(int)($e->errorInfo[1] ?? 0);
            if (in_array($number,[1054,1146,1364,1048,1265,1406],true)) { $code='RENTAL_DATABASE_SCHEMA'; $message='Araç kaydı veritabanındaki tablo yapısıyla uyumlu değil. Yönetici güncel backend dosyalarını ve PHP hata günlüğünü kontrol etmeli.'; }
            elseif (in_array($number,[1142,1143,1227],true)) { $code='RENTAL_DATABASE_PERMISSION'; $http=503; $message='Kiralama veritabanına yazma yetkisi yok. Yönetici veritabanı kullanıcısının izinlerini kontrol etmeli.'; }
        }
        error_log('Rental API: ['.$reference.'] action='.$action.' stage='.$stage.' code='.$code.' '.$e->getMessage());
        sendResponse($http,['status'=>'error','message'=>$message,'error_code'=>$code,'reference'=>$reference]);
    } finally {
        if ($plateLock) { $stmt=$pdo->prepare('SELECT RELEASE_LOCK(?)'); $stmt->execute([$plateLock]); }
    }
}
