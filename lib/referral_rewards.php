<?php

const REFERRAL_INVITER_POINTS = 100;
const REFERRAL_INVITED_POINTS = 50;

function ensureReferralSchema($pdo) {
    apiSchemaMigration($pdo,'referral_rewards_v1',function() use($pdo) {
        $columns=$pdo->query("SHOW COLUMNS FROM users")->fetchAll(PDO::FETCH_COLUMN);
        $definitions=[
            'referral_code'=>"VARCHAR(20) NULL",
            'referred_by'=>"INT NULL",
            'reward_points'=>"INT NOT NULL DEFAULT 0",
        ];
        foreach ($definitions as $column=>$definition) {
            if (!in_array($column,$columns,true)) {
                $pdo->exec("ALTER TABLE users ADD COLUMN `$column` $definition");
            }
        }
        if (!$pdo->query("SHOW INDEX FROM users WHERE Key_name='idx_users_referral_code'")->fetch()) {
            $pdo->exec("CREATE UNIQUE INDEX idx_users_referral_code ON users(referral_code)");
        }
        if (!$pdo->query("SHOW INDEX FROM users WHERE Key_name='idx_users_referred_by'")->fetch()) {
            $pdo->exec("CREATE INDEX idx_users_referred_by ON users(referred_by)");
        }

        $pdo->exec("CREATE TABLE IF NOT EXISTS referral_rewards (
            id BIGINT AUTO_INCREMENT PRIMARY KEY,
            inviter_id INT NOT NULL,
            invited_user_id INT NOT NULL,
            inviter_points INT NOT NULL DEFAULT 100,
            invited_points INT NOT NULL DEFAULT 50,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            qualifying_job_id INT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            rewarded_at DATETIME NULL,
            UNIQUE KEY uq_referral_invited (invited_user_id),
            KEY idx_referral_inviter_status (inviter_id,status),
            KEY idx_referral_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    });
}

function referralGenerateCode($pdo) {
    for ($attempt=0;$attempt<12;$attempt++) {
        $alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
        $suffix='';
        for ($i=0;$i<6;$i++) $suffix.=$alphabet[random_int(0,strlen($alphabet)-1)];
        $code='TAG-'.$suffix;
        $stmt=$pdo->prepare('SELECT id FROM users WHERE referral_code=? LIMIT 1');
        $stmt->execute([$code]);
        if (!$stmt->fetchColumn()) return $code;
    }
    throw new RuntimeException('Davet kodu oluşturulamadı.');
}

function referralEnsureUserCode($pdo,$userId) {
    ensureReferralSchema($pdo);
    $stmt=$pdo->prepare('SELECT referral_code FROM users WHERE id=?');
    $stmt->execute([$userId]);
    $code=$stmt->fetchColumn();
    if ($code) return $code;
    $code=referralGenerateCode($pdo);
    $pdo->prepare('UPDATE users SET referral_code=? WHERE id=? AND (referral_code IS NULL OR referral_code="")')
        ->execute([$code,$userId]);
    $stmt->execute([$userId]);
    return (string)$stmt->fetchColumn();
}

function referralResolveInviter($pdo,$code) {
    ensureReferralSchema($pdo);
    $code=strtoupper(trim((string)$code));
    if ($code==='') return null;
    if (!preg_match('/^TAG-[A-Z2-9]{6}$/D',$code)) {
        throw new InvalidArgumentException('Davet kodu geçersiz.');
    }
    $stmt=$pdo->prepare("SELECT id FROM users WHERE referral_code=? AND status<>'banned' LIMIT 1");
    $stmt->execute([$code]);
    $id=$stmt->fetchColumn();
    if (!$id) throw new InvalidArgumentException('Davet kodu bulunamadı.');
    return (int)$id;
}

function referralAttachNewUser($pdo,$newUserId,$inviterId=null) {
    ensureReferralSchema($pdo);
    referralEnsureUserCode($pdo,$newUserId);
    if (!$inviterId) return;
    if ((int)$inviterId===(int)$newUserId) throw new InvalidArgumentException('Kendi davet kodunuzu kullanamazsınız.');

    $stmt=$pdo->prepare('SELECT referred_by FROM users WHERE id=? FOR UPDATE');
    $stmt->execute([$newUserId]);
    $existing=$stmt->fetchColumn();
    if ($existing) return;

    $pdo->prepare('UPDATE users SET referred_by=? WHERE id=? AND referred_by IS NULL')
        ->execute([$inviterId,$newUserId]);
    $pdo->prepare("INSERT IGNORE INTO referral_rewards
        (inviter_id,invited_user_id,inviter_points,invited_points,status)
        VALUES (?,?,?,?, 'pending')")
        ->execute([$inviterId,$newUserId,REFERRAL_INVITER_POINTS,REFERRAL_INVITED_POINTS]);
}

function referralRewardUserFromCompletedJob($pdo,$invitedUserId,$jobId) {
    ensureReferralSchema($pdo);
    if ($pdo->inTransaction()) throw new RuntimeException('Davet ödülü açık işlem içinde çalıştırılamaz.');

    $pdo->beginTransaction();
    try {
        $stmt=$pdo->prepare("SELECT * FROM referral_rewards WHERE invited_user_id=? AND status='pending' FOR UPDATE");
        $stmt->execute([$invitedUserId]);
        $reward=$stmt->fetch(PDO::FETCH_ASSOC);
        if (!$reward) { $pdo->commit(); return false; }

        $prior=$pdo->prepare("SELECT COUNT(*) FROM jobs WHERE status='completed' AND id<>? AND (customer_id=? OR provider_id=?)");
        $prior->execute([$jobId,$invitedUserId,$invitedUserId]);
        if ((int)$prior->fetchColumn()>0) {
            $pdo->prepare("UPDATE referral_rewards SET status='rejected',qualifying_job_id=? WHERE id=?")
                ->execute([$jobId,$reward['id']]);
            $pdo->commit();
            return false;
        }

        $pdo->prepare('UPDATE users SET reward_points=reward_points+? WHERE id=?')
            ->execute([(int)$reward['inviter_points'],(int)$reward['inviter_id']]);
        $pdo->prepare('UPDATE users SET reward_points=reward_points+? WHERE id=?')
            ->execute([(int)$reward['invited_points'],(int)$reward['invited_user_id']]);
        $pdo->prepare("UPDATE referral_rewards SET status='rewarded',qualifying_job_id=?,rewarded_at=NOW() WHERE id=?")
            ->execute([$jobId,$reward['id']]);

        $pdo->prepare("INSERT INTO notifications(user_id,title,message) VALUES
            (?,'Davet ödülü kazandın',?),
            (?,'Hoş geldin ödülün hazır',?)")
            ->execute([
                $reward['inviter_id'],
                (int)$reward['inviter_points'].' OTO TAG Puan hesabına eklendi.',
                $reward['invited_user_id'],
                (int)$reward['invited_points'].' OTO TAG Puan hesabına eklendi.'
            ]);
        $pdo->commit();

        try {
            if (function_exists('sendOneSignalPush')) {
                sendOneSignalPush((string)$reward['inviter_id'],'Davet ödülü kazandın',(int)$reward['inviter_points'].' OTO TAG Puan hesabına eklendi.',['type'=>'referral_reward']);
                sendOneSignalPush((string)$reward['invited_user_id'],'Hoş geldin ödülün hazır',(int)$reward['invited_points'].' OTO TAG Puan hesabına eklendi.',['type'=>'referral_reward']);
            }
        } catch (Throwable $e) {}
        return true;
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
}

function referralRewardForCompletedJob($pdo,$jobId) {
    ensureReferralSchema($pdo);
    $stmt=$pdo->prepare("SELECT id,customer_id,provider_id,status FROM jobs WHERE id=?");
    $stmt->execute([$jobId]);
    $job=$stmt->fetch(PDO::FETCH_ASSOC);
    if (!$job || $job['status']!=='completed') return;
    $participants=array_values(array_unique(array_filter([
        (int)$job['customer_id'],
        (int)($job['provider_id'] ?? 0)
    ])));
    foreach ($participants as $userId) {
        try { referralRewardUserFromCompletedJob($pdo,$userId,(int)$jobId); }
        catch (Throwable $e) { error_log('Referral reward failed for user '.$userId.': '.$e->getMessage()); }
    }
}

function referralSummary($pdo,$userId) {
    ensureReferralSchema($pdo);
    $code=referralEnsureUserCode($pdo,$userId);
    $stmt=$pdo->prepare('SELECT reward_points FROM users WHERE id=?');
    $stmt->execute([$userId]);
    $points=(int)$stmt->fetchColumn();

    $stmt=$pdo->prepare("SELECT
        COUNT(*) total,
        SUM(status='pending') pending_count,
        SUM(status='rewarded') rewarded_count,
        COALESCE(SUM(CASE WHEN status='rewarded' THEN inviter_points ELSE 0 END),0) earned_points
        FROM referral_rewards WHERE inviter_id=?");
    $stmt->execute([$userId]);
    $stats=$stmt->fetch(PDO::FETCH_ASSOC) ?: [];

    $stmt=$pdo->prepare("SELECT r.status,r.created_at,r.rewarded_at,r.inviter_points,
        u.name invited_name,u.user_type invited_user_type
        FROM referral_rewards r
        JOIN users u ON u.id=r.invited_user_id
        WHERE r.inviter_id=?
        ORDER BY r.id DESC LIMIT 30");
    $stmt->execute([$userId]);

    return [
        'status'=>'success',
        'referral_code'=>$code,
        'reward_points'=>$points,
        'inviter_reward'=>REFERRAL_INVITER_POINTS,
        'invited_reward'=>REFERRAL_INVITED_POINTS,
        'stats'=>[
            'total'=>(int)($stats['total'] ?? 0),
            'pending'=>(int)($stats['pending_count'] ?? 0),
            'rewarded'=>(int)($stats['rewarded_count'] ?? 0),
            'earned_points'=>(int)($stats['earned_points'] ?? 0),
        ],
        'referrals'=>$stmt->fetchAll(PDO::FETCH_ASSOC),
    ];
}
