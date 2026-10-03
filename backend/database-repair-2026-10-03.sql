-- Run in the existing elite database. This is NOT a full backup restore.
-- Adds missing lookup indexes. Existing rows, ownership and dates are preserved.
-- Each statement is safe to rerun; DDL is not transactionally rollbackable.
SET @db = DATABASE();

SET @ddl = IF(EXISTS(SELECT 1 FROM information_schema.statistics WHERE table_schema=@db AND table_name='vehicles' AND index_name='idx_vehicle_customer_id'),
 'SELECT 1', 'ALTER TABLE vehicles ADD INDEX idx_vehicle_customer_id(customer_id,id)');
PREPARE repair_stmt FROM @ddl;
EXECUTE repair_stmt;
DEALLOCATE PREPARE repair_stmt;

SET @ddl = IF(EXISTS(SELECT 1 FROM information_schema.statistics WHERE table_schema=@db AND table_name='vehicle_records' AND index_name='idx_vehicle_records_vehicle_id'),
 'SELECT 1', 'ALTER TABLE vehicle_records ADD INDEX idx_vehicle_records_vehicle_id(vehicle_id,id)');
PREPARE repair_stmt FROM @ddl;
EXECUTE repair_stmt;
DEALLOCATE PREPARE repair_stmt;

SET @ddl = IF(EXISTS(SELECT 1 FROM information_schema.statistics WHERE table_schema=@db AND table_name='notifications' AND index_name='idx_notifications_user_id'),
 'SELECT 1', 'ALTER TABLE notifications ADD INDEX idx_notifications_user_id(user_id,id)');
PREPARE repair_stmt FROM @ddl;
EXECUTE repair_stmt;
DEALLOCATE PREPARE repair_stmt;

-- Start the new five-minute scheduler on its next run. Dedupe rows are retained.
INSERT INTO app_settings(setting_key,setting_value)
VALUES ('vehicle_reminder_scan_at','0')
ON DUPLICATE KEY UPDATE setting_value=setting_value;

-- Read-only integrity checks. Historical rows are not automatically deleted.
SELECT v.id AS vehicle_id, v.customer_id AS missing_customer
FROM vehicles v LEFT JOIN users u ON u.id=v.customer_id WHERE u.id IS NULL;
SELECT r.id AS record_id, r.vehicle_id AS missing_vehicle
FROM vehicle_records r LEFT JOIN vehicles v ON v.id=r.vehicle_id WHERE v.id IS NULL;
SELECT j.id AS job_id, j.customer_id AS missing_customer, j.status
FROM jobs j LEFT JOIN users u ON u.id=j.customer_id WHERE u.id IS NULL;
SELECT m.id AS message_id, m.job_id AS missing_job
FROM messages m LEFT JOIN jobs j ON j.id=m.job_id WHERE j.id IS NULL;
SELECT p.id AS car_id, p.provider_id AS missing_provider
FROM provider_cars p LEFT JOIN users u ON u.id=p.provider_id WHERE u.id IS NULL;
SELECT r.id AS rating_id, r.job_id AS missing_job
FROM ratings r LEFT JOIN jobs j ON j.id=r.job_id WHERE j.id IS NULL;
SELECT n.id AS notification_id, n.user_id AS missing_user
FROM notifications n LEFT JOIN users u ON u.id=n.user_id WHERE u.id IS NULL;
SELECT status, COUNT(*) AS total FROM notification_outbox GROUP BY status;
