{{ config(materialized='view') }}
select id, customer_id, amount from {{ source('raw', 'orders') }}
