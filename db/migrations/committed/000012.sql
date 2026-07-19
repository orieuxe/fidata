--! Previous: sha1:abcb1b21eb40be364121d3a25f2e9761d5b31b7f
--! Hash: sha1:01f878f8712b3b8810e885b3b0a4e20ff2611e7d

-- Enter migration here

-- Backfill missing flags for FIDE country codes -- old/alternate codes for
-- countries that already exist under their current code, and typo'd
-- duplicates in the source data.
update countries set iso2 = 'FI' where code = 'FIN'; -- Finland
update countries set iso2 = 'BY' where code = 'BLR'; -- Belarus
update countries set iso2 = 'FO' where code = 'FAI'; -- Faroe Islands
update countries set iso2 = 'RO' where code = 'ROM'; -- Romania (old code, now ROU)
update countries set iso2 = 'TT' where code = 'TRI'; -- Trinidad and Tobago (old code, now TTO)
update countries set iso2 = 'CW' where code = 'CUR'; -- Curacao
update countries set iso2 = 'CI' where code = 'IVC'; -- Cote d'Ivoire (old code, now CIV)
update countries set iso2 = 'NL' where code = 'NET'; -- Netherlands (old code, now NED)
update countries set iso2 = 'KG' where code = 'KHG'; -- Kyrgyzstan (typo of KGZ)
update countries set iso2 = 'CO' where code = 'Col'; -- Colombia (typo of COL)

-- FID (no federation), NON (non-affiliated), Ind (independent), FIE (single
-- ambiguous row) aren't real countries/codes -- no flag possible.
-- YUG, SCG, AHO are dissolved states with no current ISO 3166 code -- no
-- flag-icons entry exists for them.
