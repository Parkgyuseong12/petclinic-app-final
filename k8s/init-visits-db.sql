-- Visits Service 데이터베이스 스키마 및 더미 데이터
-- 실행 방법: mysql -h <RDS_ENDPOINT> -u <USERNAME> -p < init-visits-db.sql

CREATE DATABASE IF NOT EXISTS visits_db;
USE visits_db;

-- UTF-8 설정
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- ============================================
-- 테이블 생성
-- ============================================

-- 방문 기록(Visit) 테이블
-- 주의: pet_id는 customers_db의 pets 테이블을 참조하지만, FK 제약조건은 없음 (다른 DB 참조 불가)
CREATE TABLE IF NOT EXISTS visits (
  id INT(4) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  pet_id INT(4) UNSIGNED NOT NULL,
  visit_date DATETIME(6) NOT NULL,
  description VARCHAR(8192)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 더미 데이터
-- ============================================

-- 방문 기록 데이터
-- pet_id는 customers_db의 pets 테이블 ID를 참조 (FK 없음)
INSERT IGNORE INTO visits (id, pet_id, visit_date, description) VALUES 
(1, 7, '2010-03-04 10:00:00.000000', 'rabies shot'),
(2, 8, '2011-03-04 14:30:00.000000', 'rabies shot'),
(3, 8, '2009-06-04 09:15:00.000000', 'neutered'),
(4, 7, '2008-09-04 11:00:00.000000', 'spayed'),
(5, 1, '2024-01-15 10:30:00.000000', 'Annual checkup'),
(6, 2, '2024-02-20 15:00:00.000000', 'Vaccination');

SELECT 'Visits database schema and data created successfully!' AS status;

