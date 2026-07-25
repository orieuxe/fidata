--! Previous: sha1:a711b02f83d35ad1d5cf0c000e81723a01ee181d
--! Hash: sha1:3d80e492f8dd6b4d8f5f248da64e684ed38393b4
--! Message: feat(db): add historical federation names and iso2 codes

-- Fill in missing iso2 codes for countries the scraper inserted with
-- only a code -- historical federations (URS/YUG/CSR/GDR) and modern
-- countries the seed migration didn't cover.
update countries set name = 'Soviet Union',   iso2 = 'su' where code = 'URS' and iso2 is null;
update countries set name = 'Yugoslavia',     iso2 = 'yu' where code = 'YUG' and iso2 is null;
update countries set name = 'Czechoslovakia', iso2 = 'cs' where code = 'CSR' and iso2 is null;
update countries set name = 'East Germany',   iso2 = 'dd' where code = 'GDR' and iso2 is null;
