<?php
// Run after rental_reputation_test.php and api_entry_test.php, in the isolated local database only.
require __DIR__.'/../../lib/rentacar_api.php';
function subCheck($ok,$label) { global $count; if (!$ok) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
function subApi($action,$id,$role,$params=[],$get=false) {
    $input=['action'=>$action,'actor'=>['user_id'=>$id,'user_type'=>$role],$get?'get':'post'=>$params,'method'=>$get?'GET':'POST'];
    $process=proc_open([PHP_BINARY,__DIR__.'/rental_worker.php',json_encode($input)],[1=>['pipe','w'],2=>['pipe','w']],$pipes);
    $text=stream_get_contents($pipes[1]); $error=stream_get_contents($pipes[2]); fclose($pipes[1]); fclose($pipes[2]); proc_close($process);
    $result=json_decode($text,true); if (!$result) throw new RuntimeException('Invalid test response '.$error); return $result;
}
$pdo=new PDO('mysql:host=127.0.0.1;port=33307;dbname=ototag_rental_regression;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$count=0;
ensureBusinessSubscriptionSchema($pdo);
try {
    $pdo->exec("INSERT INTO users(id,name,city,user_type,created_at,subscription_end_date,map_link) VALUES
        (700,'Sub Customer','Konya','customer',NOW(),NULL,NULL),
        (701,'Expired Firm','Konya','rentacar',DATE_SUB(NOW(),INTERVAL 40 DAY),NULL,'https://maps.app.goo.gl/subTest'),
        (702,'Trial Firm','Konya','rentacar',NOW(),NULL,'https://maps.app.goo.gl/subTest'),
        (703,'Paid Firm','Konya','rentacar',DATE_SUB(NOW(),INTERVAL 60 DAY),DATE_ADD(NOW(),INTERVAL 1 DAY),'https://maps.app.goo.gl/subTest'),
        (704,'Expired Paid','Konya','rentacar',DATE_SUB(NOW(),INTERVAL 60 DAY),DATE_SUB(NOW(),INTERVAL 1 DAY),'https://maps.app.goo.gl/subTest'),
        (705,'Unknown Start','Konya','rentacar',NULL,NULL,'https://maps.app.goo.gl/subTest'),
        (706,'Provider','Konya','provider',DATE_SUB(NOW(),INTERVAL 60 DAY),NULL,NULL)");
    $insert=$pdo->prepare("INSERT INTO rentacar_listings(company_id,city,brand,model,car_brand_model,daily_price,status) VALUES (?,'Konya','AccessTest','Trial','AccessTest Trial',100,'active')");
    $ids=[]; foreach ([701,702,703,704,705] as $id) { $insert->execute([$id]); $ids[$id]=(int)$pdo->lastInsertId(); }
    $result=subApi('get_rentacar_listings',700,'customer',['brand'=>'AccessTest','model'=>'Trial'],true);
    if (($result['http'] ?? 0)!==200) throw new RuntimeException(json_encode($result));
    subCheck(array_column($result['listings'],'company_id')==[703,702],'only paid or trial firms appear in customer matches');
    subCheck(subApi('get_rentacar_listings',701,'rentacar',[],true)['subscription']['can_work']===false,'expired owner still sees fleet with subscription status');
    subCheck(subApi('get_rentacar_listings',702,'rentacar',[],true)['subscription']['is_trial']===true,'new firm gets existing 30 day business trial');
    subCheck(count(subApi('get_rentacar_company_profile',701,'rentacar',['company_id'=>701],true)['reviews'])===0,'expired firm retains reputation access');
    subCheck(subApi('get_rentacar_company_profile',700,'customer',['company_id'=>701],true)['company']['available']===false,'public profile marks expired firm unavailable without exposing subscription data');
    $fields=['brand'=>'Renault','model'=>'Clio','plate'=>'42 SUB 701','model_year'=>'2024','daily_price'=>'100','description'=>'Test'];
    subCheck(subApi('create_rentacar_listing',701,'rentacar',$fields)['http']===402,'expired firm cannot create a listing');
    subCheck(subApi('reserve_rentacar_listing',700,'customer',['listing_id'=>$ids[701],'listing_version'=>1,'rent_days'=>1,'total_budget'=>'100'])['http']===402,'stale expired listing cannot create reservation');
    subCheck(subApi('place_rentacar_bid',700,'customer',['listing_id'=>$ids[704],'rent_days'=>1,'total_budget'=>'100'])['http']===402,'expired paid membership cannot receive offers');
    $offer=subApi('place_rentacar_bid',700,'customer',['listing_id'=>$ids[702],'rent_days'=>1,'total_budget'=>'100']);
    subCheck($offer['http']===201,'active trial receives customer offer');
    $pdo->exec('UPDATE users SET created_at=DATE_SUB(NOW(),INTERVAL 60 DAY) WHERE id=702');
    subCheck(subApi('accept_rentacar_bid',702,'rentacar',['bid_id'=>$offer['bid_id'],'offer_version'=>1])['http']===402,'subscription rechecked at offer acceptance');
    subCheck(subApi('counter_rentacar_bid',702,'rentacar',['bid_id'=>$offer['bid_id'],'offer_version'=>1,'amount'=>'90'])['http']===402,'expired firm cannot counter offer');
    subCheck(subApi('delete_rentacar_bid',700,'customer',['bid_id'=>$offer['bid_id'],'offer_version'=>1])['http']===200,'customer can withdraw offer after firm expiry');
    $booking=subApi('reserve_rentacar_listing',700,'customer',['listing_id'=>$ids[703],'listing_version'=>1,'rent_days'=>1,'total_budget'=>'100']);
    subCheck($booking['http']===201,'paid firm creates reservation');
    $pdo->exec('UPDATE users SET subscription_end_date=DATE_SUB(NOW(),INTERVAL 1 DAY) WHERE id=703');
    $bid=$pdo->query('SELECT id,offer_version FROM rentacar_bids WHERE job_id='.(int)$booking['job_id'])->fetch(PDO::FETCH_ASSOC);
    subCheck(subApi('complete_rentacar_booking',703,'rentacar',['bid_id'=>$bid['id'],'offer_version'=>$bid['offer_version']])['http']===200,'existing reservation can finish after membership expiry');
    subCheck(count(subApi('get_rentacar_history',703,'rentacar',[],true)['history'])===1,'expired firm keeps job history');
    foreach ([[700,'customer'],[703,'rentacar']] as [$id,$role]) subCheck(subApi('report_rentacar_booking',$id,$role,['job_id'=>$booking['job_id'],'subject'=>'Ödeme anlaşmazlığı','message'=>'Abonelikten bağımsız anlaşmazlık bildirimi'])['http']===200,'complaints remain available after expiry for '.$role);

    // Trusted verification fixture exercises the persistence path; it does not bypass remote verification in api.php.
    $expiry=date('Y-m-d H:i:s',time()+86400*8); $verified=['verified_transaction_id'=>'business-test-order-1','verified_expiry'=>$expiry];
    $paid=applyVerifiedBusinessPurchase($pdo,701,'google','provider_monthly_subscription','test-business-receipt',$verified);
    subCheck($paid['subscription_end_date']===$expiry,'Rent A Car uses exact verified store expiry');
    subCheck($pdo->query("SELECT user_type FROM in_app_purchases WHERE order_id='business-test-order-1'")->fetchColumn()==='rentacar','purchase ledger records firm role correctly');
    applyVerifiedBusinessPurchase($pdo,701,'google','provider_monthly_subscription','test-business-receipt',$verified);
    subCheck((int)$pdo->query("SELECT COUNT(*) FROM in_app_purchases WHERE order_id='business-test-order-1'")->fetchColumn()===1,'duplicate restore never duplicates purchase or adds days');
    $renewal=['verified_transaction_id'=>'business-test-order-2','verified_expiry'=>date('Y-m-d H:i:s',time()+86400*15)];
    applyVerifiedBusinessPurchase($pdo,701,'google','provider_monthly_subscription','test-business-receipt',$renewal);
    try { applyVerifiedBusinessPurchase($pdo,704,'google','provider_monthly_subscription','test-business-receipt',['verified_transaction_id'=>'business-test-order-3','verified_expiry'=>$expiry]); subCheck(false,'token ownership'); }
    catch (PurchaseOwnershipException $e) { subCheck(true,'renewal order change cannot transfer same Google token to another user'); }
    $restored=applyVerifiedBusinessPurchase($pdo,701,'google','provider_monthly_subscription','test-business-receipt',$verified);
    subCheck($restored['subscription_end_date']===$renewal['verified_expiry'],'restoring older receipt cannot shorten verified renewal');
    subCheck(subApi('create_rentacar_listing',701,'rentacar',$fields)['http']===201,'renewed firm can add listings again');
    $apple=['verified_transaction_id'=>'business-test-apple','verified_expiry'=>$expiry];
    applyVerifiedBusinessPurchase($pdo,706,'apple','ototag_provider_monthly','test-apple',$apple);
    subCheck($pdo->query("SELECT user_type FROM in_app_purchases WHERE order_id='business-test-apple'")->fetchColumn()==='provider','existing provider billing remains supported');
    try { applyVerifiedBusinessPurchase($pdo,704,'apple','ototag_provider_monthly','other-receipt',$apple); subCheck(false,'Apple ownership'); }
    catch (PurchaseOwnershipException $e) { subCheck(true,'Apple transaction cannot be restored to another account'); }
    foreach ([['verified_transaction_id'=>'bad-expiry','verified_expiry'=>date('Y-m-d H:i:s',time()-1)],['verified_expiry'=>$expiry]] as $bad) {
        try { applyVerifiedBusinessPurchase($pdo,701,'google','provider_monthly_subscription','bad',$bad); subCheck(false,'invalid receipt'); }
        catch (InvalidArgumentException $e) { subCheck(true,'expired or transactionless verification denied'); }
    }
    try { applyVerifiedBusinessPurchase($pdo,701,'apple','customer_premium_monthly','bad',$apple); subCheck(false,'wrong product'); }
    catch (InvalidArgumentException $e) { subCheck(true,'customer premium cannot unlock business membership'); }
    $insert=$pdo->prepare("INSERT INTO rentacar_listings(company_id,city,brand,model,car_brand_model,daily_price,status) VALUES (701,'Konya','PageTest','Trial','PageTest Trial',?,'active')");
    for ($i=0;$i<55;$i++) $insert->execute([100+intdiv($i,3)]);
    $seen=[];
    for ($page=1;$page<=5;$page++) {
        $result=subApi('get_rentacar_listings',700,'customer',['brand'=>'PageTest','model'=>'Trial','page'=>$page,'page_size'=>12],true);
        subCheck($result['page']===$page && $result['total']===55 && $result['total_pages']===5,'bounded page '.$page.' has exact total');
        $current=array_column($result['listings'],'id'); subCheck(!array_intersect($seen,$current),'page '.$page.' has no duplicate listing'); $seen=array_merge($seen,$current);
    }
    subCheck(count($seen)===55,'all listings are accessible across pages');
    subCheck(subApi('get_rentacar_listings',700,'customer',['brand'=>'PageTest','page'=>999],true)['page']===5,'out of range page clamps to last after deletion');
    subCheck(subApi('get_rentacar_listings',700,'customer',['page_size'=>10000],true)['http']===422,'unbounded page size rejected');
    subCheck(subApi('get_rentacar_listings',700,'customer',['page'=>-1],true)['http']===422,'negative page rejected');
    subCheck(subApi('get_rentacar_listings',700,'customer',['brand'=>'PageTest','total_budget'=>'101','rent_days'=>2],true)['total']===0,'pagination count still respects total budget multiplied by days');
    echo "\n$count subscription and pagination checks passed.\n";
} finally {
    $pdo->exec('DELETE FROM tickets WHERE customer_id=700'); $pdo->exec('DELETE FROM rental_events WHERE company_id BETWEEN 701 AND 706 OR customer_id=700');
    $pdo->exec('DELETE FROM rentacar_bids WHERE customer_id=700'); $pdo->exec('DELETE FROM jobs WHERE customer_id=700');
    $pdo->exec('DELETE FROM rentacar_listings WHERE company_id BETWEEN 701 AND 706'); $pdo->exec('DELETE FROM in_app_purchases WHERE user_id BETWEEN 701 AND 706');
    $pdo->exec('DELETE FROM notifications WHERE user_id BETWEEN 700 AND 706'); $pdo->exec('DELETE FROM users WHERE id BETWEEN 700 AND 706');
}
