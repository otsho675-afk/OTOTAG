<?php
require __DIR__.'/../../lib/rental_rules.php';
require __DIR__.'/../../lib/registration_rules.php';
require __DIR__.'/../../lib/service_matching.php';
require __DIR__.'/../../lib/map_routing.php';
$count=0;
function ruleCheck($condition,$label) { global $count; if (!$condition) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
foreach (['0546 650 51 70','5466505170','+90 546 650 51 70','00905466505170'] as $phone) ruleCheck(registrationPhone($phone)==='05466505170','valid Turkish phone normalized');
foreach (['1','054665051700','05466505','09000000000','abcdef'] as $bad) {
    try { registrationPhone($bad); ruleCheck(false,'invalid phone accepted'); } catch (InvalidArgumentException $e) { ruleCheck(true,'invalid phone rejected'); }
}
ruleCheck(registrationCity('  İSTANBUL  ')==='İstanbul','city canonicalized');
try { registrationCity('Bilinmiyor'); ruleCheck(false,'unknown city'); } catch (InvalidArgumentException $e) { ruleCheck(true,'unknown city rejected'); }
$customer=['name'=>'Ali Veli','phone'=>'05466505170','city'=>'Konya','user_type'=>'customer'];
ruleCheck(registrationMissingFields($customer)===[],'verified social account still requires complete customer registration');
ruleCheck(in_array('phone',registrationMissingFields(array_replace($customer,['phone'=>'1'])),true),'invalid stored phone requires completion');
ruleCheck(in_array('city',registrationMissingFields(array_replace($customer,['city'=>'Bilinmiyor'])),true),'unknown stored city requires completion');
$firm=array_replace($customer,['user_type'=>'rentacar','iban'=>'TR'.str_repeat('1',24),'map_link'=>'https://maps.app.goo.gl/test','tax_plate'=>'uploads/tax.jpg']);
ruleCheck(registrationMissingFields($firm)===[],'firm documents, account and map are mandatory');
ruleCheck(in_array('tax_plate',registrationMissingFields(array_replace($firm,['tax_plate'=>null])),true),'social firm cannot bypass tax document');
$provider=array_replace($customer,['user_type'=>'provider','service_category'=>'wash','iban'=>'TR'.str_repeat('1',24),'tow_plate'=>'42 TAG 403','driver_license'=>'one.jpg','vehicle_photo'=>'two.jpg','equipment_photo'=>'three.jpg']);
ruleCheck(registrationMissingFields($provider)===[],'wash service complete registration');
ruleCheck(in_array('equipment_photo',registrationMissingFields(array_replace($provider,['equipment_photo'=>null])),true),'wash service cannot bypass equipment evidence');
ruleCheck(routeCoordinates('37.87,32.48')===[37.87,32.48],'route coordinates parsed');
foreach (['91,32','37,181','1e999,32','37,32&key=secret','NaN,32','37'] as $bad) {
    try { routeCoordinates($bad); ruleCheck(false,'invalid coordinate accepted'); } catch (InvalidArgumentException $e) { ruleCheck(true,'invalid coordinate rejected'); }
}
ruleCheck(serviceDistanceKm(37.87,32.48,37.87,32.48)===0.0,'same position has zero distance');
ruleCheck(serviceDistanceKm(37.87,32.48,39.93,32.85)>200,'remote candidates outside service radius');
$reply=routeGoogleResponse(['routes'=>[
 ['duration'=>'3600s','distanceMeters'=>9000,'polyline'=>['encodedPolyline'=>'_p~iF~ps|U_ulLnnqC']],
 ['duration'=>'1800s','distanceMeters'=>7000,'polyline'=>['encodedPolyline'=>'_p~iF~ps|U_ulLnnqC']]
]]);
ruleCheck($reply['routes'][0]['legs'][0]['duration']['value']===1800,'fastest Google road duration selected in seconds');
ruleCheck($reply['traffic_aware'] && $reply['source']==='google','traffic metadata genuine');
ruleCheck(routeGoogleResponse(['routes'=>[['duration'=>'broken','distanceMeters'=>5]]])===null,'unusable routes do not create invented geometry');
ruleCheck(routeLegacyResponse('abcd',60,800,'osrm')['traffic_aware']===false,'independent routing never claims live traffic');
ruleCheck(routeLegacyResponse('abcd',-1,800,'osrm')===null,'negative road duration rejected');
echo "\n$count auth and road-routing rule checks passed.\n";
