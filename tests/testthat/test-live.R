# Integration tests against a real Trino.
#
# Skipped unless RTRINO_TEST_URL points at a coordinator, for example
#
#   docker run --rm -d -p 8080:8080 --name trino trinodb/trino
#   RTRINO_TEST_URL=http://localhost:8080 Rscript -e 'devtools::test()'
#
# The rest of the suite replays recorded payloads; these check the same things
# end to end, and run the SQL that the dplyr translations generate, comparing
# what Trino computes with what R computes on the same rows. Every reference
# value is rendered by Trino itself, not by RTrino: CAST(x AS varchar) for a
# BIGINT, to_hex(to_ieee754_64(x)) for the bits of a DOUBLE, to_unixtime()
# for an instant.

live_con <- function(..., .local_envir = parent.frame()) {
  url <- Sys.getenv("RTRINO_TEST_URL")
  testthat::skip_if(!nzchar(url), "RTRINO_TEST_URL is not set")
  testthat::skip_on_cran()
  args <- utils::modifyList(
    list(
      RTrino::Trino(), host = url, user = "rtrino-test",
      catalog = "tpch", schema = "tiny"
    ),
    list(...)
  )
  con <- do.call(DBI::dbConnect, args)
  withr::defer(DBI::dbDisconnect(con), envir = .local_envir)
  con
}

# A table name no other run will use.
live_table <- function() {
  paste0("rtrino_test_", format(Sys.time(), "%H%M%S"), "_", sample.int(1e6, 1))
}

double_bits <- function(x) {
  vapply(x, function(v) {
    if (is.na(v) && !is.nan(v)) {
      return(NA_character_)
    }
    toupper(paste(writeBin(v, raw(), size = 8L, endian = "big"), collapse = ""))
  }, character(1L))
}

# ---------------------------------------------------------------- values --

test_that("15 000 BIGINT and DOUBLE values match Trino exactly", {
  con <- live_con()
  sql <- "
    SELECT orderkey * 1000000 AS b,
           CAST(orderkey * 1000000 AS varchar) AS b_text,
           totalprice / 7 AS d,
           to_hex(to_ieee754_64(totalprice / 7)) AS d_bits
    FROM tpch.tiny.orders"

  out <- DBI::dbGetQuery(con, sql)
  expect_identical(nrow(out), 15000L)
  expect_identical(sum(as.character(out$b) != out$b_text), 0L)
  expect_identical(sum(double_bits(out$d) != out$d_bits), 0L)

  as_text <- DBI::dbGetQuery(live_con(bigint = "character"), sql)
  expect_identical(as_text$b, as_text$b_text)
})

test_that("BIGINT and DOUBLE edge values match Trino exactly", {
  con <- live_con()
  out <- DBI::dbGetQuery(con, "
    SELECT CAST(b AS varchar) AS b_text, b,
           d, to_hex(to_ieee754_64(d)) AS d_bits
    FROM (VALUES
      (BIGINT '3000000000', 0.1E0 + 0.2E0),
      (BIGINT '9007199254740993', 4.9E-324),
      (BIGINT '-9007199254740993', -0.0E0),
      (BIGINT '9223372036854775807', nan()),
      (BIGINT '2147483648', infinity()),
      (BIGINT '-2147483649', -infinity())
    ) AS t (b, d)")
  expect_identical(as.character(out$b), out$b_text)
  expect_identical(double_bits(out$d), out$d_bits)
})

test_that("timestamps keep their microseconds and their instant", {
  con <- live_con()
  out <- DBI::dbGetQuery(con, "
    SELECT ts, to_unixtime(ts) AS epoch FROM (VALUES
      TIMESTAMP '2026-01-15 10:30:00.123456 Europe/Madrid',
      TIMESTAMP '2026-07-15 10:30:00.123456 Europe/Madrid',
      TIMESTAMP '1969-07-20 20:17:40.5 UTC',
      TIMESTAMP '2026-10-25 02:30:00 Europe/Madrid',
      TIMESTAMP '2026-01-15 10:30:00 -05:30'
    ) AS t (ts)")
  expect_lt(max(abs(as.numeric(out$ts) - out$epoch)), 1e-6)

  plain <- DBI::dbGetQuery(con, "
    SELECT TIMESTAMP '2026-01-15 10:30:00.123456' AS ts,
           to_unixtime(TIMESTAMP '2026-01-15 10:30:00.123456') AS epoch")
  expect_lt(abs(as.numeric(plain$ts) - plain$epoch), 1e-6)
})

test_that("literals quoted by RTrino read back as the same values", {
  con <- live_con(session.timezone = "Europe/Madrid")
  quote <- function(x) as.character(DBI::dbQuoteLiteral(con, x))

  set.seed(20260929)
  doubles <- c(
    0.1 + 0.2, 1 / 3, 5e-324, -0, 1e300, -2.5e-8, 123456789.12345679, 1,
    runif(200, -1e6, 1e6), exp(runif(200, -700, 700))
  )
  values <- paste0("(", seq_along(doubles), ", ", quote(doubles), ")",
                   collapse = ", ")
  out <- DBI::dbGetQuery(con, paste0(
    "SELECT d FROM (VALUES ", values, ") AS t (i, d) ORDER BY i"
  ))
  expect_identical(double_bits(out$d), double_bits(doubles))

  when <- as.POSIXct("2026-01-15 09:30:00.123456", tz = "UTC")
  out <- DBI::dbGetQuery(con, paste(
    "SELECT", quote(as.Date("2026-01-15")), "AS d,",
    quote(when), "AS ts,",
    quote(TRUE), "AS flag,",
    quote(bit64::as.integer64("9007199254740993")), "AS big,",
    quote("O'Brien"), "AS txt,",
    quote(NA), "AS nothing"
  ))
  expect_identical(out$d, as.Date("2026-01-15"))
  expect_lt(abs(as.numeric(out$ts) - as.numeric(when)), 1e-6)
  expect_true(out$flag)
  expect_identical(as.character(out$big), "9007199254740993")
  expect_identical(out$txt, "O'Brien")
  expect_true(is.na(out$nothing))
})

# ------------------------------------------------------------ statements --

test_that("dbExecute() reports the rows each statement changed", {
  con <- live_con(catalog = "memory", schema = "default")
  name <- live_table()
  copy <- paste0(name, "_copy")
  withr::defer({
    DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", copy))
    DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", name))
  })

  execute <- function(...) DBI::dbExecute(con, paste(...))

  expect_identical(
    execute("CREATE TABLE", name, "(id bigint, label varchar)"),
    0
  )
  expect_identical(
    execute("INSERT INTO", name, "VALUES (1, 'a'), (2, 'b')"),
    2
  )
  expect_identical(
    execute("CREATE TABLE", copy, "AS SELECT * FROM", name),
    2
  )
  expect_identical(execute("SET SESSION query_max_run_time = '1h'"), 0)
})

test_that("a table is found by any of the names DBI allows", {
  con <- live_con(catalog = "memory", schema = "default")
  name <- live_table()
  DBI::dbExecute(con, paste("CREATE TABLE", name, "(id bigint, label varchar)"))
  withr::defer(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", name)))

  names <- list(
    plain = name,
    upper = toupper(name),
    schema_table = paste0("default.", name),
    three_parts = paste0("memory.default.", name),
    id = DBI::Id(catalog = "memory", schema = "default", table = name),
    id_table = DBI::Id(table = name),
    sql = DBI::SQL(paste0('"memory"."default"."', name, '"')),
    quoted = DBI::dbQuoteIdentifier(
      con,
      DBI::Id(schema = "default", table = name)
    )
  )
  for (label in names(names)) {
    n <- names[[label]]
    expect_true(DBI::dbExistsTable(con, n), info = label)
    expect_identical(DBI::dbListFields(con, n), c("id", "label"), info = label)
  }

  expect_false(DBI::dbExistsTable(con, paste0(name, "_nope")))
  expect_false(DBI::dbExistsTable(con, paste0("nowhere.default.", name)))
  expect_true(DBI::dbExistsTable(live_con(), "NATION"))
})

test_that("the columns are known before the first fetch", {
  con <- live_con()
  res <- DBI::dbSendQuery(con, "SELECT nationkey, name FROM nation")
  withr::defer(DBI::dbClearResult(res))

  expect_identical(DBI::dbColumnInfo(res)$name, c("nationkey", "name"))
  empty <- DBI::dbFetch(res, n = 0)
  expect_identical(names(empty), c("nationkey", "name"))
  expect_s3_class(empty$nationkey, "integer64")
  expect_identical(nrow(DBI::dbFetch(res)), 25L)
})

test_that("query_max_run_time stops a query on the server", {
  con <- live_con(query_max_run_time = "1s")
  cnd <- tryCatch(
    DBI::dbGetQuery(con, "SELECT count(*) FROM tpch.sf1000.lineitem"),
    error = identity
  )
  expect_s3_class(cnd, "trino_query_error")
  expect_identical(cnd$error_name, "EXCEEDED_TIME_LIMIT")
})

# ----------------------------------------------------------------- dplyr --

test_that("dplyr expressions compute in Trino what they compute in R", {
  skip_if_not_installed("dbplyr", "2.6.0")
  skip_if_not_installed("dplyr")
  con <- live_con()

  customer <- dplyr::tbl(con, "customer")
  # The reference: the same rows computed by R, with Trino's BIGINTs as the
  # plain R integers they would be in a data frame.
  local <- dplyr::collect(customer)
  local <- dplyr::mutate(
    local,
    dplyr::across(dplyr::where(bit64::is.integer64), as.integer)
  )

  check <- function(expr) {
    expr <- rlang::enquo(expr)
    remote <- customer |>
      dplyr::transmute(custkey, value = !!expr) |>
      dplyr::collect()
    remote <- remote[order(as.integer(remote$custkey)), ]
    here <- dplyr::transmute(local, custkey, value = !!expr)
    here <- here[order(here$custkey), ]
    value <- remote$value
    if (bit64::is.integer64(value)) value <- as.integer(value)
    expect_equal(value, here$value, info = rlang::as_label(expr))
  }

  check(grepl(".", phone, fixed = TRUE))
  check(grepl("-", phone, fixed = TRUE))
  check(grepl("customer", name, ignore.case = TRUE))
  check(grepl("^Customer#00000001", name))
  check(gsub("-", "", phone))
  check(gsub("^([0-9]+)-", "\\1:", phone))
  check(sub("-", "", phone))
  check(sub("^([0-9]+)-([0-9]+)", "\\2.\\1", phone))
  check(sub(".", "", phone, fixed = TRUE))
  check(paste0(mktsegment, "-", nationkey))
  check(paste(mktsegment, nationkey))
  check(custkey / nationkey)
  check(custkey / 2L)
  check(nationkey / 2)
  check(as.integer(acctbal))
  check(as.integer(acctbal * 1000))
  check(acctbal %% 7)
  check(nationkey %% 3L)
  check((nationkey - 12L) %% 5L)
})

test_that("dates move by periods and compare with R dates", {
  skip_if_not_installed("dbplyr", "2.6.0")
  skip_if_not_installed("dplyr")
  con <- live_con()
  orders <- dplyr::tbl(con, "orders")

  moved <- orders |>
    dplyr::filter(orderkey <= 100L) |>
    dplyr::transmute(orderkey, next_day = orderdate + days(1), orderdate) |>
    dplyr::collect()
  expect_identical(moved$next_day, moved$orderdate + 1)

  since <- as.Date("1995-01-01")
  remote <- orders |>
    dplyr::filter(orderdate >= !!since) |>
    dplyr::count() |>
    dplyr::collect()
  dates <- dplyr::collect(dplyr::select(orders, orderdate))$orderdate
  expect_identical(as.integer(remote$n), sum(dates >= since))
})

test_that("compute() writes a permanent table", {
  skip_if_not_installed("dbplyr", "2.6.0")
  skip_if_not_installed("dplyr")
  con <- live_con(catalog = "memory", schema = "default")
  name <- live_table()
  withr::defer(DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", name)))

  nation <- dplyr::tbl(con, dbplyr::in_catalog("tpch", "tiny", "nation"))
  expect_error(dplyr::compute(nation), "no temporary tables")
  saved <- dplyr::compute(nation, name = name, temporary = FALSE)
  expect_identical(nrow(dplyr::collect(saved)), 25L)
  expect_true(DBI::dbExistsTable(con, name))
})
