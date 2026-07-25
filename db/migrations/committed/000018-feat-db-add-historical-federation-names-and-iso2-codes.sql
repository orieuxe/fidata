--! Previous: sha1:99f7989a02ce7bcaa8c4cd832c331800a89201d4
--! Hash: sha1:7f0ffe0febdf114977b306dddca124c86eca36ff
--! Message: feat(db): add historical federation names and iso2 codes

-- Fill in missing iso2 codes for countries the scraper inserted with
-- only a code -- historical federations (URS/YUG/CSR/GDR) and modern
-- countries the seed migration didn't cover.
update countries set name = 'Soviet Union',   iso2 = 'su' where code = 'URS' and iso2 is null;
update countries set name = 'Yugoslavia',     iso2 = 'yu' where code = 'YUG' and iso2 is null;
update countries set name = 'Czechoslovakia', iso2 = 'cs' where code = 'CSR' and iso2 is null;
update countries set name = 'East Germany',   iso2 = 'dd' where code = 'GDR' and iso2 is null;
