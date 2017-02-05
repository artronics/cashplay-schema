CREATE OR REPLACE FUNCTION cashplay.insert_user_email()
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
