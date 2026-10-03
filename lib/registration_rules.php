<?php
function registrationPhone($value) {
    $phone=preg_replace('/[^0-9]/','',(string)$value);
    if (strpos($phone,'0090')===0) $phone=substr($phone,4);
    elseif (strlen($phone)===12 && strpos($phone,'90')===0) $phone=substr($phone,2);
    if (strlen($phone)===10) $phone='0'.$phone;
    if (!preg_match('/^0[2-5][0-9]{9}$/D',$phone)) throw new InvalidArgumentException('Geçerli bir Türkiye telefon numarası girin.');
    return $phone;
}
function registrationCity($value) {
    $cities=require __DIR__.'/turkish_cities.php';
    foreach ($cities as $city) if (rentalSameCity($value,$city)) return $city;
    throw new InvalidArgumentException('Listeden geçerli bir şehir seçin.');
}
function registrationMissingFields($user) {
    $missing=[];
    if (strlen(trim($user['name'] ?? ''))<2) $missing[]='name';
    try { registrationPhone($user['phone'] ?? ''); } catch (InvalidArgumentException $e) { $missing[]='phone'; }
    try { registrationCity($user['city'] ?? ''); } catch (InvalidArgumentException $e) { $missing[]='city'; }
    if (in_array($user['user_type'] ?? '',['provider','rentacar'],true)) {
        if (!preg_match('/^TR[0-9]{24}$/D',strtoupper(str_replace(' ','',$user['iban'] ?? '')))) $missing[]='iban';
        if (($user['user_type'] ?? '')==='rentacar') {
            try { if (!rentalMapLink($user['map_link'] ?? '')) $missing[]='map_link'; }
            catch (InvalidArgumentException $e) { $missing[]='map_link'; }
            if (empty($user['tax_plate'])) $missing[]='tax_plate';
        } else {
            if (!in_array($user['service_category'] ?? '',['mechanic','tow','tire','wash'],true)) $missing[]='service_category';
            if (empty($user['tow_plate'])) $missing[]='tow_plate';
            foreach (($user['service_category'] ?? '')==='wash' ? ['driver_license','vehicle_photo','equipment_photo'] : ['tax_plate'] as $field) if (empty($user[$field])) $missing[]=$field;
        }
    }
    return array_values(array_unique($missing));
}
