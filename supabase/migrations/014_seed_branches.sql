-- Verified Evolution Optical branch baseline reconstructed from the validated Partner UI.
-- Upsert is intentional so branch contact details can be corrected without duplicate rows.

insert into public.branches(branch_code,branch_name,address,phone,status)
values
  ('MINES','The Mines','L3-56, The Mines Shopping Mall, Level 3, Seri Kembangan','012-4732881','active'),
  ('DAMAI_PERDANA','CS Damai Perdana','No. 1, Jalan Damai Perdana 6/1E, Bandar Damai Perdana, 56000 Cheras, Selangor Darul Ehsan','017-4276608','active'),
  ('BANGI','CS Bangi','Lot 27 & 28, Pasar Raya Besar CS, No. 1, Persiaran Bangi Avenue, 43000 Bangi, Selangor','017-2076413','active'),
  ('BAHAU','Bahau','No. 104, Jalan Gurney, 72100 Bahau, Negeri Sembilan','06-4540984','active'),
  ('VISTA_VALLEY','Semenyih Vista Valley','No. 12A-G, Jalan Vista Valley 3, Semenyih Vista Valley, 43500 Semenyih','010-5658922 / 03-87276827','active'),
  ('ECO_TAIPAN','Semenyih Eco Taipan','No. 12-1 (Ground Floor), Setia Eco Hill Taipan, Semenyih','011-27302218','active'),
  ('PERTAMA','Pertama Complex','No. 1.36, 1st Floor, Pertama Shopping Complex, Jalan Tuanku Abdul Rahman, Chow Kit, 50100 Kuala Lumpur','012-6766016','active')
on conflict(branch_code) do update
set branch_name=excluded.branch_name,
    address=excluded.address,
    phone=excluded.phone,
    status=excluded.status,
    updated_at=now();
