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
