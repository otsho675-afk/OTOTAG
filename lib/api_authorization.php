<?php
function apiDeny($message='Bu kayıt üzerinde işlem yapma yetkiniz yok.') { sendResponse(403,['status'=>'error','message'=>$message]); }
function apiOwn($requested,$auth) {
    if (!$requested || (string)$requested!==(string)$auth['user_id']) apiDeny();
}
function apiJob($pdo,$jobId,$auth,$allowBidder=false) {
    $stmt=$pdo->prepare('SELECT * FROM jobs WHERE id=?'); $stmt->execute([$jobId]); $job=$stmt->fetch();
    if (!$job) sendResponse(404,['status'=>'error','message'=>'İş bulunamadı.']);
    if ((int)$auth['user_id']!==(int)$job['customer_id'] && (int)$auth['user_id']!==(int)$job['provider_id']) {
        if (!$allowBidder || $auth['user_type']!=='provider') apiDeny();
        $stmt=$pdo->prepare('SELECT id FROM bids WHERE job_id=? AND provider_id=?'); $stmt->execute([$jobId,$auth['user_id']]);
        if (!$stmt->fetch()) apiDeny();
    }
    return $job;
}
function authorizeApiAction($pdo,$action,$method) {
    $public=['login','auth_user','register','oauth_login','admin_login','check_status','get_app_config','get_ads','log_telemetry','send_phone_otp','verify_phone_otp'];
    if (in_array($action,$public,true)) return;
    $auth=authenticateRequest(); $input=$method==='GET' ? $_GET : $_POST;
    if ($auth['user_type']==='admin' && in_array($action,['get_rentacar_booking','get_rentacar_company_profile','pusher_auth'],true)) return;
    if ($action==='send_notification' && $auth['user_type']==='admin') return;
    if ($action==='delete_part_record' && $auth['user_type']==='admin') return;
    if ($action==='get_part_listings' && $auth['user_type']==='admin') return;
    $admin=['admin_get_app_updates','admin_publish_app_update','admin_withdraw_app_update','admin_retry_app_update_push','admin_get_purchases','admin_change_password','admin_backup_db','admin_optimize_system','admin_dashboard',
        'suspend_provider','ban_user','ban_ip','get_all_users','admin_delete_user','admin_delete_job','approve_provider','reject_provider','growth_analytics',
        'get_tickets','update_ticket_status','admin_delete_ticket','admin_cancel_rentacar_booking','admin_get_rental_activity','admin_get_rental_detail','get_feedbacks','admin_get_telemetry_stats','add_ad','edit_ad','delete_ad'];
    if (in_array($action,$admin,true)) { if ($auth['user_type']!=='admin') apiDeny('Yönetici yetkisi gereklidir.'); return; }
    // Admins do not impersonate customer/provider actions with overlapping IDs.
    if ($auth['user_type']==='admin') apiDeny();
    expirePremiumEntitlement($pdo,$auth['user_id']);
    $stmt=$pdo->prepare('SELECT user_type,status,is_suspended FROM users WHERE id=?'); $stmt->execute([$auth['user_id']]); $account=$stmt->fetch();
    if (!$account || $account['user_type']!==$auth['user_type'] || $account['status']!=='active' || !empty($account['is_suspended'])) apiDeny('Hesabınız bu işlem için aktif değil.');
    if (in_array($action,['activate_premium','renew_provider_subscription','activate_obd_subscription'],true)) {
        $platform=$_POST['platform'] ?? '';
        $expected=purchaseExpectedProduct($action,$platform);
        if (!$expected || ($_POST['product_id'] ?? '')!==$expected || ($_POST['package_name'] ?? 'com.oto.tag')!==serverConfig('ANDROID_PACKAGE_NAME','com.oto.tag')) {
            sendResponse(422,['status'=>'error','message'=>'Satın alma ürünü veya uygulama kimliği geçersiz.']);
        }
        if ($action==='activate_premium' && $auth['user_type']!=='customer') apiDeny();
        $column=$action==='activate_premium' ? 'premium_end_date' : ($action==='activate_obd_subscription' ? 'obd_subscription_end_date':'subscription_end_date');
        if (!$pdo->query("SHOW COLUMNS FROM users LIKE '$column'")->fetch()) $pdo->exec("ALTER TABLE users ADD COLUMN `$column` DATETIME NULL");
    }
    $ownUser=['get_my_subscriptions','check_active_job','update_location','check_unread_messages','mark_read','check_obd_subscription','activate_obd_subscription','activate_premium',
        'get_user_purchases','get_notifications','mark_notif_read','delete_notification','clear_all_notifications','get_profile','get_referral_summary','link_oauth',
        'unlink_oauth','update_profile','delete_account','get_history','delete_history','change_password','send_feedback','trigger_sos'];
    if (in_array($action,$ownUser,true)) apiOwn($input['user_id'] ?? null,$auth);
    if (in_array($action,['check_provider_subscription','renew_provider_subscription'],true)) {
        if (!in_array($auth['user_type'],['provider','rentacar'],true)) apiDeny('Firma veya usta hesabı gereklidir.');
        apiOwn($input['provider_id'] ?? null,$auth);
    }
    if (in_array($action,['check_provider_subscription','renew_provider_subscription','check_obd_subscription','activate_obd_subscription','place_bid','get_pending_jobs','accept_bid'],true)) ensureBusinessSubscriptionSchema($pdo);
    if (in_array($action,['place_bid','get_pending_jobs','accept_bid'],true)) ensureServiceMatchingIndexes($pdo);
    $ownProvider=['place_bid','get_earnings','get_pending_jobs','get_provider_active_bids','appeal_rating'];
    if (in_array($action,$ownProvider,true)) { if ($auth['user_type']!=='provider') apiDeny(); apiOwn($input['provider_id'] ?? null,$auth); }
    if (in_array($action,['create_job','get_vehicles','add_vehicle','update_vehicle','delete_vehicle','create_part_listing'],true)) {
        if ($auth['user_type']!=='customer') apiDeny(); apiOwn($input['customer_id'] ?? null,$auth);
    }
    if (isset($input['user_type']) && !in_array($action,['get_part_listings','get_bids','add_rating'],true) && $input['user_type']!==$auth['user_type']) apiDeny('Hesap türü uyuşmuyor.');
    if (in_array($action,['update_vehicle','delete_vehicle','get_vehicle_records','add_vehicle_record','update_vehicle_record','delete_vehicle_record'],true)) {
        $stmt=$pdo->prepare('SELECT customer_id FROM vehicles WHERE id=?'); $stmt->execute([$input['vehicle_id'] ?? 0]);
        apiOwn($stmt->fetchColumn(),$auth);
        if (in_array($action,['update_vehicle_record','delete_vehicle_record'],true)) {
            $stmt=$pdo->prepare('SELECT vehicle_id FROM vehicle_records WHERE id=?'); $stmt->execute([$input['record_id'] ?? 0]);
            if ((int)$stmt->fetchColumn()!==(int)$input['vehicle_id']) apiDeny();
        }
    }
    if (in_array($action,['send_message','get_messages','get_job_status','upload_job_evidence','confirm_job_evidence','verify_code',
        'expand_search_radius','cancel_job','customer_payment','provider_payment','add_rating','appeal_rating','trigger_sos','create_ticket'],true)) {
        $job=apiJob($pdo,$input['job_id'] ?? 0,$auth,$action==='get_job_status');
        if (in_array($action,['customer_payment','expand_search_radius'],true) && (int)$job['customer_id']!==(int)$auth['user_id']) apiDeny();
        if (in_array($action,['provider_payment','upload_job_evidence','verify_code'],true) && (int)$job['provider_id']!==(int)$auth['user_id']) apiDeny();
        // Rental status is managed exclusively by the reservation endpoints.
        if ($job['service_type']==='rentacar' && !in_array($action,['send_message','get_messages','get_job_status','trigger_sos','create_ticket'],true)) apiDeny('Kiralama işlemini kiralama panelinden yönetin.');
        if (in_array($action,['add_rating','create_ticket'],true)) {
            if ((int)($input['customer_id'] ?? 0)!==(int)$job['customer_id'] || (int)($input['provider_id'] ?? 0)!==(int)$job['provider_id']) apiDeny();
            $_POST['rater_type']=$auth['user_type'];
        }
        if (in_array($action,['send_message','get_messages'],true)) {
            apiOwn($input[$action==='send_message' ? 'sender_id':'user_id'] ?? null,$auth);
            $receiver=(int)$auth['user_id']===(int)$job['customer_id'] ? $job['provider_id'] : $job['customer_id'];
            if ((int)($input['receiver_id'] ?? 0)!==(int)$receiver) apiDeny();
            if ($action==='send_message') $_POST['sender_type']=$auth['user_type']==='customer' ? 'customer':'provider';
        }
    }
    if (in_array($action,['accept_bid','counter_bid','reject_bid'],true)) {
        $stmt=$pdo->prepare('SELECT b.*,j.customer_id,j.service_type FROM bids b JOIN jobs j ON j.id=b.job_id WHERE b.id=?');
        $stmt->execute([$input['bid_id'] ?? 0]); $bid=$stmt->fetch();
        if (!$bid && $action==='accept_bid') {
            $stmt=$pdo->prepare('SELECT b.*,j.customer_id,j.service_type FROM bids b JOIN jobs j ON j.id=b.job_id WHERE b.job_id=? AND b.provider_id=? ORDER BY b.id DESC LIMIT 1');
            $stmt->execute([$input['job_id'] ?? 0,$input['provider_id'] ?? 0]); $bid=$stmt->fetch();
        }
        if (!$bid || $bid['service_type']==='rentacar') apiDeny();
        $actor=$auth['user_type'];
        apiOwn($bid[$actor==='customer' ? 'customer_id':'provider_id'],$auth);
        if (isset($input['user_type']) && $input['user_type']!==$actor) apiDeny();
        if ($action==='accept_bid') {
            if ((int)$bid['job_id']!==(int)($input['job_id'] ?? 0) || (int)$bid['provider_id']!==(int)($input['provider_id'] ?? 0)) apiDeny();
            if (($bid['last_bidder'] ?? 'provider')===$actor) apiDeny('Kendi teklifinizi kabul edemezsiniz.');
            // Preserve the displayed price: replacing it could accept a changed offer.
            $_POST['bid_id']=$bid['id'];
        }
    }
    if ($action==='get_bids') {
        if ($auth['user_type']==='customer') { apiJob($pdo,$input['job_id'] ?? 0,$auth); $_GET['user_type']='customer'; }
        else { apiOwn($input['provider_id'] ?? null,$auth); $_GET['user_type']='provider'; }
    }
    if ($action==='send_notification') {
        $job=apiJob($pdo,$input['job_id'] ?? 0,$auth);
        $receiver=(int)$auth['user_id']===(int)$job['customer_id'] ? $job['provider_id'] : $job['customer_id'];
        if (!empty($input['target']) && (string)$input['target']!==(string)$receiver) apiDeny();
        $_POST['target']=$receiver;
    }
    if (in_array($action,['get_part_listings','place_part_bid','delete_part_record'],true) && isset($input['user_id'])) apiOwn($input['user_id'],$auth);
    if ($action==='place_part_bid') {
        apiOwn($input['seller_id'] ?? null,$auth);
        if (($input['seller_type'] ?? '')!==$auth['user_type']) apiDeny();
    }
    if (in_array($action,['accept_part_bid','reject_part_bid','complete_part_trade','delete_part_record'],true)) {
        $listingId=$input['listing_id'] ?? 0;
        if ($action==='reject_part_bid') {
            $stmt=$pdo->prepare('SELECT listing_id FROM part_bids WHERE id=?'); $stmt->execute([$input['bid_id'] ?? 0]); $listingId=$stmt->fetchColumn();
        }
        $stmt=$pdo->prepare('SELECT * FROM part_listings WHERE id=?'); $stmt->execute([$listingId]); $listing=$stmt->fetch();
        if (!$listing) apiDeny();
        if ($action==='delete_part_record') {
            if (!in_array((int)$auth['user_id'],[(int)$listing['customer_id'],(int)$listing['seller_id']],true)) apiDeny();
        } else apiOwn($listing['customer_id'],$auth);
        if (in_array($action,['accept_part_bid','reject_part_bid'],true)) {
            $stmt=$pdo->prepare('SELECT listing_id,amount FROM part_bids WHERE id=?'); $stmt->execute([$input['bid_id'] ?? 0]); $bid=$stmt->fetch();
            if (!$bid || (int)$bid['listing_id']!==(int)$listing['id']) apiDeny();
            $_POST['amount']=$bid['amount'];
        }
    }
}
