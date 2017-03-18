INSERT INTO cashplay.customers (id, user_email_fk,pic, first_name, last_name, created_at) VALUES
  (1, 'dev@dev.com','data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==','Sara', 'Powell', '2015-07-03T14:11:30Z'),
  (2, 'dev@dev.com','','Andrea', 'Fox', '1999-04-04T21:21:42Z'),
  (3, 'dev@dev.com','','Stephen', 'Banks', '2003-12-09T04:39:10Z'),
  (4, 'dev@dev.com','','Kathy', 'ban', '2001-11-03T15:37:15Z'),
  (5, 'dev@dev.com','','Kenneth', 'Williams', '2002-08-16T19:03:47Z'),
  (6, 'dev@dev.com','','Ann', 'Peterson', '2013-09-24T15:05:29Z');


SELECT *
FROM cashplay.signup(
    'Jalal', 'Hosseini', 'Cashconversions', 'dev@dev.com', 'admin'
);
SELECT *
FROM cashplay.signup(
    'John', 'Doe', 'Cashconversions', 'dev2@dev.com', 'admin'
);

INSERT INTO cashplay_private.users (first_name,last_name,company,email,pass,role) VALUES
  (
    'anon', 'anon', 'anon', 'anon@dev.com', 'anon','cashplay_anonymous'

  );
