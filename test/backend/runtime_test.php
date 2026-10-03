<?php
require __DIR__.'/../../lib/api_runtime.php';
$count=0;
function runtimeCheck($condition,$label) { global $count; if (!$condition) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
foreach ([['action'=>['register']],['action'=>'../api.php'],['phone'=>['123']],['job_ids'=>[['nested']]],['job_ids'=>range(1,101)],['metadata'=>['huge'=>str_repeat('x',17000)]],['name'=>str_repeat('x',262145)]] as $input) {
    try { apiValidateInput($input,[]); runtimeCheck(false,'malformed transport accepted'); }
    catch (InvalidArgumentException $e) { runtimeCheck(true,'malformed transport safely rejected'); }
}
apiValidateInput(['action'=>'delete_history'],['job_ids'=>['1','2'],'metadata'=>['screen'=>'history']]);
runtimeCheck(true,'supported ID arrays and bounded telemetry remain accepted');
runtimeCheck(is_array(json_decode(apiJson(['name'=>"bad\xffutf8"]),true)),'invalid stored UTF-8 still produces valid JSON');
runtimeCheck(is_array(json_decode(apiJson(['number'=>NAN]),true)),'invalid numeric response does not become an empty body');
$safe=apiPublicResponse(500,['status'=>'error','message'=>'SQLSTATE secret password','sql'=>'private query']);
runtimeCheck(!isset($safe['sql']) && strpos(json_encode($safe),'SQLSTATE')===false && strlen($safe['error_reference'])===12,'handled failures cannot expose SQL or credentials');
runtimeCheck(apiPublicResponse(422,['message'=>'Geçersiz bütçe.'])===['message'=>'Geçersiz bütçe.'],'validation messages remain useful');
ob_start();apiUnhandledError(new TypeError('private credential must never be returned'));$data=json_decode(ob_get_clean(),true);
runtimeCheck($data['status']==='error' && strlen($data['error_reference'])===12 && strpos(json_encode($data),'credential')===false,'unhandled exception returns safe JSON and a support reference');
require __DIR__.'/../../lib/rentacar_api.php';
class CatalogCountingPDO extends PDO {
    public $catalogReads=0;
    public function query($query,?int $fetchMode=null,...$args):PDOStatement|false { if (strpos($query,'SHOW ')===0) $this->catalogReads++; return $fetchMode===null ? parent::query($query) : parent::query($query,$fetchMode,...$args); }
}
$pdo=new CatalogCountingPDO('mysql:host=127.0.0.1;port=33307;dbname=ototag_rental_regression;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->exec("DELETE FROM ototag_schema_migrations WHERE version='rental_schema_v2'");
rentalEnsureSchema($pdo);$before=$pdo->catalogReads;
rentalEnsureSchema($pdo);rentalEnsureSchema($pdo);
runtimeCheck($before>0 && $pdo->catalogReads===$before,'subsequent rental requests perform zero schema catalog scans');
$pdo->exec("DELETE FROM ototag_schema_migrations WHERE version='runtime_failure_fixture'");
try { apiSchemaMigration($pdo,'runtime_failure_fixture',function(){throw new RuntimeException('test');}); } catch (RuntimeException $e) {}
$check=$pdo->prepare('SELECT version FROM ototag_schema_migrations WHERE version=?');$check->execute(['runtime_failure_fixture']);
runtimeCheck(!$check->fetchColumn(),'failed migration is never marked as completed');
echo "\n$count runtime and migration checks passed.\n";
