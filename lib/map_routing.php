<?php
function routeCoordinates($text) {
    $parts=explode(',',(string)$text);
    if (count($parts)!==2) throw new InvalidArgumentException('Başlangıç ve hedef koordinatları geçersiz.');
    return [serviceCoordinate(trim($parts[0])),serviceCoordinate(trim($parts[1]),false)];
}
function routeLegacyResponse($polyline,$seconds,$meters,$source,$traffic=false) {
    if (!is_string($polyline) || strlen($polyline)<4 || !is_numeric($seconds) || !is_numeric($meters) || !is_finite((float)$seconds) || !is_finite((float)$meters) || $seconds<0 || $meters<0) return null;
    $duration=['value'=>(int)ceil($seconds),'text'=>ceil($seconds/60).' dk'];
    $leg=['duration'=>$duration,'distance'=>['value'=>(int)ceil($meters),'text'=>number_format($meters/1000,1,',','.').' km']];
    if ($traffic) $leg['duration_in_traffic']=$duration;
    return ['status'=>'OK','source'=>$source,'traffic_aware'=>$traffic,'routes'=>[['overview_polyline'=>['points'=>$polyline],'legs'=>[$leg]]]];
}
function routeGoogleResponse($data) {
    $best=null;
    foreach ($data['routes'] ?? [] as $route) {
        if (!preg_match('/^([0-9]+(?:\.[0-9]+)?)s$/D',$route['duration'] ?? '',$seconds)) continue;
        $item=routeLegacyResponse($route['polyline']['encodedPolyline'] ?? '',(float)$seconds[1],$route['distanceMeters'] ?? null,'google',true);
        if ($item && (!$best || $item['routes'][0]['legs'][0]['duration']['value']<$best['routes'][0]['legs'][0]['duration']['value'])) $best=$item;
    }
    return $best;
}
function routeRequest($url,$body=null,$headers=[]) {
    $curl=curl_init($url);
    curl_setopt_array($curl,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>8,CURLOPT_CONNECTTIMEOUT=>3,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_HTTPHEADER=>$headers]);
    if ($body!==null) { curl_setopt($curl,CURLOPT_POST,true); curl_setopt($curl,CURLOPT_POSTFIELDS,json_encode($body)); }
    $response=curl_exec($curl); $code=curl_getinfo($curl,CURLINFO_HTTP_CODE); curl_close($curl);
    return $code===200 ? json_decode($response,true) : null;
}
function mapRoutesApiKey() {
    foreach (['MAPS_ROUTES_API_KEY','MAPS_API_KEY','GOOGLE_MAPS_API_KEY'] as $name) {
        $value=function_exists('serverConfig') ? serverConfig($name) : (getenv($name) ?: '');
        if (trim((string)$value)!=='') return trim((string)$value);
    }
    return '';
}
function calculateServiceRoute($origin,$destination,$mapProvider) {
    // Use the backend Google Routes key for every mobile map provider so iPhone/Apple map sessions also receive a traffic-aware road route.
    $key=mapRoutesApiKey();
    if ($key!=='') {
        $data=routeRequest('https://routes.googleapis.com/directions/v2:computeRoutes',[
            'origin'=>['location'=>['latLng'=>['latitude'=>$origin[0],'longitude'=>$origin[1]]]],
            'destination'=>['location'=>['latLng'=>['latitude'=>$destination[0],'longitude'=>$destination[1]]]],
            'travelMode'=>'DRIVE','routingPreference'=>'TRAFFIC_AWARE','computeAlternativeRoutes'=>true,'languageCode'=>'tr-TR','units'=>'METRIC'
        ],['Content-Type: application/json','X-Goog-Api-Key: '.$key,'X-Goog-FieldMask: routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline']);
        if (is_array($data) && ($result=routeGoogleResponse($data))) return $result;
    }
    $base=rtrim(serverConfig('OSRM_BASE_URL'),'\/');
    if ($base!=='' && filter_var($base,FILTER_VALIDATE_URL) && parse_url($base,PHP_URL_SCHEME)==='https') {
        $path='/route/v1/driving/'.$origin[1].','.$origin[0].';'.$destination[1].','.$destination[0].'?overview=full&geometries=polyline';
        $data=routeRequest($base.$path);
        if (($data['code'] ?? '')==='Ok') {
            $route=$data['routes'][0] ?? [];
            return routeLegacyResponse($route['geometry'] ?? '',$route['duration'] ?? null,$route['distance'] ?? null,'osrm',false);
        }
    }
    return null;
}
