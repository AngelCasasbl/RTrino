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

translate <- function(expr, window = TRUE) {
  as.character(dbplyr::translate_sql(
    !!rlang::enquo(expr),
    con = simulate_trino(),
    window = window
  ))
}

test_that("casts and string functions translate to Trino spellings", {
  expect_match(translate(as.character(x)), "CAST\\(.*AS VARCHAR\\)")
  expect_match(translate(as.numeric(x)), "CAST\\(.*AS DOUBLE\\)")
  expect_match(translate(grepl("a", x)), "REGEXP_LIKE")
  expect_match(translate(gsub("a", "b", x)), "REGEXP_REPLACE")
})

test_that("division is a double division, as in R", {
  # Trino truncates the quotient of two integers.
  expect_identical(translate(x / y), 'CAST("x" AS DOUBLE) / "y"')
  expect_identical(translate(x / (y + 1L)), 'CAST("x" AS DOUBLE) / ("y" + 1)')
  expect_identical(translate((x + 1L) / 2L), 'CAST(("x" + 1) AS DOUBLE) / 2')
  # An operand built without R's parentheses still gets them in SQL.
  sum_yz <- rlang::expr(y + z)
  expect_identical(
    translate(x / !!sum_yz),
    'CAST("x" AS DOUBLE) / ("y" + "z")'
  )
})

test_that("%% takes the sign of the divisor, as in R", {
  expect_identical(
    translate(x %% y),
    paste0(
      'CASE WHEN MOD("x", "y") <> 0 AND (MOD("x", "y") < 0) <> ("y" < 0)',
      ' THEN MOD("x", "y") + "y" ELSE MOD("x", "y") END'
    )
  )
})

test_that("as.integer() and as.integer64() truncate, as in R", {
  expect_identical(
    translate(as.integer(x)),
    'CAST(TRUNCATE(CAST("x" AS DOUBLE)) AS INTEGER)'
  )
  expect_identical(
    translate(as.integer64(x)),
    'CAST(TRUNCATE(CAST("x" AS DECIMAL(38, 18))) AS BIGINT)'
  )
})

test_that("paste() casts what is not a string, which CONCAT_WS requires", {
  expect_identical(
    translate(paste0(x, "-", y)),
    "CONCAT_WS('', CAST(\"x\" AS VARCHAR), '-', CAST(\"y\" AS VARCHAR))"
  )
  expect_identical(
    translate(paste(x, 1)),
    "CONCAT_WS(' ', CAST(\"x\" AS VARCHAR), '1')"
  )
  expect_identical(
    translate(str_c(x, y)),
    "CONCAT_WS('', CAST(\"x\" AS VARCHAR), CAST(\"y\" AS VARCHAR))"
  )
  expect_error(translate(paste(x, collapse = ",")), "use str_flatten")
})

test_that("grepl() honours fixed and ignore.case", {
  expect_identical(translate(grepl(".", x)), "REGEXP_LIKE(\"x\", '.')")
  expect_identical(
    translate(grepl(".", x, fixed = TRUE)),
    "(STRPOS(\"x\", '.') > 0)"
  )
  expect_identical(
    translate(grepl("abc", x, ignore.case = TRUE)),
    "REGEXP_LIKE(\"x\", '(?i)abc')"
  )
  expect_identical(
    translate(grepl(y, x, ignore.case = TRUE)),
    "REGEXP_LIKE(\"x\", CONCAT('(?i)', \"y\", ''))"
  )
  expect_error(
    translate(grepl("a", x, fixed = TRUE, ignore.case = TRUE)),
    "cannot be combined"
  )
  expect_error(translate(grepl("a", x, useBytes = TRUE)), "not supported")
  expect_error(
    translate(grepl("a", x, fixed = NA)),
    "`fixed` must be `TRUE` or `FALSE`"
  )
})

test_that("gsub() rewrites R's back-references for Trino", {
  expect_identical(
    translate(gsub("^([0-9]+)-", "\\1:", x)),
    "REGEXP_REPLACE(\"x\", '^([0-9]+)-', '$1:')"
  )
  expect_identical(
    translate(gsub(".", "-", x, fixed = TRUE)),
    "REPLACE(\"x\", '.', '-')"
  )
  expect_error(translate(gsub("a", y, x)), "must be a string")
  expect_error(
    translate(gsub("(a)", "\\U\\1", x, perl = TRUE)),
    "Case conversion"
  )
})

test_that("R replacement strings map onto Trino's", {
  expect_identical(trino_regex_replacement("\\1", FALSE), "$1")
  # R has no group 10: it is group 1, then a zero.
  expect_identical(trino_regex_replacement("\\10", FALSE), "$1\\0")
  expect_identical(trino_regex_replacement("$1", FALSE), "\\$1")
  expect_identical(trino_regex_replacement("a\\\\b", FALSE), "a\\\\b")
  expect_identical(trino_regex_replacement("\\n", FALSE), "\\n")
  expect_identical(trino_regex_replacement("\\0", FALSE), "\\0")
  expect_identical(trino_regex_replacement("x\\", FALSE), "x")
  expect_identical(trino_regex_replacement("\\U", FALSE), "\\U")
})

test_that("sub() replaces the first match only", {
  sql <- translate(sub("-", "", x))
  expect_match(sql, "REGEXP_POSITION(\"x\", '-') = -1 THEN \"x\"", fixed = TRUE)
  expect_match(sql, "'\\A(?:-)'", fixed = TRUE)
  expect_no_match(sql, "REGEXP_REPLACE\\([^)]*, 1\\)")

  fixed <- translate(sub(".", "", x, fixed = TRUE))
  expect_match(fixed, "STRPOS(\"x\", '.') = 0", fixed = TRUE)
})

test_that("periods become intervals, so a date can be moved", {
  expect_identical(translate(days(1)), "(INTERVAL '1' DAY * 1)")
  expect_identical(translate(weeks(n)), "(INTERVAL '7' DAY * \"n\")")
  expect_identical(
    translate(d + months(2L)),
    "\"d\" + (INTERVAL '1' MONTH * 2)"
  )
})

test_that("dates and date-times from R become typed literals", {
  con <- simulate_trino()
  expect_identical(
    as.character(dbplyr::escape(as.Date("2026-01-15"), con = con)),
    "DATE '2026-01-15'"
  )
  expect_identical(
    as.character(dbplyr::escape(
      as.POSIXct("2026-01-15 10:30:00.5", tz = "UTC"),
      con = con
    )),
    "TIMESTAMP '2026-01-15 10:30:00.500000'"
  )
  expect_identical(
    as.character(dbplyr::escape(as.Date(NA), con = con)),
    "NULL"
  )
})

test_that("compute() needs a permanent table, and skips ANALYZE", {
  con <- simulate_trino()

  expect_error(
    dbplyr::sql_query_save(con, dbplyr::sql("SELECT 1"), "t"),
    "Trino has no temporary tables"
  )
  expect_identical(
    as.character(dbplyr::sql_query_save(
      con, dbplyr::sql("SELECT 1"), "t", temporary = FALSE
    )),
    "CREATE TABLE \"t\" AS\nSELECT 1"
  )
  expect_null(dbplyr::sql_table_analyze(con, "t"))
})

test_that("median and quantile use approx_percentile", {
  sql <- as.character(dbplyr::translate_sql(
    median(x),
    con = simulate_trino(),
    window = FALSE
  ))
  expect_match(sql, "APPROX_PERCENTILE\\(.*0\\.5\\)")
  expect_identical(
    translate(quantile(x, 0.9), window = FALSE),
    'APPROX_PERCENTILE("x", 0.9)'
  )
})

test_that("null-safe comparison uses IS DISTINCT FROM", {
  con <- simulate_trino()

  translate <- function(expr) {
    as.character(dbplyr::translate_sql(!!rlang::enquo(expr), con = con))
  }

  expect_match(
    translate(is_distinct_from(x, y)),
    '"x".* IS DISTINCT FROM .*"y"'
  )
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

test_that("copy_to() says RTrino does not upload data", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    dplyr::copy_to(con, data.frame(x = 1), "t"),
    "does not upload data from R"
  )
})

test_that("a date-time in a pipeline is written in the session time zone", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, session.timezone = "Europe/Madrid")

  x <- as.POSIXct("2026-01-15 09:30:00", tz = "UTC")
  lazy <- dplyr::tbl(con, dbplyr::sql("SELECT * FROM sales")) |>
    dplyr::filter(n > !!x)
  expect_match(
    as.character(dbplyr::sql_render(lazy)),
    "TIMESTAMP '2026-01-15 10:30:00'",
    fixed = TRUE
  )
})
