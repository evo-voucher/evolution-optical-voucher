-- Evolution Optical branch baseline contract
-- NON-DESTRUCTIVE. Run after migrations on the reconstruction runtime.

-- The seven current Evolution Optical branches must exist exactly once by branch_code.
with expected(branch_code, branch_name, phone) as (
  values
    ('MINES','The Mines','012-4732881'),
    ('DAMAI_PERDANA','CS Damai Perdana','017-4276608'),
    ('BANGI','CS Bangi','017-2076413'),
    ('BAHAU','Bahau','06-4540984'),
    ('VISTA_VALLEY','Semenyih Vista Valley','010-5658922 / 03-87276827'),
    ('ECO_TAIPAN','Semenyih Eco Taipan','011-27302218'),
    ('PERTAMA','Pertama Complex','012-6766016')
)
select e.branch_code,
       e.branch_name as expected_name,
       b.branch_name as actual_name,
       e.phone as expected_phone,
       b.phone as actual_phone,
       b.status
from expected e
left join public.branches b on b.branch_code=e.branch_code
order by e.branch_code;

-- Expected: 7 rows, every actual value populated and status='active'.

-- Fail the contract if any current branch is missing/inactive or contact identity drifts.
do $$
begin
  if exists (
    with expected(branch_code, branch_name, phone) as (
      values
        ('MINES','The Mines','012-4732881'),
        ('DAMAI_PERDANA','CS Damai Perdana','017-4276608'),
        ('BANGI','CS Bangi','017-2076413'),
        ('BAHAU','Bahau','06-4540984'),
        ('VISTA_VALLEY','Semenyih Vista Valley','010-5658922 / 03-87276827'),
        ('ECO_TAIPAN','Semenyih Eco Taipan','011-27302218'),
        ('PERTAMA','Pertama Complex','012-6766016')
    )
    select 1
    from expected e
    left join public.branches b on b.branch_code=e.branch_code
    where b.id is null
       or b.status<>'active'
       or b.branch_name is distinct from e.branch_name
       or b.phone is distinct from e.phone
  ) then
    raise exception 'Evolution Optical branch baseline contract failed';
  end if;
end;
$$;

-- Exact address checks for customer-facing branch data.
do $$
begin
  if exists (
    select 1 from (
      values
        ('MINES','L3-56, The Mines Shopping Mall, Level 3, Seri Kembangan'),
        ('DAMAI_PERDANA','No. 1, Jalan Damai Perdana 6/1E, Bandar Damai Perdana, 56000 Cheras, Selangor Darul Ehsan'),
        ('BANGI','Lot 27 & 28, Pasar Raya Besar CS, No. 1, Persiaran Bangi Avenue, 43000 Bangi, Selangor'),
        ('BAHAU','No. 104, Jalan Gurney, 72100 Bahau, Negeri Sembilan'),
        ('VISTA_VALLEY','No. 12A-G, Jalan Vista Valley 3, Semenyih Vista Valley, 43500 Semenyih'),
        ('ECO_TAIPAN','No. 12-1 (Ground Floor), Setia Eco Hill Taipan, Semenyih'),
        ('PERTAMA','No. 1.36, 1st Floor, Pertama Shopping Complex, Jalan Tuanku Abdul Rahman, Chow Kit, 50100 Kuala Lumpur')
    ) as e(branch_code,address)
    join public.branches b on b.branch_code=e.branch_code
    where b.address is distinct from e.address
  ) then
    raise exception 'Evolution Optical branch address contract failed';
  end if;
end;
$$;
