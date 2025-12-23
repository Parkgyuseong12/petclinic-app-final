-- Customers Service 데이터베이스 스키마 및 더미 데이터
-- 실행 방법: mysql -h <RDS_ENDPOINT> -u <USERNAME> -p < init-customers-db.sql

CREATE DATABASE IF NOT EXISTS customers_db;
USE customers_db;

-- UTF-8 설정
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

-- ============================================
-- 테이블 생성
-- ============================================

-- 애완동물 타입 테이블
CREATE TABLE IF NOT EXISTS types (
  id INT(4) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(80),
  INDEX(name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 주인(Owner) 테이블
CREATE TABLE IF NOT EXISTS owners (
  id INT(4) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  first_name VARCHAR(30),
  last_name VARCHAR(30),
  address VARCHAR(255),
  city VARCHAR(80),
  telephone VARCHAR(20),
  INDEX(last_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 애완동물(Pet) 테이블
CREATE TABLE IF NOT EXISTS pets (
  id INT(4) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(30),
  birth_date DATE,
  type_id INT(4) UNSIGNED NOT NULL,
  owner_id INT(4) UNSIGNED NOT NULL,
  INDEX(name),
  FOREIGN KEY (owner_id) REFERENCES owners(id),
  FOREIGN KEY (type_id) REFERENCES types(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- 더미 데이터
-- ============================================

-- 애완동물 타입 데이터
INSERT IGNORE INTO types (id, name) VALUES 
(1, 'cat'),
(2, 'dog'),
(3, 'lizard'),
(4, 'snake'),
(5, 'bird'),
(6, 'hamster');

-- 주인 데이터
INSERT IGNORE INTO owners (id, first_name, last_name, address, city, telephone) VALUES 
(1, 'George', 'Franklin', '110 W. Liberty St.', 'Madison', '6085551023'),
(2, 'Betty', 'Davis', '638 Cardinal Ave.', 'Sun Prairie', '6085551749'),
(3, 'Eduardo', 'Rodriquez', '2693 Commerce St.', 'McFarland', '6085558763'),
(4, 'Harold', 'Davis', '563 Friendly St.', 'Windsor', '6085553198'),
(5, 'Peter', 'McTavish', '2387 S. Fair Way', 'Madison', '6085552765');

-- 애완동물 데이터
INSERT IGNORE INTO pets (id, name, birth_date, type_id, owner_id) VALUES 
(1, 'Leo', '2000-09-07', 1, 1),
(2, 'Basil', '2002-08-06', 6, 2),
(3, 'Rosy', '2001-04-17', 2, 3),
(4, 'Jewel', '2000-03-07', 2, 3),
(5, 'Iggy', '2000-11-30', 3, 4),
(6, 'George', '2000-01-20', 4, 5),
(7, 'Samantha', '1995-09-04', 1, 1),
(8, 'Max', '1995-09-04', 1, 2);

SELECT 'Customers database schema and data created successfully!' AS status;

