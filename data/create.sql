create table books
(
    id          int primary key,
    category_id int         not null,
    title       varchar(20) not null
);