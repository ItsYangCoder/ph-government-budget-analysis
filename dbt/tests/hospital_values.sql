select * from {{ ref('hospital') }} where regulated_hospital_count < 0 or hospital_type not in ('Government','Private','Total') or unit <> 'hospitals'
