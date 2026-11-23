# export_gen1_lists.sh

Exports Gen 1's code lists (its master data) from a Gen 1 database, as one CSV file per list. The files are used to map every Gen 1 value to a Gen 2 Master Data code before the farmer migration.

## Why export from the database

Gen 1 ships starting lists in its code (the XML files in `g2p_ati/data/`), but the database is the real list:

- Some lists have no file in the code at all: seasons and kebeles were entered in the app or loaded separately.
- Staff can add, rename or archive values in the app (Configuration menu), and those changes exist only in the database.
- Production can run a different Gen 1 version from the code we have. The staging copy, for example, has lists without a `code` column.

## What it reads, and what it doesn't

| Reads | Doesn't read |
|---|---|
| The 20 list tables: geography, seasons, crops, diseases, livestock types, machinery, finance, income, water sources, languages, commodities, cooperatives, genders, membership kinds, ID types | Farmer, household, member, land, crop or livestock records |
| Odoo's metadata tables: the options of fixed choices, and which lookup tables the records point to | How many records use each value, or which value any farmer has |

The output holds codes, names and configuration only. It contains no personal data.

## Safety

- **Read only.** Every query is a SELECT, and the session is set to `default_transaction_read_only`, so the database refuses any write.
- **Light.** Each query reads one small table once. The largest is the kebele list (about 20,000 rows). On the local staging copy the whole export takes about 5 seconds.
- **Guarded.** Each query is stopped after 60 seconds (`statement_timeout`) and never waits for a lock (`lock_timeout`), so it can't hold up the application.
- **One query at a time.** The exports run one after another, never in parallel.

## Requirements

- `bash` and `psql` (the PostgreSQL client) on the machine that runs it.
- A database user that can read the Gen 1 tables. A read-only user is enough.

## Running it

Set the standard PostgreSQL connection settings and give an output folder:

```bash
PGHOST=<host> PGPORT=5432 PGDATABASE=<gen1 database> PGUSER=<read-only user> PGPASSWORD=<password> ./export_gen1_lists.sh gen1_lists
```

It shows where it's connecting, checks the connection first, then shows each file as it goes. The file's name appears before its query runs, so if one is slow you can see which:

```text
Exporting Gen 1 code lists (read only)
  Database: <gen1 database> on <host>:5432 as <read-only user>
  Output:   gen1_lists
Connecting... ok
[ 1/22] 01_regions.csv              14 rows (0s)
[ 2/22] 02_zones.csv                131 rows (0s)
...
[22/22] 22_lookup_fields.csv        28 rows (0s)
Finished in 12s: 22 files in gen1_lists
```

If it can't connect, it stops before exporting anything and exits with status 2:

```text
Connecting... failed
  psql: error: connection to server at "<host>", port 5432 failed: ...
Check the PGHOST, PGPORT, PGDATABASE, PGUSER and PGPASSWORD settings. Nothing was exported.
```

If one export fails, for example because a table doesn't exist in this Gen 1 version, the script reports it, writes the error to `<file>.error`, carries on with the rest, and exits with status 1 at the end:

```text
[ 5/22] 05_seasons.csv              FAILED: ERROR:  relation "g2p_season" does not exist
...
Finished in 12s with 1 failed export(s): 05_seasons.csv
The other files are in gen1_lists; each failure's message is in its .error file there.
```

Send back the whole output folder, including any `.error` files.

## Output

22 CSV files, each with a header row.

### Geography

| File | Gen 1 table | Columns |
|---|---|---|
| 01_regions.csv | g2p_region | id, code, name, iso_code, pcode |
| 02_zones.csv | g2p_zone | id, code, name, region_code, pcode |
| 03_woredas.csv | g2p_woreda | id, code, name, zone_code, pcode |
| 04_kebeles.csv | g2p_kebele | id, code, name, woreda_code |

Each level carries its parent's code, so the hierarchy can be rebuilt. `pcode` is the OCHA P-code where this Gen 1 version stores one; it's empty otherwise.

### Crops, seasons, diseases, livestock

| File | Gen 1 table | Columns |
|---|---|---|
| 05_seasons.csv | g2p_season | id, name, start_gc, end_gc, start_month, start_day, end_month, end_day |
| 06_crop_categories.csv | g2p_crop_category | id, code, name |
| 07_crops.csv | g2p_crop | id, code, name, category_id |
| 08_illness_types.csv | g2p_illness_type | id, code, name, illness_type (`crop` or `animal`) |
| 09_livestock_types.csv | g2p_livestock_type | id, code, species_code, name |

Gen 1 picks a crop's season from its planted date using the season's start and end month and day, which is why those columns are included.

### Farm inputs, income, language, membership

| File | Gen 1 table | Columns |
|---|---|---|
| 10_machinery.csv | g2p_machinery | id, code, name |
| 11_finance_access.csv | g2p_finance_access | id, code, name |
| 12_household_income.csv | g2p_hh_income | id, code, name |
| 13_water_sources.csv | g2p_water_source | id, code, name (used for both crop and livestock water) |
| 14_languages.csv | g2p_lang | id, code, name |
| 15_primary_commodities.csv | g2p_primary_commodity | id, code, name |
| 16_primary_cooperatives.csv | g2p_primary_cooperative | id, code, name |
| 17_cooperative_unions.csv | g2p_cooperative_union | id, code, name |

### Base OpenG2P lists

| File | Gen 1 table | Columns |
|---|---|---|
| 18_genders.csv | gender_type | id, code, value, active. Farmers store the `value` text. |
| 19_membership_kinds.csv | g2p_group_membership_kind | id, name, is_unique (Wife - Head, Son, Daughter and so on) |
| 20_id_types.csv | g2p_id_type | id, name, id_validation |

### Fixed choices

| File | Source | Columns |
|---|---|---|
| 21_fixed_choices.csv | ir_model_fields_selection (Odoo's metadata) | model, field, value, label, sequence |

Fields like marital status, education, farming type, irrigation type, land ownership type and the yes/no questions have their options written in the code, not in a table. Odoo keeps a copy of those options in its metadata, filled from the code when a module is installed or upgraded, so this file shows the options of the version actually running. It also lists fields from base modules that Gen 1 doesn't use, such as accounting ones, which can be ignored.

### Completeness check

| File | Source | Columns |
|---|---|---|
| 22_lookup_fields.csv | ir_model_fields (Odoo's metadata) | lookup_model, lookup_table, used_by |

Files 01–20 were chosen by reading the Gen 1 code and the mapping sheet. File 22 asks the database instead: it lists every lookup table that farmer, land, crop, livestock, membership, phone and ID records point to (their many2one and many2many fields), with the fields that use each one. Odoo's own tables (users, mail, calendar, website, files) are left out.

To use it, go through file 22 and check each `lookup_table`:

| If the table… | Then |
|---|---|
| has its own file (01–20) | It's covered. |
| has no file and is a code list | It's missing from the export, and needs a Master Data mapping too. |
| has no file and isn't a code list (enumerators, tags, consent settings, import bookkeeping) | No action. Note why it's skipped. |

`used_by` also shows uses of a list the mapping may not have considered, such as a second field pointing at the language list.

## What it doesn't cover

- **Free-text fields.** Soil fertility, current land use and means of acquisition are free text in Gen 1, so there's no list to export. Their values could only be seen by reading land records.
- **Usage.** Nothing says which values are used or how often. If a mapping gap needs that, ask for it separately, for that list only.
- **Gender in file 22.** Farmers store gender as text, not as a link, so it doesn't appear in the completeness check. File 18 covers it.
- **Records outside the check's list.** File 22 only looks at the record types named in its query. If another record type matters, add its model to the query.

## Version differences

Columns that differ between Gen 1 versions, such as a list without `code`, a translated `name`, or the P-code columns, are read through `to_jsonb(row)`. A column that doesn't exist comes out as an empty cell instead of an error. Empty `code` cells are the sign of an older Gen 1 version.

## Tested

23 Nov 2026, against the local copy of Gen 1 staging (`socialregistry_staging`): all 22 exports ran in about 5 seconds, and a run with a missing table reported the failure and carried on. Staging is an older Gen 1 version than the Gen 1 code provided by the team (its `g2p_crop` and `g2p_livestock_type` have no `code` column), so the test only shows the script works. The lists themselves have to come from production.
