<?php
require __DIR__.'/../../lib/server_configuration.php';
require __DIR__.'/../../lib/api_runtime.php';
require __DIR__.'/../../lib/app_updates.php';
require __DIR__.'/../../lib/api_authorization.php';
require __DIR__.'/../../lib/admin_management.php';
$env=['ANDROID_PACKAGE_NAME'=>'com.oto.tag'];
$count=0; $actor=['user_id'=>99,'user_type'=>'admin'];
class UpdateResponse extends RuntimeException { public $http; public $data; public function __construct($http,$data){$this->http=$http;$this->data=$data;} }
function sendResponse($http,$data) { throw new UpdateResponse($http,$data); }
function authenticateRequest($id=null,$admin=false) { global $actor; if (!$actor) sendResponse(401,['status'=>'error']); if ($admin && $actor['user_type']!=='admin') sendResponse(403,['status'=>'error']); return $actor; }
function updateCheck($value,$label) { global $count; if (!$value) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
function invalidUpdate($operation,$label) { try { $operation(); updateCheck(false,$label); } catch (InvalidArgumentException $e) { updateCheck(true,$label); } }
updateCheck(appUpdatePushResult(200,['id'=>'','errors'=>['All included players are not subscribed']])['status']==='no_subscribers','empty notification ID with subscriber errors is not reported as sent');
updateCheck(appUpdatePushResult(200,['id'=>'accepted-id','errors'=>['invalid_aliases'=>['external_id'=>['missing-user']]]])['status']==='sent','accepted notification with partial targeting errors retains service acceptance');
updateCheck(appUpdatePushResult(429,['errors'=>['Rate limited']],120)['retry_after']===120,'rate limited notification preserves retry delay');
updateCheck(appUpdatePushResult(401,['id'=>'','errors'=>['Unauthorized']])['status']==='failed','unauthorized notification never appears as no subscribers');
$pdo=new PDO('mysql:host=127.0.0.1;port=33307;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_EMULATE_PREPARES=>false]);
// Every destructive fixture operation is confined to this named test database.
$pdo->exec('CREATE DATABASE IF NOT EXISTS ototag_admin_update_regression CHARACTER SET utf8mb4');
$pdo->exec('USE ototag_admin_update_regression');
foreach (['app_update_releases','app_settings','ototag_schema_migrations'] as $table) $pdo->exec("DROP TABLE IF EXISTS `$table`");
appUpdateEnsureSchema($pdo);
updateCheck(appUpdateConfig($pdo)['updates']===['android'=>null,'ios'=>null],'legacy version defaults never force a new modal');
$input=['request_key'=>appUpdateUuid(),'target'=>'all','android_version'=>'1.0.1','ios_version'=>'1.0.2','android_build'=>'71','ios_build'=>'72',
    'android_store_url'=>'https://play.google.com/store/apps/details?id=com.oto.tag','ios_store_url'=>'https://apps.apple.com/tr/app/ototag/id1234567890',
    'title'=>'Yeni sürüm','message'=>'Daha hızlı ve kolay kullanım.','required_update'=>'1'];
foreach (['1.2','abc','01.0.1','-1.0.1','1.0.1+2'] as $version) invalidUpdate(function()use($input,$version){appUpdateValidate(array_replace($input,['android_version'=>$version]));},'invalid version rejected: '.$version);
foreach (['javascript:alert(1)','https://apps.apple.com.evil.test/app/id123','https://user@apps.apple.com/app/id123','https://apps.apple.com:443/app/id123'] as $url) invalidUpdate(function()use($input,$url){appUpdateValidate(array_replace($input,['ios_store_url'=>$url]));},'unsafe App Store link rejected');
invalidUpdate(function()use($input){appUpdateValidate(array_replace($input,['android_store_url'=>'https://play.google.com/store/apps/details?id=another.app']));},'wrong Android app rejected');
invalidUpdate(function()use($input){appUpdateValidate(array_replace($input,['android_build'=>'2147483648']));},'overflowing build rejected');
invalidUpdate(function()use($input){appUpdateValidate(array_replace($input,['required_update'=>'yes']));},'invalid mandatory flag rejected');
$rows=appUpdatePublish($pdo,$input,99);
updateCheck(count($rows)===2 && count(appUpdatePublish($pdo,$input,99))===2 && (int)$pdo->query('SELECT COUNT(*) FROM app_update_releases')->fetchColumn()===2,'duplicate publish creates one campaign per platform');
invalidUpdate(function()use($pdo,$input){appUpdatePublish($pdo,array_replace($input,['message'=>'Different payload']),99);},'idempotency key cannot be reused with different content');
$config=appUpdateConfig($pdo);
updateCheck($config['updates']['android']['version']==='1.0.1' && $config['updates']['ios']['version']==='1.0.2','independent platform versions published atomically');
updateCheck(!isset($config['updates']['android']['push_key']) && !isset($config['updates']['android']['created_by']),'public configuration excludes admin and push metadata');
$calls=[];
$transport=function($payload)use(&$calls){$calls[]=$payload;return ['status'=>'sent','id'=>'mock-push-id','detail'=>'Accepted'];};
appUpdateSendPush($pdo,$rows[0]['id'],$transport); appUpdateSendPush($pdo,$rows[0]['id'],$transport);
updateCheck(count($calls)===1 && $calls[0]['included_segments']===['All'] && $calls[0]['isAndroid'] && !$calls[0]['isIos'],'all Android subscribers targeted without a user limit or duplicate push');
updateCheck($calls[0]['data']['type']==='app_update' && !isset($calls[0]['url']),'push signals a trusted API recheck instead of opening an arbitrary URL');
$failedKey=null;
appUpdateSendPush($pdo,$rows[1]['id'],function($payload)use(&$failedKey){$failedKey=$payload['idempotency_key'];return ['status'=>'failed','detail'=>'Temporary failure'];});
$pdo->prepare('UPDATE app_update_releases SET push_next_attempt=0 WHERE id=?')->execute([$rows[1]['id']]);
appUpdateSendPush($pdo,$rows[1]['id'],function($payload)use($failedKey){updateCheck($payload['idempotency_key']===$failedKey && $payload['isIos'] && !$payload['isAndroid'],'retry keeps the original iPhone campaign key');return ['status'=>'sent','id'=>'retry-id','detail'=>'Accepted'];});
$bad=array_replace($input,['request_key'=>appUpdateUuid(),'android_version'=>'1.0.3','ios_version'=>'1.0.1']);
invalidUpdate(function()use($pdo,$bad){appUpdatePublish($pdo,$bad,99);},'downgrade rejected before either platform changes');
updateCheck(appUpdateConfig($pdo)['updates']['android']['version']==='1.0.1','failed multi-platform publish leaves Android intact');
$next=array_replace($input,['request_key'=>appUpdateUuid(),'target'=>'android','android_build'=>'73']);
$new=appUpdatePublish($pdo,$next,99)[0];
updateCheck(appUpdateConfig($pdo)['updates']['android']['build_number']===73,'same version with newer build is publishable');
updateCheck(appUpdateConfig($pdo)['updates']['ios']['id']===(int)$rows[1]['id'],'Android publication preserves iPhone release');
appUpdateWithdraw($pdo,$new['id'],99);
updateCheck(appUpdateConfig($pdo)['updates']['android']===null,'withdrawal does not resurrect an obsolete forced release');
appUpdateSendPush($pdo,$new['id'],$transport);
updateCheck(count($calls)===1,'withdrawn releases cannot send queued notifications');
foreach (['admin_get_app_updates','admin_publish_app_update','admin_withdraw_app_update','admin_retry_app_update_push'] as $action) {
    foreach ([null,['user_id'=>1,'user_type'=>'customer'],['user_id'=>10,'user_type'=>'rentacar'],['user_id'=>20,'user_type'=>'provider']] as $unauthorized) {
        $actor=$unauthorized;
        try { authorizeApiAction($pdo,$action,'POST'); updateCheck(false,'unauthorized admin action'); }
        catch (UpdateResponse $e) { updateCheck(in_array($e->http,[401,403],true),'release management requires an admin'); }
    }
}
$actor=['user_id'=>99,'user_type'=>'admin'];
try { handleAppUpdateAction($pdo,'admin_publish_app_update','GET'); updateCheck(false,'wrong method'); }
catch (UpdateResponse $e) { updateCheck($e->http===405,'publishing requires POST'); }
$_POST=array_replace($input,['request_key'=>appUpdateUuid(),'target'=>'android','android_version'=>'1.0.4']);
try { handleAppUpdateAction($pdo,'admin_publish_app_update','POST'); updateCheck(false,'no API response'); }
catch (UpdateResponse $e) { updateCheck($e->http===200 && $e->data['history'][0]['push_status']==='not_configured' && !$e->data['push_configured'],'missing OneSignal config saves modal but never claims push delivery'); }
$pdo->exec('CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY,name VARCHAR(100),phone VARCHAR(30)) ENGINE=InnoDB');
$pdo->exec('CREATE TABLE IF NOT EXISTS part_listings (id INT PRIMARY KEY,customer_id INT,seller_id INT,part_name VARCHAR(100),car_model VARCHAR(100),status VARCHAR(30)) ENGINE=InnoDB');
$pdo->exec('DELETE FROM part_listings');
$pdo->exec("REPLACE INTO users VALUES (1,'Customer','05460000000'),(2,'Seller','05460000001')");
$insert=$pdo->prepare('INSERT INTO part_listings VALUES (?,1,2,?,?,?)');
for ($i=1;$i<=205;$i++) $insert->execute([$i,$i===1 ? 'Old unique part' : 'Spare part','Fiat',$i%2 ? 'completed':'searching']);
$page=adminPartListings($pdo,[]);
updateCheck(count($page['market'])===100 && $page['has_more'] && $page['next_cursor']===106,'admin listings use bounded pages');
$page2=adminPartListings($pdo,['before_id'=>$page['next_cursor']]);
updateCheck(count($page2['market'])===100 && $page2['market'][0]['id']===105,'cursor loads older listings without duplicate IDs');
$old=adminPartListings($pdo,['q'=>'Old unique']);
updateCheck(count($old['market'])===1 && $old['market'][0]['id']===1 && $old['market'][0]['status']==='completed','admin searches the whole database including completed listings');
updateCheck(adminPartListings($pdo,['q'=>'205'])['market'][0]['id']===205,'exact listing ID search works');
invalidUpdate(function()use($pdo){adminPartListings($pdo,['before_id'=>'1 OR 1=1']);},'invalid admin cursor rejected');
authorizeApiAction($pdo,'get_part_listings','GET');
updateCheck(true,'admin can reach the listing management endpoint');
echo "\n$count app update and management checks passed.\n";
