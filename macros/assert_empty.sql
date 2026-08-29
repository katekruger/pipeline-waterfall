{% test assert_empty(model) %}
{#-
    Generic test: fails the build if `model` returns any rows. Used to wire
    up each models/preflight/*.sql view (which computes violation rows,
    zero when healthy) as a real dbt test, while keeping the check itself a
    plain ref()-able model -- necessary so each one can also be exercised
    with dbt's unit_tests: (see models/preflight/schema.yml), which needs a
    model, not a bare test file, to mock inputs against.
-#}

select * from {{ model }}

{% endtest %}
