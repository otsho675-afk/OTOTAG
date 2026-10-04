<?php
require __DIR__.'/../../lib/rental_rules.php';
$count=0;
function check($condition,$label) { global $count; if (!$condition) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
function worker($action,$id,$role,$params=[],$get=false) {
    $input=['action'=>$action,'actor'=>['user_id'=>$id,'user_type'=>$role],$get?'get':'post'=>$params,'method'=>$get?'GET':'POST'];
    $pipes=[];
    $process=proc_open([PHP_BINARY,__DIR__.'/rental_worker.php',json_encode($input)], [1=>['pipe','w'],2=>['pipe','w']],$pipes);
    return [$process,$pipes];
}
function result($handle) {
    [$process,$pipes]=$handle;
    $output=stream_get_contents($pipes[1]); $error=stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]); proc_close($process);
    $data=json_decode($output,true);
    if (!$data) throw new RuntimeException('Invalid response: '.$output.' '.$error);
    return $data;
}
function callApi($action,$id,$role,$params=[],$get=false) { return result(worker($action,$id,$role,$params,$get)); }
function outboxPayloads() {
    global $pdo;
    try {
        $rows=$pdo->query('SELECT payload FROM notification_outbox ORDER BY id')->fetchAll(PDO::FETCH_COLUMN);
    } catch (Throwable $e) { return []; }
    return array_values(array_filter(array_map(function($payload){ return json_decode($payload,true); },$rows)));
}
function outboxTargets($title=null,$bidId=null,$jobId=null,$after=0) {
    $targets=[];
    $payloads=array_slice(outboxPayloads(),$after);
    foreach ($payloads as $payload) {
        if ($title!==null && ($payload['headings']['tr'] ?? '')!==$title) continue;
        if ($bidId!==null && (string)($payload['data']['bid_id'] ?? '')!==(string)$bidId) continue;
        if ($jobId!==null && (string)($payload['data']['job_id'] ?? '')!==(string)$jobId) continue;
        $targets=array_merge($targets,$payload['include_aliases']['external_id'] ?? []);
    }
    return array_values(array_unique(array_map('strval',$targets)));
}
$pdo=new PDO('mysql:host=127.0.0.1;port=33307;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
// Destructive fixtures are confined to this explicitly named temporary database.
$pdo->exec('CREATE DATABASE IF NOT EXISTS ototag_rental_regression CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci');
$pdo->exec('USE ototag_rental_regression');
foreach (['ototag_schema_migrations','vehicle_reminder_deliveries','notification_outbox','rental_reviews','rental_events','tickets','notifications','jobs','rentacar_bids','rentacar_listings','users'] as $table) $pdo->exec("DROP TABLE IF EXISTS `$table`");
$pdo->exec("CREATE TABLE users (id INT PRIMARY KEY,name VARCHAR(100),phone VARCHAR(30) DEFAULT '',city VARCHAR(100),user_type VARCHAR(30),status VARCHAR(30) DEFAULT 'active',is_suspended INT DEFAULT 0,created_at DATETIME DEFAULT CURRENT_TIMESTAMP,rental_lat DECIMAL(10,7) DEFAULT 37.8700000,rental_lng DECIMAL(10,7) DEFAULT 32.4800000,rental_address VARCHAR(500) DEFAULT 'Konya teslim adresi') ENGINE=InnoDB");
$pdo->exec("CREATE TABLE tickets (id INT AUTO_INCREMENT PRIMARY KEY,job_id INT,customer_id INT,provider_id INT,subject VARCHAR(255),message TEXT,status VARCHAR(30) DEFAULT 'open',created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB");
$pdo->exec("CREATE TABLE rentacar_listings (id INT AUTO_INCREMENT PRIMARY KEY,company_id INT,city VARCHAR(100),car_brand_model VARCHAR(255),daily_price DECIMAL(10,2),description TEXT,photo VARCHAR(255),status VARCHAR(50) DEFAULT 'active',created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB");
$pdo->exec("CREATE TABLE rentacar_bids (id INT AUTO_INCREMENT PRIMARY KEY,listing_id INT,customer_id INT,amount DECIMAL(10,2),rent_days INT,status VARCHAR(50) DEFAULT 'pending',created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB");
$pdo->exec("CREATE TABLE jobs (id INT AUTO_INCREMENT PRIMARY KEY,customer_id INT,provider_id INT,service_type VARCHAR(30),status VARCHAR(30),city VARCHAR(100),agreed_price DECIMAL(10,2),created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,latitude DECIMAL(10,7) DEFAULT 0,longitude DECIMAL(10,7) DEFAULT 0,before_photo VARCHAR(255),after_photo VARCHAR(255)) ENGINE=InnoDB");
$pdo->exec('CREATE TABLE notifications (id INT AUTO_INCREMENT PRIMARY KEY,user_id INT,title VARCHAR(100),message TEXT) ENGINE=InnoDB');
$pdo->exec("INSERT INTO users (id,name,city,user_type) VALUES (1,'Müşteri A','Konya','customer'),(2,'Müşteri B','Konya','customer'),(3,'Başka Şehir','Ankara','customer'),(10,'Konya Firma','Konya','rentacar'),(11,'Ankara Firma','Ankara','rentacar'),(12,'Başka Firma','Konya','rentacar')");
$pdo->exec("INSERT INTO rentacar_listings (company_id,city,car_brand_model,daily_price) VALUES (10,'Konya','Fiat Egea',1000.25),(11,'Ankara','Renault Clio',800),(12,'Konya','Fiat Egea',1200)");
check(rentalMoneyCents('1000,25')===100025,'money uses integer cents');
check(rentalMoneyText(rentalMoneyCents('1000.25')*3)==='3000.75','decimal total exact');
check(rentalSameCity(' İSTANBUL ','istanbul'),'Turkish city normalization');
check(!rentalSameCity('Bilinmiyor','Bilinmiyor'),'unknown city never matches');
foreach (['0','-1','1.234','1e3','abc'] as $bad) { try { rentalMoneyCents($bad); check(false,'invalid money'); } catch (InvalidArgumentException $e) { check(true,'reject money '.$bad); } }
check(callApi('get_rentacar_listings',0,'customer',[],true)['http']===401,'anonymous denied');
$cars=callApi('get_rentacar_listings',1,'customer',['city'=>'Ankara'],true);
check(count($cars['listings'])===2 && $cars['city']==='Konya','caller city cannot bypass matching');
$cars=callApi('get_rentacar_listings',1,'customer',['brand'=>'Fiat','model'=>'Egea','max_budget'=>'1100'],true);
check(count($cars['listings'])===1,'brand model and daily budget filter legacy listings');
check(callApi('get_rentacar_listings',10,'rentacar',['company_id'=>11],true)['http']===403,'firm cannot read rival offers');
check(callApi('place_rentacar_bid',3,'customer',['listing_id'=>1,'rent_days'=>3,'total_budget'=>'5000'])['http']===403,'cross-city request denied');
check(callApi('place_rentacar_bid',1,'customer',['listing_id'=>1,'rent_days'=>0,'total_budget'=>'5000'])['http']===422,'invalid duration denied');
$first=callApi('place_rentacar_bid',1,'customer',['listing_id'=>1,'rent_days'=>3,'total_budget'=>'5000','amount'=>'1']);
check($first['amount']==='5000.00','client amount ignored and customer budget becomes the initial offer');
$bid=$first['bid_id'];
check(outboxTargets(null,$bid)===['10'],'customer offer queues OneSignal push to rental company');
check(callApi('place_rentacar_bid',1,'customer',['listing_id'=>1,'rent_days'=>3,'total_budget'=>'5000'])['bid']['id']===$bid,'duplicate request idempotent');
check(callApi('accept_rentacar_bid',1,'customer',['bid_id'=>$bid,'offer_version'=>1])['http']===409,'own offer cannot be accepted');
check(callApi('counter_rentacar_bid',12,'rentacar',['bid_id'=>$bid,'offer_version'=>1,'amount'=>2500])['http']===403,'unrelated firm cannot counter');
$before=count(outboxPayloads());
check(callApi('counter_rentacar_bid',10,'rentacar',['bid_id'=>$bid,'offer_version'=>1,'amount'=>'2800.50'])['http']===200,'firm counter offer');
check(outboxTargets(null,$bid,null,$before)===['1'],'rental company counteroffer queues OneSignal push to customer');
check(callApi('accept_rentacar_bid',1,'customer',['bid_id'=>$bid,'offer_version'=>1])['http']===409,'stale offer cannot be accepted');
$before=count(outboxPayloads());
check(callApi('counter_rentacar_bid',1,'customer',['bid_id'=>$bid,'offer_version'=>2,'amount'=>'2700'])['http']===200,'customer counter offer');
check(outboxTargets(null,$bid,null,$before)===['10'],'customer counteroffer queues OneSignal push to rental company');
$second=callApi('place_rentacar_bid',2,'customer',['listing_id'=>1,'rent_days'=>4,'total_budget'=>'6000']);
$parallelA=worker('accept_rentacar_bid',10,'rentacar',['bid_id'=>$bid,'offer_version'=>3]);
$parallelB=worker('accept_rentacar_bid',10,'rentacar',['bid_id'=>$second['bid_id'],'offer_version'=>1]);
$a=result($parallelA); $b=result($parallelB);
check(($a['http']===200 && $b['http']===409) || ($a['http']===409 && $b['http']===200),'concurrent acceptance reserves vehicle exactly once');
check((int)$pdo->query('SELECT COUNT(*) FROM jobs')->fetchColumn()===1,'one matching job only');
$accepted=$pdo->query("SELECT * FROM rentacar_bids WHERE status='accepted'")->fetch(PDO::FETCH_ASSOC);
$job=$pdo->query('SELECT * FROM jobs')->fetch(PDO::FETCH_ASSOC);
check($job['agreed_price']===$accepted['amount'] && $job['city']==='Konya','job uses final accepted price and verified city');
check(outboxTargets(null,$accepted['id'],$job['id'])===[(string)$accepted['customer_id']],'accepted rental queues OneSignal push to customer');
$repeat=callApi('accept_rentacar_bid',10,'rentacar',['bid_id'=>$accepted['id'],'offer_version'=>$accepted['offer_version']]);
check($repeat['job_id']===(int)$job['id'] && (int)$pdo->query('SELECT COUNT(*) FROM jobs')->fetchColumn()===1,'repeat acceptance returns same booking');
check(callApi('place_rentacar_bid',2,'customer',['listing_id'=>1,'rent_days'=>2,'total_budget'=>'6000'])['http']===409,'reserved vehicle cannot receive new requests');
check(callApi('get_rentacar_booking',(int)$accepted['customer_id'],'customer',['job_id'=>$job['id']],true)['booking']['pickup_lat']===null,'pickup remains hidden before agreement');
check(callApi('report_rentacar_booking',(int)$accepted['customer_id'],'customer',['job_id'=>$job['id'],'subject'=>'Diğer','message'=>'Görüşme sırasında sorun yaşandı'])['http']===409,'complaint waits for completed or cancelled job');
check(callApi('agree_rentacar_booking',(int)$accepted['customer_id'],'customer',['bid_id'=>$accepted['id'],'offer_version'=>$accepted['offer_version']])['http']===409,'customer cannot self-confirm company agreement');
check(callApi('complete_rentacar_booking',10,'rentacar',['bid_id'=>$accepted['id'],'offer_version'=>$accepted['offer_version']])['http']===409,'completion requires agreement');
check(callApi('agree_rentacar_booking',10,'rentacar',['bid_id'=>$accepted['id'],'offer_version'=>$accepted['offer_version']])['http']===200,'company confirms agreement');
$accepted=$pdo->query('SELECT * FROM rentacar_bids WHERE id='.(int)$accepted['id'])->fetch(PDO::FETCH_ASSOC);
check(callApi('get_rentacar_booking',(int)$accepted['customer_id'],'customer',['job_id'=>$job['id']],true)['booking']['pickup_lat']!==null,'pickup opens after company agreement');
check(callApi('complete_rentacar_booking',10,'rentacar',['bid_id'=>$accepted['id'],'offer_version'=>$accepted['offer_version']])['http']===200,'firm completes agreed rental');
check($pdo->query('SELECT status FROM rentacar_listings WHERE id=1')->fetchColumn()==='active','returned vehicle available again');
check(callApi('place_rentacar_bid',2,'customer',['listing_id'=>1,'rent_days'=>1,'total_budget'=>'6000'])['http']===201,'new booking allowed after return');
$pdo->exec("UPDATE users SET city='Ankara' WHERE id=2");
$pending=$pdo->query("SELECT * FROM rentacar_bids WHERE customer_id=2 AND status='pending' ORDER BY id DESC LIMIT 1")->fetch(PDO::FETCH_ASSOC);
check(callApi('accept_rentacar_bid',10,'rentacar',['bid_id'=>$pending['id'],'offer_version'=>$pending['offer_version']])['http']===403,'city rechecked at acceptance after profile change');

$pdo->exec("UPDATE users SET city='Konya' WHERE id=2");
$sortedLowBudget=callApi('get_rentacar_listings',1,'customer',['total_budget'=>'3000','rent_days'=>3],true)['listings'];
check(count($sortedLowBudget)===2 && (int)$sortedLowBudget[0]['id']===1,'total budget sorts but does not hide over-budget vehicles');
$sortedExactBudget=callApi('get_rentacar_listings',1,'customer',['total_budget'=>'3000.75','rent_days'=>3],true)['listings'];
check(count($sortedExactBudget)===2 && (int)$sortedExactBudget[0]['id']===1,'exact total budget keeps matching vehicle first');
check(callApi('get_rentacar_listings',1,'customer',['total_budget'=>'3000'],true)['http']===422,'budget search requires duration');
check(callApi('place_rentacar_bid',1,'customer',['listing_id'=>1,'rent_days'=>3])['http']===422,'booking requires explicit customer budget');
$lowBudget=callApi('place_rentacar_bid',1,'customer',['listing_id'=>1,'rent_days'=>3,'total_budget'=>'3000','city'=>'Konya']);
check($lowBudget['http']===201 && $lowBudget['amount']==='3000.00','customer budget becomes the rental offer amount even when the listing total is higher');

$fields=['brand'=>'Renault','model'=>'Clio','plate'=>'42 TAG 403','model_year'=>'2024','daily_price'=>'900.50','description'=>'Otomatik'];
check(callApi('create_rentacar_listing',1,'customer',$fields)['http']===403,'customer cannot create rental listing');
$created=callApi('create_rentacar_listing',10,'rentacar',$fields);
check($created['http']===201,'firm creates its own listing');
$listingId=$created['listing_id'];
check(callApi('create_rentacar_listing',10,'rentacar',$fields)['http']===409,'duplicate normalized plate denied');
$edit=$fields+['listing_id'=>$listingId,'listing_version'=>1];
check(callApi('update_rentacar_listing',12,'rentacar',$edit)['http']===403,'rival cannot edit listing');
check(callApi('delete_rentacar_listing',12,'rentacar',['listing_id'=>$listingId,'listing_version'=>1])['http']===403,'rival cannot delete listing');
$offer=callApi('place_rentacar_bid',2,'customer',['listing_id'=>$listingId,'listing_version'=>1,'rent_days'=>3,'total_budget'=>'3000']);
check($offer['amount']==='3000.00','quote uses the customer budget as the offer amount');
check(callApi('counter_rentacar_bid',10,'rentacar',['bid_id'=>$offer['bid_id'],'offer_version'=>1,'amount'=>'3000.01'])['http']===422,'company counter cannot exceed customer budget');
$edit['daily_price']='950';
check(callApi('update_rentacar_listing',10,'rentacar',$edit)['http']===200,'owner edits vehicle price');
check($pdo->query('SELECT status FROM rentacar_bids WHERE id='.(int)$offer['bid_id'])->fetchColumn()==='rejected','price edit closes outdated pending quote');
check(callApi('update_rentacar_listing',10,'rentacar',$edit)['http']===409,'stale listing edit denied');
check(callApi('place_rentacar_bid',2,'customer',['listing_id'=>$listingId,'listing_version'=>1,'rent_days'=>3,'total_budget'=>'3000'])['http']===409,'stale customer card cannot request changed listing');
$offer=callApi('place_rentacar_bid',2,'customer',['listing_id'=>$listingId,'listing_version'=>2,'rent_days'=>3,'total_budget'=>'3000']);
$match=callApi('accept_rentacar_bid',10,'rentacar',['bid_id'=>$offer['bid_id'],'offer_version'=>1]);
check($match['http']===200 && $match['amount']==='3000.00','firm confirmation creates booking from customer offer amount');
$edit['listing_version']=3;
check(callApi('update_rentacar_listing',10,'rentacar',$edit)['http']===409,'rented vehicle cannot be edited');
check(callApi('delete_rentacar_listing',10,'rentacar',['listing_id'=>$listingId,'listing_version'=>3])['http']===409,'rented vehicle cannot be deleted');
check(callApi('agree_rentacar_booking',10,'rentacar',['bid_id'=>$offer['bid_id'],'offer_version'=>2])['http']===200,'firm confirms edited vehicle agreement');
check(callApi('complete_rentacar_booking',10,'rentacar',['bid_id'=>$offer['bid_id'],'offer_version'=>3])['http']===200,'firm returns edited vehicle');
$edit['listing_version']=4; $edit['model']='Megane';
check(callApi('update_rentacar_listing',10,'rentacar',$edit)['http']===200,'returned vehicle becomes editable');
$history=callApi('get_rentacar_bids',2,'customer',[],true)['bids'];
$past=array_values(array_filter($history,function($row) use($offer) { return (int)$row['id']===(int)$offer['bid_id']; }))[0];
check($past['car_brand_model']==='Renault Clio','accepted vehicle identity is retained after later edits');
$offer2=callApi('place_rentacar_bid',2,'customer',['listing_id'=>$listingId,'listing_version'=>5,'rent_days'=>1,'total_budget'=>'1000']);
check(callApi('delete_rentacar_listing',10,'rentacar',['listing_id'=>$listingId,'listing_version'=>5])['http']===200,'owner removes available listing');
check($pdo->query('SELECT status FROM rentacar_bids WHERE id='.(int)$offer2['bid_id'])->fetchColumn()==='rejected','deletion closes pending quotes');
check((int)$pdo->query('SELECT COUNT(*) FROM jobs WHERE id='.(int)$match['job_id'])->fetchColumn()===1,'deletion preserves completed rental history');
check(!array_filter(callApi('get_rentacar_listings',10,'rentacar',[],true)['listings'],function($row) use($listingId){return (int)$row['id']===$listingId;}),'deleted vehicle hidden from fleet');
check(callApi('delete_rentacar_listing',10,'rentacar',['listing_id'=>$listingId,'listing_version'=>5])['http']===200,'repeated deletion is idempotent');
check(callApi('create_rentacar_listing',10,'rentacar',$fields)['http']===201,'removed plate can be listed again');

check(callApi('update_rentacar_location',1,'customer',['latitude'=>37.87,'longitude'=>32.48,'address'=>'Konya teslim merkezi'])['http']===403,'customer cannot alter company pickup location');
check(callApi('update_rentacar_location',10,'rentacar',['latitude'=>91,'longitude'=>32.48,'address'=>'Konya teslim merkezi'])['http']===422,'invalid geographic coordinates denied');
check(callApi('update_rentacar_location',10,'rentacar',['latitude'=>0,'longitude'=>0,'address'=>'Konya teslim merkezi'])['http']===422,'empty placeholder coordinates denied');
check(callApi('update_rentacar_location',10,'rentacar',['latitude'=>37.87,'longitude'=>32.48,'address'=>'Konya teslim merkezi'])['http']===200,'firm stores fixed pickup location');
$pdo->exec("UPDATE users SET rental_lat=NULL,rental_lng=NULL,rental_address=NULL WHERE id=12");
check((bool)array_filter(callApi('get_rentacar_listings',1,'customer',[],true)['listings'],function($l){return (int)$l['company_id']===12;}),'same-city listings remain visible without separate pickup coordinates');
check(callApi('reserve_rentacar_listing',1,'customer',['listing_id'=>3,'listing_version'=>1,'rent_days'=>1,'total_budget'=>'1500'])['http']===422,'unconfigured company cannot be reserved through forged request');
$pdo->exec("UPDATE users SET map_link='https://maps.app.goo.gl/testLocation' WHERE id=12");
$mapOnly=callApi('reserve_rentacar_listing',1,'customer',['listing_id'=>3,'listing_version'=>1,'rent_days'=>1,'total_budget'=>'1500','pickup_map_link'=>'https://maps.app.goo.gl/forged']);
check($mapOnly['http']===201,'registered map link permits booking without coordinates or separate modal');
$mapBooking=callApi('get_rentacar_booking',1,'customer',['job_id'=>$mapOnly['job_id']],true)['booking'];
check($mapBooking['pickup_map_link']==='https://maps.app.goo.gl/testLocation' && $mapBooking['pickup_lat']===null,'booking snapshots registered map link and ignores client location');
$pdo->exec("UPDATE users SET map_link='https://maps.app.goo.gl/newLocation' WHERE id=12");
check(callApi('get_rentacar_booking',1,'customer',['job_id'=>$mapOnly['job_id']],true)['booking']['pickup_map_link']==='https://maps.app.goo.gl/testLocation','profile location change preserves agreed reservation location');
$mapBid=$pdo->query('SELECT id,offer_version FROM rentacar_bids WHERE job_id='.(int)$mapOnly['job_id'])->fetch(PDO::FETCH_ASSOC);
check(callApi('complete_rentacar_booking',12,'rentacar',['bid_id'=>$mapBid['id'],'offer_version'=>$mapBid['offer_version']])['http']===200,'map-link-only reservation completes normally');
foreach (['https://maps.app.goo.gl/a','https://share.google/qyjEIveuWA0VTv9xS','https://goo.gl/maps/a','https://www.google.com/maps/place/Konya','https://maps.apple.com/?q=Konya'] as $url) check(rentalMapLink($url)===$url,'valid shared map link accepted '.$url);
foreach (['javascript:alert(1)','https://www.google.com.evil.test/maps','https://evil.test','https://user@maps.app.goo.gl/a','http://maps.app.goo.gl/a','https://www.google.com/search?q=Konya','https://maps.app.goo.gl:8080/a','https://share.google/konya/maps','https://goo.gl/other'] as $url) { try { rentalMapLink($url); check(false,'unsafe link accepted'); } catch (InvalidArgumentException $e) { check(true,'unsafe map link rejected'); } }
check(callApi('reserve_rentacar_listing',3,'customer',['listing_id'=>1,'listing_version'=>3,'rent_days'=>3,'total_budget'=>'4000'])['http']===403,'automatic reservation cannot cross cities');
$pdo->exec("UPDATE rentacar_bids SET status='rejected' WHERE status='pending'");
$version=(int)$pdo->query('SELECT listing_version FROM rentacar_listings WHERE id=1')->fetchColumn();
$bookingParams=['listing_id'=>1,'listing_version'=>$version,'rent_days'=>3,'total_budget'=>'3000.75','amount'=>'1'];
$before=(int)$pdo->query('SELECT COUNT(*) FROM jobs')->fetchColumn();
$parallelA=worker('reserve_rentacar_listing',1,'customer',$bookingParams);
$parallelB=worker('reserve_rentacar_listing',2,'customer',$bookingParams);
$a=result($parallelA); $b=result($parallelB);
check(($a['http']===201 && $b['http']===409) || ($a['http']===409 && $b['http']===201),'simultaneous automatic reservations allocate vehicle exactly once');
check((int)$pdo->query('SELECT COUNT(*) FROM jobs')->fetchColumn()===$before+1,'automatic booking creates exactly one job without company approval');
$reserved=$pdo->query("SELECT * FROM rentacar_bids WHERE listing_id=1 AND status='accepted'")->fetch(PDO::FETCH_ASSOC);
$owner=(int)$reserved['customer_id']; $stranger=$owner===1?2:1;
$detail=callApi('get_rentacar_booking',$owner,'customer',['job_id'=>$reserved['job_id']],true);
check($detail['http']===200 && $detail['booking']['amount']==='3000.75','booking details use server price rather than supplied amount');
check($detail['booking']['pickup_address']==='Konya teslim merkezi' && $detail['booking']['reserved_at'] && $detail['booking']['expected_return_at'],'booking includes pickup snapshot and planned return');
check(callApi('get_rentacar_booking',$stranger,'customer',['job_id'=>$reserved['job_id']],true)['http']===403,'another customer cannot see reservation location');
check(callApi('get_rentacar_booking',12,'rentacar',['job_id'=>$reserved['job_id']],true)['http']===403,'another firm cannot see reservation');
check(callApi('get_rentacar_booking',10,'rentacar',['job_id'=>$reserved['job_id']],true)['http']===200,'own company can see reservation');
$retry=callApi('reserve_rentacar_listing',$owner,'customer',$bookingParams);
check($retry['http']===200 && $retry['job_id']===(int)$reserved['job_id'],'network retry returns existing reservation');
check((int)$pdo->query('SELECT COUNT(*) FROM jobs')->fetchColumn()===$before+1,'network retry does not duplicate booking');
check(callApi('update_rentacar_location',10,'rentacar',['latitude'=>37.9,'longitude'=>32.5,'address'=>'Yeni teslim merkezi Konya'])['http']===200,'firm can set pickup for future reservations');
$detail=callApi('get_rentacar_booking',$owner,'customer',['job_id'=>$reserved['job_id']],true)['booking'];
check($detail['pickup_address']==='Konya teslim merkezi' && (float)$detail['pickup_lat']===37.87,'existing pickup stays immutable after company changes location');
$report=['job_id'=>$reserved['job_id'],'subject'=>'Rezervasyona uyulmadı','message'=>'Firma rezervasyon saatinde aracı teslim etmedi.','customer_id'=>999,'provider_id'=>999];
check(callApi('report_rentacar_booking',$stranger,'customer',$report)['http']===403,'unrelated account cannot complain about reservation');
check(callApi('report_rentacar_booking',$owner,'customer',$report)['http']===409,'active matching cannot be reported before completion');
check(callApi('complete_rentacar_booking',$owner,'customer',['bid_id'=>$reserved['id'],'offer_version'=>$reserved['offer_version']])['http']===409,'customer cannot silently release reserved vehicle');
check(callApi('complete_rentacar_booking',10,'rentacar',['bid_id'=>$reserved['id'],'offer_version'=>$reserved['offer_version']])['http']===200,'company completes automatic booking after return');
check(callApi('get_rentacar_booking',$owner,'customer',['job_id'=>$reserved['job_id']],true)['booking']['job_status']==='completed','completed booking retains detail and pickup');
$tooShort=$report; $tooShort['message']='Kısa';
check(callApi('report_rentacar_booking',$owner,'customer',$tooShort)['http']===422,'complaint requires meaningful explanation');
$ticket=callApi('report_rentacar_booking',$owner,'customer',$report);
check($ticket['http']===200 && $ticket['ticket_id']>0,'customer creates reservation-linked admin complaint');
$stored=$pdo->query('SELECT * FROM tickets WHERE id='.(int)$ticket['ticket_id'])->fetch(PDO::FETCH_ASSOC);
check((int)$stored['customer_id']===$owner && (int)$stored['provider_id']===10 && (int)$stored['reporter_id']===$owner,'complaint participants are derived from reservation not client');
check(callApi('report_rentacar_booking',$owner,'customer',$report)['ticket_id']===$ticket['ticket_id'],'repeated open complaint does not duplicate tickets');
check(callApi('report_rentacar_booking',10,'rentacar',$report)['ticket_id']!==$ticket['ticket_id'],'company can report its own reservation separately');
$pdo->prepare("UPDATE tickets SET status='closed' WHERE job_id=?")->execute([$reserved['job_id']]);
$postJobReport=['job_id'=>$reserved['job_id'],'subject'=>'Ödeme anlaşmazlığı','message'=>'Kiralama tamamlandıktan sonra ücret konusunda anlaşmazlık yaşandı.'];
$postCustomer=callApi('report_rentacar_booking',$owner,'customer',$postJobReport);
$postCompany=callApi('report_rentacar_booking',10,'rentacar',$postJobReport);
check($postCustomer['http']===200 && $postCompany['http']===200 && $postCustomer['ticket_id']!==$postCompany['ticket_id'],'both parties may independently complain after completion');
check(callApi('report_rentacar_booking',$stranger,'customer',$postJobReport)['http']===403,'stranger cannot complain after completion');
$history=callApi('get_rentacar_history',$owner,'customer',['customer_id'=>$stranger],true)['history'];
check((bool)array_filter($history,function($r)use($reserved){return (int)$r['job_id']===(int)$reserved['job_id'];}),'customer history contains completed own booking');
check(!array_filter($history,function($r)use($owner){return (int)$r['customer_id']!==$owner;}),'history ignores forged customer ID and contains only actor records');
check((bool)array_filter(callApi('get_rentacar_history',10,'rentacar',[],true)['history'],function($r)use($reserved){return (int)$r['job_id']===(int)$reserved['job_id'];}),'firm history contains its completed booking');
$withdraw=callApi('place_rentacar_bid',$owner,'customer',['listing_id'=>3,'rent_days'=>1,'total_budget'=>'1500']);
$remove=['bid_id'=>$withdraw['bid_id'],'offer_version'=>1];
check(callApi('delete_rentacar_bid',$stranger,'customer',$remove)['http']===403,'another customer cannot remove offer');
check(callApi('delete_rentacar_bid',12,'rentacar',$remove)['http']===403,'firm cannot remove customer offer from customer list');
$stale=$remove; $stale['offer_version']=99;
check(callApi('delete_rentacar_bid',$owner,'customer',$stale)['http']===409,'stale removal cannot close changed offer');
check(callApi('delete_rentacar_bid',$owner,'customer',$remove)['http']===200,'customer removes and withdraws pending offer');
check(callApi('delete_rentacar_bid',$owner,'customer',$remove)['http']===200,'removing same offer again is idempotent');
check(!array_filter(callApi('get_rentacar_bids',$owner,'customer',[],true)['bids'],function($r)use($remove){return (int)$r['id']===(int)$remove['bid_id'];}),'removed offer no longer appears to customer');
check((bool)array_filter(callApi('get_rentacar_bids',12,'rentacar',[],true)['bids'],function($r)use($remove){return (int)$r['id']===(int)$remove['bid_id'] && $r['status']==='rejected';}),'firm retains cancellation record');
check(callApi('accept_rentacar_bid',12,'rentacar',$remove)['http']===409,'firm cannot accept removed offer');
$completedVersion=(int)$pdo->query('SELECT offer_version FROM rentacar_bids WHERE id='.(int)$reserved['id'])->fetchColumn();
check(callApi('delete_rentacar_bid',$owner,'customer',['bid_id'=>$reserved['id'],'offer_version'=>$completedVersion])['http']===200,'closed offer can be removed from customer offer list');
check((bool)array_filter(callApi('get_rentacar_history',$owner,'customer',[],true)['history'],function($r)use($reserved){return (int)$r['id']===(int)$reserved['id'];}),'removing closed offer preserves completed rental history');
check(callApi('get_rentacar_booking',$owner,'customer',['job_id'=>$reserved['job_id']],true)['http']===200,'removed offer retains booking access for review and complaints');
$activeVersion=(int)$pdo->query('SELECT listing_version FROM rentacar_listings WHERE id=3')->fetchColumn();
$activeTest=callApi('reserve_rentacar_listing',$owner,'customer',['listing_id'=>3,'listing_version'=>$activeVersion,'rent_days'=>1,'total_budget'=>'1500']);
$activeBid=$pdo->query('SELECT id,offer_version FROM rentacar_bids WHERE job_id='.(int)$activeTest['job_id'])->fetch(PDO::FETCH_ASSOC);
check(callApi('delete_rentacar_bid',$owner,'customer',['bid_id'=>$activeBid['id'],'offer_version'=>$activeBid['offer_version']])['http']===409,'active booking cannot be deleted or free a vehicle');
check(callApi('complete_rentacar_booking',12,'rentacar',['bid_id'=>$activeBid['id'],'offer_version'=>$activeBid['offer_version']])['http']===200,'active deletion rejection preserves valid completion');
// Bounded history pages on temporary records; remove these fixtures before reputation checks.
for($n=90000;$n<90055;$n++) {
    $pdo->exec("INSERT INTO jobs(id,customer_id,provider_id,service_type,status,city,agreed_price) VALUES($n,$owner,10,'rentacar','completed','Konya',1000)");
    $pdo->exec("INSERT INTO rentacar_bids(id,listing_id,customer_id,amount,rent_days,status,job_id) VALUES($n,1,$owner,1000,1,'completed',$n)");
}
$page=callApi('get_rentacar_history',$owner,'customer',[],true);
$older=callApi('get_rentacar_history',$owner,'customer',['before_id'=>$page['next_before_id']],true);
check(count($page['history'])===50 && $page['next_before_id']!==null,'history uses bounded pages');
check(!array_intersect(array_column($page['history'],'id'),array_column($older['history'],'id')) && count($older['history'])>=5,'history cursor reaches older jobs without duplicate rows');
$pdo->exec('DELETE FROM rentacar_bids WHERE id BETWEEN 90000 AND 90054'); $pdo->exec('DELETE FROM jobs WHERE id BETWEEN 90000 AND 90054');
echo "\n$count backend checks passed.\n";
