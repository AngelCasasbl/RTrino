test_that("parameterised types reduce to their bare name", {
  expect_identical(trino_raw_type("varchar(10)"), "varchar")
  expect_identical(trino_raw_type("DECIMAL(38,9)"), "decimal")
  expect_identical(
    trino_raw_type("timestamp(6) with time zone"),
    "timestamp with time zone"
  )
  expect_identical(trino_raw_type("array(row(a integer, b varchar))"), "array")
  expect_identical(trino_raw_type("map(varchar, array(integer))"), "map")
})

test_that("every documented Trino type maps to the documented R type", {
  expected <- c(
    boolean = "logical",
    tinyint = "integer",
    smallint = "integer",
    integer = "integer",
    real = "numeric",
    double = "numeric",
    `decimal(10,2)` = "numeric",
    `varchar(5)` = "character",
    char = "character",
    varbinary = "raw",
    date = "Date",
    `time(3)` = "character",
    `timestamp(3)` = "POSIXct",
    `timestamp(3) with time zone` = "POSIXct",
    `array(integer)` = "list",
    `map(varchar, integer)` = "list",
    `row(a integer)` = "list",
    json = "character",
    uuid = "character",
    ipaddress = "character"
  )
  for (type in names(expected)) {
    expect_identical(trino_type_to_r(type), expected[[type]], info = type)
  }
})

test_that("bigint follows the connection setting", {
  expect_identical(trino_type_to_r("bigint"), "integer64")
  expect_identical(trino_type_to_r("bigint", "numeric"), "numeric")
  expect_identical(trino_type_to_r("bigint", "character"), "character")
})

test_that("an unknown type warns and falls back to character", {
  expect_warning(
    out <- trino_type_to_r("hyperdimensional"),
    "Unknown Trino type 'hyperdimensional'"
  )
  expect_identical(out, "character")
})

test_that("NULL values become NA of the right type", {
  expect_identical(
    trino_cast_column(list(1L, NULL, 3L), "integer"),
    c(1L, NA_integer_, 3L)
  )
  expect_identical(
    trino_cast_column(list("a", NULL), "varchar(1)"),
    c("a", NA_character_)
  )
  expect_identical(
    trino_cast_column(list(TRUE, NULL), "boolean"),
    c(TRUE, NA)
  )
})

test_that("BIGINT keeps its precision as integer64", {
  big <- "9007199254740993"
  out <- trino_cast_column(list(big), "bigint", bigint = "integer64")
  expect_s3_class(out, "integer64")
  expect_identical(as.character(out), big)

  expect_identical(
    trino_cast_column(list(big), "bigint", bigint = "character"),
    big
  )
  expect_identical(
    trino_cast_column(list(big), "bigint", bigint = "numeric"),
    as.numeric(big)
  )
})

test_that("VARBINARY is decoded from base64 into raw", {
  encoded <- jsonlite::base64_enc(as.raw(c(1L, 2L, 255L)))
  out <- trino_cast_column(list(encoded, NULL), "varbinary")
  expect_type(out, "list")
  expect_identical(out[[1]], as.raw(c(1L, 2L, 255L)))
  expect_null(out[[2]])
})

test_that("DATE becomes Date", {
  expect_identical(
    trino_cast_column(list("2026-01-15"), "date"),
    as.Date("2026-01-15")
  )
})

test_that("TIMESTAMP is read in the session time zone", {
  out <- trino_cast_column(
    list("2026-01-15 10:30:00.000"),
    "timestamp(3)",
    timezone = "Europe/Madrid"
  )
  expect_s3_class(out, "POSIXct")
  expect_identical(attr(out, "tzone"), "Europe/Madrid")
  expect_identical(
    format(out, "%Y-%m-%d %H:%M:%S", tz = "Europe/Madrid"),
    "2026-01-15 10:30:00"
  )
})

test_that("TIMESTAMP WITH TIME ZONE resolves the instant, named or offset", {
  named <- trino_cast_column(
    list("2026-01-15 10:30:00.000 Europe/Madrid"),
    "timestamp(3) with time zone",
    timezone = "UTC"
  )
  # Madrid is UTC+1 in January.
  expect_identical(format(named, "%H:%M", tz = "UTC"), "09:30")

  offset <- trino_cast_column(
    list("2026-01-15 10:30:00.000 +02:00"),
    "timestamp(3) with time zone",
    timezone = "UTC"
  )
  expect_identical(format(offset, "%H:%M", tz = "UTC"), "08:30")
})

test_that("nested types stay as lists", {
  out <- trino_cast_column(list(list(1L, 2L), NULL), "array(integer)")
  expect_type(out, "list")
  expect_identical(out[[1]], list(1L, 2L))
  expect_null(out[[2]])
})

test_that("a row of every type round-trips through dbFetch()", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- DBI::dbGetQuery(con, "SELECT types")
  expect_identical(nrow(out), 1L)
  expect_true(out$flag)
  expect_identical(out$small, 3L)
  expect_identical(out$n, 7L)
  expect_s3_class(out$big, "integer64")
  expect_identical(as.character(out$big), "9007199254740993")
  expect_identical(out$dbl, 1.5)
  expect_identical(out$dec, 12.34)
  expect_identical(out$txt, "hello")
  expect_identical(out$bin[[1]], as.raw(c(1L, 2L, 255L)))
  expect_identical(out$d, as.Date("2026-01-15"))
  expect_identical(out$t, "10:30:00.000")
  expect_s3_class(out$ts, "POSIXct")
  expect_s3_class(out$tsz, "POSIXct")
  expect_identical(out$arr[[1]], list(1L, 2L, 3L))
  expect_identical(out$js, "{\"k\": 1}")
  expect_identical(out$uid, "f79a24f4-0b3a-4a1b-9f61-4f2f3a9c1d5e")
  expect_true(is.na(out$nil))
})

test_that("bigint = \"numeric\" is honoured end to end", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, bigint = "numeric")

  out <- DBI::dbGetQuery(con, "SELECT types")
  expect_type(out$big, "double")
})
