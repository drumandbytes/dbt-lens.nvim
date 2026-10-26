{# diamond: fct_orders and dim_customers both descend from stg_customers #}
select f.id, d.name
from {{ ref('fct_orders') }} f
join {{ ref('dim_customers') }} d on d.name = f.name
