
-- Индекс 1: поиск поездок конкретного пользователя — частый паттерн "история поездок" в приложении
CREATE INDEX idx_trips_user_id ON trips(user_id);

-- Индекс 2: поиск действующей версии тарифа по коду — используется почти в каждом
-- запросе расчёта стоимости поездки (SCD2: нужно быстро найти is_current = true)
CREATE INDEX idx_tariffs_code_current ON tariffs(tariff_code, is_current) WHERE is_current = TRUE;

-- Индекс 3: фильтрация поездок по диапазону дат — частый паттерн в отчётах ("поездки за март")
CREATE INDEX idx_trips_start_time ON trips(start_time);

-- Индекс 4: быстрый поиск платежей по поездке — JOIN trips-payments происходит
-- почти в каждом финансовом запросе
CREATE INDEX idx_payments_trip_id ON payments(trip_id);

-- Индекс 5: поиск ТС по статусу — частый запрос в мобильном приложении
-- ("показать все available самокаты рядом")
CREATE INDEX idx_vehicles_status ON vehicles(status);


-- View 1: полная детализация поездки — избавляет от необходимости писать 4 JOIN вручную
CREATE VIEW v_trip_details AS
SELECT t.trip_id, u.first_name || ' ' || u.last_name AS user_name,
       v.model, v.vehicle_type, s1.name AS start_station, s2.name AS end_station,
       t.start_time, t.end_time, t.distance_km, t.status
FROM trips t
JOIN users u ON t.user_id = u.user_id
JOIN vehicles v ON t.vehicle_id = v.vehicle_id
JOIN stations s1 ON t.start_station_id = s1.station_id
LEFT JOIN stations s2 ON t.end_station_id = s2.station_id;

-- View 2: только действующие сейчас тарифы
CREATE VIEW v_current_tariffs AS
SELECT tariff_key, tariff_code, name, price_per_minute, unlock_fee
FROM tariffs
WHERE is_current = TRUE;

-- View 3: финансовая сводка по пользователю — готовый агрегат для профиля клиента
CREATE VIEW v_user_spending AS
SELECT u.user_id, u.first_name, u.last_name,
       COUNT(DISTINCT t.trip_id) AS total_trips,
       COALESCE(SUM(p.amount), 0) AS total_spent
FROM users u
LEFT JOIN trips t ON u.user_id = t.user_id
LEFT JOIN payments p ON t.trip_id = p.trip_id AND p.payment_status = 'success'
GROUP BY u.user_id, u.first_name, u.last_name;

-- Процедура 1: добавление новой станции.
-- Обоснование: даёт единую точку входа с логированием вместо прямого INSERT;
-- если позже понадобится, например, запрет дублирующихся координат -
-- логику достаточно изменить в одном месте.
CREATE OR REPLACE PROCEDURE add_station(
    p_name VARCHAR, p_address VARCHAR, p_city VARCHAR,
    p_lat NUMERIC, p_lon NUMERIC, p_capacity INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO stations (name, address, city, latitude, longitude, capacity)
    VALUES (p_name, p_address, p_city, p_lat, p_lon, p_capacity);
    RAISE NOTICE 'Станция % добавлена', p_name;
END;
$$;

CALL add_station('Люблино', 'Люблинская ул., 3', 'Москва', 55.6772, 37.7522, 16);



-- Транзакция 1: завершение поездки + создание платежа.
-- Обоснование: нельзя оставить поездку "завершённой" без соответствующего платежа —
-- это создало бы финансовую дыру в учёте.
BEGIN;

UPDATE trips
SET end_time = NOW(), end_station_id = 5, distance_km = 4.20, status = 'completed'
WHERE trip_id = 39;

INSERT INTO payments (trip_id, amount, payment_method, payment_status, transaction_reference)
VALUES (39, 210.00, 'card', 'success', 'TXN00039');

COMMIT;


-- Транзакция 2: применение промокода с проверкой и уменьшением лимита использования.
-- Обоснование: нельзя списать скидку, если параллельно кто-то уже исчерпал лимит промокода 
-- FOR UPDATE блокирует строку промокода на время транзакции.
BEGIN;

SELECT usage_limit FROM promocodes WHERE promocode_id = 5 FOR UPDATE;

INSERT INTO trip_promocodes (trip_id, promocode_id, applied_discount_amount)
VALUES (40, 5, 91.00);

UPDATE promocodes
SET usage_limit = usage_limit - 1
WHERE promocode_id = 5 AND usage_limit > 0;

COMMIT;
