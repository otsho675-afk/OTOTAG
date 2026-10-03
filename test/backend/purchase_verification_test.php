<?php
require __DIR__.'/../../lib/purchase_verification.php';
$count=0;
function checkReceipt($condition,$label) { global $count; if (!$condition) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
$now=1800000000000; $expiry=$now+86400000;
$google=['expiryTimeMillis'=>(string)$expiry,'paymentState'=>1,'orderId'=>'test-order'];
checkReceipt(normalizeGoogleSubscription($google,$now)['verified_transaction_id']==='test-order','Google verified order is authoritative');
checkReceipt(normalizeGoogleSubscription($google,$now)['verified_expiry']===date('Y-m-d H:i:s',intdiv($expiry,1000)),'Google real expiry preserved');
checkReceipt(normalizeGoogleSubscription(array_replace($google,['expiryTimeMillis'=>$now-1]),$now)===false,'expired Google subscription denied');
checkReceipt(normalizeGoogleSubscription(array_replace($google,['paymentState'=>0]),$now)===false,'pending Google payment denied');
checkReceipt(normalizeGoogleSubscription(array_replace($google,['cancelReason'=>3]),$now)===false,'revoked Google subscription denied');
checkReceipt(normalizeGoogleSubscription(array_replace($google,['paymentState'=>2]),$now)!==false,'active Google trial allowed');
$transaction=['product_id'=>'ototag_premium_monthly','expires_date_ms'=>(string)$expiry,'transaction_id'=>'apple-order'];
$apple=['status'=>0,'receipt'=>['bundle_id'=>'com.oto.tag','in_app'=>[$transaction]],'latest_receipt_info'=>[]];
checkReceipt(normalizeAppleSubscription($apple,'ototag_premium_monthly','com.oto.tag',$now)['verified_transaction_id']==='apple-order','Apple matching product verified');
checkReceipt(normalizeAppleSubscription($apple,'diagnostic_monthly_100tl','com.oto.tag',$now)===false,'unrelated Apple product cannot unlock subscription');
checkReceipt(normalizeAppleSubscription($apple,'ototag_premium_monthly','wrong.app',$now)===false,'wrong Apple bundle denied');
$cancelled=$apple; $cancelled['latest_receipt_info']=[array_replace($transaction,['expires_date_ms'=>$expiry+1000,'cancellation_date_ms'=>$now-1])];
checkReceipt(normalizeAppleSubscription($cancelled,'ototag_premium_monthly','com.oto.tag',$now)===false,'refunded latest Apple renewal denied');
checkReceipt(normalizeAppleSubscription($apple,'ototag_premium_monthly','com.oto.tag',$expiry)===false,'expired Apple subscription denied');
checkReceipt(purchaseExpectedProduct('activate_premium','google')==='customer_premium_monthly','premium matches actual Android product');
checkReceipt(purchaseExpectedProduct('activate_premium','apple')==='ototag_premium_monthly','premium matches actual Apple product');
checkReceipt(purchaseExpectedProduct('renew_provider_subscription','apple')==='ototag_provider_monthly','provider matches actual Apple product');
checkReceipt(purchaseExpectedProduct('activate_premium','unknown')===null,'unknown purchase platform denied');
echo "\n$count purchase checks passed.\n";
