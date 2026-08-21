-- Запрос 1: Список активных тс с зарядом ниже 50%
-- Назначение: планирование подзарядки тс
SELECT vehicle_id, model, vehicle_type, battery_level, current_station_id
FROM vehicles
WHERE status != 'maintenance' AND battery_level < 50
ORDER BY battery_level ASC;

-- Запрос 2: Топ-5 пользователей по бонусному балансу
-- Назначение: программа лояльности, кому предложить бонусные акции
SELECT user_id, first_name, last_name, bonus_balance
FROM users
WHERE bonus_balance > 0
ORDER BY bonus_balance DESC
LIMIT 5;

-- Запрос 3: Выручка по способам оплаты (только успешные транзакции)
-- Назначение: финансовый отчёт по каналам оплаты
SELECT payment_method, SUM(amount) AS total_revenue, COUNT(*) AS payments_count
FROM payments
WHERE payment_status = 'success'
GROUP BY payment_method
ORDER BY total_revenue DESC;

-- Запрос 4: Станции с более чем 3 стартами поездок
-- Назначение: выявление популярных станций для анализа парка
SELECT start_station_id, COUNT(*) AS trips_started
FROM trips
GROUP BY start_station_id
HAVING COUNT(*) > 3
ORDER BY trips_started DESC;

-- Запрос 5: Пагинация завершённых поездок (вторая страница по 10 штук)
-- Назначение: постраничный вывод истории поездок в приложении
SELECT trip_id, user_id, vehicle_id, start_time, distance_km
FROM trips
WHERE status = 'completed'
ORDER BY start_time
LIMIT 10 OFFSET 10;

-- Запрос 6: Детализация поездок — пользователь, ТС, станции старта/финиша
-- Назначение: полная карточка поездки одним запросом
SELECT t.trip_id, u.first_name || ' ' || u.last_name AS user_name,
       v.model, s1.name AS start_station, s2.name AS end_station
FROM trips t
INNER JOIN users u ON t.user_id = u.user_id
INNER JOIN vehicles v ON t.vehicle_id = v.vehicle_id
INNER JOIN stations s1 ON t.start_station_id = s1.station_id
LEFT JOIN stations s2 ON t.end_station_id = s2.station_id
ORDER BY t.trip_id;

-- Запрос 7: Пользователи без единой поездки
-- Назначение: сегмент для рассылки "неактивным" клиентам
SELECT u.user_id, u.first_name, u.last_name, t.trip_id, t.start_time
FROM users u
LEFT JOIN trips t ON u.user_id = t.user_id
WHERE t.trip_id IS NULL;

-- Запрос 8: Все ТС и их обслуживание, включая ни разу не обслуживавшиеся
-- Назначение: контроль полноты сервисной истории парка 
SELECT v.vehicle_id, v.model, vm.maintenance_type, vm.start_date
FROM vehicle_maintenance vm
RIGHT JOIN vehicles v ON vm.vehicle_id = v.vehicle_id
ORDER BY v.vehicle_id;

-- Запрос 9: Проверка целостности — поездки без платежей и платежи без поездок
-- Назначение: аудит данных на случай сбоев 
SELECT t.trip_id, t.status, p.payment_id, p.payment_status
FROM trips t
FULL JOIN payments p ON t.trip_id = p.trip_id
WHERE t.trip_id IS NULL OR p.payment_id IS NULL;

-- Запрос 10: Поездки длиннее средней длительности
-- Назначение: находим  долгие аренды
SELECT trip_id, user_id, start_time, end_time,
       EXTRACT(EPOCH FROM (end_time - start_time))/60 AS duration_min
FROM trips
WHERE status = 'completed'
  AND EXTRACT(EPOCH FROM (end_time - start_time))/60 >
      (SELECT AVG(EXTRACT(EPOCH FROM (end_time - start_time))/60)
       FROM trips WHERE status = 'completed')
ORDER BY duration_min DESC;

-- Запрос 11: Пользователи, применявшие процентную скидку
-- Назначение: сегмент клиентов для новой процентной акции
SELECT DISTINCT user_id, first_name, last_name
FROM users
WHERE user_id IN (
    SELECT t.user_id
    FROM trips t
    JOIN trip_promocodes tp ON t.trip_id = tp.trip_id
    JOIN promocodes p ON tp.promocode_id = p.promocode_id
    WHERE p.discount_type = 'percent'
);

-- Запрос 12: Станции, где не обслуживалось ни одно стоящее на ней ТС
-- Назначение: сигнал для проверки состояния транспорта на станции
SELECT s.station_id, s.name
FROM stations s
WHERE NOT EXISTS (
    SELECT 1
    FROM vehicles v
    JOIN vehicle_maintenance vm ON vm.vehicle_id = v.vehicle_id
    WHERE v.current_station_id = s.station_id
);

-- Запрос 13: Версии тарифа PREMIUM дороже всех версий ECONOMY
-- Назначение: подтверждение, что премиум-сегмент ценово не пересекается с эконом
SELECT tariff_key, name, price_per_minute, valid_from
FROM tariffs
WHERE tariff_code = 'PREMIUM'
  AND price_per_minute > ALL (
      SELECT price_per_minute FROM tariffs WHERE tariff_code = 'ECONOMY'
  );

-- Запрос 14: Пары поездок одного пользователя в один день подряд
-- Назначение: находим активных клиентов с несколькими поездками за день
SELECT t1.user_id, t1.trip_id AS first_trip, t2.trip_id AS second_trip,
       t1.end_time AS first_ends, t2.start_time AS second_starts
FROM trips t1
JOIN trips t2 ON t1.user_id = t2.user_id
              AND t1.trip_id != t2.trip_id
              AND DATE(t1.end_time) = DATE(t2.start_time)
              AND t2.start_time > t1.end_time;

-- Запрос 15: Порядковый номер поездки пользователя
-- Назначение: для начисления приветственных бонусов за первую поездку
SELECT trip_id, user_id, start_time,
       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY start_time) AS trip_number
FROM trips
ORDER BY user_id, trip_number;

-- Запрос 16: Накопительная сумма трат и сумма предыдущей поездки
-- Назначение: анализ динамики трат клиента во времени
SELECT t.trip_id, t.user_id, t.start_time, p.amount,
       SUM(p.amount) OVER (PARTITION BY t.user_id ORDER BY t.start_time) AS running_total,
       LAG(p.amount) OVER (PARTITION BY t.user_id ORDER BY t.start_time) AS previous_trip_amount
FROM trips t
JOIN payments p ON t.trip_id = p.trip_id
WHERE p.payment_status = 'success'
ORDER BY t.user_id, t.start_time;

-- Запрос 17: Отклонение стоимости поездки от средней по пользователю
-- Назначение: находим нетипично дорогие/дешёвые поездки относительно привычного поведения клиента
SELECT t.trip_id, t.user_id, p.amount,
       ROUND(p.amount - AVG(p.amount) OVER (PARTITION BY t.user_id), 2) AS diff_from_user_avg
FROM trips t
JOIN payments p ON t.trip_id = p.trip_id
WHERE p.payment_status = 'success'
ORDER BY t.user_id;

-- Запрос 18: Календарь дат ноября 2025 с количеством поездок по каждому дню
-- Назначение: вспомогательная таблица 
WITH RECURSIVE date_series AS (
    SELECT DATE '2025-11-01' AS d
    UNION ALL
    SELECT d + 1 FROM date_series WHERE d < DATE '2025-11-30'
)
SELECT ds.d AS calendar_date, COUNT(t.trip_id) AS trips_count
FROM date_series ds
LEFT JOIN trips t ON DATE(t.start_time) = ds.d
GROUP BY ds.d
ORDER BY ds.d;
