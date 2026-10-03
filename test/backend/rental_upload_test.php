<?php
require_once __DIR__.'/../../lib/oauth_verification.php';
require_once __DIR__.'/../../lib/rentacar_api.php';
$count=0;
function uploadCheck($condition,$label) { global $count; if (!$condition) throw new RuntimeException('FAIL: '.$label); $count++; echo "PASS: $label\n"; }
foreach (['2M'=>2097152,'1.5M'=>1572864,'512K'=>524288,'1G'=>1073741824,'100'=>100,'0'=>0,'-1'=>0,''=>0] as $value=>$expected) uploadCheck(rentalIniBytes($value)===$expected,'PHP size parse '.(string)$value);
foreach ([UPLOAD_ERR_NO_TMP_DIR,UPLOAD_ERR_CANT_WRITE,UPLOAD_ERR_EXTENSION] as $code) {
    try { rentalUploadError($code); uploadCheck(false,'server upload failure expected'); }
    catch (RentalServerException $e) { uploadCheck(strpos($e->errorCode,'RENTAL_UPLOAD_')===0,'server upload error has actionable code '.$code); }
}
foreach ([UPLOAD_ERR_INI_SIZE,UPLOAD_ERR_FORM_SIZE,UPLOAD_ERR_PARTIAL] as $code) {
    try { rentalUploadError($code); uploadCheck(false,'upload input failure expected'); }
    catch (InvalidArgumentException $e) { uploadCheck(true,'upload input error distinguished '.$code); }
}
// This test server deliberately runs without fileinfo. Its database and files are isolated.
$pdo=new PDO('mysql:host=127.0.0.1;port=33307;charset=utf8mb4','root','',[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);
$pdo->exec('CREATE DATABASE IF NOT EXISTS ototag_rental_upload_regression CHARACTER SET utf8mb4 COLLATE utf8mb4_turkish_ci');
$pdo->exec('USE ototag_rental_upload_regression');
$pdo->exec('DROP TABLE IF EXISTS ototag_schema_migrations');
uploadCheck($pdo->query('SELECT DATABASE()')->fetchColumn()==='ototag_rental_upload_regression','destructive fixtures restricted to upload regression database');
foreach (['rental_reviews','rental_events','tickets','notifications','jobs','rentacar_bids','rentacar_listings','users'] as $table) {
    $pdo->exec("DROP TABLE IF EXISTS `$table`");
    $pdo->exec("CREATE TABLE `$table` LIKE ototag_rental_regression.`$table`");
}
$pdo->exec("INSERT INTO users(id,name,city,user_type,status,is_suspended) VALUES (10,'Fotoğraf Test Firma','Konya','rentacar','active',0)");
// Emulate older installations missing base/metadata fields; the module itself must add them.
$pdo->exec('ALTER TABLE rentacar_listings DROP COLUMN photo,DROP COLUMN plate,DROP COLUMN model_year');
rentalEnsureSchema($pdo);
$columns=$pdo->query('SHOW COLUMNS FROM rentacar_listings')->fetchAll(PDO::FETCH_COLUMN);
uploadCheck(!array_diff(['photo','plate','model_year'], $columns),'migration restores missing legacy listing fields independently');
$root=realpath(__DIR__.'/../..'); $serverRoot=$root.'/.dart_tool/rental_upload_http';
if (!is_dir($serverRoot)) mkdir($serverRoot,0755,true);
foreach (glob($root.'/lib/*.php') as $file) copy($file,$serverRoot.'/'.basename($file));
function uploadCopy($from,$to) { if (!is_dir($to)) mkdir($to,0755,true); foreach(new DirectoryIterator($from) as $entry) {
    if ($entry->isDot()) continue; if ($entry->isDir()) uploadCopy($entry->getPathname(),$to.'/'.$entry->getFilename()); else copy($entry->getPathname(),$to.'/'.$entry->getFilename());
} }
uploadCopy($root.'/lib/php_jwt',$serverRoot.'/php_jwt');
$secret=str_repeat('isolated-upload-secret-',3);
file_put_contents($serverRoot.'/.env', "DB_HOST=\"127.0.0.1;port=33307\"\nDB_NAME=ototag_rental_upload_regression\nDB_USER=root\nDB_PASS=\"\"\nJWT_SECRET=\"$secret\"\n");
file_put_contents($serverRoot.'/probe.php','<?php echo json_encode(["fileinfo"=>class_exists("finfo")]);');
$png=$serverRoot.'/valid.png';
file_put_contents($png,base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII='));
$fake=$serverRoot.'/fake.png'; file_put_contents($fake,'Not an image.');
$svg=$serverRoot.'/fake.svg'; file_put_contents($svg,'<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"></svg>');
$polyglot=$serverRoot.'/polyglot.png'; file_put_contents($polyglot,file_get_contents($png).'<?php echo "disallowed";');
$extDir=ini_get('extension_dir');
$command=[PHP_BINARY,'-n','-d','extension_dir='.$extDir];
foreach (['pdo_mysql','mbstring','openssl','curl'] as $extension) {$command[]='-d';$command[]='extension='.$extension;}
$command=array_merge($command,['-d','display_errors=0','-d','post_max_size=1M','-d','upload_max_filesize=512K','-S','127.0.0.1:33309','-t',$serverRoot]);
$process=proc_open($command,[1=>['file',$serverRoot.'/server.log','a'],2=>['file',$serverRoot.'/server.log','a']],$pipes);
$token=\Firebase\JWT\JWT::encode(['user_id'=>10,'user_type'=>'rentacar','iat'=>time(),'exp'=>time()+3600],$secret,'HS256');
function uploadRequest($token,$fields) {
    $curl=curl_init('http://127.0.0.1:33309/api.php?action=create_rentacar_listing');
    curl_setopt_array($curl,[CURLOPT_POST=>true,CURLOPT_POSTFIELDS=>$fields,CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>15,CURLOPT_HTTPHEADER=>['Authorization: Bearer '.$token]]);
    $body=curl_exec($curl); $code=curl_getinfo($curl,CURLINFO_HTTP_CODE); curl_close($curl);
    $data=json_decode($body,true); if (!is_array($data)) throw new RuntimeException('Invalid upload response: '.substr($body,0,300));
    return ['http'=>$code]+$data;
}
$fields=['company_id'=>10,'brand'=>'TOYOTA','model'=>'Camry','plate'=>'45 TAG 252','model_year'=>date('Y'),'daily_price'=>'5000','description'=>'Fotoğraflı araç'];
try {
    for ($i=0;$i<40;$i++) { $socket=@fsockopen('127.0.0.1',33309,$errno,$errstr,0.1); if ($socket) {fclose($socket);break;} usleep(100000); }
    $probe=json_decode(file_get_contents('http://127.0.0.1:33309/probe.php'),true);
    uploadCheck($probe['fileinfo']===false,'test HTTP runtime actually lacks fileinfo');
    $response=uploadRequest($token,$fields+['image_1'=>new CURLFile($png,'image/png','car.png')]);
    uploadCheck($response['http']===201,'screenshot Toyota Camry fields and PNG save without fileinfo');
    $photo=$pdo->query('SELECT photo1 FROM rentacar_listings WHERE id='.(int)$response['listing_id'])->fetchColumn();
    uploadCheck(is_file($serverRoot.'/'.$photo) && preg_match('#^uploads/rentacar/[a-f0-9]{32}\.png$#D',$photo),'validated contents determine safe random PNG name');
    uploadCheck($pdo->query('SELECT status FROM rentacar_listings WHERE id='.(int)$response['listing_id'])->fetchColumn()==='active','new listing explicitly active despite legacy defaults');
    $beforeRows=(int)$pdo->query('SELECT COUNT(*) FROM rentacar_listings')->fetchColumn();
    $beforeFiles=count(glob($serverRoot.'/uploads/rentacar/*'));
    foreach ([$fake,$svg,$polyglot] as $path) {
        $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 253'])+['image_1'=>new CURLFile($path,'image/png','fake.png')]);
        uploadCheck($response['http']===422,'missing fileinfo does not accept fake MIME or SVG: '.basename($path));
    }
    $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 254'])+['image_1'=>new CURLFile($png,'image/png','car.png'),'image_2'=>new CURLFile($fake,'image/png','fake.png')]);
    uploadCheck($response['http']===422 && count(glob($serverRoot.'/uploads/rentacar/*'))===$beforeFiles,'second invalid image cleans first uploaded image');
    uploadCheck((int)$pdo->query('SELECT COUNT(*) FROM rentacar_listings')->fetchColumn()===$beforeRows,'invalid images leave no partial listing');
    $dir=$serverRoot.'/uploads/rentacar'; $backup=$serverRoot.'/uploads/rentacar-test-backup';
    if (strpos(realpath($dir),realpath($serverRoot).DIRECTORY_SEPARATOR)!==0 || file_exists($backup)) throw new RuntimeException('Unsafe fixture directory');
    rename($dir,$backup); file_put_contents($dir,'Block upload directory');
    try {
        $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 255'])+['image_1'=>new CURLFile($png,'image/png','car.png')]);
        uploadCheck($response['http']===503 && $response['error_code']==='RENTAL_UPLOAD_DIRECTORY','storage failure returns precise actionable error instead of generic 500');
        uploadCheck((bool)preg_match('/^[a-f0-9]{12}$/D',$response['reference']) && strpos($response['message'],'uploads/rentacar')!==false,'storage response carries support reference and relative directory guidance');
        uploadCheck(strpos(json_encode($response),$secret)===false && strpos(json_encode($response),'SQLSTATE')===false,'storage response leaks no signing secret or SQL internals');
        uploadCheck((int)$pdo->query('SELECT COUNT(*) FROM rentacar_listings')->fetchColumn()===$beforeRows,'storage failure rolls back listing');
    } finally { unlink($dir); rename($backup,$dir); }
    $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 255'])+['image_1'=>new CURLFile($png,'image/png','car.png')]);
    uploadCheck($response['http']===201,'retry after directory repair saves successfully');
    $large=$serverRoot.'/large.png'; file_put_contents($large,file_get_contents($png).str_repeat('x',600*1024));
    $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 256'])+['image_1'=>new CURLFile($large,'image/png','large.png')]);
    uploadCheck($response['http']===422 && strpos($response['message'],'upload_max_filesize')!==false,'PHP file limit gives smaller-photo guidance');
    file_put_contents($large,file_get_contents($png).str_repeat('x',1100*1024));
    $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 256'])+['image_1'=>new CURLFile($large,'image/png','large.png')]);
    uploadCheck($response['http']===413 && strpos($response['message'],'post_max_size')!==false,'oversized total body distinguished from missing form fields');
    $pdo->exec('ALTER TABLE rental_events ENGINE=MyISAM');
    try {
        $response=uploadRequest($token,array_replace($fields,['plate'=>'45 TAG 257']));
        uploadCheck($response['http']===503 && $response['error_code']==='RENTAL_DATABASE_SCHEMA','unsafe database engine surfaces actionable schema error');
    } finally { $pdo->exec('ALTER TABLE rental_events ENGINE=InnoDB'); }
    echo "\n$count upload checks passed.\n";
} finally { proc_terminate($process); proc_close($process); }
