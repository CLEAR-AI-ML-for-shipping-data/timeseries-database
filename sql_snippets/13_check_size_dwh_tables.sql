SELECT
    tablename,
    pg_size_pretty(
        pg_total_relation_size('"dwh"."' || tablename || '"')
    ) AS size_on_disk
FROM
    pg_tables
WHERE
    schemaname = 'dwh';
