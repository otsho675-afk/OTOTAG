<?php
// Only connects to the isolated local regression database, never production.
function sendResponse($code,$body) { echo json_encode(['http'=>$code]+$body,JSON_UNESCAPED_UNICODE); exit; }
function authenticateRequest() {
    if (empty($GLOBALS['testActor']['user_id'])) sendResponse(401,['status'=>'error']);
    return $GLOBALS['testActor'];
}
function deletePhysicalFile($path) {}
$input=json_decode($argv[1],true);
$GLOBALS['testActor']=$input['actor'];
$_GET=$input['get'] ?? []; $_POST=$input['post'] ?? [];
$pdo=new PDO('mysql:host=127.0.0.1;port=33307;dbname=ototag_rental_regression;charset=utf8mb4','root','',[
    PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION,PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES=>false,
]);
require __DIR__.'/../../lib/rentacar_api.php';
handleRentalAction($pdo,$input['action'],$input['method'] ?? 'POST');
