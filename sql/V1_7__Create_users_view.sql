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

CREATE TRIGGER update_users
INSTEAD OF INSERT OR UPDATE OR DELETE ON
  cashplay.users
FOR EACH ROW EXECUTE PROCEDURE update_users();
