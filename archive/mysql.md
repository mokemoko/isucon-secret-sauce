## テーブル構成確認
```mysql
select 
table_name, engine, table_rows as tbl_rows, avg_row_length as rowlen, 
floor((data_length+index_length)/1024/1024) as allMB,  #総容量
floor((data_length)/1024/1024) as dMB,  #データ容量
floor((index_length)/1024/1024) as iMB   #インデックス容量
from information_schema.tables 
where table_schema=database() 
order by (data_length+index_length) desc;
```

## index作成
```mysql
CREATE INDEX index_name ON table_name (column_name)
```

## generated column
timestampの逆順カラムを作成
```mysql
ALTER TABLE table_name ADD COLUMN column_name BIGINT GENERATED ALWAYS AS (-CAST(timestamp AS SIGNED)) STORED
```

## リモート接続用設定
```
# mysqld.conf
bind-address = 0.0.0.0
```

```
CREATE USER 'isucon'@'%' IDENTIFIED BY 'isucon';
GRANT ALL on *.* TO 'isucon'@'%';
FLUSH PRIVILEGES;
```