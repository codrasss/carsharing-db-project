CREATE TABLE stations (
    station_id      SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    address         VARCHAR(200) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    latitude        NUMERIC(9,6) NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude       NUMERIC(9,6) NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    capacity        INT NOT NULL CHECK (capacity > 0)
);
COMMENT ON TABLE stations IS 'Станции парковки самокатов/автомобилей каршеринга';

CREATE TABLE users (
    user_id                 SERIAL PRIMARY KEY,
    first_name              VARCHAR(50) NOT NULL,
    last_name               VARCHAR(50) NOT NULL,
    email                   VARCHAR(100) NOT NULL UNIQUE,
    phone                   VARCHAR(20) NOT NULL UNIQUE,
    password_hash           VARCHAR(255) NOT NULL,
    driver_license_number   VARCHAR(20) NOT NULL UNIQUE,
    registration_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    bonus_balance           NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (bonus_balance >= 0)
);
COMMENT ON TABLE users IS 'Пользователи сервиса каршеринга';

CREATE TABLE vehicles (
    vehicle_id          SERIAL PRIMARY KEY,
    model                VARCHAR(50) NOT NULL,
    vehicle_type         VARCHAR(20) NOT NULL CHECK (vehicle_type IN ('scooter','car','bike')),
    license_plate        VARCHAR(20) UNIQUE,
    status                VARCHAR(20) NOT NULL DEFAULT 'available'
                          CHECK (status IN ('available','in_use','maintenance')),
    current_station_id   INT REFERENCES stations(station_id) ON DELETE SET NULL,
    battery_level         INT CHECK (battery_level BETWEEN 0 AND 100),
    purchase_date         DATE NOT NULL
);
COMMENT ON TABLE vehicles IS 'Транспортные средства парка (самокаты, велосипеды, автомобили)';


CREATE TABLE tariffs (
    tariff_key        SERIAL PRIMARY KEY,
    tariff_code        VARCHAR(20) NOT NULL,
    name                VARCHAR(50) NOT NULL,
    price_per_minute    NUMERIC(6,2) NOT NULL CHECK (price_per_minute >= 0),
    unlock_fee          NUMERIC(6,2) NOT NULL DEFAULT 0 CHECK (unlock_fee >= 0),
    description         TEXT,
    valid_from           TIMESTAMP NOT NULL,
    valid_to             TIMESTAMP,
    is_current           BOOLEAN NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE tariffs IS 'Тарифы каршеринга. SCD2: каждая строка — версия тарифа, действовавшая в период [valid_from, valid_to]';

CREATE TABLE promocodes (
    promocode_id      SERIAL PRIMARY KEY,
    code                VARCHAR(20) NOT NULL UNIQUE,
    discount_type       VARCHAR(10) NOT NULL CHECK (discount_type IN ('percent','fixed')),
    discount_value      NUMERIC(6,2) NOT NULL CHECK (discount_value > 0),
    valid_from           DATE NOT NULL,
    valid_to             DATE NOT NULL CHECK (valid_to >= valid_from),
    usage_limit          INT CHECK (usage_limit > 0)
);
COMMENT ON TABLE promocodes IS 'Промокоды на скидку';


CREATE TABLE trips (
    trip_id            SERIAL PRIMARY KEY,
    user_id             INT NOT NULL REFERENCES users(user_id) ON DELETE RESTRICT,
    vehicle_id           INT NOT NULL REFERENCES vehicles(vehicle_id) ON DELETE RESTRICT,
    tariff_key           INT NOT NULL REFERENCES tariffs(tariff_key) ON DELETE RESTRICT,
    start_station_id     INT NOT NULL REFERENCES stations(station_id),
    end_station_id       INT REFERENCES stations(station_id),
    start_time            TIMESTAMP NOT NULL DEFAULT NOW(),
    end_time              TIMESTAMP CHECK (end_time > start_time),
    distance_km           NUMERIC(6,2) CHECK (distance_km >= 0),
    status                 VARCHAR(20) NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active','completed','cancelled'))
);
COMMENT ON TABLE trips IS 'Поездки пользователей — центральная таблица схемы';


CREATE TABLE payments (
    payment_id             SERIAL PRIMARY KEY,
    trip_id                  INT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    amount                    NUMERIC(8,2) NOT NULL CHECK (amount >= 0),
    payment_method            VARCHAR(20) NOT NULL CHECK (payment_method IN ('card','wallet','bonus')),
    payment_status            VARCHAR(20) NOT NULL CHECK (payment_status IN ('pending','success','failed')),
    payment_date              TIMESTAMP NOT NULL DEFAULT NOW(),
    transaction_reference     VARCHAR(50) UNIQUE
);
COMMENT ON TABLE payments IS 'Платежи по поездкам';


CREATE TABLE trip_promocodes (
    trip_id                    INT NOT NULL REFERENCES trips(trip_id) ON DELETE CASCADE,
    promocode_id                INT NOT NULL REFERENCES promocodes(promocode_id) ON DELETE RESTRICT,
    applied_discount_amount     NUMERIC(8,2) NOT NULL CHECK (applied_discount_amount >= 0),
    applied_at                   TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (trip_id, promocode_id)
);
COMMENT ON TABLE trip_promocodes IS 'Связка поездок и применённых промокодов (M:M)';


CREATE TABLE vehicle_maintenance (
    maintenance_id       SERIAL PRIMARY KEY,
    vehicle_id             INT NOT NULL REFERENCES vehicles(vehicle_id) ON DELETE CASCADE,
    maintenance_type       VARCHAR(50) NOT NULL,
    description             TEXT,
    cost                    NUMERIC(8,2) NOT NULL CHECK (cost >= 0),
    start_date               DATE NOT NULL,
    end_date                 DATE CHECK (end_date >= start_date),
    technician_name           VARCHAR(100)
);
COMMENT ON TABLE vehicle_maintenance IS 'Журнал технического обслуживания транспорта';