<?php
// Release management is separate from generic notifications. The saved release
// is the source of truth even when a phone has denied push permission.
function appUpdateEnsureSchema($pdo) {
    apiSchemaMigration($pdo, 'app_updates_v1', function () use ($pdo) {
        $pdo->exec('CREATE TABLE IF NOT EXISTS app_settings (setting_key VARCHAR(50) PRIMARY KEY,setting_value TEXT) ENGINE=InnoDB');
        $pdo->exec("CREATE TABLE IF NOT EXISTS app_update_releases (
            id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
            request_key CHAR(36) NOT NULL, request_hash CHAR(64) NOT NULL,
            platform VARCHAR(10) NOT NULL, version VARCHAR(30) NOT NULL,
            build_number INT UNSIGNED NOT NULL DEFAULT 0,
            title VARCHAR(100) NOT NULL, message TEXT NOT NULL,
            store_url VARCHAR(500) NOT NULL, required_update TINYINT NOT NULL DEFAULT 0,
            active TINYINT NOT NULL DEFAULT 1, created_by INT NOT NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            withdrawn_at TIMESTAMP NULL, withdrawn_by INT NULL,
            push_key CHAR(36) NOT NULL, push_status VARCHAR(20) NOT NULL DEFAULT 'pending',
            push_detail VARCHAR(255) NOT NULL DEFAULT '', push_id VARCHAR(100) NULL,
            push_attempts INT NOT NULL DEFAULT 0, push_next_attempt BIGINT NOT NULL DEFAULT 0,
            push_locked_at BIGINT NOT NULL DEFAULT 0,
            UNIQUE KEY unique_update_request (request_key,platform),
            INDEX active_update (platform,active,id), INDEX pending_update_push (push_status,push_next_attempt)
        ) ENGINE=InnoDB");
    });
}

function appUpdateUuid() {
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 15) | 64);
    $bytes[8] = chr((ord($bytes[8]) & 63) | 128);
    $hex = bin2hex($bytes);
    return substr($hex,0,8).'-'.substr($hex,8,4).'-'.substr($hex,12,4).'-'.substr($hex,16,4).'-'.substr($hex,20);
}

function appUpdateStoreUrl($platform, $raw) {
    $url = trim((string)$raw);
    $parts = parse_url($url);
    if (strlen($url)>500 || !$parts || ($parts['scheme'] ?? '')!=='https' || isset($parts['user']) || isset($parts['pass']) || isset($parts['port']) || isset($parts['fragment'])) {
        throw new InvalidArgumentException('Geçerli bir HTTPS mağaza bağlantısı girin.');
    }
    if ($platform==='android') {
        parse_str($parts['query'] ?? '', $query);
        if (($parts['host'] ?? '')!=='play.google.com' || ($parts['path'] ?? '')!=='/store/apps/details' || ($query['id'] ?? '')!==serverConfig('ANDROID_PACKAGE_NAME','com.oto.tag')) {
            throw new InvalidArgumentException('Android için Ototag Google Play bağlantısını girin.');
        }
    } elseif ($platform==='ios') {
        if (($parts['host'] ?? '')!=='apps.apple.com' || !preg_match('#/id[0-9]+/?$#D',$parts['path'] ?? '')) {
            throw new InvalidArgumentException('iPhone için uygulamanın App Store bağlantısını girin.');
        }
    } else throw new InvalidArgumentException('Geçersiz platform.');
    return $url;
}

function appUpdateValidate($input) {
    $target = $input['target'] ?? 'all';
    if (!in_array($target,['all','android','ios'],true)) throw new InvalidArgumentException('Platform seçimi geçersiz.');
    $key = $input['request_key'] ?? '';
    if (!preg_match('/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/D',$key)) throw new InvalidArgumentException('İstek kimliği geçersiz.');
    $title = trim($input['title'] ?? '');
    $message = trim($input['message'] ?? '');
    if ($title==='' || strlen($title)>100 || $message==='' || strlen($message)>4000) throw new InvalidArgumentException('Başlık ve duyuru metni girin; metin çok uzun olmamalı.');
    $required = (string)($input['required_update'] ?? '0');
    if (!in_array($required,['0','1'],true)) throw new InvalidArgumentException('Güncelleme türü geçersiz.');
    $releases = [];
    foreach ($target==='all' ? ['android','ios'] : [$target] as $platform) {
        $version = trim($input[$platform.'_version'] ?? '');
        if (!preg_match('/^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$/D',$version)) throw new InvalidArgumentException('Sürümü 1.0.1 biçiminde girin.');
        $build = (string)($input[$platform.'_build'] ?? '0');
        if (!preg_match('/^(0|[1-9][0-9]{0,9})$/D',$build) || (float)$build>2147483647) throw new InvalidArgumentException('Derleme numarası geçersiz.');
        $releases[] = ['platform'=>$platform,'version'=>$version,'build_number'=>(int)$build,
            'title'=>$title,'message'=>$message,'store_url'=>appUpdateStoreUrl($platform,$input[$platform.'_store_url'] ?? ''),'required_update'=>$required==='1'];
    }
    return ['request_key'=>$key,'releases'=>$releases,'hash'=>hash('sha256',json_encode($releases,JSON_UNESCAPED_UNICODE))];
}

function appUpdateNewer($next, $previous) {
    $comparison = version_compare($next['version'],$previous['version']);
    return $comparison>0 || ($comparison===0 && $next['build_number']>(int)$previous['build_number']);
}

function appUpdateVersionCode($version) {
    if (!preg_match('/^([0-9]+)\.([0-9]+)\.([0-9]+)$/D',(string)$version,$m)) return null;
    return ((int)$m[1])*100000000 + ((int)$m[2])*10000 + (int)$m[3];
}

function appUpdatePublicRelease($row, $admin=false) {
    $result = ['id'=>(int)$row['id'],'platform'=>$row['platform'],'version'=>$row['version'],
        'build_number'=>(int)$row['build_number'],'title'=>$row['title'],'message'=>$row['message'],
        'store_url'=>$row['store_url'],'required_update'=>(bool)$row['required_update'],'active'=>(bool)$row['active'],'created_at'=>$row['created_at']];
    if ($admin) foreach (['created_by','withdrawn_at','withdrawn_by','push_status','push_detail','push_id','push_attempts'] as $key) $result[$key]=$row[$key];
    return $result;
}

function appUpdateConfig($pdo) {
    $updates = ['android'=>null,'ios'=>null];
    $rows = $pdo->query('SELECT * FROM app_update_releases WHERE active=1 ORDER BY id DESC LIMIT 2')->fetchAll(PDO::FETCH_ASSOC);
    foreach ($rows as $row) if ($updates[$row['platform']]===null) $updates[$row['platform']]=appUpdatePublicRelease($row);
    $settings = $pdo->query('SELECT setting_key,setting_value FROM app_settings')->fetchAll(PDO::FETCH_KEY_PAIR);
    return ['status'=>'success','updates'=>$updates,
        'android_version'=>$updates['android']['version'] ?? $settings['android_version'] ?? '1.0.0',
        'ios_version'=>$updates['ios']['version'] ?? $settings['ios_version'] ?? '1.0.0',
        'force_update'=>!empty($updates['android']['required_update']) || !empty($updates['ios']['required_update']),
        'update_message'=>$updates['android']['message'] ?? $updates['ios']['message'] ?? 'Yeni bir güncelleme mevcut.'];
}

function appUpdatePublish($pdo, $input, $adminId) {
    $validated = appUpdateValidate($input);
    // Serialize publication/withdrawal so two admins cannot downgrade a release.
    $lock = $pdo->prepare("SELECT GET_LOCK(CONCAT(DATABASE(),':app_updates'),10)"); $lock->execute();
    if ((int)$lock->fetchColumn()!==1) throw new RuntimeException('Güncelleme işlemi sürüyor.');
    try {
        $pdo->beginTransaction();
        $existing = $pdo->prepare('SELECT * FROM app_update_releases WHERE request_key=? ORDER BY id');
        $existing->execute([$validated['request_key']]); $rows=$existing->fetchAll(PDO::FETCH_ASSOC);
        if ($rows) {
            if ($rows[0]['request_hash']!==$validated['hash']) throw new InvalidArgumentException('Bu istek kimliği farklı bir duyuruda kullanılmış. Formu yeniden açın.');
            $pdo->commit(); return $rows;
        }
        foreach ($validated['releases'] as $release) {
            $latest = $pdo->prepare('SELECT * FROM app_update_releases WHERE platform=? AND active=1 ORDER BY id DESC LIMIT 1');
            $latest->execute([$release['platform']]); $previous=$latest->fetch(PDO::FETCH_ASSOC);
            if ($previous && !appUpdateNewer($release,$previous)) throw new InvalidArgumentException('Yayındaki sürümden daha yeni bir sürüm veya derleme numarası girin.');
        }
        foreach ($validated['releases'] as $release) {
            $pdo->prepare('UPDATE app_update_releases SET active=0 WHERE platform=? AND active=1')->execute([$release['platform']]);
            $pdo->prepare('INSERT INTO app_update_releases (request_key,request_hash,platform,version,build_number,title,message,store_url,required_update,created_by,push_key) VALUES (?,?,?,?,?,?,?,?,?,?,?)')
                ->execute([$validated['request_key'],$validated['hash'],$release['platform'],$release['version'],$release['build_number'],$release['title'],$release['message'],$release['store_url'],(int)$release['required_update'],$adminId,appUpdateUuid()]);
            $pdo->prepare('INSERT INTO app_settings (setting_key,setting_value) VALUES (?,?) ON DUPLICATE KEY UPDATE setting_value=VALUES(setting_value)')->execute([$release['platform'].'_version',$release['version']]);
        }
        $existing->execute([$validated['request_key']]); $rows=$existing->fetchAll(PDO::FETCH_ASSOC);
        $pdo->commit(); return $rows;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack(); throw $e;
    } finally { $pdo->query("SELECT RELEASE_LOCK(CONCAT(DATABASE(),':app_updates'))"); }
}

function appUpdatePushPayload($release, $appId) {
    $versionCode = appUpdateVersionCode($release['version']);
    $filters = [
        ['field'=>'tag','key'=>'ototag_app_version_code','relation'=>'not_exists'],
        ['operator'=>'OR'],
        ['field'=>'tag','key'=>'ototag_app_platform','relation'=>'=','value'=>$release['platform']],
        ['operator'=>'AND'],
        ['field'=>'tag','key'=>'ototag_app_version_code','relation'=>'<','value'=>(string)$versionCode],
    ];
    if ((int)$release['build_number']>0) {
        $filters = array_merge($filters, [
            ['operator'=>'OR'],
            ['field'=>'tag','key'=>'ototag_app_platform','relation'=>'=','value'=>$release['platform']],
            ['operator'=>'AND'],
            ['field'=>'tag','key'=>'ototag_app_version_code','relation'=>'=','value'=>(string)$versionCode],
            ['operator'=>'AND'],
            ['field'=>'tag','key'=>'ototag_app_build','relation'=>'not_exists'],
            ['operator'=>'OR'],
            ['field'=>'tag','key'=>'ototag_app_platform','relation'=>'=','value'=>$release['platform']],
            ['operator'=>'AND'],
            ['field'=>'tag','key'=>'ototag_app_version_code','relation'=>'=','value'=>(string)$versionCode],
            ['operator'=>'AND'],
            ['field'=>'tag','key'=>'ototag_app_build','relation'=>'<','value'=>(string)(int)$release['build_number']],
        ]);
    }
    return ['app_id'=>$appId,'target_channel'=>'push','filters'=>$filters,
        'isAndroid'=>$release['platform']==='android','isIos'=>$release['platform']==='ios','isAnyWeb'=>false,
        'headings'=>['en'=>$release['title'],'tr'=>$release['title']],
        'contents'=>['en'=>$release['message'],'tr'=>$release['message']],
        'data'=>['type'=>'app_update','release_id'=>(string)$release['id'],'platform'=>$release['platform']],
        'idempotency_key'=>$release['push_key']];
}

function appUpdatePushTransport($payload) {
    $appId=serverConfig('ONESIGNAL_APP_ID'); $key=serverConfig('ONESIGNAL_REST_API_KEY');
    if ($appId==='' || $key==='' || !function_exists('curl_init')) return ['status'=>'not_configured','detail'=>'Sunucuda OneSignal App ID, REST API anahtarı ve cURL yapılandırılmalı.'];
    $retryAfter=0;
    $ch=curl_init('https://api.onesignal.com/notifications?c=push');
    curl_setopt_array($ch,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>json_encode($payload,JSON_UNESCAPED_UNICODE),
        CURLOPT_HTTPHEADER=>['Content-Type: application/json','Authorization: Key '.$key],
        CURLOPT_RETURNTRANSFER=>true,CURLOPT_CONNECTTIMEOUT=>5,CURLOPT_TIMEOUT=>12,
        CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,
        CURLOPT_HEADERFUNCTION=>function($ch,$header)use(&$retryAfter){
            if (stripos($header,'Retry-After:')===0) {
                $value=trim(substr($header,12));
                $delay=ctype_digit($value) ? (int)$value : max(0,(int)strtotime($value)-time());
                $retryAfter=max($retryAfter,min(86400,$delay));
            }
            return strlen($header);
        }]);
    $raw=curl_exec($ch); $status=(int)curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch);
    $result=is_string($raw) ? json_decode($raw,true) : null;
    return appUpdatePushResult($status,$result,$retryAfter);
}

function appUpdatePushResult($status, $result, $retryAfter=0) {
    if ($status>=200 && $status<300 && is_array($result) && !empty($result['id'])) return ['status'=>'sent','id'=>$result['id'],'detail'=>'Bildirim servisi gönderimi kabul etti.'];
    if ($status>=200 && $status<300 && is_array($result) && array_key_exists('id',$result) && empty($result['id'])) return ['status'=>'no_subscribers','detail'=>'Bu platformda bildirim alabilen cihaz bulunamadı.'];
    return ['status'=>'failed','retry_after'=>$retryAfter,'detail'=>$status ? 'Bildirim servisi gönderimi kabul etmedi (HTTP '.$status.').' : 'Bildirim servisine ulaşılamadı; yeniden denenecek.'];
}

function appUpdateSendPush($pdo, $id, $transport=null) {
    // Never replay an old or withdrawn campaign. OneSignal deduplicates retries
    // for 30 days; the outbox's retry window is deliberately limited to one day.
    $claim=$pdo->prepare("UPDATE app_update_releases SET push_status='sending',push_locked_at=?,push_attempts=push_attempts+1
        WHERE id=? AND active=1 AND created_at>DATE_SUB(NOW(),INTERVAL 1 DAY) AND push_attempts<5 AND push_next_attempt<=?
        AND (push_status IN ('pending','failed','not_configured') OR (push_status='sending' AND push_locked_at<?))");
    $claim->execute([time(),$id,time(),time()-60]);
    if ($claim->rowCount()!==1) return;
    $stmt=$pdo->prepare('SELECT * FROM app_update_releases WHERE id=?'); $stmt->execute([$id]); $release=$stmt->fetch(PDO::FETCH_ASSOC);
    try { $result=($transport ?? 'appUpdatePushTransport')(appUpdatePushPayload($release,serverConfig('ONESIGNAL_APP_ID'))); }
    catch (Throwable $e) { $result=['status'=>'failed','detail'=>'Bildirim gönderimi tamamlanamadı; yeniden denenecek.']; }
    $retry=time()+max((int)($result['retry_after'] ?? 0),min(3600,60*(2**max(0,(int)$release['push_attempts']-1))));
    $pdo->prepare('UPDATE app_update_releases SET push_status=?,push_detail=?,push_id=?,push_next_attempt=?,push_locked_at=0 WHERE id=? AND push_status=\'sending\'')
        ->execute([$result['status'],$result['detail'],$result['id'] ?? null,$retry,$id]);
}

function appUpdateWithdraw($pdo,$id,$adminId) {
    $lock=$pdo->query("SELECT GET_LOCK(CONCAT(DATABASE(),':app_updates'),10)");
    if ((int)$lock->fetchColumn()!==1) throw new RuntimeException('Güncelleme işlemi sürüyor.');
    try {
        $stmt=$pdo->prepare('UPDATE app_update_releases SET active=0,withdrawn_at=NOW(),withdrawn_by=? WHERE id=? AND active=1');
        $stmt->execute([$adminId,$id]);
        if ($stmt->rowCount()!==1) throw new InvalidArgumentException('Yayında olan duyuru bulunamadı.');
    } finally { $pdo->query("SELECT RELEASE_LOCK(CONCAT(DATABASE(),':app_updates'))"); }
}

function handleAppUpdateAction($pdo,$action,$method) {
    if (!in_array($action,['get_app_config','admin_get_app_updates','admin_publish_app_update','admin_withdraw_app_update','admin_retry_app_update_push'],true)) return;
    $read=in_array($action,['get_app_config','admin_get_app_updates'],true);
    if ($method!==($read ? 'GET':'POST')) sendResponse(405,['status'=>'error','message'=>'Geçersiz metod.']);
    $auth=$action==='get_app_config' ? null : authenticateRequest(null,true);
    appUpdateEnsureSchema($pdo);
    try {
        if ($action==='get_app_config') sendResponse(200,appUpdateConfig($pdo));
        if ($action==='admin_publish_app_update') {
            $rows=appUpdatePublish($pdo,$_POST,(int)$auth['user_id']);
            foreach ($rows as $row) appUpdateSendPush($pdo,$row['id']);
        } elseif ($action==='admin_withdraw_app_update' || $action==='admin_retry_app_update_push') {
            $id=$_POST['release_id'] ?? '';
            if (!preg_match('/^[1-9][0-9]{0,17}$/D',(string)$id)) throw new InvalidArgumentException('Duyuru kimliği geçersiz.');
            if ($action==='admin_withdraw_app_update') appUpdateWithdraw($pdo,$id,(int)$auth['user_id']);
            else {
                // Retry keeps the original campaign's idempotency key.
                $check=$pdo->prepare('SELECT * FROM app_update_releases WHERE id=?'); $check->execute([$id]); $release=$check->fetch(PDO::FETCH_ASSOC);
                if (!$release || !$release['active'] || !in_array($release['push_status'],['failed','not_configured'],true) || (int)$release['push_attempts']>=5 || strtotime($release['created_at'])<time()-86400) {
                    throw new InvalidArgumentException('Bu duyuru için yeniden gönderim yapılamıyor. Güncel sürüm için yeni bir duyuru yayımlayın.');
                }
                if ($release['push_status']==='failed' && (int)$release['push_next_attempt']>time()) throw new InvalidArgumentException('Bildirim servisi yeniden denemek için bekleme istiyor. Biraz sonra tekrar deneyin.');
                if ($release['push_status']==='not_configured') $pdo->prepare('UPDATE app_update_releases SET push_next_attempt=0 WHERE id=?')->execute([$id]);
                appUpdateSendPush($pdo,$id);
            }
        }
        $config=appUpdateConfig($pdo);
        $history=$pdo->query('SELECT * FROM app_update_releases ORDER BY id DESC LIMIT 30')->fetchAll(PDO::FETCH_ASSOC);
        $config['history']=array_map(function($row){return appUpdatePublicRelease($row,true);},$history);
        $config['push_configured']=serverConfig('ONESIGNAL_APP_ID')!=='' && serverConfig('ONESIGNAL_REST_API_KEY')!=='' && function_exists('curl_init');
        if (function_exists('notificationHealth')) $config['notification_health']=notificationHealth($pdo);
        $config['message']=$action==='admin_publish_app_update' ? 'Duyuru yayımlandı. Bildirim sonucunu aşağıdan kontrol edebilirsiniz.' : 'İşlem tamamlandı.';
        sendResponse(200,$config);
    } catch (InvalidArgumentException $e) { sendResponse(422,['status'=>'error','message'=>$e->getMessage()]); }
}
