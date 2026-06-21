-- （一）基础数据清洗与异常剔除
-- 1. 修改关键字列名(因为占用了mysql的关键字）
alter table raw_data  
  change `group` group_type varchar(255),  
  change `date` record_date varchar(255);

-- 2. 剔除含有缺失值的无效记录
-- （由于样本量远大于所需最小样本量，则不需要填充）
delete from raw_data  
where user_id is null  
   or record_date is null  
   or group_type is null  
   or page_type is null  
   or if_convert is null;

-- 3. 剔除完全重复的记录（保留ID最大的那条）
alter table raw_data add id int first;   
alter table raw_data modify id int primary key auto_increment;   

with df1 as (
  select user_id, record_date, group_type, page_type, if_convert, max(id) as max_id   
  from raw_data   
  group by user_id, record_date, group_type, page_type, if_convert   
  having count(*) > 1   
)   
delete raw_data   
from raw_data, df1
where raw_data.user_id = df1.user_id   
  and raw_data.record_date = df1.record_date   
  and raw_data.group_type = df1.group_type   
  and raw_data.page_type = df1.page_type   
  and raw_data.if_convert = df1.if_convert   
  and raw_data.id < df1.max_id;

-- 4. 清理异常日期，聚焦于2017年1月份的主实验周期，并且排除星期效应
update raw_data set record_date = date_format(record_date,'%Y-%m-%d');
delete from raw_data
where record_date >= '2017-01-22' or record_date <= '2016-12-31';

-- （二）实验系统公平性验证：排除双重分流用户
-- 5. 遵循单一变量，剔除跨组（在control和treatment均有记录）的异常用户
with df2 as (
  select user_id from raw_data
  group by user_id
  having count(distinct group_type) > 1
)
delete raw_data
from raw_data, df2
where raw_data.user_id = df2.user_id;

-- （三）A/A测试与A/B测试数据集切分
-- 由于原始数据集限制，为了模拟严谨的实验流程：
-- ①将对照组（control）一月份的数据从中间（1月15日）切开，前半月为 control_1，后半月为 control_2，用于进行 A/A Test，验证基线平稳度。
-- ②将实验组（treatment）的后半月数据取出，与 control_2 进行 A/B Test。
-- 6. 构建实验切片表
create table df_abtest (   
  user_id int(9),   
  record_date varchar(66),   
  group_type varchar(66),   
  page_type varchar(66),   
  if_convert int(6)   
);   

insert into df_abtest   
select   
  user_id,   
  record_date,   
  case   
    when record_date <= '2017-01-15' and group_type = 'control' then 'control_1'   
    when record_date > '2017-01-15' and group_type = 'control' then 'control_2'   
    when record_date > '2017-01-15' and group_type = 'treatment' then 'treatment'   
    else 'no_effective'   
  end as group_type,   
  page_type,   
  if_convert   
from raw_data   
where (group_type = 'control' and page_type = 'old_page')   
   or (group_type = 'treatment' and page_type = 'new_page');