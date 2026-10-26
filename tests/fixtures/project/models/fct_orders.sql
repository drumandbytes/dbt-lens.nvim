{{ config(materialized='table') }}
select o.id, c.name, {{ money('o.amount') }} as amount
from {{ ref('stg_orders') }} o
join {{ ref('stg_customers') }} c on c.id = o.customer_id
