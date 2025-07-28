-- CREATE TYPE "tablestruct";

CREATE TYPE "public"."tablestruct" AS (
	"fields_key_name" character varying(100 char),
	"fields_name" character varying(200 char),
	"fields_type" character varying(20 char),
	"fields_length" bigint,
	"fields_not_null" character varying(10 char),
	"fields_default" character varying(500 char),
	"fields_comment" character varying(1000 char),
	"fields_index" integer
);

CREATE OR REPLACE FUNCTION public.pgsql_type(a_type varchar) RETURNS varchar LANGUAGE plpgsql AS $function$ 
DECLARE
     v_type varchar;
BEGIN
     IF a_type='int8' THEN
          v_type:='bigint';
     ELSIF a_type='int4' THEN
          v_type:='integer';
     ELSIF a_type='int2' THEN
          v_type:='smallint';
     ELSIF a_type='bpchar' THEN
          v_type:='char';
     ELSE
          v_type:=a_type;
     END IF;
     RETURN v_type;
END;
$function$

CREATE OR REPLACE FUNCTION public.table_msg(a_schema_name varchar, a_table_name varchar) RETURNS SETOF tablestruct LANGUAGE plpgsql AS $function$  
DECLARE
    v_ret tablestruct;
    v_oid oid;
    v_sql text;
    v_rec RECORD;
    v_key varchar;
BEGIN
    -- 获取表的OID
    SELECT c.oid INTO v_oid
    FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = lower(a_schema_name)
      AND c.relname = lower(a_table_name);
    
    IF NOT FOUND THEN
        RAISE NOTICE 'Table %.% not found', a_schema_name, a_table_name;
        RETURN;
    END IF;
    
    -- 构建查询SQL,使用pg_get_expr获取默认值(兼容新版本)
    v_sql := $sql$
        SELECT
            a.attname AS fields_name,
            a.attnum AS fields_index,
            t.typname AS fields_type,
            CASE 
                WHEN t.typname IN ('varchar', 'char', 'bpchar') THEN a.atttypmod - 4
                WHEN t.typname IN ('numeric', 'decimal') THEN (a.atttypmod >> 16) & 65535
                ELSE t.typlen 
            END as fields_length,
            CASE WHEN a.attnotnull THEN 'not null'::varchar
                 ELSE ''::varchar
            END AS fields_not_null,
            -- 使用pg_get_expr替代adsrc,兼容PostgreSQL 12+
            pg_get_expr(ad.adbin, ad.adrelid) AS fields_default,
            d.description AS fields_comment
        FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_type t ON a.atttypid = t.oid
        LEFT JOIN pg_attrdef ad ON ad.adrelid = c.oid AND ad.adnum = a.attnum
        LEFT JOIN pg_description d ON d.objoid = c.oid AND d.objsubid = a.attnum
        WHERE a.attnum > 0
          AND a.attisdropped = false
          AND c.oid = $1
        ORDER BY a.attnum
    $sql$;
    
    -- 执行查询并处理结果
    FOR v_rec IN EXECUTE v_sql USING v_oid LOOP
        v_ret.fields_name := v_rec.fields_name;
        v_ret.fields_index := v_rec.fields_index;
        v_ret.fields_type := v_rec.fields_type;
        v_ret.fields_length := v_rec.fields_length;
        v_ret.fields_not_null := v_rec.fields_not_null;
        v_ret.fields_default := v_rec.fields_default;
        v_ret.fields_comment := v_rec.fields_comment;
        
        SELECT constraint_name INTO v_key 
        FROM information_schema.key_column_usage 
        WHERE table_schema = lower(a_schema_name)
          AND table_name = lower(a_table_name)
          AND column_name = v_rec.fields_name;
        
        v_ret.fields_key_name := COALESCE(v_key, '');
        
        RETURN NEXT v_ret;
    END LOOP;
    
    RETURN;
END;
$function$

CREATE OR REPLACE FUNCTION public.table_msg(a_table_name varchar) RETURNS SETOF tablestruct AS   
DECLARE
	v_ret tablestruct;
BEGIN
    FOR v_ret IN SELECT * FROM table_msg('public',a_table_name) LOOP
        RETURN NEXT v_ret;
    END LOOP;
    RETURN;
END


CREATE OR REPLACE  FUNCTION find_in_set(str text, strlist text) RETURNS int
AS
DECLARE b1 VARCHAR;
begin
 b1:=array_position(string_to_array($2, ','),$1);
RETURN b1;
end;

CREATE OR REPLACE FUNCTION public.time_to_sec(time_str text) RETURNS integer LANGUAGE plpgsql AS $function$ 
DECLARE
    time_val TIME;
BEGIN
    -- 先检查输入是否为空
    IF time_str IS NULL THEN
        RETURN NULL;
    END IF;
    
    -- 严格验证时间格式 (HH:MM:SS)
    IF time_str !~ '^\d{2}:\d{2}:\d{2}$' THEN
        RAISE NOTICE 'Invalid time format (expected HH:MM:SS): %', time_str;
        RETURN NULL;
    END IF;
    
    -- 尝试将字符串转换为时间类型
    BEGIN
        time_val := time_str::TIME;
    EXCEPTION
        WHEN invalid_text_representation THEN
            RAISE NOTICE 'Invalid time value: %', time_str;
            RETURN NULL;
        WHEN others THEN
            RAISE NOTICE 'Unexpected error processing: %', time_str;
            RETURN NULL;
    END;
    
    -- 计算总秒数
    RETURN 
        EXTRACT(HOUR FROM time_val)::INTEGER * 3600 +
        EXTRACT(MINUTE FROM time_val)::INTEGER * 60 +
        EXTRACT(SECOND FROM time_val)::INTEGER;
END;
$function$
