DROP TABLE IF EXISTS cashplay.currencies;
CREATE TABLE IF NOT EXISTS cashplay.currencies(
  id SERIAL PRIMARY KEY,
  country_code TEXT NOT NULL CHECK (char_length(country_code)<3),
  currency_code TEXT NOT NULL CHECK (char_length(country_code)<4),
  we_buy DOUBLE PRECISION DEFAULT 1,
  we_sell DOUBLE PRECISION DEFAULT 1
);

