CREATE TABLE cashplay.customer (
  id         SERIAL PRIMARY KEY,
  first_name TEXT NOT NULL CHECK (char_length(first_name) < 80),
  last_name  TEXT NOT NULL CHECK (char_length(last_name) < 80),
  created_at TIMESTAMP DEFAULT now()
);

GRANT SELECT ,INSERT ,UPDATE ,DELETE ON cashplay.customer to cashplay_person;

CREATE FUNCTION cashplay.customer_full_name(customer cashplay.customer)
  RETURNS TEXT AS $$
SELECT customer.first_name || ' ' || customer.last_name
$$ LANGUAGE SQL STABLE;

CREATE FUNCTION cashplay.customers_search_by_full_name(search TEXT)
  RETURNS SETOF cashplay.customer AS $$
SELECT customer.*
FROM cashplay.customer AS customer
WHERE customer.first_name ILIKE ('%' || search || '%') OR customer.last_name ILIKE ('%' || search || '%')
$$ LANGUAGE SQL STABLE;
