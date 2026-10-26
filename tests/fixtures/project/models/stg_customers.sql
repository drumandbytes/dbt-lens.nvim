select id, name from {{ source('raw', 'customers') }}
