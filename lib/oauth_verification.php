<?php
spl_autoload_register(function($class) {
    $prefix='Firebase\\JWT\\';
    if (strpos($class,$prefix)!==0) return;
    $name=substr($class,strlen($prefix));
    if (!preg_match('/^[A-Za-z]+$/D',$name)) return;
    $path=__DIR__.'/php_jwt/src/'.$name.'.php';
    if (is_file($path)) require_once $path;
});

function validateOAuthClaims($claims,$provider,$audiences) {
    $issuers=$provider==='google' ? ['accounts.google.com','https://accounts.google.com'] : ['https://appleid.apple.com'];
    if (!in_array($claims['iss'] ?? '',$issuers,true) || !in_array($claims['aud'] ?? '',$audiences,true)
        || empty($claims['sub']) || !isset($claims['exp']) || $claims['exp']<=time()) {
        throw new UnexpectedValueException('Kimlik doğrulanamadı.');
    }
    $verified=in_array($claims['email_verified'] ?? false,[true,'true',1,'1'],true);
    return ['sub'=>(string)$claims['sub'],'email'=>$verified ? (string)($claims['email'] ?? '') : ''];
}
function verifyOAuthIdentity($provider,$token) {
    global $env,$redis;
    if (!in_array($provider,['google','apple'],true) || !$token || strlen($token)>16384) {
        sendResponse(401,['status'=>'error','message'=>'Google veya Apple kimlik doğrulamasını tekrar yapın.']);
    }
    $config=$provider==='google' ? 'GOOGLE_OAUTH_CLIENT_IDS' : 'APPLE_OAUTH_CLIENT_IDS';
    $configured = function_exists('serverConfig') ? serverConfig($config) : (getenv($config) ?: ($env[$config] ?? ''));
    $audiences=array_values(array_filter(array_map('trim',explode(',', $configured))));
    if (!$audiences) sendResponse(503,['status'=>'error','message'=>'Sosyal giriş sunucu ayarları henüz tamamlanmadı.']);
    $cacheKey='oauth_jwks_'.$provider;
    try {
        $json=$redis ? $redis->get($cacheKey) : false;
        if (!$json) {
            $url=$provider==='google' ? 'https://www.googleapis.com/oauth2/v3/certs' : 'https://appleid.apple.com/auth/keys';
            $ch=curl_init($url);
            curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>10,CURLOPT_CONNECTTIMEOUT=>4,
                CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2]);
            $json=curl_exec($ch); $status=curl_getinfo($ch,CURLINFO_HTTP_CODE); curl_close($ch);
            if ($status!==200 || !$json) throw new RuntimeException('Kimlik sağlayıcıya ulaşılamadı.');
        }
        $jwks=json_decode($json,true);
        if (!is_array($jwks) || empty($jwks['keys'])) throw new RuntimeException('Anahtarlar alınamadı.');
        $jwks['keys']=array_values(array_filter($jwks['keys'],function($key) {
            return ($key['kty'] ?? '')==='RSA' && (!isset($key['alg']) || $key['alg']==='RS256');
        }));
        if ($redis) $redis->setex($cacheKey,600,$json);
        $claims=(array)\Firebase\JWT\JWT::decode($token,\Firebase\JWT\JWK::parseKeySet($jwks,'RS256'));
        return validateOAuthClaims($claims,$provider,$audiences);
    } catch (Throwable $e) {
        if ($redis) $redis->del($cacheKey);
        sendResponse(401,['status'=>'error','message'=>'Kimlik doğrulanamadı. Google veya Apple ile tekrar giriş yapın.']);
    }
}
