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

// Compare money as cents, never as a float or a formatted string.
function serviceOfferIsCurrent($bid, $input) {
    try {
        if (!array_key_exists('amount', $input) ||
            rentalMoneyCents((string)$input['amount']) !== rentalMoneyCents((string)$bid['amount'])) return false;
    } catch (InvalidArgumentException $e) { return false; }
    return !isset($input['offer_version']) ||
        (filter_var($input['offer_version'], FILTER_VALIDATE_INT) !== false &&
         (int)$input['offer_version'] === (int)$bid['negotiation_count']);
}


function serviceEligibleRealProviders($pdo,$job,$limit=1) {
    if (!$job || ($job['status'] ?? '')!=='searching' || ($job['service_type'] ?? '')==='rentacar') return [];
    $city=trim((string)($job['city'] ?? ''));
    $service=trim((string)($job['service_type'] ?? ''));
    if ($city==='' || $service==='') return [];
    $stmt=$pdo->prepare("SELECT * FROM users
        WHERE user_type='provider' AND status='active' AND COALESCE(is_suspended,0)=0
        AND service_category=? AND LOWER(TRIM(city))=LOWER(TRIM(?))
        AND lat IS NOT NULL AND lng IS NOT NULL AND NOT (lat=0 AND lng=0)
        ORDER BY id ASC LIMIT 100");
    $stmt->execute([$service,$city]);
    $radius=min(50,max(1,(float)($job['search_radius'] ?? 50)));
    $eligible=[];
    while ($provider=$stmt->fetch(PDO::FETCH_ASSOC)) {
        if (!businessSubscriptionStatus($provider)['can_work']) continue;
        try {
            if (serviceDistanceKm($provider['lat'],$provider['lng'],$job['latitude'],$job['longitude'])>$radius) continue;
        } catch (Throwable $e) { continue; }
        $eligible[]=$provider;
        if (count($eligible)>=$limit) break;
    }
    return $eligible;
}

function serviceSimulationFallback($pdo,$job) {
    if (!$job || ($job['status'] ?? '')!=='searching' || ($job['service_type'] ?? '')==='rentacar') return null;
    if (serviceEligibleRealProviders($pdo,$job,1)) return null;

    try {
        $lat=serviceCoordinate($job['latitude'] ?? null);
        $lng=serviceCoordinate($job['longitude'] ?? null,false);
    } catch (Throwable $e) { return null; }

    $service=(string)($job['service_type'] ?? 'mechanic');
    $pricing=[
        'mechanic'=>['base'=>700,'km'=>55],
        'tow'=>['base'=>950,'km'=>75],
        'tire'=>['base'=>450,'km'=>40],
        'wash'=>['base'=>280,'km'=>22],
    ];
    $rule=$pricing[$service] ?? $pricing['mechanic'];
    $jobId=(int)($job['id'] ?? 0);
    $radius=min(8.0,max(2.0,(float)($job['search_radius'] ?? 8)));
    $cos=max(0.2,cos(deg2rad($lat)));
    $points=[];

    for ($i=1;$i<=3;$i++) {
        $seed=(int)sprintf('%u',crc32($jobId.'|'.$service.'|'.($job['city'] ?? '').'|'.$i));
        $distance=min($radius,1.2+(($seed % 58)/10));
        $angle=deg2rad(($seed >> 5) % 360);
        $pointLat=$lat+((cos($angle)*$distance)/111.0);
        $pointLng=$lng+((sin($angle)*$distance)/(111.0*$cos));

        $priceJitter=((($seed >> 9)%17)-8)/100;
        $suggested=(int)(round((($rule['base']+($distance*$rule['km']))*(1+$priceJitter))/10)*10);
        $low=(int)(floor(($suggested*0.90)/10)*10);
        $high=(int)(ceil(($suggested*1.10)/10)*10);

        $trafficJitter=(($seed >> 13)%5);
        $eta=(int)ceil(($distance/25.0)*60)+4+$trafficJitter;
        $eta=max(6,min(35,$eta));

        $points[]=[
            'id'=>'est-'.$jobId.'-'.$i,
            'label'=>'Yakındaki seçenek '.$i,
            'latitude'=>round($pointLat,6),
            'longitude'=>round($pointLng,6),
            'distance_km'=>round($distance,1),
            'estimated_time'=>$eta,
            'suggested_price'=>$suggested,
            'estimate_low'=>$low,
            'estimate_high'=>$high,
            'estimated'=>true,
        ];
    }

    usort($points,function($a,$b){ return $a['distance_km'] <=> $b['distance_km']; });

    return [
        'active'=>true,
        'mode'=>'estimated_fallback',
        'service_type'=>$service,
        'city'=>(string)($job['city'] ?? ''),
        'real_provider_available'=>false,
        'points'=>$points,
    ];
}

function serviceAcceptOffer($pdo, $actor, $input) {
    $jobId=(int)($input['job_id'] ?? 0); $bidId=(int)($input['bid_id'] ?? 0);
    $providerId=(int)($input['provider_id'] ?? 0);
    if ($jobId<=0 || $bidId<=0 || $providerId<=0) throw new DomainException('Geçerli bir teklif seçin.');
    try {
        $pdo->beginTransaction();
        $stmt=$pdo->prepare('SELECT * FROM jobs WHERE id=? FOR UPDATE'); $stmt->execute([$jobId]); $job=$stmt->fetch(PDO::FETCH_ASSOC);
        $stmt=$pdo->prepare('SELECT * FROM users WHERE id=? FOR UPDATE'); $stmt->execute([$providerId]); $provider=$stmt->fetch(PDO::FETCH_ASSOC);
        $stmt=$pdo->prepare('SELECT * FROM bids WHERE id=? AND job_id=? AND provider_id=? FOR UPDATE');
        $stmt->execute([$bidId,$jobId,$providerId]); $bid=$stmt->fetch(PDO::FETCH_ASSOC);
        $role=$actor['user_type'] ?? '';
        if (!$job || !$bid || !in_array($role,['customer','provider'],true) ||
            (int)$actor['user_id'] !== (int)($role==='customer' ? $job['customer_id'] : $providerId)) {
            throw new DomainException('Bu teklif üzerinde işlem yapamazsınız.');
        }
        if (!serviceOfferIsCurrent($bid,$input) || $bid['last_bidder']===$role) {
            throw new DomainException('Teklif değişti. Güncel tutarı inceleyip yeniden onaylayın.');
        }
        // A lost HTTP response can safely be retried without matching twice.
        if ($bid['status']==='accepted' && (int)$job['provider_id']===$providerId &&
            in_array($job['status'],['matched','accepted','approved','in_progress','customer_paid','completed'],true)) {
            $pdo->commit(); return ['job'=>$job,'bid'=>$bid,'repeated'=>true];
        }
        if ($job['status']!=='searching' || !in_array($bid['status'],['pending','negotiating'],true)) {
            throw new DomainException('Bu talep eşleşmiş veya kapanmış. Güncel durumu kontrol edin.');
        }
        serviceCandidate($pdo,$provider,$job);
        $code=!empty($job['match_code']) ? $job['match_code'] : random_int(1000,9999);
        $pdo->prepare("UPDATE jobs SET provider_id=?,agreed_price=?,status='matched',match_code=? WHERE id=?")
            ->execute([$providerId,$bid['amount'],$code,$jobId]);
        $pdo->prepare("UPDATE bids SET status=CASE WHEN id=? THEN 'accepted' ELSE 'rejected' END WHERE job_id=?")
            ->execute([$bidId,$jobId]);
        $pdo->commit();
        // Close other offers after releasing job/provider locks to avoid an
        // inverted lock order when the same provider is selected concurrently.
        try {
            $pdo->prepare("UPDATE bids SET status='cancelled' WHERE provider_id=? AND job_id<>? AND status IN ('pending','negotiating')")
                ->execute([$providerId,$jobId]);
        } catch (Throwable $e) { error_log('Deferred competing offer cleanup failed.'); }
        return ['job'=>array_merge($job,['provider_id'=>$providerId,'agreed_price'=>$bid['amount'],'match_code'=>$code,'status'=>'matched']),
            'bid'=>$bid,'repeated'=>false];
    } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
}

function serviceRejectOffer($pdo, $bidId) {
    $lookup=$pdo->prepare('SELECT job_id FROM bids WHERE id=?'); $lookup->execute([$bidId]); $jobId=$lookup->fetchColumn();
    if (!$jobId) throw new DomainException('Teklif bulunamadı.');
    try {
        $pdo->beginTransaction();
        $stmt=$pdo->prepare('SELECT status FROM jobs WHERE id=? FOR UPDATE'); $stmt->execute([$jobId]); $status=$stmt->fetchColumn();
        $stmt=$pdo->prepare('SELECT * FROM bids WHERE id=? FOR UPDATE'); $stmt->execute([$bidId]); $bid=$stmt->fetch(PDO::FETCH_ASSOC);
        if ($status!=='searching' || !$bid || !in_array($bid['status'],['pending','negotiating','rejected'],true)) {
            throw new DomainException('Eşleşmiş veya kapanmış teklif reddedilemez.');
        }
        $pdo->prepare("UPDATE bids SET status='rejected' WHERE id=?")->execute([$bidId]);
        $pdo->commit();
        return $bid;
    } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
}

function serviceCancelJob($pdo, $jobId, $expectedStatus=null) {
    try {
        $pdo->beginTransaction();
        $stmt=$pdo->prepare('SELECT * FROM jobs WHERE id=? FOR UPDATE'); $stmt->execute([$jobId]); $job=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$job || $job['service_type']==='rentacar') throw new DomainException('İptal edilebilecek servis talebi bulunamadı.');
        if ($job['status']==='cancelled') { $pdo->commit(); return $job; }
        if (($expectedStatus!==null && $job['status']!==$expectedStatus) ||
            !in_array($job['status'],['searching','matched','accepted','approved','in_progress'],true)) {
            throw new DomainException('Talebin durumu değişti. Güncel durumu inceleyip tekrar deneyin.');
        }
        $pdo->prepare("UPDATE jobs SET status='cancelled' WHERE id=?")->execute([$jobId]);
        $pdo->prepare("UPDATE bids SET status='cancelled' WHERE job_id=? AND status IN ('pending','negotiating','accepted')")->execute([$jobId]);
        $pdo->commit(); return $job;
    } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
}
