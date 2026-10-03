<?php
// Reject malformed transport values before typed validators or database work.
function apiValidateInput($get,$post) {
    foreach ([$get,$post] as $fields) {
        if (count($fields)>100) throw new InvalidArgumentException('Çok fazla istek alanı gönderildi.');
        foreach ($fields as $name=>$value) {
            if (!is_string($name) || strlen($name)>100) throw new InvalidArgumentException('Geçersiz istek alanı.');
            if (is_array($value)) {
                if ($name==='job_ids' && count($value)<=100 && !array_filter($value,function($id){return !is_scalar($id) || !preg_match('/^[1-9][0-9]{0,9}$/D',(string)$id);})) continue;
                if ($name==='metadata' && strlen(json_encode($value))<=16384) continue;
                throw new InvalidArgumentException('İstek alanlarının biçimi geçersiz.');
            }
            if (!is_scalar($value) && $value!==null) throw new InvalidArgumentException('Geçersiz istek değeri.');
            if (is_string($value) && strlen($value)>262144) throw new InvalidArgumentException('İstek alanı çok uzun.');
        }
    }
    if (isset($get['action']) && !preg_match('/^[a-z][a-z0-9_]{0,79}$/D',$get['action'])) throw new InvalidArgumentException('Geçersiz işlem adı.');
}
function apiJson($data) {
    $json=json_encode($data,JSON_UNESCAPED_UNICODE|JSON_INVALID_UTF8_SUBSTITUTE|JSON_PARTIAL_OUTPUT_ON_ERROR);
    return $json===false ? '{"status":"error","message":"Yanıt oluşturulamadı."}' : $json;
}
function apiPublicResponse($statusCode,$data) {
    if ((int)$statusCode!==500) return $data;
    $reference=bin2hex(random_bytes(6));
    error_log('OTOTAG API handled error '.$reference);
    return ['status'=>'error','message'=>'İşlem tamamlanamadı. Lütfen tekrar deneyin.','error_reference'=>$reference];
}
function apiUnhandledError($error) {
    global $pdo;
    try { if ($pdo instanceof PDO && $pdo->inTransaction()) $pdo->rollBack(); } catch (Throwable $ignored) {}
    $reference=bin2hex(random_bytes(6));
    // No request bodies, credential values or raw SQL errors in public responses/logs.
    error_log('OTOTAG API error '.$reference.' '.get_class($error).' '.basename($error->getFile()).':'.$error->getLine());
    http_response_code(500);
    if (!headers_sent()) header('Content-Type: application/json; charset=utf-8');
    echo apiJson(['status'=>'error','message'=>'İşlem tamamlanamadı. Lütfen tekrar deneyin.','error_reference'=>$reference]);
}
function apiSchemaMigration($pdo,$version,$operation) {
    // Store completion in the database, so it is shared by all PHP workers.
    try {
        $check=$pdo->prepare('SELECT version FROM ototag_schema_migrations WHERE version=?');
        $check->execute([$version]);
    } catch (PDOException $e) {
        if ($e->getCode()!=='42S02') throw $e;
        $pdo->exec('CREATE TABLE IF NOT EXISTS ototag_schema_migrations (version VARCHAR(100) PRIMARY KEY,completed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB');
        $check=$pdo->prepare('SELECT version FROM ototag_schema_migrations WHERE version=?'); $check->execute([$version]);
    }
    if ($check->fetchColumn()) return false;
    $database=$pdo->query('SELECT DATABASE()')->fetchColumn();
    $name='ototag_schema_'.substr(hash('sha256',$database.'|'.$version),0,48);
    $lock=$pdo->prepare('SELECT GET_LOCK(?,10)'); $lock->execute([$name]);
    if ((int)$lock->fetchColumn()!==1) throw new RuntimeException('Şema güncellemesi sürüyor. Tekrar deneyin.');
    try {
        $check->execute([$version]); if ($check->fetchColumn()) return false;
        $operation();
        $pdo->prepare('INSERT INTO ototag_schema_migrations(version) VALUES (?)')->execute([$version]);
        return true;
    } finally { $pdo->prepare('SELECT RELEASE_LOCK(?)')->execute([$name]); }
}
