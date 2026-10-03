-- Salt okunur. phpMyAdmin'de elite veritabaninin SQL sekmesinde calistirin.
-- Son 5 talebi inceler; talep olusturmaz, iptal etmez ve bildirim gondermez.
-- Konum mesafesi kayitli sunucu konumuna gore; Chrome'un anlik konumu farkli olabilir.
SELECT j.id AS talep, j.created_at AS olusturulma,
       j.status AS talep_durumu, j.service_type AS istenen_hizmet,
       p.service_category AS usta_hizmeti, j.city AS talep_sehri,
       p.city AS usta_sehri, j.search_radius AS talep_alani_km,
       ROUND(ST_Distance_Sphere(POINT(p.lng,p.lat), POINT(j.longitude,j.latitude))/1000,2) AS kayitli_mesafe_km,
       (p.status='active' AND COALESCE(p.is_suspended,0)=0) AS usta_aktif,
       (c.status='active' AND COALESCE(c.is_suspended,0)=0) AS musteri_aktif,
       (p.subscription_end_date>NOW() OR DATE_ADD(p.created_at,INTERVAL 30 DAY)>NOW()) AS uyelik_uygun,
       EXISTS(SELECT 1 FROM bids b WHERE b.job_id=j.id AND b.provider_id=p.id) AS onceden_teklif_var,
       EXISTS(SELECT 1 FROM jobs busy WHERE busy.provider_id=p.id
         AND busy.status IN ('matched','accepted','approved','in_progress','customer_paid')) AS usta_baska_iste
FROM jobs j
JOIN users c ON c.id=j.customer_id
JOIN users p ON p.id=53 AND p.user_type='provider'
WHERE j.customer_id=45
ORDER BY j.id DESC LIMIT 5;
