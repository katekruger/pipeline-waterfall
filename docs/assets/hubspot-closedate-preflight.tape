# Regenerate with: vhs docs/assets/hubspot-closedate-preflight.tape
# (run from the repo root; requires integration_tests/ to already have
# `dbt deps` run once so the demo command doesn't show package resolution)
#
# Shows the refusal, not a passing build: hubspot_closedate_tracked firing
# against a HubSpot config missing `closedate`, then the exact message
# naming the fix -- dbt's own console output only shows a row count on
# test failure, so the message needs a follow-up query to actually see it.
# This is the product.

Output docs/assets/hubspot-closedate-preflight.gif

Set Shell "bash"
Set FontSize 15
Set Width 1200
Set Height 750
Set Theme "Dracula"
Set TypingSpeed 45ms
Set Padding 20

Type "cd integration_tests"
Enter
Sleep 500ms

Type `uv run --with-requirements requirements.txt dbt build -s hubspot_closedate_tracked --vars '{"hubspot__deal_property_history_columns": ["amount", "dealstage"]}'`
Enter
Sleep 4s

Type `uv run --with-requirements requirements.txt python3 -c "import duckdb; print(duckdb.connect('dev.duckdb').execute('select message from hubspot_closedate_tracked').fetchone()[0])"`
Enter
Sleep 5s
