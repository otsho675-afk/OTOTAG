<?php
// Only uses a dedicated localhost database; concurrent workers call production rules.
require __DIR__.'/../../lib/rental_rules.php';
require __DIR__.'/../../lib/purchase_verification.php';
require __DIR__.'/../../lib/service_matching.php';
function connection() {
    return new PDO('mysql:host=127.0.0.1;port=33307;dbname=ototag_service_regression;charset=utf8mb4','root','',
        [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,PDO::ATTR_EMULATE_PREPARES=>false]);
}
if (($argv[1] ?? '')==='worker') {
    $input=json_decode($argv[2],true); $pdo=connection();
    while (microtime(true)<$input['start']) usleep(1000);
    try {
        if ($input['action']==='accept') $result=serviceAcceptOffer($pdo,['user_id'=>$input['customer'],'user_type'=>'customer'],
            ['job_id'=>$input['job'],'bid_id'=>$input['bid'],'provider_id'=>$input['provider'],'amount'=>$input['amount'] ?? '500.0','offer_version'=>$input['version'] ?? 0]);
        elseif ($input['action']==='reject') $result=serviceRejectOffer($pdo,$input['bid']);
        else $result=serviceCancelJob($pdo,$input['job'],'searching');
        echo json_encode(['code'=>200,'result'=>$result]);
    } catch (DomainException $e) { echo json_encode(['code'=>409,'message'=>$e->getMessage()]); }
    exit;
}
$admin=new PDO('mysql:host=127.0.0.1;port=33307','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$admin->exec('CREATE DATABASE IF NOT EXISTS ototag_service_regression CHARACTER SET utf8mb4');
$pdo=connection();
foreach (['bids','jobs','users'] as $table) $pdo->exec("DROP TABLE IF EXISTS `$table`");
$pdo->exec("CREATE TABLE users(id INT PRIMARY KEY,user_type VARCHAR(20),status VARCHAR(20) DEFAULT 'active',city VARCHAR(50) DEFAULT 'Konya',service_category VARCHAR(20) DEFAULT 'mechanic',is_suspended INT DEFAULT 0,lat DOUBLE DEFAULT 37.87,lng DOUBLE DEFAULT 32.48,created_at DATETIME DEFAULT CURRENT_TIMESTAMP,subscription_end_date DATETIME NULL) ENGINE=InnoDB");
$pdo->exec("CREATE TABLE jobs(id INT PRIMARY KEY,customer_id INT,provider_id INT NULL,service_type VARCHAR(20) DEFAULT 'mechanic',city VARCHAR(50) DEFAULT 'Konya',status VARCHAR(30) DEFAULT 'searching',latitude DOUBLE DEFAULT 37.87,longitude DOUBLE DEFAULT 32.48,search_radius INT DEFAULT 50,agreed_price DECIMAL(10,2),match_code VARCHAR(10)) ENGINE=InnoDB");
$pdo->exec("CREATE TABLE bids(id INT PRIMARY KEY,job_id INT,provider_id INT,amount DECIMAL(10,2) DEFAULT 500,status VARCHAR(20) DEFAULT 'pending',last_bidder VARCHAR(20) DEFAULT 'provider',negotiation_count INT DEFAULT 0) ENGINE=InnoDB");
$pdo->exec("INSERT INTO users(id,user_type) VALUES (1,'customer'),(2,'customer'),(10,'provider'),(11,'provider')");
$count=0;
function verify($ok,$label) { global $count; if (!$ok) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
function resetOffers() {
    global $pdo;
    $pdo->exec('DELETE FROM bids'); $pdo->exec('DELETE FROM jobs');
    $pdo->exec('INSERT INTO jobs(id,customer_id) VALUES(1,1),(2,2)');
    $pdo->exec('INSERT INTO bids(id,job_id,provider_id) VALUES(1,1,10),(2,1,11),(3,2,10)');
}
function parallel($requests) {
    $handles=[]; $start=microtime(true)+0.4;
    foreach ($requests as $request) {
        $process=proc_open([PHP_BINARY,__FILE__,'worker',json_encode($request+['start'=>$start])],[1=>['pipe','w'],2=>['pipe','w']],$pipes);
        $handles[]=[$process,$pipes];
    }
    $results=[];
    foreach ($handles as [$process,$pipes]) {
        $out=stream_get_contents($pipes[1]); $error=stream_get_contents($pipes[2]);
        fclose($pipes[1]); fclose($pipes[2]); $code=proc_close($process);
        $data=json_decode($out,true);
        if ($code!==0 || !$data) throw new RuntimeException('Worker failed: '.$out.' '.$error);
        $results[]=$data;
    }
    return $results;
}
$accept=['action'=>'accept','customer'=>1,'job'=>1,'bid'=>1,'provider'=>10];
for ($iteration=0;$iteration<5;$iteration++) {
    resetOffers();
    $results=parallel([$accept,array_replace($accept,['bid'=>2,'provider'=>11])]);
    $codes=array_column($results,'code'); sort($codes);
    verify($codes===[200,409],"two providers / one job: exactly one match ($iteration)");
    verify((int)$pdo->query("SELECT COUNT(*) FROM bids WHERE job_id=1 AND status='accepted'")->fetchColumn()===1,'one accepted bid');
    resetOffers();
    $results=parallel([$accept,array_replace($accept,['customer'=>2,'job'=>2,'bid'=>3])]);
    $codes=array_column($results,'code'); sort($codes);
    verify($codes===[200,409],"one provider / two jobs: exactly one match ($iteration)");
    verify((int)$pdo->query("SELECT COUNT(*) FROM jobs WHERE provider_id=10 AND status='matched'")->fetchColumn()===1,'provider has one active job');
    resetOffers();
    $results=parallel([$accept,['action'=>'cancel','job'=>1]]);
    $codes=array_column($results,'code'); sort($codes);
    verify($codes===[200,409],"stale cancellation cannot override acceptance ($iteration)");
    $status=$pdo->query('SELECT status FROM jobs WHERE id=1')->fetchColumn();
    $bidStatus=$pdo->query('SELECT status FROM bids WHERE id=1')->fetchColumn();
    verify(($status==='matched' && $bidStatus==='accepted') || ($status==='cancelled' && $bidStatus==='cancelled'),'job and bid terminal states agree');
    resetOffers();
    $results=parallel([$accept,['action'=>'reject','bid'=>1]]);
    $codes=array_column($results,'code'); sort($codes);
    verify($codes===[200,409],"accept/reject race cannot corrupt a matched bid ($iteration)");
}
resetOffers();
verify(parallel([array_replace($accept,['amount'=>'600'])])[0]['code']===409,'changed amount is rejected');
verify(parallel([array_replace($accept,['version'=>1])])[0]['code']===409,'changed version is rejected');
verify(parallel([$accept])[0]['code']===200,'equivalent decimal amount is accepted');
$repeat=parallel([$accept])[0];
verify($repeat['code']===200 && $repeat['result']['repeated']===true,'lost response retry returns original match');
echo "\n$count service matching checks passed.\n";
