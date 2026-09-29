-- dbt/tests/assert_salary_amounts_valid.sql
-- Parsed salaries (data_model.md, section 7.1). Every returned row breaks a rule:
--   1. amounts are positive and the minimum is not above the maximum;
--   2. a monthly SAR value exists exactly when the period converts (month, week, year);
--   3. the monthly SAR value is the amount made yearly (month x12, week x52, year x1), converted
--      with seed_currency_rates, divided by 12 and rounded to whole riyals.
select
    l.source_record_sk,
    l.salary_text,
    l.salary_min_amount,
    l.salary_max_amount,
    l.salary_period,
    l.salary_min_sar_month,
    l.salary_max_sar_month
from {{ ref('int_job_listings') }} l
left join {{ ref('seed_currency_rates') }} fx
    on l.salary_currency = fx.currency
where l.salary_is_parsed
  and (   l.salary_min_amount <= 0
       or l.salary_min_amount > l.salary_max_amount
       or (l.salary_period in ('month', 'week', 'year')) <> (l.salary_min_sar_month is not null)
       or l.salary_min_sar_month <> round(l.salary_min_amount * decode(l.salary_period, 'month', 12, 'week', 52, 'year', 1)
                                          * fx.sar_per_unit / 12, 0)
       or l.salary_max_sar_month <> round(l.salary_max_amount * decode(l.salary_period, 'month', 12, 'week', 52, 'year', 1)
                                          * fx.sar_per_unit / 12, 0))
