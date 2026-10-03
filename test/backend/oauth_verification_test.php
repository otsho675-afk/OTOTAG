<?php
require __DIR__.'/../../lib/oauth_verification.php';
class TestResponse extends RuntimeException { public $http; public function __construct($http) { $this->http=$http; } }
function sendResponse($code,$data) { throw new TestResponse($code); }
class PublicKeyTestCache {
    public $json;
    public function get($key) { return $this->json; }
    public function setex($key,$ttl,$value) {}
    public function del($key) {}
}
$redis=new PublicKeyTestCache();
$env=['GOOGLE_OAUTH_CLIENT_IDS'=>'test-client','APPLE_OAUTH_CLIENT_IDS'=>'com.oto.tag'];
$options=['private_key_bits'=>2048,'private_key_type'=>OPENSSL_KEYTYPE_RSA];
$localConfig=dirname(PHP_BINARY).'/extras/ssl/openssl.cnf';
if (is_file($localConfig)) $options['config']=$localConfig;
$key=openssl_pkey_new($options);
openssl_pkey_export($key,$privateKey,null,$options); $details=openssl_pkey_get_details($key);
$encode=function($value) { return rtrim(strtr(base64_encode($value),'+/','-_'),'='); };
$redis->json=json_encode(['keys'=>[['kty'=>'RSA','kid'=>'test','alg'=>'RS256','n'=>$encode($details['rsa']['n']),'e'=>$encode($details['rsa']['e'])]]]);
$count=0;
function checkOauth($condition,$label) { global $count; if (!$condition) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
function identityToken($claims,$privateKey) { return \Firebase\JWT\JWT::encode($claims,$privateKey,'RS256','test'); }
$claims=['iss'=>'https://accounts.google.com','aud'=>'test-client','sub'=>'verified-user','exp'=>time()+3600,'iat'=>time(),'email'=>'verified@example.com','email_verified'=>true];
checkOauth(verifyOAuthIdentity('google',identityToken($claims,$privateKey))['sub']==='verified-user','signed Google identity verified');
$apple=array_replace($claims,['iss'=>'https://appleid.apple.com','aud'=>'com.oto.tag']);
checkOauth(verifyOAuthIdentity('apple',identityToken($apple,$privateKey))['sub']==='verified-user','signed Apple identity verified');
checkOauth(verifyOAuthIdentity('google',identityToken(array_replace($claims,['email_verified'=>false]),$privateKey))['email']==='','unverified email not trusted');
foreach ([array_replace($claims,['aud'=>'another-app']),array_replace($claims,['iss'=>'attacker']),array_replace($claims,['exp'=>time()-1])] as $invalid) {
    try { verifyOAuthIdentity('google',identityToken($invalid,$privateKey)); checkOauth(false,'invalid identity'); }
    catch (TestResponse $e) { checkOauth($e->http===401,'wrong audience issuer or expired token denied'); }
}
$valid=identityToken($claims,$privateKey); $parts=explode('.',$valid); $parts[1]=$encode(json_encode(array_replace($claims,['sub'=>'forged-user'])));
try { verifyOAuthIdentity('google',implode('.',$parts)); checkOauth(false,'forged identity'); }
catch (TestResponse $e) { checkOauth($e->http===401,'tampered signature denied'); }
echo "\n$count OAuth checks passed.\n";
