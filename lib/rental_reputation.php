<?php
require_once __DIR__.'/rental_rules.php';
require_once __DIR__.'/notification_delivery.php';

function rentalReputationSchema($pdo) {
    notificationEnsureSchema($pdo);
    $pdo->exec("CREATE TABLE IF NOT EXISTS rental_reviews (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,job_id INT NOT NULL,company_id INT NOT NULL,customer_id INT NOT NULL,
        rating TINYINT NOT NULL,comment TEXT NOT NULL,created_at DATETIME NOT NULL,
        UNIQUE KEY rental_one_review(job_id),KEY rental_company_reviews(company_id,id),KEY rental_review_customer(company_id,customer_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $pdo->exec("CREATE TABLE IF NOT EXISTS rental_events (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,event_type VARCHAR(50) NOT NULL,actor_id INT NOT NULL,actor_role VARCHAR(20) NOT NULL,
        company_id INT NULL,customer_id INT NULL,listing_id INT NULL,bid_id INT NULL,job_id INT NULL,
        city VARCHAR(100) NULL,details TEXT NOT NULL,created_at DATETIME NOT NULL,
        KEY rental_event_booking(job_id,id),KEY rental_event_bid(bid_id,id),KEY rental_event_company(company_id,id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
}
function rentalEvent($pdo,$type,$refs=[],$details=[]) {
    $auth=authenticateRequest();
    $stmt=$pdo->prepare('INSERT INTO rental_events(event_type,actor_id,actor_role,company_id,customer_id,listing_id,bid_id,job_id,city,details,created_at) VALUES (?,?,?,?,?,?,?,?,?,?,UTC_TIMESTAMP())');
    $stmt->execute([$type,$auth['user_id'],$auth['user_type'],$refs['company_id'] ?? null,$refs['customer_id'] ?? null,
        $refs['listing_id'] ?? null,$refs['bid_id'] ?? null,$refs['job_id'] ?? null,$refs['city'] ?? null,json_encode($details,JSON_UNESCAPED_UNICODE)]);
    $GLOBALS['rental_event_id']=(int)$pdo->lastInsertId();
    $messages=['offer_placed'=>['Yeni kiralama teklifi','Aracınız için yeni teklif geldi. Teklifler panelinden inceleyin.'],
        'counter_offer'=>['Kiralama karşı teklifi','Teklifiniz için yeni bir tutar önerildi. Güncel fiyatı inceleyin.'],
        'reserved'=>['Kiralama eşleşti','Rezervasyon oluşturuldu. Teslim bilgilerini rezervasyon detayında görebilirsiniz.'],
        'offer_rejected'=>['Kiralama teklifi kapatıldı','Teklifiniz reddedildi. Diğer araç ve teklifleri inceleyebilirsiniz.'],
        'offer_closed'=>['Kiralama teklifi kapatıldı','Araç artık bu teklif için uygun değil. Güncel ilanları inceleyin.'],
        'offer_removed'=>['Teklif geri çekildi','Müşteri kiralama teklifini geri çekti.'],
        'admin_cancelled'=>['Rezervasyon iptal edildi','Rezervasyon yönetici tarafından iptal edildi. Detayları inceleyin.'],
        'completed'=>['Kiralama tamamlandı','Kiralamanız tamamlandı. Firmayı rezervasyon detayından değerlendirebilirsiniz.']];
    if (isset($messages[$type])) {
        $targets=array_filter([$refs['company_id'] ?? null,$refs['customer_id'] ?? null],function($id)use($auth){ return $id && (int)$id!==(int)$auth['user_id']; });
        notificationQueue($pdo,$targets,$messages[$type][0],$messages[$type][1],
            ['type'=>'rental_update','job_id'=>(string)($refs['job_id'] ?? ''),'bid_id'=>(string)($refs['bid_id'] ?? '')],
            'rental:'.$GLOBALS['rental_event_id']);
    }

    if (!empty($GLOBALS['rental_event_shutdown'])) return;
    $GLOBALS['rental_event_shutdown']=true;
    // Publish only committed audit entries. A rolled-back mutation sends no signal.
    register_shutdown_function(function() use($pdo) {
        try {
            if ($pdo->inTransaction() || !function_exists('triggerPusherEvent') || !defined('PUSHER_KEY') || !PUSHER_KEY || !PUSHER_SECRET || !PUSHER_APP_ID) return;
            $stmt=$pdo->prepare('SELECT id FROM rental_events WHERE id=?'); $stmt->execute([$GLOBALS['rental_event_id']]);
            if (!$stmt->fetchColumn()) return;
            if (function_exists('fastcgi_finish_request')) fastcgi_finish_request();
            triggerPusherEvent('private-admin_rental','rental_changed',['event_id'=>$GLOBALS['rental_event_id']],2);
        } catch (Throwable $e) { error_log('Rental live signal unavailable.'); }
    });
}
function rentalReviewStats($pdo,$companyId) {
    // Eligibility is verified under the reservation lock at insertion. Keep verified
    // ratings stable if the author later deletes an account or its old job records.
    $valid="FROM rental_reviews r WHERE r.company_id=? AND r.rating BETWEEN 1 AND 5";
    $stmt=$pdo->prepare("SELECT COUNT(*) AS total,AVG(r.rating) AS average $valid");
    $stmt->execute([$companyId]); $aggregate=$stmt->fetch(PDO::FETCH_ASSOC); $count=(int)$aggregate['total'];
    $stmt=$pdo->prepare("SELECT COUNT(*) AS customers,SUM(score) AS scores FROM (SELECT AVG(r.rating) AS score $valid GROUP BY r.customer_id) averages");
    $stmt->execute([$companyId]); $customers=$stmt->fetch(PDO::FETCH_ASSOC); $unique=(int)$customers['customers'];
    $balanced=((float)$customers['scores']+15)/($unique+5);
    $stmt=$pdo->prepare("SELECT r.rating,COUNT(*) AS total $valid GROUP BY r.rating"); $stmt->execute([$companyId]);
    $distribution=array_fill(1,5,0); foreach ($stmt->fetchAll(PDO::FETCH_ASSOC) as $row) $distribution[(int)$row['rating']]=(int)$row['total'];
    return ['average'=>$count ? round((float)$aggregate['average'],2):null,'review_count'=>$count,'unique_customers'=>$unique,
        'badge_score'=>round($balanced,2),'badge'=>rentalRatingBadge($unique,$balanced),'distribution'=>$distribution,
        'badge_rules'=>['bronze'=>['customers'=>5,'score'=>3.8],'silver'=>['customers'=>10,'score'=>4.2],'gold'=>['customers'=>20,'score'=>4.5]]];
}
function rentalEvents($pdo,$clause='1=1',$params=[],$before=0) {
    if ($before>0) { $clause.=' AND e.id<?'; $params[]=$before; }
    $stmt=$pdo->prepare("SELECT e.*,f.name AS company_name,c.name AS customer_name FROM rental_events e
        LEFT JOIN users f ON f.id=e.company_id LEFT JOIN users c ON c.id=e.customer_id WHERE $clause ORDER BY e.id DESC LIMIT 51");
    $stmt->execute($params); $rows=$stmt->fetchAll(PDO::FETCH_ASSOC); $more=count($rows)>50; $rows=array_slice($rows,0,50);
    foreach ($rows as &$row) $row['details']=json_decode($row['details'],true) ?: [];
    unset($row);
    return ['events'=>$rows,'next_cursor'=>$more ? (int)end($rows)['id']:null];
}
function handleRentalReputationAction($pdo,$action,$method,$auth) {
    $actions=['get_rentacar_company_profile','add_rentacar_review','admin_get_rental_activity','admin_get_rental_detail'];
    if (!in_array($action,$actions,true)) return;
    if ($method!==($action==='add_rentacar_review'?'POST':'GET')) rentalFail(405,'Geçersiz metod.');
    $admin=strpos($action,'admin_')===0;
    if ($admin && $auth['user_type']!=='admin') rentalFail(403,'Yönetici yetkisi gereklidir.');
    if (!$admin && !in_array($auth['user_type'],['customer','rentacar','admin'],true)) rentalFail(403,'Bu profil için müşteri veya firma hesabı gereklidir.');
    try {
        rentalEnsureSchema($pdo);
        if ($action==='get_rentacar_company_profile') {
            $companyId=filter_var($_GET['company_id'] ?? null,FILTER_VALIDATE_INT);
            $stmt=$pdo->prepare("SELECT id,name,city,status,is_suspended,created_at,subscription_end_date FROM users WHERE id=? AND user_type='rentacar'"); $stmt->execute([$companyId]); $company=$stmt->fetch(PDO::FETCH_ASSOC);
            if (!$company) rentalFail(404,'Firma bulunamadı.');
            $company['available']=$company['status']==='active' && !$company['is_suspended'] && businessSubscriptionStatus($company)['can_work']; unset($company['status'],$company['is_suspended'],$company['created_at'],$company['subscription_end_date']);
            $before=max(0,(int)($_GET['before_id'] ?? 0));
            $stmt=$pdo->prepare("SELECT r.id,r.rating,r.comment,r.created_at,COALESCE(c.name,'Müşteri') AS reviewer_name FROM rental_reviews r
                LEFT JOIN users c ON c.id=r.customer_id WHERE r.company_id=? AND r.rating BETWEEN 1 AND 5
                ".($before?'AND r.id<?':'')." ORDER BY r.id DESC LIMIT 21");
            $stmt->execute($before?[$companyId,$before]:[$companyId]); $reviews=$stmt->fetchAll(PDO::FETCH_ASSOC); $more=count($reviews)>20; $reviews=array_slice($reviews,0,20);
            foreach ($reviews as &$review) {
                $names=preg_split('/\s+/',trim($review['reviewer_name']));
                $review['reviewer_name']=$names[0].(count($names)>1?' '.mb_substr(end($names),0,1).'.':'');
                $review['verified_rental']=true;
            } unset($review);
            sendResponse(200,['status'=>'success','company'=>$company,'reputation'=>rentalReviewStats($pdo,$companyId),'reviews'=>$reviews,'next_cursor'=>$more?(int)end($reviews)['id']:null]);
        }
        if ($action==='add_rentacar_review') {
            if ($auth['user_type']!=='customer') rentalFail(403,'Değerlendirmeyi kiralamanın müşterisi yapabilir.');
            if (isset($_POST['comment']) && !is_string($_POST['comment'])) throw new InvalidArgumentException('Geçersiz yorum.');
            $rating=filter_var($_POST['rating'] ?? null,FILTER_VALIDATE_INT); $comment=trim($_POST['comment'] ?? '');
            if (!$rating || $rating<1 || $rating>5 || mb_strlen($comment)>2000) throw new InvalidArgumentException('1–5 yıldız seçin; yorum en fazla 2.000 karakter olabilir.');
            $pdo->beginTransaction();
            $stmt=$pdo->prepare("SELECT * FROM jobs WHERE id=? AND service_type='rentacar' FOR UPDATE"); $stmt->execute([$_POST['job_id'] ?? 0]); $job=$stmt->fetch(PDO::FETCH_ASSOC);
            if (!$job || (int)$job['customer_id']!==(int)$auth['user_id']) { $pdo->rollBack(); rentalFail(403,'Bu kiralamayı değerlendiremezsiniz.'); }
            if ($job['status']!=='completed') { $pdo->rollBack(); rentalFail(409,'Değerlendirme araç iade edilip kiralama tamamlanınca açılır.'); }
            $stmt=$pdo->prepare("SELECT b.id,b.listing_id FROM rentacar_bids b JOIN rentacar_listings l ON l.id=b.listing_id
                WHERE b.job_id=? AND b.status='completed' AND b.customer_id=? AND l.company_id=?");
            $stmt->execute([$job['id'],$auth['user_id'],$job['provider_id']]); $bid=$stmt->fetch(PDO::FETCH_ASSOC);
            if (!$bid) { $pdo->rollBack(); rentalFail(409,'Tamamlanmış kiralama rezervasyonu bulunamadı.'); }
            $stmt=$pdo->prepare('SELECT id,rating,comment FROM rental_reviews WHERE job_id=?'); $stmt->execute([$job['id']]); $existing=$stmt->fetch(PDO::FETCH_ASSOC);
            if ($existing) {
                $pdo->commit();
                if ((int)$existing['rating']!==$rating || $existing['comment']!==$comment) rentalFail(409,'Bu kiralama için değerlendirme zaten kaydedilmiş.');
                sendResponse(200,['status'=>'success','review'=>$existing]);
            }
            $pdo->prepare('SELECT id FROM users WHERE id=? FOR UPDATE')->execute([$job['provider_id']]);
            $pdo->prepare('INSERT INTO rental_reviews(job_id,company_id,customer_id,rating,comment,created_at) VALUES (?,?,?,?,?,UTC_TIMESTAMP())')
                ->execute([$job['id'],$job['provider_id'],$auth['user_id'],$rating,$comment]);
            $reviewId=(int)$pdo->lastInsertId(); $stats=rentalReviewStats($pdo,$job['provider_id']);
            $pdo->prepare('UPDATE users SET rating=?,reviews_count=? WHERE id=?')->execute([$stats['average'],$stats['review_count'],$job['provider_id']]);
            rentalEvent($pdo,'review_added',['company_id'=>$job['provider_id'],'customer_id'=>$auth['user_id'],'job_id'=>$job['id'],'city'=>$job['city'],'listing_id'=>$bid['listing_id'] ?? null,'bid_id'=>$bid['id'] ?? null],['rating'=>$rating,'review_id'=>$reviewId]);
            $pdo->commit(); sendResponse(201,['status'=>'success','review'=>['id'=>$reviewId,'rating'=>$rating,'comment'=>$comment],'reputation'=>$stats]);
        }
        if ($action==='admin_get_rental_detail') {
            $bidId=filter_var($_GET['bid_id'] ?? null,FILTER_VALIDATE_INT);
            $rows=rentalQueryBids($pdo,'b.id=?',[$bidId]); if (!$rows) rentalFail(404,'Kiralama talebi bulunamadı.');
            sendResponse(200,['status'=>'success','bid'=>$rows[0]]+rentalEvents($pdo,'e.bid_id=?',[$bidId],max(0,(int)($_GET['before_event_id'] ?? 0))));
        }
        $status=$_GET['stage'] ?? ''; if (!in_array($status,['','pending','accepted','completed','cancelled','rejected'],true)) throw new InvalidArgumentException('Geçersiz aşama.');
        $city=trim($_GET['city'] ?? ''); $clause='1=1'; $params=[];
        if ($status!=='') {$clause.=' AND b.status=?';$params[]=$status;}
        if ($city!=='') {$clause.=' AND COALESCE(j.city,l.city)=?';$params[]=$city;}
        $before=max(0,(int)($_GET['before_bid_id'] ?? 0)); if ($before) {$clause.=' AND b.id<?';$params[]=$before;}
        // List query is bounded; older entries use a stable ID cursor.
        $stmt=$pdo->prepare("SELECT b.*,l.company_id,COALESCE(b.vehicle_label,l.car_brand_model) AS car_brand_model,COALESCE(j.city,l.city) AS city,
            f.name AS company_name,c.name AS customer_name,(SELECT COUNT(*) FROM tickets t WHERE t.job_id=b.job_id AND t.status='open') AS open_complaints,
            (SELECT r.rating FROM rental_reviews r WHERE r.job_id=b.job_id) AS customer_rating
            FROM rentacar_bids b JOIN rentacar_listings l ON l.id=b.listing_id LEFT JOIN jobs j ON j.id=b.job_id LEFT JOIN users f ON f.id=l.company_id LEFT JOIN users c ON c.id=b.customer_id
            WHERE $clause ORDER BY b.id DESC LIMIT 51");
        $stmt->execute($params); $bids=$stmt->fetchAll(PDO::FETCH_ASSOC); $more=count($bids)>50;$bids=array_slice($bids,0,50);
        $counts=$pdo->query('SELECT status,COUNT(*) AS total FROM rentacar_bids GROUP BY status')->fetchAll(PDO::FETCH_KEY_PAIR);
        $cities=$pdo->query("SELECT DISTINCT city FROM (SELECT CONVERT(city USING utf8mb4) COLLATE utf8mb4_unicode_ci AS city FROM rentacar_listings
            UNION SELECT CONVERT(city USING utf8mb4) COLLATE utf8mb4_unicode_ci FROM rental_events) places WHERE city IS NOT NULL AND city<>'' ORDER BY city LIMIT 100")->fetchAll(PDO::FETCH_COLUMN);
        $events=rentalEvents($pdo,$city!==''?'e.city=?':'1=1',$city!==''?[$city]:[],max(0,(int)($_GET['before_event_id'] ?? 0)));
        sendResponse(200,['status'=>'success','bids'=>$bids,'counts'=>(object)$counts,'cities'=>$cities,'next_bid_cursor'=>$more?(int)end($bids)['id']:null,'server_time'=>gmdate('c')]+$events);
    } catch (InvalidArgumentException $e) { if ($pdo->inTransaction()) $pdo->rollBack(); rentalFail(422,$e->getMessage()); }
    catch (Throwable $e) { if ($pdo->inTransaction()) $pdo->rollBack(); error_log('Rental reputation: '.$e->getMessage()); rentalFail(500,'Kiralama bilgileri alınamadı.'); }
}
