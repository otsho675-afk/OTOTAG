<?php

function ensureGrowthSchema($pdo) {
    apiSchemaMigration($pdo,'growth_features_v4_no_phone_verification',function() use($pdo) {
        $jobColumns=$pdo->query("SHOW COLUMNS FROM jobs")->fetchAll(PDO::FETCH_COLUMN);
        if(!in_array('preferred_provider_id',$jobColumns,true)) {
            $pdo->exec("ALTER TABLE jobs ADD COLUMN preferred_provider_id INT NULL");
            $pdo->exec("CREATE INDEX idx_jobs_preferred_provider ON jobs(preferred_provider_id,status,created_at)");
        }

        $pdo->exec("CREATE TABLE IF NOT EXISTS favorite_providers(
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            customer_id INT NOT NULL,
            provider_id INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_favorite_provider(customer_id,provider_id),
            KEY idx_favorite_provider_customer(customer_id),
            KEY idx_favorite_provider_provider(provider_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

        $pdo->exec("CREATE TABLE IF NOT EXISTS reward_redemptions(
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            user_id INT NOT NULL,
            reward_code VARCHAR(40) NOT NULL,
            points_spent INT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            KEY idx_reward_redemptions_user(user_id,created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    });
}

function growthRewardCatalog($userType) {
    $items=[
        ['code'=>'premium_7d','title'=>'7 Gün Premium','points'=>100,'days'=>7,'kind'=>'premium','roles'=>['customer']],
        ['code'=>'premium_30d','title'=>'30 Gün Premium','points'=>250,'days'=>30,'kind'=>'premium','roles'=>['customer']],
        ['code'=>'obd_30d','title'=>'30 Gün OBD','points'=>300,'days'=>30,'kind'=>'obd','roles'=>['customer','provider','rentacar']],
        ['code'=>'business_30d','title'=>'30 Gün İşletme Üyeliği','points'=>500,'days'=>30,'kind'=>'business','roles'=>['provider','rentacar']],
    ];
    return array_values(array_filter($items,fn($x)=>in_array($userType,$x['roles'],true)));
}

function growthRedeemReward($pdo,$userId,$rewardCode) {
    ensureGrowthSchema($pdo);
    ensureBusinessSubscriptionSchema($pdo);
    ensureReferralSchema($pdo);

    $pdo->beginTransaction();
    try {
        $stmt=$pdo->prepare('SELECT id,user_type,reward_points,premium_end_date,obd_subscription_end_date,subscription_end_date FROM users WHERE id=? FOR UPDATE');
        $stmt->execute([$userId]);
        $user=$stmt->fetch(PDO::FETCH_ASSOC);
        if(!$user) throw new InvalidArgumentException('Hesap bulunamadı.');
        $catalog=growthRewardCatalog($user['user_type']);
        $item=null;
        foreach($catalog as $candidate) if($candidate['code']===$rewardCode) {$item=$candidate;break;}
        if(!$item) throw new InvalidArgumentException('Bu ödül hesabınız için kullanılamıyor.');
        if((int)$user['reward_points']<(int)$item['points']) throw new InvalidArgumentException('Yeterli OTO TAG Puanınız yok.');

        $column=$item['kind']==='premium' ? 'premium_end_date' : ($item['kind']==='obd' ? 'obd_subscription_end_date':'subscription_end_date');
        $current=$user[$column] ?? null;
        $base=($current && strtotime($current)>time()) ? new DateTime($current) : new DateTime();
        $base->modify('+'.(int)$item['days'].' days');
        $newDate=$base->format('Y-m-d H:i:s');

        $sql="UPDATE users SET reward_points=reward_points-?, `$column`=?";
        if($item['kind']==='premium') $sql.=", is_premium=1";
        $sql.=" WHERE id=?";
        $pdo->prepare($sql)->execute([(int)$item['points'],$newDate,$userId]);
        $pdo->prepare('INSERT INTO reward_redemptions(user_id,reward_code,points_spent) VALUES (?,?,?)')
            ->execute([$userId,$rewardCode,(int)$item['points']]);
        $pdo->commit();
        return ['status'=>'success','message'=>$item['title'].' hesabınıza tanımlandı.','reward_code'=>$rewardCode,'new_end_date'=>$newDate];
    } catch(Throwable $e) {
        if($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
}

function growthPriceQuote($service,$distanceKm,$hour=null) {
    $distance=max(0,min(100,(float)$distanceKm));
    $hour=$hour===null ? (int)date('G') : max(0,min(23,(int)$hour));
    $rules=[
        'mechanic'=>['base'=>700,'km'=>45,'spread'=>0.16],
        'tow'=>['base'=>950,'km'=>70,'spread'=>0.18],
        'tire'=>['base'=>450,'km'=>35,'spread'=>0.15],
        'wash'=>['base'=>280,'km'=>15,'spread'=>0.12],
    ];
    $rule=$rules[$service] ?? $rules['mechanic'];
    $night=($hour>=22 || $hour<7) ? 1.18 : 1.0;
    $mid=(int)(round((($rule['base']+$distance*$rule['km'])*$night)/10)*10);
    $low=(int)(floor(($mid*(1-$rule['spread']))/10)*10);
    $high=(int)(ceil(($mid*(1+$rule['spread']))/10)*10);
    $eta=max(6,min(90,(int)ceil(($distance/28)*60)+5));
    return [
        'service_type'=>$service,
        'distance_km'=>round($distance,1),
        'suggested_price'=>$mid,
        'estimate_low'=>$low,
        'estimate_high'=>$high,
        'estimated_eta_min'=>$eta,
        'night_multiplier'=>$night
    ];
}

function growthProviderVerification($row) {
    $active=($row['status'] ?? '')==='active' && empty($row['is_suspended']);
    $type=$row['user_type'] ?? 'provider';
    if($type==='rentacar') {
        $docs=!empty($row['tax_plate']) || !empty($row['map_link']);
    } else {
        $docs=!empty($row['tax_plate']) || !empty($row['driver_license']) || !empty($row['tow_plate']);
    }
    return $active && $docs;
}

function growthFavoriteList($pdo,$customerId) {
    ensureGrowthSchema($pdo);
    $stmt=$pdo->prepare("SELECT u.id,u.name,u.service_category,u.rating,u.reviews_count,u.city,u.status,u.is_suspended,
        u.tax_plate,u.driver_license,u.tow_plate,u.user_type
        FROM favorite_providers f JOIN users u ON u.id=f.provider_id
        WHERE f.customer_id=? ORDER BY f.id DESC");
    $stmt->execute([$customerId]);
    $rows=$stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach($rows as &$row) {
        $row['verified']=growthProviderVerification($row);
        unset($row['tax_plate'],$row['driver_license'],$row['tow_plate'],$row['status'],$row['is_suspended']);
    }
    return $rows;
}

function growthToggleFavorite($pdo,$customerId,$providerId) {
    ensureGrowthSchema($pdo);
    if($customerId===$providerId) throw new InvalidArgumentException('Kendi hesabınızı favoriye ekleyemezsiniz.');
    $stmt=$pdo->prepare("SELECT id FROM users WHERE id=? AND user_type='provider' AND status='active'");
    $stmt->execute([$providerId]);
    if(!$stmt->fetchColumn()) throw new InvalidArgumentException('Usta bulunamadı.');
    $stmt=$pdo->prepare('SELECT id FROM favorite_providers WHERE customer_id=? AND provider_id=?');
    $stmt->execute([$customerId,$providerId]);
    $existing=$stmt->fetchColumn();
    if($existing) {
        $pdo->prepare('DELETE FROM favorite_providers WHERE id=?')->execute([$existing]);
        return false;
    }
    $pdo->prepare('INSERT INTO favorite_providers(customer_id,provider_id) VALUES (?,?)')->execute([$customerId,$providerId]);
    return true;
}

// One row per verified account and server calendar day. No location, device ID or
// message content is stored; counters start accumulating after deployment.
function ensureEngagementSchema($pdo) {
    apiSchemaMigration($pdo,'engagement_daily_v1',function() use($pdo) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS engagement_daily (
            user_id INT NOT NULL,
            user_type VARCHAR(20) NOT NULL,
            active_date DATE NOT NULL,
            PRIMARY KEY(user_id,active_date),
            KEY idx_engagement_date_role(active_date,user_type,user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    });
}

function growthRecordDailyActive($pdo,$actor) {
    if (!in_array($actor['user_type'] ?? '', ['customer','provider','rentacar'],true)
        || (int)($actor['user_id'] ?? 0)<=0) {
        throw new InvalidArgumentException('Geçersiz hesap.');
    }
    ensureEngagementSchema($pdo);
    $stmt=$pdo->prepare("INSERT INTO engagement_daily(user_id,user_type,active_date)
        VALUES (?,?,CURRENT_DATE())
        ON DUPLICATE KEY UPDATE user_type=VALUES(user_type)");
    $stmt->execute([(int)$actor['user_id'],(string)$actor['user_type']]);
}

function growthActiveUsage($pdo) {
    ensureEngagementSchema($pdo);
    $stmt=$pdo->query("SELECT user_type,
        COUNT(DISTINCT CASE WHEN active_date=CURRENT_DATE() THEN user_id END) AS daily,
        COUNT(DISTINCT CASE WHEN active_date>=DATE_SUB(CURRENT_DATE(),INTERVAL 6 DAY) THEN user_id END) AS weekly,
        COUNT(DISTINCT user_id) AS monthly
        FROM engagement_daily
        WHERE active_date BETWEEN DATE_SUB(CURRENT_DATE(),INTERVAL 29 DAY) AND CURRENT_DATE()
        GROUP BY user_type");
    $counts=['customer'=>['daily'=>0,'weekly'=>0,'monthly'=>0],
             'provider'=>['daily'=>0,'weekly'=>0,'monthly'=>0],
             'rentacar'=>['daily'=>0,'weekly'=>0,'monthly'=>0]];
    foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $role=(string)$row['user_type'];
        if (!array_key_exists($role,$counts)) continue;
        foreach (['daily','weekly','monthly'] as $window) $counts[$role][$window]=(int)$row[$window];
    }
    return $counts;
}

function growthAnalytics($pdo) {
    ensureGrowthSchema($pdo);
    ensureReferralSchema($pdo);
    $activeUsage=growthActiveUsage($pdo);
    $todayUsers=(int)$pdo->query("SELECT COUNT(*) FROM users WHERE created_at>=CURDATE()")->fetchColumn();
    $todayJobs=(int)$pdo->query("SELECT COUNT(*) FROM jobs WHERE created_at>=CURDATE()")->fetchColumn();
    $completed30=(int)$pdo->query("SELECT COUNT(*) FROM jobs WHERE status='completed' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)")->fetchColumn();
    $cancelled30=(int)$pdo->query("SELECT COUNT(*) FROM jobs WHERE status='cancelled' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)")->fetchColumn();
    $openJobs=(int)$pdo->query("SELECT COUNT(*) FROM jobs WHERE status='searching'")->fetchColumn();
    $activeProviders=(int)$pdo->query("SELECT COUNT(*) FROM users WHERE user_type='provider' AND status='active' AND COALESCE(is_suspended,0)=0")->fetchColumn();
    $newProviders=(int)$pdo->query("SELECT COUNT(*) FROM users WHERE user_type='provider' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)")->fetchColumn();
    // Engagement proxies based on real job activity; these are NOT login retention cohorts.
    $requestingCustomers30=(int)$pdo->query("SELECT COUNT(DISTINCT customer_id) FROM jobs WHERE created_at>=DATE_SUB(NOW(), INTERVAL 30 DAY)")->fetchColumn();
    $repeatCustomers90=(int)$pdo->query("SELECT COUNT(*) FROM (SELECT customer_id FROM jobs WHERE created_at>=DATE_SUB(NOW(), INTERVAL 90 DAY) GROUP BY customer_id HAVING COUNT(*)>=2) AS repeat_customers")->fetchColumn();
    $workingProviders30=(int)$pdo->query("SELECT COUNT(DISTINCT provider_id) FROM jobs WHERE provider_id IS NOT NULL AND status IN ('matched','accepted','approved','in_progress','customer_paid','completed') AND created_at>=DATE_SUB(NOW(), INTERVAL 30 DAY)")->fetchColumn();
    $referrals=(int)$pdo->query("SELECT COUNT(*) FROM referral_rewards")->fetchColumn();
    $rewarded=(int)$pdo->query("SELECT COUNT(*) FROM referral_rewards WHERE status='rewarded'")->fetchColumn();
    $city=$pdo->query("SELECT city,COUNT(*) total FROM users WHERE city IS NOT NULL AND city<>'' GROUP BY city ORDER BY total DESC LIMIT 12")->fetchAll(PDO::FETCH_ASSOC);
    $daily=$pdo->query("SELECT DATE(created_at) day,COUNT(*) total FROM users WHERE created_at>=DATE_SUB(CURDATE(),INTERVAL 13 DAY) GROUP BY DATE(created_at) ORDER BY day")->fetchAll(PDO::FETCH_ASSOC);
    return [
        'today_users'=>$todayUsers,
        'active_usage'=>$activeUsage,
        'today_jobs'=>$todayJobs,
        'open_jobs'=>$openJobs,
        'active_providers'=>$activeProviders,
        'new_providers_30d'=>$newProviders,
        'requesting_customers_30d'=>$requestingCustomers30,
        'repeat_customers_90d'=>$repeatCustomers90,
        'working_providers_30d'=>$workingProviders30,
        'completed_30d'=>$completed30,
        'cancelled_30d'=>$cancelled30,
        'completion_rate'=>($completed30+$cancelled30)>0 ? round($completed30*100/($completed30+$cancelled30),1) : 0,
        'referral_total'=>$referrals,
        'referral_rewarded'=>$rewarded,
        'referral_conversion'=>$referrals>0 ? round($rewarded*100/$referrals,1) : 0,
        'top_cities'=>$city,
        'daily_registrations'=>$daily,
    ];
}
