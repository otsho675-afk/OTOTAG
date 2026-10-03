<?php
require_once __DIR__.'/server_configuration.php';
require_once __DIR__.'/api_runtime.php';
require_once __DIR__.'/app_updates.php';

function notificationEnsureSchema($pdo) {
    apiSchemaMigration($pdo,'notification_outbox_v1',function() use($pdo) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS notification_outbox (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,event_key VARCHAR(160) NOT NULL,push_key CHAR(36) NOT NULL,
            payload MEDIUMTEXT NOT NULL,status VARCHAR(24) NOT NULL DEFAULT 'pending',attempts INT NOT NULL DEFAULT 0,
            next_attempt BIGINT NOT NULL DEFAULT 0,locked_at BIGINT NOT NULL DEFAULT 0,created_at BIGINT NOT NULL,
            expires_at BIGINT NOT NULL,detail VARCHAR(255) NULL,push_id VARCHAR(100) NULL,
            UNIQUE KEY notification_event(event_key),KEY notification_due(status,next_attempt),KEY notification_created(created_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
        $pdo->exec("CREATE TABLE IF NOT EXISTS vehicle_reminder_deliveries (
            vehicle_id INT NOT NULL,kind VARCHAR(24) NOT NULL,due_date DATE NOT NULL,stage VARCHAR(32) NOT NULL,
            created_at BIGINT NOT NULL,PRIMARY KEY(vehicle_id,kind,due_date,stage)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    });
}
function notificationHealth($pdo) {
    $last=(int)$pdo->query("SELECT setting_value FROM app_settings WHERE setting_key='notification_worker_at'")->fetchColumn();
    $counts=$pdo->query('SELECT status,COUNT(*) AS total FROM notification_outbox WHERE created_at>'.(time()-604800).' GROUP BY status')->fetchAll(PDO::FETCH_KEY_PAIR);
    $detail=$pdo->query("SELECT detail FROM notification_outbox WHERE status IN ('failed','not_configured','no_subscribers') ORDER BY id DESC LIMIT 1")->fetchColumn();
    return ['worker_recent'=>$last>time()-600,'last_run'=>$last ? gmdate('c',$last):null,
        'pending'=>(int)($counts['pending'] ?? 0)+(int)($counts['sending'] ?? 0),
        'failed'=>(int)($counts['failed'] ?? 0)+(int)($counts['not_configured'] ?? 0),
        'accepted'=>(int)($counts['sent'] ?? 0),'no_subscribers'=>(int)($counts['no_subscribers'] ?? 0),
        'last_issue'=>$detail ?: null];
}
function notificationQueue($pdo,$targets,$title,$message,$data=[],$eventKey=null) {
    $targets=array_values(array_unique(array_filter(array_map('strval',(array)$targets),function($id){return preg_match('/^[1-9][0-9]*$/D',$id);} )));
    if (!$targets) return [];
    $base=$eventKey ?? appUpdateUuid(); $ids=[];
    foreach (array_chunk($targets,2000) as $index=>$users) {
        $payload=['app_id'=>serverConfig('ONESIGNAL_APP_ID'),'target_channel'=>'push',
            'include_aliases'=>['external_id'=>$users],'headings'=>['en'=>$title,'tr'=>$title],
            'contents'=>['en'=>$message,'tr'=>$message],'data'=>$data ?: ['type'=>'general'],
            'priority'=>10,'ios_sound'=>'default','ttl'=>86400];
        $stmt=$pdo->prepare('INSERT IGNORE INTO notification_outbox(event_key,push_key,payload,created_at,expires_at) VALUES (?,?,?,?,?)');
        $key=hash('sha256',$base).':'.$index;
        $stmt->execute([$key,appUpdateUuid(),json_encode($payload,JSON_UNESCAPED_UNICODE),time(),time()+86400]);
        $stmt=$pdo->prepare('SELECT id FROM notification_outbox WHERE event_key=?'); $stmt->execute([$key]);
        $ids[]=(int)$stmt->fetchColumn();
        $GLOBALS['notification_queued']=true;
    }
    return $ids;
}
function notificationSend($pdo,$id,$transport=null,$now=null) {
    if ($pdo->inTransaction()) return;
    $now=$now ?? time();
    $claim=$pdo->prepare("UPDATE notification_outbox SET status='sending',locked_at=?,attempts=attempts+1
        WHERE id=? AND expires_at>? AND next_attempt<=? AND attempts<8
        AND (status IN ('pending','failed','not_configured') OR (status='sending' AND locked_at<?))");
    $claim->execute([$now,$id,$now,$now,$now-60]);
    if (!$claim->rowCount()) return;
    $stmt=$pdo->prepare('SELECT * FROM notification_outbox WHERE id=?'); $stmt->execute([$id]); $row=$stmt->fetch(PDO::FETCH_ASSOC);
    $payload=json_decode($row['payload'],true); $payload['app_id']=serverConfig('ONESIGNAL_APP_ID');
    $payload['idempotency_key']=$row['push_key'];
    if (($payload['data']['type'] ?? '')==='vehicle_reminder') {
        $kind=$payload['data']['kind'] ?? '';
        if (!in_array($kind,['inspection_date','insurance_date'],true)) return;
        $check=$pdo->prepare("SELECT v.customer_id,v.$kind FROM vehicles v JOIN users u ON u.id=v.customer_id WHERE v.id=? AND u.status='active' AND COALESCE(u.is_suspended,0)=0");
        $check->execute([$payload['data']['vehicle_id']]); $vehicle=$check->fetch(PDO::FETCH_ASSOC);
        if (!$vehicle || $vehicle[$kind]!==$payload['data']['due_date'] ||
            !in_array((string)$vehicle['customer_id'],$payload['include_aliases']['external_id'],true)) {
            $pdo->prepare("UPDATE notification_outbox SET status='cancelled',locked_at=0 WHERE id=?")->execute([$id]); return;
        }
    }
    try { $result=($transport ?? 'appUpdatePushTransport')($payload); }
    catch (Throwable $e) { $result=['status'=>'failed','detail'=>'Gönderim tamamlanamadı; yeniden denenecek.']; }
    $next=$now+max((int)($result['retry_after'] ?? 0),min(3600,60*(2**max(0,(int)$row['attempts']-1))));
    $pdo->prepare('UPDATE notification_outbox SET status=?,detail=?,push_id=?,next_attempt=?,locked_at=0 WHERE id=? AND locked_at=?')
        ->execute([$result['status'],$result['detail'] ?? '',$result['id'] ?? null,$next,$id,$now]);
}
function notificationDrain($pdo,$limit=50,$transport=null,$now=null) {
    $now=$now ?? time();
    $stmt=$pdo->prepare("SELECT id FROM notification_outbox WHERE expires_at>? AND next_attempt<=? AND attempts<8
        AND (status IN ('pending','failed','not_configured') OR (status='sending' AND locked_at<?)) ORDER BY id LIMIT ".max(1,min(200,(int)$limit)));
    $stmt->execute([$now,$now,$now-60]);
    foreach ($stmt->fetchAll(PDO::FETCH_COLUMN) as $id) notificationSend($pdo,$id,$transport,$now);
    $pdo->prepare("UPDATE notification_outbox SET status='expired' WHERE expires_at<=? AND status IN ('pending','failed','sending','not_configured')")->execute([$now]);
}
function vehicleReminderPlan($rawDate,$now=null) {
    if (!is_string($rawDate) || !preg_match('/^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}:\d{2})?$/D',$rawDate)) return null;
    $rawDate=substr($rawDate,0,10);
    $zone=new DateTimeZone('Europe/Istanbul');
    $date=DateTimeImmutable::createFromFormat('!Y-m-d',$rawDate,$zone);
    if (!$date || $date->format('Y-m-d')!==$rawDate || substr($rawDate,0,4)<'1900') return null;
    $today=($now ?? new DateTimeImmutable('now',$zone))->setTimezone($zone)->setTime(0,0);
    $days=(int)$today->diff($date)->format('%r%a');
    if ($days>15) return null;
    $stage=$days<0 ? 'late-'.(int)floor((abs($days)-1)/7) : ($days===0 ? 'today':($days<=3?'soon-3':($days<=7?'soon-7':'soon-15')));
    return ['days'=>$days,'stage'=>$stage,'label'=>$days<0 ? abs($days).' gün geçti' : ($days===0?'Bugün son gün':$days.' gün kaldı')];
}
function vehicleReminderScanDue($lastScan,$now=null) {
    $now=($now ?? new DateTimeImmutable('now',new DateTimeZone('Europe/Istanbul')))
        ->setTimezone(new DateTimeZone('Europe/Istanbul'));
    // Revisit edited/new vehicles during the day. Per-vehicle stage keys still
    // deduplicate reminders, so a repeated scan does not repeat a sent warning.
    return (int)$now->format('G')>=9 &&
        ((int)$lastScan<=0 || (int)$lastScan>$now->getTimestamp() ||
        $now->getTimestamp()-(int)$lastScan>=300);
}
function vehicleReminderQueue($pdo,$now=null) {
    $now=$now ?? new DateTimeImmutable('now',new DateTimeZone('Europe/Istanbul'));
    $now=$now->setTimezone(new DateTimeZone('Europe/Istanbul'));
    if ((int)$now->format('G')<9) return 0;
    $last=0; $count=0;
    do {
        $stmt=$pdo->prepare("SELECT v.id,v.customer_id,v.plate,v.inspection_date,v.insurance_date FROM vehicles v
            JOIN users u ON u.id=v.customer_id WHERE v.id>? AND u.status='active' AND COALESCE(u.is_suspended,0)=0
            AND (v.inspection_date<=? OR v.insurance_date<=?) ORDER BY v.id LIMIT 200");
        $cutoff=$now->modify('+15 days')->format('Y-m-d'); $stmt->execute([$last,$cutoff,$cutoff]); $vehicles=$stmt->fetchAll(PDO::FETCH_ASSOC);
        foreach ($vehicles as $vehicle) {
            $last=(int)$vehicle['id'];
            foreach (['inspection_date'=>'Araç muayenesi','insurance_date'=>'Trafik sigortası'] as $kind=>$title) {
                $plan=vehicleReminderPlan($vehicle[$kind],$now); if (!$plan) continue;
                try {
                    $pdo->beginTransaction();
                    // Recheck under a lock: a renewed/deleted vehicle must not enqueue its old date.
                    $current=$pdo->prepare("SELECT $kind,customer_id FROM vehicles WHERE id=? FOR UPDATE"); $current->execute([$last]); $fresh=$current->fetch(PDO::FETCH_ASSOC);
                    if (!$fresh || $fresh[$kind]!==$vehicle[$kind] || (int)$fresh['customer_id']!==(int)$vehicle['customer_id']) { $pdo->rollBack(); continue; }
                    $dedupe=$pdo->prepare('INSERT IGNORE INTO vehicle_reminder_deliveries(vehicle_id,kind,due_date,stage,created_at) VALUES (?,?,?,?,?)');
                    $dedupe->execute([$last,$kind,$vehicle[$kind],$plan['stage'],$now->getTimestamp()]);
                    if ($dedupe->rowCount()) {
                        $message=$vehicle['plate'].' • '.$title.': '.$plan['label'].'. Kayıtlarınızı kontrol edin.';
                        $pdo->prepare('INSERT INTO notifications(user_id,title,message) VALUES (?,?,?)')->execute([$vehicle['customer_id'],$title,$message]);
                        notificationQueue($pdo,[$vehicle['customer_id']],$title,$message,
                            ['type'=>'vehicle_reminder','vehicle_id'=>(string)$last,'kind'=>$kind,'due_date'=>$vehicle[$kind]],
                            'vehicle:'.$last.':'.$kind.':'.$vehicle[$kind].':'.$plan['stage']); $count++;
                    }
                    $pdo->commit();
                } catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $e; }
            }
        }
    } while (count($vehicles)===200);
    return $count;
}
