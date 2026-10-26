select * from {{ ref('pkg_a', 'pkg_only') }}
