<?php
// OTO TAG yönetici kullanıcı konsolu. Kimlik doğrulama api_authorization.php içinde yapılır.
function adminConsoleEnsureSchema(PDO $pdo) {
    static $ready = false;
    if ($ready) return;
    $pdo->exec("CREATE TABLE IF NOT EXISTS user_access_state (
        user_id INT NOT NULL PRIMARY KEY,
        last_login_at DATETIME NULL,
        last_seen_at DATETIME NULL,
        login_count INT NOT NULL DEFAULT 0,
        INDEX idx_user_access_last_seen (last_seen_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $pdo->exec("CREATE TABLE IF NOT EXISTS admin_user_activity (
        id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        actor_type VARCHAR(20) NOT NULL,
        actor_id INT NOT NULL,
        event_name VARCHAR(100) NOT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_admin_user_activity (user_id, created_at),
        INDEX idx_admin_activity_actor (actor_type, actor_id, created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $ready = true;
}

function adminConsoleTrackLogin(PDO $pdo, $userId, $kind = 'password') {
    try {
        adminConsoleEnsureSchema($pdo);
        $pdo->prepare("INSERT INTO user_access_state (user_id,last_login_at,last_seen_at,login_count)
            VALUES (?,NOW(),NOW(),1) ON DUPLICATE KEY UPDATE
            last_login_at=NOW(),last_seen_at=NOW(),login_count=login_count+1")
            ->execute([(int)$userId]);
        adminConsoleLog($pdo, (int)$userId, 'user', (int)$userId, 'Giriş: '.$kind);
    } catch (Throwable $e) { error_log('User login tracking unavailable.'); }
}

function adminConsoleTrackSeen(PDO $pdo, $userId, $action, $method) {
    try {
        // Telemetri/giriş ayrı kaydedilir; gereksiz konum/poll kayıtları yazılmaz.
        $pdo->prepare("INSERT IGNORE INTO user_access_state (user_id,last_seen_at) VALUES (?,NOW())")
            ->execute([(int)$userId]);
        $pdo->prepare("UPDATE user_access_state SET last_seen_at=NOW()
            WHERE user_id=? AND (last_seen_at IS NULL OR last_seen_at < NOW() - INTERVAL 90 SECOND)")
            ->execute([(int)$userId]);
        if ($method === 'POST' && !in_array($action, ['update_location','mark_read','mark_notif_read','check_unread_messages','log_telemetry'],true)) {
            adminConsoleLog($pdo, (int)$userId, 'user', (int)$userId, 'İstek: '.substr((string)$action,0,88));
        }
    } catch (Throwable $e) { /* Eski kurulumda tablo henüz oluşmamış olabilir. */ }
}

function adminConsoleLog(PDO $pdo, $userId, $actorType, $actorId, $event) {
    $pdo->prepare("INSERT INTO admin_user_activity(user_id,actor_type,actor_id,event_name)
       VALUES (?,?,?,?)")->execute([(int)$userId,$actorType,(int)$actorId,substr($event,0,100)]);
}

function adminConsoleId($raw) {
    if (!is_scalar($raw) || !preg_match('/^[1-9][0-9]{0,9}$/D',(string)$raw)) {
        sendResponse(422,['status'=>'error','message'=>'Geçersiz kayıt numarası.']);
    }
    return (int)$raw;
}

function adminConsoleUser(PDO $pdo, $userId) {
    $stmt=$pdo->prepare("SELECT id,user_type,name,email,phone,city,status,service_category,iban,
        is_premium,is_suspended,suspension_end_date,created_at,rating,reviews_count,
        tax_plate,driver_license,vehicle_photo,equipment_photo
        FROM users WHERE id=?");
    $stmt->execute([$userId]);
    $row=$stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) sendResponse(404,['status'=>'error','message'=>'Üye bulunamadı.']);
    return $row;
}

function adminConsoleUpdateVehicle(PDO $pdo, $userId, $vehicleId, $input) {
    $check=$pdo->prepare("SELECT id FROM vehicles WHERE id=? AND customer_id=?");
    $check->execute([$vehicleId,$userId]);
    if (!$check->fetchColumn()) sendResponse(404,['status'=>'error','message'=>'Araç bu kullanıcıya ait değil.']);
    $allowed=['plate','brand_model','engine_type','model_year','insurance_date',
        'inspection_date','mtv_date','current_km','maintenance_km'];
    $data=[]; $values=[];
    foreach ($allowed as $key) {
        if (!array_key_exists($key,$input)) continue;
        $val=trim((string)$input[$key]);
        if (strlen($val)>255) sendResponse(422,['status'=>'error','message'=>'Araç alanı çok uzun.']);
        if (in_array($key,['current_km','maintenance_km'],true)) {
            if (!ctype_digit($val) || (float)$val > 99999999) sendResponse(422,['status'=>'error','message'=>'Kilometre geçersiz.']);
            $val=(int)$val;
        } elseif (in_array($key,['insurance_date','inspection_date','mtv_date'],true)) {
            if ($val!=='' && !preg_match('/^\\d{4}-\\d{2}-\\d{2}$/D',$val)) sendResponse(422,['status'=>'error','message'=>'Tarih YYYY-AA-GG olmalı.']);
            $val=$val!=='' ? $val : null;
        } elseif ($key==='plate') {
            $val=strtoupper($val);
            if ($val==='') sendResponse(422,['status'=>'error','message'=>'Plaka boş olamaz.']);
        } elseif ($key==='brand_model' && $val==='') {
            sendResponse(422,['status'=>'error','message'=>'Marka/model boş olamaz.']);
        }
        $data[]="`$key`=?"; $values[]=$val;
    }
    if (!$data) sendResponse(422,['status'=>'error','message'=>'Güncellenecek alan yok.']);
    $values[]=$vehicleId; $values[]=$userId;
    $pdo->prepare("UPDATE vehicles SET ".implode(',',$data)." WHERE id=? AND customer_id=?")->execute($values);
}

function handleAdminConsoleAction(PDO $pdo, $action, $method) {
    $actions=['admin_get_user_detail','admin_update_user','admin_add_vehicle','admin_update_vehicle','admin_delete_vehicle','admin_delete_vehicle_record'];
    if (!in_array($action,$actions,true)) return;
    $actor=authenticateRequest(null,true);
    $input=$method==='GET' ? $_GET : $_POST;
    $userId=adminConsoleId($input['user_id'] ?? null);
    $user=adminConsoleUser($pdo,$userId);
    if ($action==='admin_get_user_detail') {
        if ($method!=='GET') sendResponse(405,['status'=>'error','message'=>'GET gerekli.']);
        adminConsoleEnsureSchema($pdo);
        $access=$pdo->prepare("SELECT last_login_at,last_seen_at,login_count FROM user_access_state WHERE user_id=?");
        $access->execute([$userId]);
        $row=$access->fetch(PDO::FETCH_ASSOC) ?: [];
        $user=array_merge($user,$row);
        $vehicles=$pdo->prepare("SELECT * FROM vehicles WHERE customer_id=? ORDER BY id DESC LIMIT 100");
        $vehicles->execute([$userId]);
        $fleet=$vehicles->fetchAll(PDO::FETCH_ASSOC);
        $records=[];
        if ($fleet) {
            $ids=array_column($fleet,'id');
            $placeholders=implode(',',array_fill(0,count($ids),'?'));
            $stmt=$pdo->prepare("SELECT id,vehicle_id,record_type,description,cost,created_at
                FROM vehicle_records WHERE vehicle_id IN ($placeholders) ORDER BY id DESC LIMIT 100");
            $stmt->execute($ids);
            $records=$stmt->fetchAll(PDO::FETCH_ASSOC);
        }
        $jobs=$pdo->prepare("SELECT id,service_type,status,agreed_price,created_at FROM jobs
            WHERE customer_id=? OR provider_id=? ORDER BY id DESC LIMIT 50");
        $jobs->execute([$userId,$userId]);
        $rentals=$pdo->prepare("SELECT id,plate,car_brand_model,daily_price,status,created_at FROM rentacar_listings
            WHERE company_id=? ORDER BY id DESC LIMIT 50");
        $rentals->execute([$userId]);
        $parts=$pdo->prepare("SELECT id,part_name,car_model,status,price,created_at FROM part_listings
            WHERE customer_id=? OR seller_id=? ORDER BY id DESC LIMIT 50");
        $parts->execute([$userId,$userId]);
        $activity=$pdo->prepare("SELECT event_name,actor_type,created_at FROM admin_user_activity
            WHERE user_id=? ORDER BY id DESC LIMIT 80");
        $activity->execute([$userId]);
        $events=$activity->fetchAll(PDO::FETCH_ASSOC);
        // Telemetri istemci tarafından gönderilir: doğrulanmamış geçmiş sinyalidir.
        $telemetry=$pdo->prepare("SELECT event_type,event_name,screen_name,created_at FROM app_telemetry
            WHERE user_id=? ORDER BY id DESC LIMIT 50");
        $telemetry->execute([$userId]);
        sendResponse(200,['status'=>'success','user'=>$user,'vehicles'=>$fleet,'vehicle_records'=>$records,
            'jobs'=>$jobs->fetchAll(PDO::FETCH_ASSOC),
            'rental_listings'=>$rentals->fetchAll(PDO::FETCH_ASSOC),'part_listings'=>$parts->fetchAll(PDO::FETCH_ASSOC),
            'activity'=>$events,'telemetry'=>$telemetry->fetchAll(PDO::FETCH_ASSOC)]);
    }
    if ($method!=='POST') sendResponse(405,['status'=>'error','message'=>'POST gerekli.']);
    adminConsoleEnsureSchema($pdo);
    if ($action==='admin_update_user') {
        $fields=['name'=>120,'phone'=>32,'email'=>255,'city'=>100,'iban'=>34,'service_category'=>50];
        $set=[]; $params=[];
        foreach($fields as $field=>$max) {
            if (!array_key_exists($field,$input)) continue;
            if (!is_scalar($input[$field]) || mb_strlen(trim((string)$input[$field]))>$max) sendResponse(422,['status'=>'error','message'=>'Alan geçersiz: '.$field]);
            $v=trim((string)$input[$field]);
            if (in_array($field,['name','phone'],true) && $v==='') sendResponse(422,['status'=>'error','message'=>'Ad ve telefon boş olamaz.']);
            if ($field==='email' && $v!=='' && !filter_var($v,FILTER_VALIDATE_EMAIL)) sendResponse(422,['status'=>'error','message'=>'E-posta geçersiz.']);
            $set[]="`$field`=?"; $params[]=$v;
        }
        if (isset($input['status'])) {
            if (!in_array($input['status'],['active','pending','banned','rejected'],true)) sendResponse(422,['status'=>'error','message'=>'Hesap durumu geçersiz.']);
            $set[]='status=?'; $params[]=$input['status'];
        }
        foreach(['is_premium','is_suspended'] as $flag) {
            if (array_key_exists($flag,$input)) {
                if (!in_array((string)$input[$flag],['0','1'],true)) sendResponse(422,['status'=>'error','message'=>'Geçersiz durum.']);
                $set[]="`$flag`=?"; $params[]=(int)$input[$flag];
                if ($flag==='is_suspended' && (int)$input[$flag]===0) $set[]='suspension_end_date=NULL';
            }
        }
        if (!$set) sendResponse(422,['status'=>'error','message'=>'Güncellenecek alan yok.']);
        $params[]=$userId;
        try {
            $pdo->prepare("UPDATE users SET ".implode(',',$set)." WHERE id=?")->execute($params);
            adminConsoleLog($pdo,$userId,'admin',$actor['user_id'],'Üye güncellendi');
            sendResponse(200,['status'=>'success','message'=>'Üye bilgileri kaydedildi.']);
        } catch (PDOException $e) { sendResponse(409,['status'=>'error','message'=>'Üye bilgileri kaydedilemedi. Benzersiz alanları kontrol edin.']); }
    }
    if ($user['user_type']!=='customer') sendResponse(422,['status'=>'error','message'=>'Bu hesap müşteri aracı kullanmıyor.']);
    if ($action==='admin_add_vehicle') {
        $plate=strtoupper(trim((string)($input['plate'] ?? '')));
        $model=trim((string)($input['brand_model'] ?? ''));
        if ($plate==='' || $model==='' || strlen($plate)>30 || strlen($model)>255) sendResponse(422,['status'=>'error','message'=>'Plaka ve marka/model zorunludur.']);
        $pdo->prepare("INSERT INTO vehicles (customer_id,plate,brand_model,current_km,maintenance_km) VALUES (?,?,?,0,10000)")
            ->execute([$userId,$plate,$model]);
        $vehicleId=(int)$pdo->lastInsertId();
        adminConsoleLog($pdo,$userId,'admin',$actor['user_id'],'Araç eklendi #'.$vehicleId);
    } else {
        $vehicleId=adminConsoleId($input['vehicle_id'] ?? null);
        $vehicle=$pdo->prepare("SELECT id FROM vehicles WHERE id=? AND customer_id=?");
        $vehicle->execute([$vehicleId,$userId]);
        if (!$vehicle->fetchColumn()) sendResponse(404,['status'=>'error','message'=>'Araç bulunamadı.']);
        if ($action==='admin_update_vehicle') {
            adminConsoleUpdateVehicle($pdo,$userId,$vehicleId,$input);
            adminConsoleLog($pdo,$userId,'admin',$actor['user_id'],'Araç güncellendi #'.$vehicleId);
        } elseif ($action==='admin_delete_vehicle_record') {
            $recordId=adminConsoleId($input['record_id'] ?? null);
            $files=$pdo->prepare("SELECT document_url,image_url FROM vehicle_records WHERE id=? AND vehicle_id=?");
            $files->execute([$recordId,$vehicleId]);
            $fileRow=$files->fetch(PDO::FETCH_ASSOC);
            if (!$fileRow) sendResponse(404,['status'=>'error','message'=>'Araç kaydı bulunamadı.']);
            $stmt=$pdo->prepare("DELETE FROM vehicle_records WHERE id=? AND vehicle_id=?");
            $stmt->execute([$recordId,$vehicleId]);
            foreach (['document_url','image_url'] as $key) deletePhysicalFile($fileRow[$key] ?? null);
            adminConsoleLog($pdo,$userId,'admin',$actor['user_id'],'Araç kaydı silindi #'.$recordId);
        } elseif ($action==='admin_delete_vehicle') {
            $fileStmt=$pdo->prepare("SELECT document_url,image_url FROM vehicle_records WHERE vehicle_id=?");
            $fileStmt->execute([$vehicleId]);
            $files=$fileStmt->fetchAll(PDO::FETCH_ASSOC);
            $pdo->beginTransaction();
            try {
                $pdo->prepare("DELETE FROM vehicle_records WHERE vehicle_id=?")->execute([$vehicleId]);
                $pdo->prepare("DELETE FROM vehicles WHERE id=? AND customer_id=?")->execute([$vehicleId,$userId]);
                $pdo->commit();
            } catch(Throwable $e) { $pdo->rollBack(); throw $e; }
            foreach ($files as $fileRow) {
                foreach (['document_url','image_url'] as $key) deletePhysicalFile($fileRow[$key] ?? null);
            }
            adminConsoleLog($pdo,$userId,'admin',$actor['user_id'],'Araç silindi #'.$vehicleId);
        }
    }
    if (!empty($GLOBALS['redis'])) $GLOBALS['redis']->del('cust_vehicles_'.$userId);
    sendResponse(200,['status'=>'success','message'=>'Yönetici işlemi tamamlandı.']);
}
