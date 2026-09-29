-- dbt/analyses/companies_not_in_seed.sql
--
-- Employer entity resolution, step 2 (data_model.md, dim_company): candidate spellings of one
-- employer that the alias seed does not merge yet. Two company keys are candidates when they
-- appear in the same city and one is contained in the other as whole words ("qiddiya" in
-- "qiddiya investment") or they share most of their words. A person accepts or rejects each
-- pair; accepted pairs go into seeds/seed_company_aliases.csv (alias stored in
-- normalize_company() form). Report: candidates listed, pairs accepted, listings resolved.

with companies as (
    select company_norm, city_std, count(*) as listings, any_value(company_raw) as example_name
    from {{ ref('int_job_listings') }}
    where company_norm is not null
      and city_std is not null
    group by company_norm, city_std
),

tokens as (
    select distinct c.company_norm, t.value::string as token
    from (select distinct company_norm from companies) c,
    lateral flatten(input => split(c.company_norm, ' ')) t
    where length(t.value::string) > 1
),

token_counts as (
    select company_norm, count(*) as tokens from tokens group by company_norm
),

pairs as (
    select distinct a.company_norm as company_a, b.company_norm as company_b
    from companies a
    join companies b
        on  a.city_std = b.city_std
        and a.company_norm < b.company_norm
),

shared as (
    select p.company_a, p.company_b, count(*) as tokens_shared
    from pairs p
    join tokens ta on ta.company_norm = p.company_a
    join tokens tb on tb.company_norm = p.company_b and tb.token = ta.token
    group by p.company_a, p.company_b
),

listing_totals as (
    select company_norm, sum(listings) as listings, any_value(example_name) as example_name
    from companies
    group by company_norm
)

select
    s.company_a,
    s.company_b,
    la.example_name                                                  as example_a,
    lb.example_name                                                  as example_b,
    la.listings                                                      as listings_a,
    lb.listings                                                      as listings_b,
    round(100 * s.tokens_shared / (ca.tokens + cb.tokens - s.tokens_shared), 1) as word_overlap,
    ' ' || s.company_b || ' ' like '% ' || s.company_a || ' %'
        or ' ' || s.company_a || ' ' like '% ' || s.company_b || ' %' as one_contains_other
from shared s
join token_counts ca on ca.company_norm = s.company_a
join token_counts cb on cb.company_norm = s.company_b
join listing_totals la on la.company_norm = s.company_a
join listing_totals lb on lb.company_norm = s.company_b
where ' ' || s.company_b || ' ' like '% ' || s.company_a || ' %'
   or ' ' || s.company_a || ' ' like '% ' || s.company_b || ' %'
   or 100 * s.tokens_shared / (ca.tokens + cb.tokens - s.tokens_shared) >= 60
order by la.listings + lb.listings desc
