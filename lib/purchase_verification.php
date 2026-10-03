<?php
// A business entitlement is derived only from account creation and a verified store expiry.
function businessSubscriptionStatus($user,$now=null) {
    $now=$now ?? time();
    $created=strtotime($user['created_at'] ?? '') ?: 0;
    $trial=$created>0 ? strtotime('+30 days',$created) : 0;
    $paid=strtotime($user['subscription_end_date'] ?? '') ?: 0;
    $isTrial=$trial>$now && $paid<=$now;
    $end=max($trial,$paid);
    return ['can_work'=>$end>$now,'is_trial'=>$isTrial,
        'subscription_end'=>$paid ? date('Y-m-d H:i:s',$paid):null,
        'trial_end'=>$trial ? date('Y-m-d H:i:s',$trial):null,
        'access_end'=>$end ? date('Y-m-d H:i:s',$end):null,
        'message'=>$end>$now ? ($isTrial?'30 günlük ücretsiz deneme aktif.':'Mağazada doğrulanan abonelik aktif.'):'Abonelik süresi doldu. Yeni işlemler için aylık aboneliğinizi yenileyin.'];
}
function ensureBusinessSubscriptionSchema($pdo) {
    $lock=$pdo->query("SELECT GET_LOCK('ototag_business_subscription_schema',10)")->fetchColumn();
    if ((int)$lock!==1) throw new RuntimeException('Abonelik şema kilidi alınamadı.');
    try {
        $columns=$pdo->query('SHOW COLUMNS FROM users')->fetchAll(PDO::FETCH_COLUMN);
        foreach (['created_at'=>'DATETIME NULL','subscription_end_date'=>'DATETIME NULL','obd_subscription_end_date'=>'DATETIME NULL'] as $column=>$definition) {
            if (!in_array($column,$columns,true)) $pdo->exec("ALTER TABLE users ADD `$column` $definition");
        }
        $type=$pdo->query("SHOW COLUMNS FROM in_app_purchases LIKE 'user_type'")->fetch(PDO::FETCH_ASSOC);
        if ($type && strpos($type['Type'],'rentacar')===false && strpos($type['Type'],'enum(')===0) {
            $pdo->exec("ALTER TABLE in_app_purchases MODIFY user_type ENUM('customer','provider','rentacar') DEFAULT 'customer'");
        }
    } finally { $pdo->query("SELECT RELEASE_LOCK('ototag_business_subscription_schema')"); }
}
class PurchaseOwnershipException extends RuntimeException {}
function applyVerifiedBusinessPurchase($pdo,$userId,$platform,$productId,$receipt,$verification) {
    if (purchaseExpectedProduct('renew_provider_subscription',$platform)!==$productId
        || empty($verification['verified_transaction_id']) || (strtotime($verification['verified_expiry'] ?? '') ?: 0)<=time()) {
        throw new InvalidArgumentException('Geçerli ve aktif mağaza makbuzu gereklidir.');
    }
    $order=(string)$verification['verified_transaction_id'];
    $hash=hash('sha256',$platform.'|'.$productId.'|'.$order);
    // Google tokens remain stable across renewal order IDs: ownership and locking follow the token.
    $lock='purchase_'.substr(hash('sha256',$platform.'|'.$productId.'|'.($platform==='google'?$receipt:$order)),0,55);
    $stmt=$pdo->prepare('SELECT GET_LOCK(?,10)'); $stmt->execute([$lock]);
    if ((int)$stmt->fetchColumn()!==1) throw new RuntimeException('Satın alma doğrulanıyor. Tekrar deneyin.');
    try {
        $pdo->beginTransaction();
        $stmt=$pdo->prepare("SELECT user_type FROM users WHERE id=? AND user_type IN ('provider','rentacar') AND status='active' AND COALESCE(is_suspended,0)=0 FOR UPDATE");
        $stmt->execute([$userId]); $role=$stmt->fetchColumn();
        if (!$role) throw new InvalidArgumentException('Aktif firma veya usta hesabı gereklidir.');
        $stmt=$pdo->prepare("SELECT id,user_id,token_hash FROM in_app_purchases WHERE token_hash=? OR (platform=? AND order_id=?) OR (platform='google' AND ?='google' AND product_id=? AND purchase_token=?)");
        $stmt->execute([$hash,$platform,$order,$platform,$productId,$receipt]); $exists=false;
        foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $purchase) {
            if ((int)$purchase['user_id']!==(int)$userId) throw new PurchaseOwnershipException('Bu mağaza aboneliği başka bir hesaba ait.');
            if ($purchase['token_hash']===$hash) $exists=true;
        }
        $expiry=$verification['verified_expiry'];
        $pdo->prepare('UPDATE users SET subscription_end_date=GREATEST(COALESCE(subscription_end_date,?),?) WHERE id=?')->execute([$expiry,$expiry,$userId]);
        if (!$exists) $pdo->prepare("INSERT INTO in_app_purchases (user_id,user_type,platform,product_id,order_id,purchase_token,token_hash,purchase_type,status) VALUES (?,?,?,?,?,?,?,'subscription','completed')")
            ->execute([$userId,$role,$platform,$productId,$order,$receipt,$hash]);
        $stmt=$pdo->prepare('SELECT subscription_end_date FROM users WHERE id=?'); $stmt->execute([$userId]); $end=$stmt->fetchColumn();
        $pdo->commit(); return ['status'=>'success','message'=>$exists?'Aboneliğiniz geri yüklendi.':'Aboneliğiniz mağazada doğrulandı.','subscription_end_date'=>$end,'platform'=>$platform];
    } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
    finally { $stmt=$pdo->prepare('SELECT RELEASE_LOCK(?)'); $stmt->execute([$lock]); }
}
function normalizeGoogleSubscription($data,$nowMillis=null) {
    $nowMillis=$nowMillis ?? time()*1000;
    if (!is_array($data) || !is_numeric($data['expiryTimeMillis'] ?? null) || (float)$data['expiryTimeMillis']<=$nowMillis
        || empty($data['orderId']) || (isset($data['paymentState']) && !in_array((int)$data['paymentState'],[1,2],true))
        || (isset($data['cancelReason']) && in_array((int)$data['cancelReason'],[1,2,3],true))) return false;
    $data['verified_expiry']=date('Y-m-d H:i:s',intdiv((int)$data['expiryTimeMillis'],1000));
    $data['verified_transaction_id']=(string)$data['orderId'];
    return $data;
}
function normalizeAppleSubscription($data,$productId,$bundleId,$nowMillis=null) {
    $nowMillis=$nowMillis ?? time()*1000;
    if (!is_array($data) || ($data['status'] ?? -1)!==0 || ($data['receipt']['bundle_id'] ?? '')!==$bundleId) return false;
    $transactions=array_merge($data['latest_receipt_info'] ?? [],$data['receipt']['in_app'] ?? []);
    $transactions=array_values(array_filter($transactions,function($item) use($productId) { return ($item['product_id'] ?? '')===$productId; }));
    usort($transactions,function($a,$b) { return (int)($b['expires_date_ms'] ?? 0)<=>(int)($a['expires_date_ms'] ?? 0); });
    $latest=$transactions[0] ?? null;
    if (!$latest || !is_numeric($latest['expires_date_ms'] ?? null) || (float)$latest['expires_date_ms']<=$nowMillis
        || !empty($latest['cancellation_date_ms']) || !empty($latest['cancellation_date']) || empty($latest['transaction_id'])) return false;
    $data['verified_expiry']=date('Y-m-d H:i:s',intdiv((int)$latest['expires_date_ms'],1000));
    $data['verified_transaction_id']=(string)$latest['transaction_id'];
    return $data;
}
function purchaseExpectedProduct($action,$platform) {
    $products=[
        'activate_premium'=>['google'=>'customer_premium_monthly','apple'=>'ototag_premium_monthly'],
        'renew_provider_subscription'=>['google'=>'provider_monthly_subscription','apple'=>'ototag_provider_monthly'],
        'activate_obd_subscription'=>['google'=>'diagnostic_monthly_100tl','apple'=>'diagnostic_monthly_100tl'],
    ];
    return $products[$action][$platform] ?? null;
}
function expirePremiumEntitlement($pdo,$id) {
    $column=$pdo->query("SHOW COLUMNS FROM users LIKE 'premium_end_date'")->fetch();
    if (!$column) return;
    $pdo->prepare('UPDATE users SET is_premium=0 WHERE id=? AND premium_end_date IS NOT NULL AND premium_end_date<=NOW() AND is_premium=1')->execute([$id]);
}
