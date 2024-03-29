-- This is a source file for pgjwt extension
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
