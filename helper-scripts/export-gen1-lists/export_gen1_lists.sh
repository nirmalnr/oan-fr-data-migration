#!/usr/bin/env bash
# Export Gen 1's code lists (its master data) as CSV files, one file per list.
#
# Reads only the list tables themselves: no farmer, household, land, crop or livestock
# records, and no counts of them. The lists are small (the largest is the kebele list),
# so each query reads one small table once.
#
# Read only: every query is a SELECT, and the session is set read-only. Each query is
# stopped after 60 seconds, and never waits for a lock.
#
# Connection comes from the standard libpq settings, for example:
#   PGHOST=<gen1 db host> PGPORT=5432 PGDATABASE=<gen1 db> PGUSER=<read-only user> PGPASSWORD=... \
#     ./export_gen1_lists.sh <output folder>
#
# Columns that differ between Gen 1 versions (a list with no `code`, a translated `name`)
# are read through to_jsonb(row), so a missing column gives an empty cell, not an error.
set -euo pipefail

OUT="${1:?usage: export_gen1_lists.sh <output folder>}"
mkdir -p "$OUT"
export PGOPTIONS="${PGOPTIONS:-} -c default_transaction_read_only=on -c statement_timeout=60s -c lock_timeout=1s"

# name of a list row: the English text when `name` is translated (jsonb), else the plain value
NAME="coalesce(to_jsonb(t)->'name'->>'en_US', to_jsonb(t)->>'name')"
CODE="to_jsonb(t)->>'code'"
ACTIVE="to_jsonb(t)->>'active'"

TOTAL=22        # number of export_csv calls below
DONE=0
FAILED_COUNT=0
FAILED_LIST=""

echo "Exporting Gen 1 code lists (read only)"
echo "  Database: ${PGDATABASE:-<default>} on ${PGHOST:-localhost}:${PGPORT:-5432} as ${PGUSER:-$(whoami)}"
echo "  Output:   $OUT"
printf "Connecting... "
if ! CONNECT_ERROR=$(psql -X -At -c "select 1" 2>&1 >/dev/null); then
  echo "failed"
  echo "  $CONNECT_ERROR"
  echo "Check the PGHOST, PGPORT, PGDATABASE, PGUSER and PGPASSWORD settings. Nothing was exported."
  exit 2
fi
echo "ok"

export_csv() {  # export_csv <file name> <query>; a failed export is reported and skipped
  DONE=$((DONE + 1))
  printf "[%2d/%d] %-27s " "$DONE" "$TOTAL" "$1"   # shown before the query runs, so a slow one is visible
  local started=$SECONDS
  if psql -X -v ON_ERROR_STOP=1 -q -c "COPY ($2) TO STDOUT WITH (FORMAT csv, HEADER)" > "$OUT/$1" 2> "$OUT/$1.error"; then
    rm -f "$OUT/$1.error"
    echo "$(($(wc -l < "$OUT/$1") - 1)) rows ($((SECONDS - started))s)"
  else
    rm -f "$OUT/$1"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_LIST="$FAILED_LIST $1"
    echo "FAILED: $(head -1 "$OUT/$1.error")"
  fi
}

# ---- Geography -------------------------------------------------------------
# The admin*_pcod columns are OCHA P-codes, where this Gen 1 version has them.
export_csv 01_regions.csv "
select t.id, $CODE as code, $NAME as name, to_jsonb(t)->>'iso_code' as iso_code,
  to_jsonb(t)->>'admin1_pcod' as pcode
from g2p_region t order by t.id"

export_csv 02_zones.csv "
select t.id, $CODE as code, $NAME as name, r.code as region_code,
  to_jsonb(t)->>'admin2_pcod' as pcode
from g2p_zone t left join g2p_region r on r.id = t.region order by t.id"

export_csv 03_woredas.csv "
select t.id, $CODE as code, $NAME as name, z.code as zone_code,
  to_jsonb(t)->>'admin3_pcod' as pcode
from g2p_woreda t left join g2p_zone z on z.id = t.zone order by t.id"

export_csv 04_kebeles.csv "
select t.id, $CODE as code, $NAME as name, w.code as woreda_code
from g2p_kebele t left join g2p_woreda w on w.id = t.woreda order by t.id"

# ---- Crops, seasons, diseases, livestock ------------------------------------
export_csv 05_seasons.csv "
select t.id, $NAME as name, t.start_gc, t.end_gc, t.start_month, t.start_day, t.end_month, t.end_day
from g2p_season t order by t.id"

export_csv 06_crop_categories.csv "
select t.id, $CODE as code, $NAME as name
from g2p_crop_category t order by t.id"

export_csv 07_crops.csv "
select t.id, $CODE as code, $NAME as name,
  coalesce(to_jsonb(t)->>'category', to_jsonb(t)->>'category_id') as category_id
from g2p_crop t order by t.id"

export_csv 08_illness_types.csv "
select t.id, $CODE as code, $NAME as name, t.illness_type
from g2p_illness_type t order by t.illness_type, t.id"

export_csv 09_livestock_types.csv "
select t.id, $CODE as code, to_jsonb(t)->>'species_code' as species_code, $NAME as name
from g2p_livestock_type t order by t.id"

# ---- Farm inputs, income, membership ----------------------------------------
export_csv 10_machinery.csv "
select t.id, $CODE as code, $NAME as name from g2p_machinery t order by t.id"

export_csv 11_finance_access.csv "
select t.id, $CODE as code, $NAME as name from g2p_finance_access t order by t.id"

export_csv 12_household_income.csv "
select t.id, $CODE as code, $NAME as name from g2p_hh_income t order by t.id"

export_csv 13_water_sources.csv "
select t.id, $CODE as code, $NAME as name from g2p_water_source t order by t.id"

export_csv 14_languages.csv "
select t.id, $CODE as code, $NAME as name from g2p_lang t order by t.id"

export_csv 15_primary_commodities.csv "
select t.id, $CODE as code, $NAME as name from g2p_primary_commodity t order by t.id"

export_csv 16_primary_cooperatives.csv "
select t.id, $CODE as code, $NAME as name from g2p_primary_cooperative t order by t.id"

export_csv 17_cooperative_unions.csv "
select t.id, $CODE as code, $NAME as name from g2p_cooperative_union t order by t.id"

# ---- Base OpenG2P lists ------------------------------------------------------
export_csv 18_genders.csv "
select t.id, t.code, t.value, $ACTIVE as active from gender_type t order by t.id"

export_csv 19_membership_kinds.csv "
select t.id, $NAME as name, t.is_unique from g2p_group_membership_kind t order by t.id"

export_csv 20_id_types.csv "
select t.id, $NAME as name, t.id_validation from g2p_id_type t order by t.id"

# ---- Fixed choices (Odoo selection fields) ----------------------------------
# The options of every selection field on Gen 1's own records, from Odoo's metadata table
# (filled from the code when a module is installed or upgraded). Configuration only: it
# doesn't read which option any farmer picked.
export_csv 21_fixed_choices.csv "
select f.model, f.name as field, s.value, coalesce(to_jsonb(s)->'name'->>'en_US', to_jsonb(s)->>'name') as label,
  s.sequence
from ir_model_fields_selection s join ir_model_fields f on f.id = s.field_id
where f.model in ('res.partner', 'g2p.land.information', 'g2p.crop.information',
  'g2p.livestock.information', 'g2p.illness.type', 'g2p.group.membership', 'g2p.phone.number', 'g2p.reg.id')
  and f.store
order by f.model, f.name, s.sequence, s.id"

# ---- Completeness check -----------------------------------------------------
# Every lookup table that Gen 1's records point to, from Odoo's field metadata, with the
# fields that use it. Compare it with the files above: a lookup listed here with no file of
# its own is a list this export doesn't cover. Configuration only.
export_csv 22_lookup_fields.csv "
select f.relation as lookup_model, replace(f.relation, '.', '_') as lookup_table,
  string_agg(distinct f.model || '.' || f.name || ' (' || f.ttype || ')', ', ') as used_by
from ir_model_fields f
where f.model in ('res.partner', 'g2p.land.information', 'g2p.crop.information',
  'g2p.livestock.information', 'g2p.group.membership', 'g2p.phone.number', 'g2p.reg.id',
  'g2p.crop', 'g2p.zone', 'g2p.woreda', 'g2p.kebele')
  and f.ttype in ('many2one', 'many2many') and f.store
  and split_part(f.relation, '.', 1) not in ('res', 'ir', 'mail', 'calendar', 'discuss', 'website', 'storage')
group by f.relation order by f.relation"

if [ "$FAILED_COUNT" -gt 0 ]; then
  echo "Finished in ${SECONDS}s with $FAILED_COUNT failed export(s):$FAILED_LIST"
  echo "The other files are in $OUT; each failure's message is in its .error file there."
  exit 1
fi
echo "Finished in ${SECONDS}s: $DONE files in $OUT"
