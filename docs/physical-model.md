## users

| Поле | Тип | Ограничения |
|---|---|---|
| user_id | serial | PRIMARY KEY |
| first_name | varchar(50) | NOT NULL |
| last_name | varchar(50) | NOT NULL |
| email | varchar(100) | NOT NULL, UNIQUE |
| phone | varchar(20) | NOT NULL, UNIQUE |
| password_hash | varchar(255) | NOT NULL |
| driver_license_number | varchar(20) | NOT NULL, UNIQUE |
| registration_date | date | NOT NULL, DEFAULT current_date |
| bonus_balance | numeric(10,2) | NOT NULL, DEFAULT 0, CHECK (bonus_balance >= 0) |

## stations

| Поле | Тип | Ограничения |
|---|---|---|
| station_id | serial | PRIMARY KEY |
| name | varchar(100) | NOT NULL |
| address | varchar(200) | NOT NULL |
| city | varchar(100) | NOT NULL |
| latitude | numeric(9,6) | NOT NULL, CHECK (latitude BETWEEN -90 AND 90) |
| longitude | numeric(9,6) | NOT NULL, CHECK (longitude BETWEEN -180 AND 180) |
| capacity | int | NOT NULL, CHECK (capacity > 0) |

## vehicles

| Поле | Тип | Ограничения |
|---|---|---|
| vehicle_id | serial | PRIMARY KEY |
| model | varchar(50) | NOT NULL |
| vehicle_type | varchar(20) | NOT NULL, CHECK (vehicle_type IN ('scooter','car','bike')) |
| license_plate | varchar(20) | UNIQUE (NULL допустим — у самокатов номера нет) |
| status | varchar(20) | NOT NULL, DEFAULT 'available', CHECK (status IN ('available','in_use','maintenance')) |
| current_station_id | int | FOREIGN KEY → stations(station_id) ON DELETE SET NULL |
| battery_level | int | CHECK (battery_level BETWEEN 0 AND 100) |
| purchase_date | date | NOT NULL |

## tariffs (версионируемая таблица, SCD2)

| Поле | Тип | Ограничения |
|---|---|---|
| tariff_key | serial | PRIMARY KEY (суррогатный ключ, уникален для каждой версии) |
| tariff_code | varchar(20) | NOT NULL (бизнес-ключ, общий для всех версий одного тарифа) |
| name | varchar(50) | NOT NULL |
| price_per_minute | numeric(6,2) | NOT NULL, CHECK (price_per_minute >= 0) |
| unlock_fee | numeric(6,2) | NOT NULL, DEFAULT 0, CHECK (unlock_fee >= 0) |
| description | text | — |
| valid_from | timestamp | NOT NULL |
| valid_to | timestamp | NULL допустим (NULL = версия ещё действует) |
| is_current | boolean | NOT NULL, DEFAULT true |

**Обоснование SCD2:** тарифы каршеринга меняются со временем. Если хранить только текущую цену и перезаписывать её (SCD1), теряется история — а это критично: поездка, совершённая по старой цене, должна навсегда остаться посчитанной по цене, действовавшей в момент поездки. SCD3 (хранение только "предыдущего" значения) не подходит, так как изменений тарифа за время жизни проекта может быть много, а не одно. SCD2 хранит каждую версию отдельной строкой с периодом действия `[valid_from, valid_to)`, и таблица `trips` ссылается на конкретную версию тарифа (`tariff_key`), а не на "тариф вообще" — это не даёт истории исказиться при последующих изменениях цены.

## trips

| Поле | Тип | Ограничения |
|---|---|---|
| trip_id | serial | PRIMARY KEY |
| user_id | int | NOT NULL, FOREIGN KEY → users(user_id) ON DELETE RESTRICT |
| vehicle_id | int | NOT NULL, FOREIGN KEY → vehicles(vehicle_id) ON DELETE RESTRICT |
| tariff_key | int | NOT NULL, FOREIGN KEY → tariffs(tariff_key) ON DELETE RESTRICT |
| start_station_id | int | NOT NULL, FOREIGN KEY → stations(station_id) |
| end_station_id | int | FOREIGN KEY → stations(station_id) (NULL, пока поездка не завершена) |
| start_time | timestamp | NOT NULL, DEFAULT now() |
| end_time | timestamp | CHECK (end_time > start_time) |
| distance_km | numeric(6,2) | CHECK (distance_km >= 0) |
| status | varchar(20) | NOT NULL, DEFAULT 'active', CHECK (status IN ('active','completed','cancelled')) |

## payments

| Поле | Тип | Ограничения |
|---|---|---|
| payment_id | serial | PRIMARY KEY |
| trip_id | int | NOT NULL, FOREIGN KEY → trips(trip_id) ON DELETE CASCADE |
| amount | numeric(8,2) | NOT NULL, CHECK (amount >= 0) |
| payment_method | varchar(20) | NOT NULL, CHECK (payment_method IN ('card','wallet','bonus')) |
| payment_status | varchar(20) | NOT NULL, CHECK (payment_status IN ('pending','success','failed')) |
| payment_date | timestamp | NOT NULL, DEFAULT now() |
| transaction_reference | varchar(50) | UNIQUE |

## promocodes

| Поле | Тип | Ограничения |
|---|---|---|
| promocode_id | serial | PRIMARY KEY |
| code | varchar(20) | NOT NULL, UNIQUE |
| discount_type | varchar(10) | NOT NULL, CHECK (discount_type IN ('percent','fixed')) |
| discount_value | numeric(6,2) | NOT NULL, CHECK (discount_value > 0) |
| valid_from | date | NOT NULL |
| valid_to | date | NOT NULL, CHECK (valid_to >= valid_from) |
| usage_limit | int | CHECK (usage_limit > 0) |

## trip_promocodes (таблица-связка, составной первичный ключ)

| Поле | Тип | Ограничения |
|---|---|---|
| trip_id | int | PRIMARY KEY (составной), FOREIGN KEY → trips(trip_id) ON DELETE CASCADE |
| promocode_id | int | PRIMARY KEY (составной), FOREIGN KEY → promocodes(promocode_id) ON DELETE RESTRICT |
| applied_discount_amount | numeric(8,2) | NOT NULL, CHECK (applied_discount_amount >= 0) |
| applied_at | timestamp | NOT NULL, DEFAULT now() |

**Обоснование составного ключа:** ни `trip_id`, ни `promocode_id` по отдельности не уникальны в этой таблице (одна поездка может иметь несколько промокодов, один промокод — использоваться в разных поездках), но их сочетание уникально — одна и та же пара "поездка + промокод" не может встретиться дважды. Составной первичный ключ технически запрещает такие дубли на уровне СУБД.

## vehicle_maintenance

| Поле | Тип | Ограничения |
|---|---|---|
| maintenance_id | serial | PRIMARY KEY |
| vehicle_id | int | NOT NULL, FOREIGN KEY → vehicles(vehicle_id) ON DELETE CASCADE |
| maintenance_type | varchar(50) | NOT NULL |
| description | text | — |
| cost | numeric(8,2) | NOT NULL, CHECK (cost >= 0) |
| start_date | date | NOT NULL |
| end_date | date | CHECK (end_date >= start_date) |
| technician_name | varchar(100) | — |

