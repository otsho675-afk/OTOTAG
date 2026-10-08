<?php

function ensureGrowthSchema($pdo) {
    apiSchemaMigration($pdo,'growth_features_v1',function() use($pdo) {
        $columns=$pdo->query("SHOW COLUMNS FROM users")->fetchAll(PDO::FETCH_COLUMN);
        $userDefs=[
            'is_verified'=>"TINYINT(1) NOT NULL DEFAULT 0",
            'phone_verified_at'=>"DATETIME NULL",
            'last_active_at'=>"DATETIME NULL",
        ];
        foreach ($userDefs as $column=>$definition) {
            if (!in_array($column,$columns,true)) {
                $pdo->exec("ALTER TABLE users ADD COLUMN `$column` $definition");
            }
        }

        $jobColumns=$pdo->query("SHOW COLUMNS FROM jobs")->fetchAll(PDO::FETCH_COLUMN);
        $jobDefs=[
            'is_emergency'=>"TINYINT(1) NOT NULL DEFAULT 0",
            'prefer_favorites'=>"TINYINT(1) NOT NULL DEFAULT 1",
        ];
        foreach ($jobDefs as $column=>$definition) {
            if (!in_array($column,$jobColumns,true)) {
                $pdo->exec("ALTER TABLE jobs ADD COLUMN `$column` $definition");
            }
        }

        $pdo->exec("CREATE TABLE IF NOT EXISTS phone_verifications (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            phone VARCHAR(32) NOT NULL,
            code_hash CHAR(64) NOT NULL,
            attempts INT NOT NULL DEFAULT 0,
            expires_at DATETIME NOT NULL,
            verified_at DATETIME NULL,
            verification_token_hash CHAR(64) NULL,
            ip_address VARCHAR(64) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY idx_phone_verify_phone (phone,created_at),
            KEY idx_phone_verify_expiry (expires_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        $pdo->exec("CREATE TABLE IF NOT EXISTS favorite_providers (
            customer_id INT NOT NULL,
            provider_id INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY(customer_id,provider_id),
            KEY idx_favorite_provider (provider_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        $pdo->exec("CREATE TABLE IF NOT EXISTS reward_redemptions (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            reward_id VARCHAR(50) NOT NULL,
            points_spent INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY idx_reward_redemptions_user (user_id,created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        $pdo->exec("CREATE TABLE IF NOT EXISTS growth_reminder_log (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            vehicle_id INT NOT NULL,
            reminder_type VARCHAR(40) NOT NULL,
            reminder_key VARCHAR(80) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_growth_reminder (user_id,vehicle_id,reminder_type,reminder_key)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    });
}

function growthBoolConfig($key,$default=false) {
    $value=strtolower(trim((string)serverConfig($key,$default ? '1':'0')));
    return in_array($value,['1','true','yes','on'],true);
}

function growthConfig() {
    return [
        'status'=>'success',
        'sms_verification_required'=>growthBoolConfig('SMS_VERIFICATION_REQUIRED',false),
        'sms_configured'=>trim((string)serverConfig('SMS_HTTP_URL'))!=='',
        'features'=>[
            'reward_store'=>true,
            'smart_price'=>true,
            'favorites'=>true,
            'vehicle_health'=>true,
            'growth_analytics'=>true,
        ],
    ];
}

function growthRewardCatalog() {
    return [
        ['id'=>'premium_7','title'=>'7 Gün Premium','points'=>100,'roles'=>['customer'],'icon'=>'workspace_premium'],
        ['id'=>'premium_30','title'=>'30 Gün Premium','points'=>250,'roles'=>['customer'],'icon'=>'workspace_premium'],
        ['id'=>'obd_30','title'=>'30 Gün OBD Paketi','points'=>300,'roles'=>['customer','provider','rentacar'],'icon'=>'settings_input_component'],
        ['id'=>'business_15','title'=>'15 Gün İşletme Üyeliği','points'=>500,'roles'=>['provider','rentacar'],'icon'=>'business_center'],
    ];
}

function growthRewardDefinition($rewardId) {
    foreach (growthRewardCatalog() as $item) if ($item['id']===$rewardId) return $item;
    return null;
}

function growthAddEntitlementDays($pdo,$userId,$column,$days,$setPremium=false) {
    $allowed=['premium_end_date','obd_subscription_end_date','subscription_end_date'];
    if (!in_array($column,$allowed,true)) throw new InvalidArgumentException('Ödül paketi geçersiz.');
    $days=(int)$days;
    if ($days<1 || $days>365) throw new InvalidArgumentException('Ödül süresi geçersiz.');
    if (!$pdo->query("SHOW COLUMNS FROM users LIKE ".$pdo->quote($column))->fetch()) {
        $pdo->exec("ALTER TABLE users ADD COLUMN `$column` DATETIME NULL");
    }
    $premiumSql=$setPremium ? ', is_premium=1' : '';
    $sql="UPDATE users SET `$column`=CASE
        WHEN `$column` IS NULL OR `$column`<NOW() THEN DATE_ADD(NOW(), INTERVAL $days DAY)
        ELSE DATE_ADD(`$column`, INTERVAL $days DAY) END$premiumSql
        WHERE id=?";
    $pdo->prepare($sql)->execute([$userId]);
}

function growthRedeemReward($pdo,$userId,$rewardId) {
    ensureGrowthSchema($pdo);
    ensureReferralSchema($pdo);
    $reward=growthRewardDefinition($rewardId);
    if (!$reward) throw new InvalidArgumentException('Ödül bulunamadı.');

    $pdo->beginTransaction();
    try {
        $stmt=$pdo->prepare('SELECT id,user_type,reward_points FROM users WHERE id=? FOR UPDATE');
        $stmt->execute([$userId]);
        $user=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$user) throw new InvalidArgumentException('Hesap bulunamadı.');
        if (!in_array($user['user_type'],$reward['roles'],true)) throw new InvalidArgumentException('Bu ödül hesap türünüz için uygun değil.');
        if ((int)$user['reward_points']<(int)$reward['points']) throw new InvalidArgumentException('Yeterli OTO TAG Puanınız yok.');

        $pdo->prepare('UPDATE users SET reward_points=reward_points-? WHERE id=?')->execute([(int)$reward['points'],$userId]);
        if ($rewardId==='premium_7') growthAddEntitlementDays($pdo,$userId,'premium_end_date',7,true);
        elseif ($rewardId==='premium_30') growthAddEntitlementDays($pdo,$userId,'premium_end_date',30,true);
        elseif ($rewardId==='obd_30') growthAddEntitlementDays($pdo,$userId,'obd_subscription_end_date',30,false);
        elseif ($rewardId==='business_15') growthAddEntitlementDays($pdo,$userId,'subscription_end_date',15,false);

        $pdo->prepare('INSERT INTO reward_redemptions(user_id,reward_id,points_spent) VALUES (?,?,?)')
            ->execute([$userId,$rewardId,(int)$reward['points']]);
        $message=$reward['title'].' etkinleştirildi. '.(int)$reward['points'].' OTO TAG Puan kullanıldı.';
        $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Puan ödülün aktif',?)")->execute([$userId,$message]);
        $pdo->commit();
        try { sendOneSignalPush((string)$userId,'Puan ödülün aktif',$message,['type'=>'reward_redemption']); } catch (Throwable $e) {}

        $stmt=$pdo->prepare('SELECT reward_points FROM users WHERE id=?'); $stmt->execute([$userId]);
        return ['status'=>'success','message'=>$message,'reward_points'=>(int)$stmt->fetchColumn()];
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
}

function growthSendSms($phone,$message) {
    $url=trim((string)serverConfig('SMS_HTTP_URL'));
    if ($url==='') return false;
    $token=trim((string)serverConfig('SMS_HTTP_TOKEN'));
    $sender=trim((string)serverConfig('SMS_HTTP_SENDER','OTO TAG'));
    $payload=json_encode(['to'=>$phone,'message'=>$message,'sender'=>$sender],JSON_UNESCAPED_UNICODE);
    $ch=curl_init($url);
    curl_setopt_array($ch,[
        CURLOPT_POST=>true,
        CURLOPT_RETURNTRANSFER=>true,
        CURLOPT_CONNECTTIMEOUT=>5,
        CURLOPT_TIMEOUT=>10,
        CURLOPT_HTTPHEADER=>array_values(array_filter([
            'Content-Type: application/json',
            $token!=='' ? 'Authorization: Bearer '.$token : null,
        ])),
        CURLOPT_POSTFIELDS=>$payload,
    ]);
    curl_exec($ch);
    $status=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE);
    curl_close($ch);
    return $status>=200 && $status<300;
}

function growthRequestPhoneVerification($pdo,$phone,$ipAddress='') {
    ensureGrowthSchema($pdo);
    $phone=registrationPhone($phone);
    $recent=$pdo->prepare('SELECT COUNT(*) FROM phone_verifications WHERE phone=? AND created_at>=DATE_SUB(NOW(),INTERVAL 2 MINUTE)');
    $recent->execute([$phone]);
    if ((int)$recent->fetchColumn()>=3) throw new DomainException('Çok sık kod istendi. Lütfen iki dakika sonra tekrar deneyin.');

    if (!growthBoolConfig('SMS_VERIFICATION_REQUIRED',false)) {
        return ['status'=>'success','required'=>false,'message'=>'SMS doğrulaması şu anda zorunlu değil.'];
    }
    if (trim((string)serverConfig('SMS_HTTP_URL'))==='') throw new RuntimeException('SMS servisi henüz yapılandırılmadı.');

    $code=(string)random_int(100000,999999);
    $hash=hash_hmac('sha256',$code,JWT_SECRET);
    $pdo->prepare('INSERT INTO phone_verifications(phone,code_hash,expires_at,ip_address) VALUES (?,?,DATE_ADD(NOW(),INTERVAL 5 MINUTE),?)')
        ->execute([$phone,$hash,$ipAddress ?: null]);
    if (!growthSendSms($phone,'OTO TAG doğrulama kodunuz: '.$code.' Kod 5 dakika geçerlidir.')) {
        throw new RuntimeException('SMS gönderilemedi. Lütfen tekrar deneyin.');
    }
    return ['status'=>'success','required'=>true,'message'=>'Doğrulama kodu gönderildi.'];
}

function growthVerifyPhoneCode($pdo,$phone,$code) {
    ensureGrowthSchema($pdo);
    $phone=registrationPhone($phone);
    $code=preg_replace('/\D/','',(string)$code);
    if (!preg_match('/^[0-9]{6}$/D',$code)) throw new InvalidArgumentException('6 haneli doğrulama kodunu girin.');

    $stmt=$pdo->prepare('SELECT * FROM phone_verifications WHERE phone=? AND verified_at IS NULL ORDER BY id DESC LIMIT 1');
    $stmt->execute([$phone]);
    $row=$stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row || strtotime($row['expires_at'])<time()) throw new InvalidArgumentException('Doğrulama kodunun süresi dolmuş.');
    if ((int)$row['attempts']>=5) throw new InvalidArgumentException('Çok fazla hatalı deneme yapıldı.');

    $pdo->prepare('UPDATE phone_verifications SET attempts=attempts+1 WHERE id=?')->execute([$row['id']]);
    if (!hash_equals($row['code_hash'],hash_hmac('sha256',$code,JWT_SECRET))) throw new InvalidArgumentException('Doğrulama kodu hatalı.');

    $token=bin2hex(random_bytes(24));
    $tokenHash=hash('sha256',$token);
    $pdo->prepare('UPDATE phone_verifications SET verified_at=NOW(),verification_token_hash=? WHERE id=?')
        ->execute([$tokenHash,$row['id']]);
    return ['status'=>'success','verification_token'=>$token,'message'=>'Telefon doğrulandı.'];
}

function growthValidatePhoneVerification($pdo,$phone,$token) {
    if (!growthBoolConfig('SMS_VERIFICATION_REQUIRED',false)) return true;
    ensureGrowthSchema($pdo);
    $phone=registrationPhone($phone);
    $token=trim((string)$token);
    if ($token==='') return false;
    $stmt=$pdo->prepare('SELECT id FROM phone_verifications WHERE phone=? AND verified_at IS NOT NULL AND verification_token_hash=? AND verified_at>=DATE_SUB(NOW(),INTERVAL 30 MINUTE) ORDER BY id DESC LIMIT 1');
    $stmt->execute([$phone,hash('sha256',$token)]);
    return (bool)$stmt->fetchColumn();
}

function growthSmartPrice($service,$distanceKm,$hour=null) {
    $service=strtolower(trim((string)$service));
    $distance=max(0.0,min(100.0,(float)$distanceKm));
    $rules=[
        'mechanic'=>['base'=>700,'km'=>55],
        'tow'=>['base'=>950,'km'=>75],
        'tire'=>['base'=>450,'km'=>40],
        'wash'=>['base'=>280,'km'=>22],
    ];
    $rule=$rules[$service] ?? $rules['mechanic'];
    $hour=$hour===null ? (int)date('G') : max(0,min(23,(int)$hour));
    $multiplier=1.0;
    $reason='normal';
    if ($hour>=22 || $hour<6) { $multiplier=1.15; $reason='gece'; }
    elseif ($hour>=16 && $hour<=20) { $multiplier=1.08; $reason='yoğun_saat'; }

    $recommended=(int)(round((($rule['base']+$distance*$rule['km'])*$multiplier)/10)*10);
    $low=(int)(floor(($recommended*.90)/10)*10);
    $high=(int)(ceil(($recommended*1.15)/10)*10);
    $eta=max(6,min(90,(int)ceil(($distance/25.0)*60)+6));
    return [
        'status'=>'success',
        'service_type'=>$service,
        'distance_km'=>round($distance,1),
        'recommended'=>$recommended,
        'low'=>$low,
        'high'=>$high,
        'estimated_minutes'=>$eta,
        'price_factor'=>$reason,
        'currency'=>'TRY',
    ];
}

function growthProviderMetrics($pdo,$providerId) {
    ensureGrowthSchema($pdo);
    $stmt=$pdo->prepare('SELECT id,name,user_type,service_category,rating,reviews_count,is_verified,last_active_at FROM users WHERE id=?');
    $stmt->execute([$providerId]);
    $user=$stmt->fetch(PDO::FETCH_ASSOC);
    if (!$user) return null;

    $jobs=$pdo->prepare("SELECT
        SUM(status='completed') completed_jobs,
        SUM(status='cancelled') cancelled_jobs,
        COUNT(*) total_jobs
        FROM jobs WHERE provider_id=?");
    $jobs->execute([$providerId]);
    $j=$jobs->fetch(PDO::FETCH_ASSOC) ?: [];
    $closed=max(1,(int)($j['completed_jobs'] ?? 0)+(int)($j['cancelled_jobs'] ?? 0));

    $response=$pdo->prepare("SELECT AVG(TIMESTAMPDIFF(SECOND,j.created_at,x.first_bid)) avg_seconds
        FROM jobs j
        JOIN (SELECT job_id,MIN(created_at) first_bid FROM bids WHERE provider_id=? GROUP BY job_id) x ON x.job_id=j.id");
    $response->execute([$providerId]);
    $avgResponse=$response->fetchColumn();

    $last=$pdo->prepare("SELECT GREATEST(
        COALESCE((SELECT MAX(created_at) FROM bids WHERE provider_id=?),'1970-01-01'),
        COALESCE((SELECT MAX(created_at) FROM jobs WHERE provider_id=?),'1970-01-01')
    )");
    $last->execute([$providerId,$providerId]);
    $lastActive=$last->fetchColumn();

    return [
        'is_verified'=>(bool)($user['is_verified'] ?? 0),
        'completed_jobs'=>(int)($j['completed_jobs'] ?? 0),
        'cancellation_rate'=>round(((int)($j['cancelled_jobs'] ?? 0)/$closed)*100,1),
        'average_response_seconds'=>$avgResponse===null ? null : (int)round((float)$avgResponse),
        'last_active_at'=>$lastActive && $lastActive!=='1970-01-01' ? $lastActive : ($user['last_active_at'] ?? null),
        'rating'=>(float)($user['rating'] ?? 0),
        'review_count'=>(int)($user['reviews_count'] ?? 0),
    ];
}

function growthToggleFavorite($pdo,$customerId,$providerId) {
    ensureGrowthSchema($pdo);
    if ((int)$customerId===(int)$providerId) throw new InvalidArgumentException('Kendi hesabınızı favorileyemezsiniz.');
    $stmt=$pdo->prepare("SELECT id FROM users WHERE id=? AND user_type IN ('provider','rentacar') AND status='active'");
    $stmt->execute([$providerId]);
    if (!$stmt->fetchColumn()) throw new InvalidArgumentException('Sağlayıcı bulunamadı.');

    $stmt=$pdo->prepare('SELECT provider_id FROM favorite_providers WHERE customer_id=? AND provider_id=?');
    $stmt->execute([$customerId,$providerId]);
    if ($stmt->fetchColumn()) {
        $pdo->prepare('DELETE FROM favorite_providers WHERE customer_id=? AND provider_id=?')->execute([$customerId,$providerId]);
        return ['status'=>'success','favorite'=>false];
    }
    $pdo->prepare('INSERT IGNORE INTO favorite_providers(customer_id,provider_id) VALUES (?,?)')->execute([$customerId,$providerId]);
    return ['status'=>'success','favorite'=>true];
}

function growthFavoriteProviders($pdo,$customerId) {
    ensureGrowthSchema($pdo);
    $stmt=$pdo->prepare("SELECT u.id,u.name,u.user_type,u.service_category,u.rating,u.reviews_count,u.city,u.is_verified,
        (SELECT COUNT(*) FROM jobs WHERE provider_id=u.id AND status='completed') completed_jobs
        FROM favorite_providers f JOIN users u ON u.id=f.provider_id
        WHERE f.customer_id=? AND u.status='active'
        ORDER BY f.created_at DESC");
    $stmt->execute([$customerId]);
    return ['status'=>'success','providers'=>$stmt->fetchAll(PDO::FETCH_ASSOC)];
}

function growthMatchingMeta($pdo,$jobId) {
    ensureGrowthSchema($pdo);
    $stmt=$pdo->prepare('SELECT id,customer_id,service_type,city,search_radius,status FROM jobs WHERE id=?');
    $stmt->execute([$jobId]);
    $job=$stmt->fetch(PDO::FETCH_ASSOC);
    if (!$job) return null;
    $count=$pdo->prepare("SELECT COUNT(*) FROM users
        WHERE user_type='provider' AND status='active' AND COALESCE(is_suspended,0)=0
        AND service_category=? AND LOWER(TRIM(city))=LOWER(TRIM(?))");
    $count->execute([$job['service_type'],$job['city']]);
    $providers=(int)$count->fetchColumn();

    $bids=$pdo->prepare("SELECT COUNT(*) FROM bids WHERE job_id=? AND status IN ('pending','negotiating')");
    $bids->execute([$jobId]);

    $fav=$pdo->prepare("SELECT COUNT(*) FROM favorite_providers f JOIN users u ON u.id=f.provider_id
        WHERE f.customer_id=? AND u.status='active' AND u.service_category=? AND LOWER(TRIM(u.city))=LOWER(TRIM(?))");
    $fav->execute([$job['customer_id'],$job['service_type'],$job['city']]);

    return [
        'status'=>$job['status'],
        'providers_scanned'=>$providers,
        'favorite_providers'=>(int)$fav->fetchColumn(),
        'real_bids'=>(int)$bids->fetchColumn(),
        'radius_km'=>(float)($job['search_radius'] ?? 50),
    ];
}

function growthReminderBucket($days) {
    if ($days<0) return 'overdue';
    if ($days===0) return 'today';
    if ($days<=1) return '1d';
    if ($days<=7) return '7d';
    if ($days<=15) return '15d';
    return null;
}

function growthSyncVehicleReminders($pdo,$userId) {
    ensureGrowthSchema($pdo);
    $stmt=$pdo->prepare('SELECT * FROM vehicles WHERE customer_id=? ORDER BY id DESC');
    $stmt->execute([$userId]);
    $vehicles=$stmt->fetchAll(PDO::FETCH_ASSOC);
    $alerts=[];

    foreach ($vehicles as $vehicle) {
        $plate=$vehicle['plate'] ?? 'Araç';
        foreach (['insurance_date'=>'Trafik sigortası','inspection_date'=>'Muayene','mtv_date'=>'MTV'] as $field=>$label) {
            if (empty($vehicle[$field])) continue;
            try {
                $today=new DateTime('today');
                $target=new DateTime($vehicle[$field]);
                $days=(int)$today->diff($target)->format('%r%a');
            } catch (Throwable $e) { continue; }
            if ($days>15) continue;
            $bucket=growthReminderBucket($days);
            if ($days<0) $message="$plate: $label ".abs($days)." gün gecikti.";
            elseif ($days===0) $message="$plate: $label bugün.";
            else $message="$plate: $label için $days gün kaldı.";
            $alerts[]=$message;
            $key=substr((string)$vehicle[$field],0,10).'|'.$bucket;
            $ins=$pdo->prepare('INSERT IGNORE INTO growth_reminder_log(user_id,vehicle_id,reminder_type,reminder_key) VALUES (?,?,?,?)');
            $ins->execute([$userId,$vehicle['id'],$field,$key]);
            if ($ins->rowCount()>0) {
                $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Araç hatırlatması',?)")->execute([$userId,$message]);
                try { sendOneSignalPush((string)$userId,'Araç hatırlatması',$message,['type'=>'vehicle_reminder','vehicle_id'=>(string)$vehicle['id']]); } catch (Throwable $e) {}
            }
        }

        $current=(int)($vehicle['current_km'] ?? 0);
        $maintenance=(int)($vehicle['maintenance_km'] ?? 0);
        if ($maintenance>0) {
            $remaining=$maintenance-$current;
            if ($remaining<=1000) {
                $message=$remaining<=0
                    ? "$plate: Bakım kilometresi ".abs($remaining)." km geçti."
                    : "$plate: Bakıma yaklaşık $remaining km kaldı.";
                $alerts[]=$message;
                $key=$remaining<=0 ? 'due' : '1000km';
                $ins=$pdo->prepare('INSERT IGNORE INTO growth_reminder_log(user_id,vehicle_id,reminder_type,reminder_key) VALUES (?,?,?,?)');
                $ins->execute([$userId,$vehicle['id'],'maintenance_km',$key]);
                if ($ins->rowCount()>0) {
                    $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES (?,'Bakım hatırlatması',?)")->execute([$userId,$message]);
                    try { sendOneSignalPush((string)$userId,'Bakım hatırlatması',$message,['type'=>'vehicle_reminder','vehicle_id'=>(string)$vehicle['id']]); } catch (Throwable $e) {}
                }
            }
        }
    }
    return ['status'=>'success','alerts'=>$alerts,'vehicles'=>$vehicles];
}

function growthAdminAnalytics($pdo) {
    ensureGrowthSchema($pdo);
    ensureReferralSchema($pdo);

    $summary=$pdo->query("SELECT
        (SELECT COUNT(*) FROM users WHERE created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)) new_users_30d,
        (SELECT COUNT(*) FROM jobs WHERE created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)) jobs_30d,
        (SELECT COUNT(*) FROM jobs WHERE status='completed' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)) completed_30d,
        (SELECT COUNT(*) FROM jobs WHERE status='cancelled' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)) cancelled_30d,
        (SELECT COUNT(*) FROM users WHERE user_type='provider' AND status='active') active_providers,
        (SELECT COUNT(*) FROM favorite_providers) favorites_total,
        (SELECT COUNT(*) FROM referral_rewards WHERE created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)) referrals_30d,
        (SELECT COUNT(*) FROM referral_rewards WHERE status='rewarded' AND rewarded_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)) referrals_rewarded_30d,
        (SELECT COALESCE(SUM(reward_points),0) FROM users) points_outstanding")->fetch(PDO::FETCH_ASSOC);

    $jobs=max(1,(int)($summary['jobs_30d'] ?? 0));
    $summary['completion_rate']=round(((int)($summary['completed_30d'] ?? 0)/$jobs)*100,1);

    $city=$pdo->query("SELECT city,COUNT(*) jobs FROM jobs WHERE created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY) AND city IS NOT NULL AND city<>'' GROUP BY city ORDER BY jobs DESC LIMIT 10")->fetchAll(PDO::FETCH_ASSOC);
    $services=$pdo->query("SELECT service_type,COUNT(*) jobs FROM jobs WHERE created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY) GROUP BY service_type ORDER BY jobs DESC")->fetchAll(PDO::FETCH_ASSOC);
    return ['status'=>'success','summary'=>$summary,'top_cities'=>$city,'services'=>$services];
}

function handleGrowthAction($pdo,$action,$method) {
    $actions=[
        'get_growth_config','get_reward_catalog','redeem_reward_points',
        'request_phone_verification','verify_phone_code','get_smart_price',
        'toggle_favorite_provider','get_favorite_providers','get_matching_status',
        'sync_vehicle_reminders','admin_growth_analytics'
    ];
    if (!in_array($action,$actions,true)) return;

    if ($action==='get_growth_config') sendResponse(200,growthConfig());

    if ($action==='request_phone_verification') {
        if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        try { sendResponse(200,growthRequestPhoneVerification($pdo,$_POST['phone'] ?? '',$_SERVER['REMOTE_ADDR'] ?? '')); }
        catch (DomainException|InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
        catch (Throwable $e) { sendResponse(503,['status'=>'error','message'=>$e->getMessage()]); }
    }

    if ($action==='verify_phone_code') {
        if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        try { sendResponse(200,growthVerifyPhoneCode($pdo,$_POST['phone'] ?? '',$_POST['code'] ?? '')); }
        catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
    }

    if ($action==='get_smart_price') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        sendResponse(200,growthSmartPrice($_GET['service_type'] ?? 'mechanic',$_GET['distance_km'] ?? 0));
    }

    if ($action==='get_reward_catalog') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        ensureGrowthSchema($pdo); ensureReferralSchema($pdo);
        $userId=(int)($_GET['user_id'] ?? 0);
        $stmt=$pdo->prepare('SELECT user_type,reward_points FROM users WHERE id=?'); $stmt->execute([$userId]);
        $user=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$user) sendResponse(404,['status'=>'error','message'=>'Hesap bulunamadı.']);
        $catalog=array_values(array_filter(growthRewardCatalog(),fn($r)=>in_array($user['user_type'],$r['roles'],true)));
        sendResponse(200,['status'=>'success','reward_points'=>(int)$user['reward_points'],'catalog'=>$catalog]);
    }

    if ($action==='redeem_reward_points') {
        if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        try { sendResponse(200,growthRedeemReward($pdo,(int)($_POST['user_id'] ?? 0),trim($_POST['reward_id'] ?? ''))); }
        catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
    }

    if ($action==='toggle_favorite_provider') {
        if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        try { sendResponse(200,growthToggleFavorite($pdo,(int)($_POST['customer_id'] ?? 0),(int)($_POST['provider_id'] ?? 0))); }
        catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
    }

    if ($action==='get_favorite_providers') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        sendResponse(200,growthFavoriteProviders($pdo,(int)($_GET['user_id'] ?? 0)));
    }

    if ($action==='get_matching_status') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        $meta=growthMatchingMeta($pdo,(int)($_GET['job_id'] ?? 0));
        if (!$meta) sendResponse(404,['status'=>'error','message'=>'Talep bulunamadı.']);
        sendResponse(200,['status'=>'success','matching'=>$meta]);
    }

    if ($action==='sync_vehicle_reminders') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        sendResponse(200,growthSyncVehicleReminders($pdo,(int)($_GET['user_id'] ?? 0)));
    }

    if ($action==='admin_growth_analytics') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
        sendResponse(200,growthAdminAnalytics($pdo));
    }
}
