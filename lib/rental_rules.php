<?php
// Pure rules shared by the API and its regression tests.
function rentalRatingBadge($customers,$score) {
    if ($customers>=20 && $score>=4.5) return ['id'=>'gold','title'=>'Altın Memnuniyet'];
    if ($customers>=10 && $score>=4.2) return ['id'=>'silver','title'=>'Gümüş Memnuniyet'];
    if ($customers>=5 && $score>=3.8) return ['id'=>'bronze','title'=>'Bronz Memnuniyet'];
    return null;
}
function rentalCityKey($city) {
    $city = trim((string)$city);
    $city = strtr($city, ['İ'=>'i', 'I'=>'ı', 'Ş'=>'ş', 'Ğ'=>'ğ', 'Ü'=>'ü', 'Ö'=>'ö', 'Ç'=>'ç']);
    return function_exists('mb_strtolower') ? mb_strtolower($city, 'UTF-8') : strtolower($city);
}
function rentalSameCity($first, $second) {
    $key = rentalCityKey($first);
    return $key !== '' && $key !== 'bilinmiyor' && $key === rentalCityKey($second);
}
// Keep shared map links intact; never resolve shortened links on the server.
function rentalMapLink($value) {
    $value=trim((string)$value);
    $url=parse_url($value);
    $hosts=['maps.app.goo.gl','goo.gl','www.google.com','google.com','maps.google.com','www.google.com.tr','google.com.tr','maps.google.com.tr','maps.apple.com'];
    if (strlen($value)>500 || preg_match('/[\x00-\x20\\\\]/',$value) || !$url || strtolower($url['scheme'] ?? '')!=='https'
        || !in_array(strtolower($url['host'] ?? ''),$hosts,true) || isset($url['user']) || isset($url['pass']) || (isset($url['port']) && $url['port']!==443)) {
        throw new InvalidArgumentException('Geçerli bir HTTPS Google Maps veya Apple Haritalar konum linki girin.');
    }
    $host=strtolower($url['host']); $path=$url['path'] ?? '';
    if (($host==='goo.gl' && strpos($path,'/maps/')!==0) || (strpos($host,'google.com')!==false && strpos($host,'maps.')!==0 && !preg_match('~^/maps(?:/|$)~',$path))) {
        throw new InvalidArgumentException('Link bir harita konumunu açmalıdır.');
    }
    return $value;
}
function rentalMoneyCents($value) {
    $value = str_replace(',', '.', trim((string)$value));
    if (!preg_match('/^\d{1,8}(?:\.\d{1,2})?$/D', $value)) {
        throw new InvalidArgumentException('Ücret pozitif olmalı ve en fazla iki ondalık basamak içermelidir.');
    }
    $parts = explode('.', $value);
    $cents = (int)$parts[0] * 100 + (int)str_pad($parts[1] ?? '', 2, '0');
    if ($cents < 1 || $cents > 9999999999) throw new InvalidArgumentException('Ücret geçersiz.');
    return $cents;
}
function rentalMoneyText($cents) {
    if ($cents < 1 || $cents > 9999999999) throw new InvalidArgumentException('Toplam ücret sınırı aşıldı.');
    return intdiv($cents, 100) . '.' . str_pad((string)($cents % 100), 2, '0', STR_PAD_LEFT);
}
function rentalDays($value) {
    $days = filter_var($value, FILTER_VALIDATE_INT);
    if ($days === false || $days < 1 || $days > 365) throw new InvalidArgumentException('Kiralama süresi 1–365 gün olmalıdır.');
    return $days;
}
function rentalCanRespond($bid, $actor, $version) {
    return $bid['status'] === 'pending' && (int)$bid['offer_version'] === (int)$version
        && in_array($actor, ['customer', 'company'], true) && $bid['last_offer_by'] !== $actor;
}
function rentalQuote($daily, $days, $budget) {
    $days = rentalDays($days);
    $budget = rentalMoneyCents($budget);
    $total = rentalMoneyCents($daily) * $days;
    return ['days'=>$days, 'amount'=>rentalMoneyText($total), 'budget'=>rentalMoneyText($budget)];
}
function rentalListingFields($input) {
    $brand=trim($input['brand'] ?? ''); $model=trim($input['model'] ?? '');
    $plate=strtoupper(preg_replace('/\s+/', '', trim($input['plate'] ?? '')));
    $year=(int)($input['model_year'] ?? 0);
    if ($brand==='' || $model==='' || strlen($brand)>100 || strlen($model)>150) throw new InvalidArgumentException('Marka ve model seçin.');
    if (!preg_match('/^(0[1-9]|[1-7][0-9]|8[01])[A-Z]{1,3}\d{2,4}$/D', $plate)) throw new InvalidArgumentException('Geçerli bir araç plakası girin.');
    if ($year<1980 || $year>(int)date('Y')+1) throw new InvalidArgumentException('Model yılı geçersiz.');
    return [$brand, $model, $plate, $year, rentalMoneyText(rentalMoneyCents($input['daily_price'] ?? '')), mb_substr($input['description'] ?? '',0,4000)];
}
