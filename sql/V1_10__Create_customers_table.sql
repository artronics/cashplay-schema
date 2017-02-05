DROP TABLE IF EXISTS cashplay.customers CASCADE;
CREATE TABLE cashplay.customers (
  id            SERIAL PRIMARY KEY,
  user_email_fk TEXT REFERENCES cashplay_private.users (email) ON DELETE CASCADE,
  pic           TEXT NOT NULL,
  first_name    TEXT NOT NULL CHECK (char_length(first_name) < 80),
  last_name     TEXT NOT NULL CHECK (char_length(last_name) < 80),
  created_at    TIMESTAMP DEFAULT now()
);

CREATE TRIGGER insert_user_email
BEFORE INSERT ON
  cashplay.customers
FOR EACH ROW EXECUTE PROCEDURE cashplay.insert_user_email();

ALTER TABLE cashplay.customers ENABLE ROW LEVEL SECURITY ;

CREATE POLICY user_all ON
  cashplay.customers
TO cashplay_admin USING (cashplay_private.current_email() = cashplay.customers.user_email_fk);

CREATE OR REPLACE FUNCTION cashplay.customers_search_by_name(search TEXT)
  RETURNS SETOF cashplay.customers AS $$
SELECT customers.*
FROM cashplay.customers AS customers
WHERE customers.first_name ILIKE ('%' || search || '%') OR customers.last_name ILIKE ('%' || search || '%')
$$ LANGUAGE SQL STABLE;

GRANT SELECT, INSERT, UPDATE, DELETE ON cashplay.customers TO cashplay_admin;
GRANT USAGE ON SEQUENCE cashplay.customers_id_seq TO cashplay_admin;
