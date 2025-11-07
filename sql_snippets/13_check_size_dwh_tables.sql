\pset numericlocale

SELECT
    t1.tablename,
    pg_size_pretty(
        pg_total_relation_size('"dwh"."' || t1.tablename || '"')
    ) AS size_on_disk,
    t2.estimate_rowcount
FROM
    pg_tables AS t1
    LEFT JOIN (
        SELECT
            relname,
            reltuples::bigint AS estimate_rowcount
        FROM
            pg_class AS c
            JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE
            n.nspname = 'dwh'
    ) AS t2 ON t1.tablename = t2.relname
WHERE
    t1.schemaname = 'dwh';
