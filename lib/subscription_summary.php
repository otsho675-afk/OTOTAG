<?php
require_once __DIR__.'/purchase_verification.php';
function subscriptionSummary($user,$now=null) {
    $now=$now ?? time(); $plans=[];
    $add=function($id,$name,$end,$active,$included=false,$trial=false)use(&$plans,$now) {
        $expiry=$end ? strtotime($end) : false;
        $plans[]=['id'=>$id,'name'=>$name,'active'=>(bool)$active,'included'=>$included,'trial'=>$trial,
            'ends_at'=>$expiry ? gmdate('c',$expiry):null,
            'remaining_days'=>$active && $expiry ? max(0,(int)ceil(($expiry-$now)/86400)):0];
    };
    $role=$user['user_type']; $business=null;
    if (in_array($role,['provider','rentacar'],true)) {
        $business=businessSubscriptionStatus($user,$now);
        $add('business',$role==='rentacar'?'Rent A Car üyeliği':'Usta üyeliği',$business['access_end'],$business['can_work'],false,$business['is_trial']);
    }
    if ($role==='customer') {
        $end=$user['premium_end_date'] ?? null;
        $active=!empty($user['is_premium']) && (!$end || strtotime($end)>$now);
        $add('premium','Premium garaj',$end,$active);
    }
    $included=$role==='rentacar' && $business['can_work'];
    $end=$user['obd_subscription_end_date'] ?? null;
    if ($included && strtotime($business['access_end'])>(strtotime($end ?? '') ?: 0)) $end=$business['access_end'];
    $add('diagnostic','OBD arıza tespit',$end,$included || ($end && strtotime($end)>$now),$included);
    return ['status'=>'success','server_time'=>gmdate('c',$now),'plans'=>$plans];
}
