skip_if_not_installed("dbplyr", "2.6.0")
skip_if_not_installed("dplyr")

test_that("the connection has a Trino dialect", {
  dialect <- dbplyr::sql_dialect(simulate_trino())
  expect_s3_class(dialect, "sql_dialect_trino")
  expect_true(dialect$has$window_clause)
  expect_true(dialect$has$table_alias_with_as)
  expect_false(dialect$has$star_table_prefix)
})

test_that("identifiers are quoted with double quotes", {
  dialect <- dbplyr::sql_dialect(simulate_trino())
  expect_identical(as.character(dialect$quote_identifier("x")), '"x"')
})

test_that("casts and string functions translate to Trino spellings", {
  con <- simulate_trino()

  translate <- function(expr) {
    as.character(dbplyr::translate_sql(!!rlang::enquo(expr), con = con))
  }

  expect_match(translate(as.character(x)), "CAST\\(.*AS VARCHAR\\)")
  expect_match(translate(as.numeric(x)), "CAST\\(.*AS DOUBLE\\)")
  expect_match(translate(as.integer(x)), "CAST\\(.*AS INTEGER\\)")
  expect_match(translate(grepl("a", x)), "REGEXP_LIKE")
  expect_match(translate(gsub("a", "b", x)), "REGEXP_REPLACE")
  expect_match(translate(paste0(x, y)), 'CONCAT_WS\\(\'\', "x", "y"\\)')
})

test_that("median and quantile use approx_percentile", {
  sql <- as.character(dbplyr::translate_sql(
    median(x),
    con = simulate_trino(),
    window = FALSE
  ))
  expect_match(sql, "APPROX_PERCENTILE\\(.*0\\.5\\)")
})

test_that("null-safe comparison uses IS DISTINCT FROM", {
  con <- simulate_trino()

  translate <- function(expr) {
    as.character(dbplyr::translate_sql(!!rlang::enquo(expr), con = con))
  }

  expect_match(translate(is_distinct_from(x, y)), '"x".* IS DISTINCT FROM .*"y"')
  expect_match(
    translate(is_not_distinct_from(x, y)),
    '"x".* IS NOT DISTINCT FROM .*"y"'
  )
})

test_that("filter_out() renders Trino's IS DISTINCT FROM", {
  # dplyr 1.2.0 added filter_out(); dbplyr reaches the backend through
  # is_distinct_from(), whose portable fallback is a long CASE WHEN.
  skip_if_not_installed("dplyr", "1.2.0")

  lazy <- dbplyr::lazy_frame(x = 1, y = 2, con = simulate_trino()) |>
    dplyr::filter_out(x > 1)

  sql <- as.character(dbplyr::sql_render(lazy))
  expect_match(sql, "IS DISTINCT FROM")
  expect_no_match(sql, "CASE WHEN")
})

test_that("a dplyr pipeline renders Trino SQL", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # The fake server describes this query as columns `n` and `label`.
  lazy <- dplyr::tbl(con, dbplyr::sql("SELECT * FROM sales")) |>
    dplyr::filter(n > 1) |>
    dplyr::group_by(label) |>
    dplyr::summarise(total = sum(n, na.rm = TRUE))

  sql <- as.character(dbplyr::sql_render(lazy, con = con))
  expect_match(sql, 'GROUP BY\\s+"label"')
  expect_match(sql, "SUM\\(")
  expect_match(sql, 'WHERE\\s+\\("n" > 1')
})

test_that("explain prepends EXPLAIN", {
  sql <- dbplyr::sql_query_explain(
    dbplyr::sql_dialect(simulate_trino()),
    dbplyr::sql("SELECT 1")
  )
  expect_identical(as.character(sql), "EXPLAIN SELECT 1")
})

test_that("collect() pulls rows through dbFetch()", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- dplyr::tbl(con, dbplyr::sql("SELECT * FROM big")) |>
    dplyr::collect()
  expect_identical(nrow(out), 8L)
})
