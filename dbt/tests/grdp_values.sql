select * from {{ ref('grdp_per_capita') }} where grdp_per_capita <= 0 or price_basis not in (2018, year)
