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

--PROCEDURES
CREATE OR REPLACE FUNCTION cashplay_private.set_updated_at()
  RETURNS TRIGGER AS $$
BEGIN
  new.updated_at := current_timestamp;
  RETURN new;
END;
$$ LANGUAGE plpgsql;

---------------------------------------------------------------------
-- ENTITIES
---------------------------------------------------------------------
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

--------------------------------------------------------------------
--JWT AUTH
--------------------------------------------------------------------
DROP TYPE IF EXISTS cashplay_private.jwt_claims CASCADE;
CREATE TYPE cashplay_private.jwt_claims AS (role TEXT, email TEXT, exp INTEGER);

DROP TABLE IF EXISTS cashplay_private.users;
CREATE TABLE IF NOT EXISTS
  cashplay_private.users (
  email TEXT PRIMARY KEY CHECK ( email ~* '^.+@.+\..+$' ),
  pass  TEXT NOT NULL CHECK (length(pass) < 512),
  role  NAME NOT NULL CHECK (length(role) < 512)
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
    actual.role   AS role,
    '***' :: TEXT AS pass,
    actual.email  AS email
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
    (role, pass, email)
    VALUES
      (new.role, new.pass, new.email);
    RETURN new;
  ELSIF tg_op = 'UPDATE'
    THEN
      -- no need to check clearance for old.role because
      -- an ineligible row would not have been available to update (http 404)
      PERFORM cashplay_private.clearance_for_role(new.role);

      UPDATE cashplay_private.users
      SET
        email = new.email,
        role  = new.role,
        pass  = new.pass
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
  cashplay.signup(email TEXT, pass TEXT)
  RETURNS VOID
AS $$
INSERT INTO cashplay_private.users (email, pass, role) VALUES
  (signup.email, signup.pass, 'cashplay_user');
$$ LANGUAGE SQL;

---- Generating JWT
DROP TYPE IF EXISTS cashplay_private.jwt_claims CASCADE;
CREATE TYPE cashplay_private.jwt_claims AS (role TEXT, email TEXT, exp INTEGER);

CREATE OR REPLACE FUNCTION
  cashplay.login(email TEXT, pass TEXT)
  RETURNS cashplay_private.jwt_claims
LANGUAGE plpgsql
AS $$
DECLARE
  _role  NAME;
  result cashplay_private.jwt_claims;
BEGIN
  -- check email and password
  SELECT cashplay_private.user_role($1,$2)
  INTO _role;
  IF _role IS NULL
  THEN
    RAISE invalid_password
    USING MESSAGE = 'invalid user or password';
  END IF;

  SELECT
    _role                                          AS role,
    email                                             AS email,
    extract(EPOCH FROM now()) :: INTEGER + 60 * 60 AS exp
  INTO result;
  RETURN result;
END;
$$;

-- You can distinguish one user from another in SQL by examining the JWT claims
-- which PostgREST makes available in the SQL variable postgrest.claims
-- Here's a function to get the email of the currently authenticated user.

-- Prevent current_setting('postgrest.claims.email') from raising
-- an exception if the setting is not present. Default it to ''.
ALTER DATABASE cashplay_dev SET postgrest.claims.email TO '';

CREATE OR REPLACE FUNCTION
  cashplay_private.current_email()
  RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN current_setting('postgrest.claims.email');
END;
$$;

GRANT USAGE ON SCHEMA cashplay_private TO cashplay_anonymous;
GRANT INSERT ON TABLE cashplay_private.users, cashplay_private.tokens TO cashplay_anonymous;
GRANT SELECT ON TABLE pg_authid, cashplay_private.users TO cashplay_anonymous;

GRANT EXECUTE ON FUNCTION
cashplay.login(TEXT, TEXT),
cashplay.signup(TEXT, TEXT)
TO cashplay_anonymous;

-------------------------------------------------------------------------------
-- CUSTOMER
-------------------------------------------------------------------------------

DROP TABLE IF EXISTS cashplay.customers CASCADE ;
CREATE TABLE cashplay.customers (
  id         SERIAL PRIMARY KEY,
  first_name TEXT NOT NULL CHECK (char_length(first_name) < 80),
  last_name  TEXT NOT NULL CHECK (char_length(last_name) < 80),
  created_at TIMESTAMP DEFAULT now()
);

GRANT SELECT ,INSERT ,UPDATE ,DELETE ON cashplay.customers to cashplay_user;

CREATE OR REPLACE FUNCTION cashplay.customers_full_name(customers cashplay.customers)
  RETURNS TEXT AS $$
SELECT customers.first_name || ' ' || customers.last_name
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION cashplay.customerss_search_by_full_name(search TEXT)
  RETURNS SETOF cashplay.customers AS $$
SELECT customers.*
FROM cashplay.customers AS customers
WHERE customers.first_name ILIKE ('%' || search || '%') OR customers.last_name ILIKE ('%' || search || '%')
$$ LANGUAGE SQL STABLE;


-------------------------------------------------------------------------------
--CURRENCY
-------------------------------------------------------------------------------
DROP TABLE IF EXISTS cashplay.currencies;
CREATE TABLE IF NOT EXISTS cashplay.currencies(
  id SERIAL PRIMARY KEY,
  country_code TEXT NOT NULL CHECK (char_length(country_code)<3),
  currency_code TEXT NOT NULL CHECK (char_length(country_code)<4),
  we_buy DOUBLE PRECISION DEFAULT 1,
  we_sell DOUBLE PRECISION DEFAULT 1
);
