BEGIN;
DROP SCHEMA IF EXISTS cashplay CASCADE;
CREATE SCHEMA cashplay;

DROP SCHEMA IF EXISTS cashplay_private CASCADE;
CREATE SCHEMA cashplay_private;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DROP ROLE IF EXISTS cashplay_postgres;
--fixme change password
CREATE ROLE cashplay_postgres LOGIN PASSWORD 'admin';

DROP OWNED BY cashplay_anonymous;
DROP ROLE IF EXISTS cashplay_anonymous;
CREATE ROLE cashplay_anonymous;

DROP ROLE IF EXISTS cashplay_user;
CREATE ROLE cashplay_user;

GRANT cashplay_anonymous TO cashplay_postgres;
GRANT cashplay_user TO cashplay_postgres;

GRANT USAGE ON SCHEMA cashplay TO cashplay_user, cashplay_anonymous;

ALTER DATABASE cashplay_dev SET "cashplay.jwt_secret" TO 'foo';


--PROCEDURES
CREATE OR REPLACE FUNCTION cashplay_private.set_updated_at()
  RETURNS TRIGGER AS $$
BEGIN
  new.updated_at := current_timestamp;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------
--JWT AUTH
--------------------------------------------------------------------
-- This is a source file for pgjwt extension
--pgjwt Begin
CREATE OR REPLACE FUNCTION cashplay_private.url_encode(data bytea) RETURNS text LANGUAGE sql AS $$
SELECT translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;


CREATE OR REPLACE FUNCTION cashplay_private.url_decode(data text) RETURNS bytea LANGUAGE sql AS $$
WITH t AS (SELECT translate(data, '-_', '+/')),
    rem AS (SELECT length((SELECT * FROM t)) % 4) -- compute padding size
SELECT decode(
    (SELECT * FROM t) ||
    CASE WHEN (SELECT * FROM rem) > 0
      THEN repeat('=', (4 - (SELECT * FROM rem)))
    ELSE '' END,
    'base64');
$$;


CREATE OR REPLACE FUNCTION cashplay_private.algorithm_sign(signables text, secret text, algorithm text)
  RETURNS text LANGUAGE sql AS $$
WITH
    alg AS (
      SELECT CASE
             WHEN algorithm = 'HS256' THEN 'sha256'
             WHEN algorithm = 'HS384' THEN 'sha384'
             WHEN algorithm = 'HS512' THEN 'sha512'
             ELSE '' END)  -- hmac throws error
SELECT cashplay_private.url_encode(hmac(signables, secret, (select * FROM alg)));
$$;


CREATE OR REPLACE FUNCTION cashplay_private.sign(payload json, secret text, algorithm text DEFAULT 'HS256')
  RETURNS text LANGUAGE sql AS $$
WITH
    header AS (
      SELECT cashplay_private.url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8'))
  ),
    payload AS (
      SELECT cashplay_private.url_encode(convert_to(payload::text, 'utf8'))
  ),
    signables AS (
      SELECT (SELECT * FROM header) || '.' || (SELECT * FROM payload)
  )
SELECT
  (SELECT * FROM signables)
  || '.' ||
  cashplay_private.algorithm_sign((SELECT * FROM signables), secret, algorithm);
$$;


CREATE OR REPLACE FUNCTION verify(token text, secret text, algorithm text DEFAULT 'HS256')
  RETURNS table(header json, payload json, valid boolean) LANGUAGE sql AS $$
SELECT
  convert_from(cashplay_private.url_decode(r[1]), 'utf8')::json AS header,
  convert_from(cashplay_private.url_decode(r[2]), 'utf8')::json AS payload,
  r[3] = cashplay_private.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) AS valid
FROM regexp_split_to_array(token, '\.') r;
$$;
--pgjwt end

DROP TYPE IF EXISTS cashplay_private.jwt_token CASCADE;
CREATE TYPE cashplay_private.jwt_token AS (token TEXT);


DROP TABLE IF EXISTS cashplay_private.users;
CREATE TABLE IF NOT EXISTS
  cashplay_private.users (
  first_name TEXT NOT NULL CHECK (length(first_name) < 64),
  last_name  TEXT NOT NULL CHECK (length(first_name) < 64),
  company    TEXT NOT NULL CHECK (length(first_name) < 64),

  email      TEXT PRIMARY KEY CHECK ( email ~* '^.+@.+\..+$' ),
  pass       TEXT NOT NULL CHECK (length(pass) < 512),
  role       NAME NOT NULL CHECK (length(role) < 512)
);
-- encrypt pass on insert or update
CREATE OR REPLACE FUNCTION
  cashplay_private.encrypt_pass()
  RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF tg_op = 'INSERT' OR new.pass <> old.pass
  THEN
    new.pass = crypt(new.pass, gen_salt('bf'));
  END IF;
  RETURN new;
END
$$;

DROP TRIGGER IF EXISTS encrypt_pass
ON cashplay_private.users;
CREATE TRIGGER encrypt_pass
BEFORE INSERT OR UPDATE ON cashplay_private.users
FOR EACH ROW
EXECUTE PROCEDURE cashplay_private.encrypt_pass();


-- check if inserted role exists
CREATE OR REPLACE FUNCTION
  cashplay_private.check_role_exists()
  RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT exists(SELECT 1
                FROM pg_roles AS r
                WHERE r.rolname = new.role)
  THEN
    RAISE foreign_key_violation
    USING MESSAGE =
      'unknown database role: ' || new.role;
    RETURN NULL;
  END IF;
  RETURN new;
END
$$;


DROP TRIGGER IF EXISTS ensure_user_role_exists
ON cashplay_private.users;

CREATE CONSTRAINT TRIGGER ensure_user_role_exists
AFTER INSERT OR UPDATE ON cashplay_private.users
FOR EACH ROW
EXECUTE PROCEDURE cashplay_private.check_role_exists();

-- check if username and pass is correct, it returns role
CREATE OR REPLACE FUNCTION
  cashplay_private.user_role(email TEXT, pass TEXT)
  RETURNS NAME
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN (
    SELECT role
    FROM cashplay_private.users AS users
    WHERE users.email = $1
          AND users.pass = crypt($2, users.pass)
  );
END;
$$;


DROP TYPE IF EXISTS cashplay.token_type_enum CASCADE;
CREATE TYPE cashplay.token_type_enum AS ENUM ('authenticator', 'validation', 'reset');

DROP TABLE IF EXISTS cashplay_private.tokens;
CREATE TABLE IF NOT EXISTS
  cashplay_private.tokens (
  token      UUID PRIMARY KEY,
  token_type cashplay.token_type_enum NOT NULL,
  email      TEXT                     NOT NULL REFERENCES cashplay_private.users (email)
  ON DELETE CASCADE ON UPDATE CASCADE,
  created_at TIMESTAMPTZ              NOT NULL DEFAULT current_date
);

--for now we just add authenticator token
CREATE OR REPLACE FUNCTION
  cashplay_private.send_authenticator()
  RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  tok UUID;
BEGIN
  SELECT gen_random_uuid()
  INTO tok;
  INSERT INTO cashplay_private.tokens (token, token_type, email)
  VALUES (tok, 'authenticator' :: cashplay.token_type_enum, new.email);
  PERFORM pg_notify('authenticator',
                    json_build_object(
                        'email', new.email,
                        'token', tok,
                        'token_type', 'authenticator'
                    ) :: TEXT
  );
  RETURN new;
END
$$;

-- insert token when user registers
DROP TRIGGER IF EXISTS send_authenticator
ON cashplay_private.users;
CREATE TRIGGER send_authenticator
AFTER INSERT ON cashplay_private.users
FOR EACH ROW
EXECUTE PROCEDURE cashplay_private.send_authenticator();

-- We'll construct a redacted view for users. It hides passwords and
--  shows only those users whose roles the currently logged in user has db permission to access.
CREATE OR REPLACE VIEW cashplay.users AS
  SELECT
    actual.first_name AS first_name,
    actual.last_name  AS last_name,
    actual.company    AS company,
    actual.email      AS email,
    '***' :: TEXT     AS pass,
    actual.role       AS role

  FROM cashplay_private.users AS actual,
    (SELECT rolname
     FROM pg_authid
     WHERE pg_has_role(current_user, oid, 'member')
    ) AS member_of
  WHERE actual.role = member_of.rolname;

-- use this function to insert to user view
CREATE OR REPLACE FUNCTION
  cashplay_private.clearance_for_role(u NAME)
  RETURNS VOID AS
$$
DECLARE
  ok BOOLEAN;
BEGIN
  SELECT exists(
      SELECT rolname
      FROM pg_authid
      WHERE pg_has_role(current_user, oid, 'member')
            AND rolname = u
  )
  INTO ok;
  IF NOT ok
  THEN
    RAISE invalid_password
    USING MESSAGE =
      'current user not member of role ' || u;
  END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION
  update_users()
  RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF tg_op = 'INSERT'
  THEN
    PERFORM cashplay_private.clearance_for_role(new.role);

    INSERT INTO cashplay_private.users
    (first_name, last_name, company, email, pass, role)
    VALUES
      (new.first_name, new.last_name, new.company, new.email, new.pass, new.role);
    RETURN new;
  ELSIF tg_op = 'UPDATE'
    THEN
      -- no need to check clearance for old.role because
      -- an ineligible row would not have been available to update (http 404)
      PERFORM cashplay_private.clearance_for_role(new.role);

      UPDATE cashplay_private.users
      SET
        first_name = new.first_name,
        last_name  = new.last_name,
        company    = new.company,
        email      = new.email,
        pass       = new.pass,
        role       = new.role
      WHERE email = old.email;
      RETURN new;
  ELSIF tg_op = 'DELETE'
    THEN
      -- no need to check clearance for old.role (see previous case)

      DELETE FROM cashplay_private.users
      WHERE cashplay_private.email = old.email;
      RETURN NULL;
  END IF;
END
$$;

DROP TRIGGER IF EXISTS update_users
ON cashplay.users;
CREATE TRIGGER update_users
INSTEAD OF INSERT OR UPDATE OR DELETE ON
  cashplay.users
FOR EACH ROW EXECUTE PROCEDURE update_users();


CREATE OR REPLACE FUNCTION
  cashplay.signup(first_name TEXT, last_name TEXT, company TEXT, email TEXT, pass TEXT)
  RETURNS VOID
AS $$
INSERT INTO cashplay_private.users (first_name, last_name, company, email, pass, role) VALUES
  (signup.first_name, signup.last_name, signup.company, signup.email, signup.pass, 'cashplay_user');
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION
  cashplay.login(email TEXT, pass TEXT)
  RETURNS cashplay_private.jwt_token
LANGUAGE plpgsql
AS $$
DECLARE
  _role  NAME;
  result cashplay_private.jwt_token;
BEGIN
  -- check email and password
  SELECT cashplay_private.user_role($1, $2)
  INTO _role;
  IF _role IS NULL
  THEN
    RAISE invalid_password
    USING MESSAGE = 'Invalid email or password';
  END IF;

  select cashplay_private.sign(
             row_to_json(r), current_setting('cashplay.jwt_secret')
         ) as token
  from (
         select _role as role, login.email as email,
                extract(epoch from now())::integer + 60*60 as exp
       ) r
  into result;
  RETURN result;
END;
$$;

-- You can distinguish one user from another in SQL by examining the JWT claims
-- which PostgREST makes available in the SQL variable postgrest.claims
-- Here's a function to get the email of the currently authenticated user.

-- Prevent current_setting('postgrest.claims.email') from raising
-- an exception if the setting is not present. Default it to ''.
ALTER DATABASE cashplay_dev SET request.jwt.claim.email TO '';

CREATE OR REPLACE FUNCTION
  cashplay_private.current_email()
  RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN current_setting('request.jwt.claim.email');
END;
$$;

GRANT USAGE ON SCHEMA cashplay_private TO cashplay_anonymous;
GRANT INSERT ON TABLE cashplay_private.users, cashplay_private.tokens TO cashplay_anonymous;
GRANT SELECT ON TABLE pg_authid, cashplay_private.users TO cashplay_anonymous;

GRANT EXECUTE ON FUNCTION
cashplay.login(TEXT, TEXT),
cashplay.signup(TEXT, TEXT, TEXT, TEXT, TEXT)
TO cashplay_anonymous;

---------------------------------------------------------------------
-- ENTITIES
---------------------------------------------------------------------

-------------------------------------------------------------------------------
-- CUSTOMER
-------------------------------------------------------------------------------

DROP TABLE IF EXISTS cashplay.customers CASCADE;
CREATE TABLE cashplay.customers (
  id            SERIAL PRIMARY KEY,
  user_email_fk TEXT REFERENCES cashplay_private.users (email) ON DELETE CASCADE,
  pic           TEXT NOT NULL,
  first_name    TEXT NOT NULL CHECK (char_length(first_name) < 80),
  last_name     TEXT NOT NULL CHECK (char_length(last_name) < 80),
  created_at    TIMESTAMP DEFAULT now()
);
ALTER TABLE cashplay.customers ENABLE ROW LEVEL SECURITY ;


GRANT SELECT, INSERT, UPDATE, DELETE ON cashplay.customers TO cashplay_user;
GRANT USAGE ON SEQUENCE cashplay.customers_id_seq TO cashplay_user;


CREATE OR REPLACE FUNCTION cashplay.customers_full_name(customers cashplay.customers)
  RETURNS TEXT AS $$
SELECT customers.first_name || ' ' || customers.last_name
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION cashplay.customers_search_by_full_name(search TEXT)
  RETURNS SETOF cashplay.customers AS $$
SELECT customers.*
FROM cashplay.customers AS customers
WHERE customers.first_name ILIKE ('%' || search || '%') OR customers.last_name ILIKE ('%' || search || '%')
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE VIEW cashplay.customer AS
  SELECT
    *,
    cashplay.customers_full_name(cashplay.customers.*) AS full_name
  FROM cashplay.customers;
GRANT SELECT, INSERT, UPDATE, DELETE ON cashplay.customer TO cashplay_user;

-------------------------------------------------------------------------------
--CUSTOMERS_PICS
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS cashplay.customer_docs CASCADE;
CREATE TABLE cashplay.customer_docs (
  id            SERIAL PRIMARY KEY,
  customer_id INTEGER REFERENCES cashplay.customers (id) ON DELETE CASCADE,
  img TEXT NOT NULL
);

GRANT SELECT, INSERT, UPDATE, DELETE ON cashplay.customer_docs TO cashplay_user;
GRANT USAGE ON SEQUENCE cashplay.customer_docs_id_seq TO cashplay_user;

-------------------------------------------------------------------------------
--ITEM
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS cashplay.items;
CREATE TABLE IF NOT EXISTS cashplay.items (
  id          SERIAL PRIMARY KEY,
  description TEXT
);
GRANT SELECT, INSERT, UPDATE, DELETE ON cashplay.items TO cashplay_user;
-------------------------------------------------------------------------------
--CURRENCY
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS cashplay.currencies;
CREATE TABLE IF NOT EXISTS cashplay.currencies (
  id            SERIAL PRIMARY KEY,
  country_code  TEXT NOT NULL CHECK (char_length(country_code) < 3),
  currency_code TEXT NOT NULL CHECK (char_length(country_code) < 4),
  we_buy        DOUBLE PRECISION DEFAULT 1,
  we_sell       DOUBLE PRECISION DEFAULT 1,
  updated_at    TIMESTAMP        DEFAULT now()
);
GRANT SELECT ON TABLE cashplay.currencies TO cashplay_anonymous, cashplay_user;

INSERT INTO cashplay.currencies (country_code, currency_code) VALUES
  ('EU', 'EUR'),
  ('US', 'USD');

CREATE TRIGGER currencies_updated_at
BEFORE UPDATE ON cashplay.currencies
FOR EACH ROW EXECUTE PROCEDURE cashplay_private.set_updated_at();
-------------------------------------------------------------------------------
--TRIGGERS
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cashplay.insert_user_email_fk()
  RETURNS TRIGGER
LANGUAGE plpgsql STRICT SECURITY DEFINER AS
$$
DECLARE user_email TEXT;
BEGIN
  SELECT current_email
  FROM cashplay_private.current_email()
  INTO user_email;

  new.user_email_fk:= user_email;

  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS insert_user_email_fk
ON
  cashplay.customers;
CREATE TRIGGER insert_user_email_fk
BEFORE INSERT ON
  cashplay.customers
FOR EACH ROW EXECUTE PROCEDURE cashplay.insert_user_email_fk();

-------------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-------------------------------------------------------------------------------
DROP POLICY IF EXISTS user_all ON cashplay.customers;
CREATE POLICY user_all ON
  cashplay.customers
  TO cashplay_user USING (cashplay_private.current_email() = cashplay.customers.user_email_fk);
COMMIT;

