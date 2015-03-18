-- 1 up
create table if not exists posts (
  id    integer auto_increment primary key,
  title text,
  body  text
);

-- 1 down
drop table if exists posts;
