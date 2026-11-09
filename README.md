# Toronto-Bylaw-SQL-Analytics  
Relational database and SQL analysis of the City of Toronto's Municipal Licensing & Standards – Investigation Activity open dataset (active investigations plus those closed in the last two years).
Source: City of Toronto Open Data – Open Government Licence – Toronto. Data refreshed daily; snapshot taken Nov 2026.
## Data model:
Three source CSVs (336K+ rows) loaded into four normalized tables:
Table	Rows	Purpose
`investigations`	146,218	One row per investigation: standardized category and stage, status, dates
`properties`	51,700	One row per distinct address (68 flagged as placeholders)
`investigation_properties`	155,118	Bridge table: an investigation can cover several addresses
`deficiencies`	35,301	Child records (location, description, status) for 15,083 investigations
Views: `v_investigation_detail`, `v_open_backlog`.
## Cleaning decisions: 
Parsed text dates (`Jan 15, 2025`) to ISO dates; `N/A` and blanks became NULL.
Split `INVESTIGATION_TYPE` into category and stage (Initial / Notice Issued / Order Issued) and reconciled inconsistent names (`Prop Standards` vs `Property Standards`, `Long Grass` vs `Long Grass and Weeds`): 26 raw types became 14 categories.
Normalized addresses into a property dimension; found and flagged 68 placeholder "addresses" (e.g. ward-level stand-ins used for election signs) that would otherwise dominate repeat-property results.
Nulled two placeholder `NEXT_INSPECTION` dates in the year 2100; excluded 53 records where the notice date precedes the opened date from timing analysis.
## Selected findings (snapshot Nov 2026):
Property Standards is the largest category (37.6%), followed by Waste (17.7%) and Zoning (15.5%).
Time to Notice/Order varies widely: median 7 days for Waste and 9 for Property Standards, versus 44 for Rooming House and 41 for Fence.
Repeat activity is concentrated: about 10% of properties (5,146 with 6+ investigations) account for 43.6% of investigation-address links. Large multi-unit sites dominate the top of the list.
Backlog: 7,439 Property Standards investigations are not closed, 986 of them opened over a year ago.
Seasonality: monthly volume peaked in June–July 2025 (about 7.7K) and again in June 2026 (12.8K), driven partly by a one-month jump in Adequate Heat investigations (1,914 in June 2026 vs 72 in May).
## Limitations:
The dataset has no closed date, so time-to-close cannot be measured; "days to notice" is used as the timing metric instead.
Records appear only once an officer acts on a complaint, so counts reflect enforcement activity, not the number of underlying problems.
Coverage is mostly Oct 2024 onward (about 145K of 146K investigations were opened since 2024), so multi-year trends are not possible.
Only about 10% of investigations have deficiency records.
Address-level counts reflect large buildings with many units; they are not a ranking of problem landlords.
## Reproduce:
```bash
python3 load.py <folder with the 3 CSVs> mls.db   # builds the database (schema.sql)
python3 run_queries.py mls.db                      # runs queries.sql
```
Requires Python 3 and pandas. SQLite is used for portability; the SQL is standard (CTEs, window functions) and ports to PostgreSQL with minor changes (date functions).
