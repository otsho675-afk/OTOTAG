<?php
require_once __DIR__.'/api_runtime.php';
function ensureServiceMatchingIndexes($pdo) {
    apiSchemaMigration($pdo,'service_matching_indexes_v1',function() use($pdo) {
        foreach (['jobs'=>['service_city_status'=>['city','service_type','status'], 'service_provider_status'=>['provider_id','status']],
            'users'=>['service_phone_role'=>['phone','user_type']]] as $table=>$indexes) {
            $existing=$pdo->query("SHOW INDEX FROM `$table`")->fetchAll(PDO::FETCH_ASSOC);
            $columns=[];
            foreach ($existing as $index) $columns[$index['Key_name']][(int)$index['Seq_in_index']]=$index['Column_name'];
            foreach ($indexes as $name=>$wanted) {
                $covered=false;
                foreach ($columns as $indexColumns) { ksort($indexColumns); if (array_slice(array_values($indexColumns),0,count($wanted))===$wanted) $covered=true; }
                if (!$covered) $pdo->exec("CREATE INDEX `$name` ON `$table` (`".implode('`,`',$wanted).'`)');
            }
        }
    });
}
function serviceCoordinate($value,$latitude=true) {
    if (!is_scalar($value) || !is_numeric($value)) throw new InvalidArgumentException('Geçersiz konum bilgisi.');
    $value=(float)$value; $limit=$latitude ? 90 : 180;
    if (!is_finite($value) || abs($value)>$limit) throw new InvalidArgumentException('Geçersiz konum bilgisi.');
    return $value;
}
function serviceCandidate($pdo,$provider,$job,$checkBusy=true) {
    if (!$provider || $provider['user_type']!=='provider' || $provider['status']!=='active' || !empty($provider['is_suspended'])) throw new DomainException('Usta hesabı bu işlem için aktif değil.');
    if (!businessSubscriptionStatus($provider)['can_work']) throw new DomainException('Teklif vermek için usta üyeliğinizi yenileyin.');
    if (!$job || !rentalSameCity($provider['city'],$job['city']) || ($provider['service_category'] ?? '')!==$job['service_type']) throw new DomainException('Şehir veya hizmet türü bu taleple eşleşmiyor.');
    $customer=$pdo->prepare("SELECT id FROM users WHERE id=? AND user_type='customer' AND status='active' AND COALESCE(is_suspended,0)=0");
    $customer->execute([$job['customer_id']]);
    if (!$customer->fetch()) throw new DomainException('Müşteri hesabı bu işlem için aktif değil.');
    if (($provider['lat'] ?? null)===null || ($provider['lng'] ?? null)===null || ($provider['lat']==0 && $provider['lng']==0)) throw new DomainException('Teklif için güncel konumunuz gereklidir.');
    $distance=serviceDistanceKm($provider['lat'],$provider['lng'],$job['latitude'],$job['longitude']);
    if ($distance>min(50,max(1,(float)($job['search_radius'] ?? 50)))) throw new DomainException('Talep hizmet alanınızın dışında.');
    if ($checkBusy) {
        $busy=$pdo->prepare("SELECT id FROM jobs WHERE provider_id=? AND id<>? AND status IN ('matched','accepted','approved','in_progress','customer_paid') LIMIT 1");
        $busy->execute([$provider['id'],$job['id']]);
        if ($busy->fetch()) throw new DomainException('Devam eden işinizi tamamlamadan başka bir işle eşleşemezsiniz.');
    }
}
function serviceDistanceKm($aLat,$aLng,$bLat,$bLng) {
    $aLat=deg2rad(serviceCoordinate($aLat)); $bLat=deg2rad(serviceCoordinate($bLat));
    $deltaLat=$bLat-$aLat; $deltaLng=deg2rad(serviceCoordinate($bLng,false)-serviceCoordinate($aLng,false));
    $value=sin($deltaLat/2)**2+cos($aLat)*cos($bLat)*sin($deltaLng/2)**2;
    return 6371*2*atan2(sqrt(max(0,min(1,$value))),sqrt(max(0,1-$value)));
}
