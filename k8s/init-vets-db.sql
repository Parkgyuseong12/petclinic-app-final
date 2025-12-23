-- Vets Service 데이터베이스 스키마 및 더미 데이터
-- 실행 방법: mysql -h <RDS_ENDPOINT> -u <USERNAME> -p < init-vets-db.sql

CREATE DATABASE IF NOT EXISTS vets_db;
USE vets_db;

-- UTF-8 설정
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- ============================================
-- 테이블 생성
-- ============================================

-- 수의사(Vet) 테이블
CREATE TABLE IF NOT EXISTS vets (
  id INT(4) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(30),
  last_name VARCHAR(30),
  INDEX(last_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 전문 분야(Specialty) 테이블
CREATE TABLE IF NOT EXISTS specialties (
  id INT(4) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(80),
  INDEX(name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 수의사-전문 분야 연관 테이블
CREATE TABLE IF NOT EXISTS vet_specialties (
  vet_id INT(4) UNSIGNED NOT NULL,
  specialty_id INT(4) UNSIGNED NOT NULL,
  FOREIGN KEY (vet_id) REFERENCES vets(id),
  FOREIGN KEY (specialty_id) REFERENCES specialties(id),
  UNIQUE (vet_id, specialty_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 더미 데이터
-- ============================================

-- 수의사 데이터
INSERT IGNORE INTO vets (id, first_name, last_name) VALUES 
(1, 'James', 'Carter'),
(2, 'Helen', 'Leary'),
(3, 'Linda', 'Douglas'),
(4, 'Rafael', 'Ortega'),
(5, 'Henry', 'Stevens'),
(6, 'Sharon', 'Jenkins');

-- 전문 분야 데이터
INSERT IGNORE INTO specialties (id, name) VALUES 
(1, 'radiology'),
(2, 'surgery'),
(3, 'dentistry');

-- 수의사-전문 분야 연관 데이터
INSERT IGNORE INTO vet_specialties (vet_id, specialty_id) VALUES 
(2, 1),
(3, 2),
(3, 3),
(4, 2),
(5, 1);

SELECT 'Vets database schema and data created successfully!' AS status;

