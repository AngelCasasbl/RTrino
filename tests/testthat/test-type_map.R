test_that("parameterised types reduce to their bare name", {
  expect_identical(trino_raw_type("varchar(10)"), "varchar")
  expect_identical(trino_raw_type("DECIMAL(38,9)"), "decimal")
  expect_identical(
    trino_raw_type("timestamp(6) with time zone"),
    "timestamp with time zone"
  )
  expect_identical(trino_raw_type("array(row(a integer, b varchar))"), "array")
  expect_identical(trino_raw_type("map(varchar, array(integer))"), "map")
  expect_identical(
    trino_raw_type("INTERVAL DAY TO SECOND"),
    "interval day to second"
  )
})

test_that("every documented Trino type maps to the documented R type", {
  expected <- c(
    boolean = "logical",
    unknown = "logical",
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
    `INTERVAL DAY TO SECOND` = "character",
    `INTERVAL YEAR TO MONTH` = "character",
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

test_that("trino_type_to_r() takes a single type name", {
  expect_error(trino_type_to_r(NA_character_), "`type` must be a single string")
  expect_error(trino_type_to_r(character()), "`type` must be a single string")
  expect_error(trino_type_to_r(c("bigint", "date")), "must be a single string")
  expect_error(trino_type_to_r(""), "`type` must not be empty")
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
  expect_identical(
    trino_cast_column(list(NULL, NULL), "double"),
    c(NA_real_, NA)
  )
})

test_that("an empty column keeps its type", {
  expect_identical(trino_cast_column(list(), "integer"), integer())
  expect_identical(trino_cast_column(list(), "double"), numeric())
  expect_identical(trino_cast_column(list(), "varchar"), character())
  expect_identical(trino_cast_column(list(), "date"), as.Date(character()))
  expect_s3_class(trino_cast_column(list(), "bigint"), "integer64")
  expect_length(trino_cast_column(list(), "bigint"), 0L)
})

test_that("BIGINT sent as JSON numbers keeps every digit", {
  # What jsonlite hands over for Trino's JSON numbers: an integer within 32
  # bits, an exact double up to 2^53, the digits as a string beyond that.
  values <- list(
    2147483647L, 3e9, 44995000000, 9007199254740992, "9007199254740993",
    "-9223372036854775808", NULL
  )
  digits <- c(
    "2147483647", "3000000000", "44995000000", "9007199254740992",
    "9007199254740993", "-9223372036854775808", NA
  )

  # bit64 keeps the lowest 64-bit integer for its NA, so that one value
  # cannot be represented; it is the only one, and it is not silent.
  expect_warning(
    out <- trino_cast_column(values, "bigint", bigint = "integer64"),
    "-9223372036854775808 has no integer64 representation"
  )
  expect_s3_class(out, "integer64")
  expect_identical(as.character(out), replace(digits, 6L, NA))

  # jsonlite hands that value over as the double -2^63, not as digits.
  expect_warning(
    lowest <- trino_cast_column(list(1L, -2^63), "bigint"),
    "has no integer64 representation"
  )
  expect_identical(as.character(lowest), c("1", NA))
  expect_identical(
    trino_cast_column(list(-2^63), "bigint", bigint = "character"),
    "-9223372036854775808"
  )

  expect_identical(
    trino_cast_column(values, "bigint", bigint = "character"),
    digits
  )
  expect_identical(
    trino_cast_column(values, "bigint", bigint = "numeric"),
    as.numeric(digits)
  )
})

test_that("DOUBLE keeps every bit, and the non-finite values arrive as text", {
  values <- list(0.1 + 0.2, 1 / 3, 5e-324, -0, "NaN", "Infinity", "-Infinity",
                 NULL)
  out <- trino_cast_column(values, "double")
  expect_identical(
    out,
    c(0.1 + 0.2, 1 / 3, 5e-324, -0, NaN, Inf, -Inf, NA)
  )
  expect_identical(1 / out[[4]], -Inf)
})

test_that("DECIMAL, sent as text, becomes a double", {
  expect_identical(
    trino_cast_column(list("12.34", NULL, "-0.50"), "decimal(10,2)"),
    c(12.34, NA, -0.5)
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
    trino_cast_column(list("2026-01-15", NULL), "date"),
    as.Date(c("2026-01-15", NA))
  )
})

test_that("repeated dates and timestamps are parsed once and put back", {
  dates <- list("2026-01-15", "2026-01-16", NULL, "2026-01-15", "2026-01-16")
  expect_identical(
    trino_cast_column(dates, "date"),
    as.Date(c("2026-01-15", "2026-01-16", NA, "2026-01-15", "2026-01-16"))
  )

  stamps <- list(
    "2026-01-15 10:30:00.000 +02:00",
    NULL,
    "2026-01-15 10:30:00.000 +02:00",
    "2026-01-15 10:30:00.000 UTC"
  )
  out <- trino_cast_column(stamps, "timestamp(3) with time zone")
  expect_identical(
    format(out, "%H:%M", tz = "UTC"),
    c("08:30", NA, "08:30", "10:30")
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
  out <- trino_cast_column(
    list(
      "2026-01-15 10:30:00.000 Europe/Madrid",
      "2026-01-15 10:30:00.000 +02:00",
      NULL,
      "2026-07-15 10:30:00.000 Europe/Madrid",
      "2026-01-15 10:30:00.000 -05:30"
    ),
    "timestamp(3) with time zone",
    timezone = "UTC"
  )
  # Madrid is UTC+1 in January and UTC+2 in July.
  expect_identical(
    format(out, "%m-%d %H:%M", tz = "UTC"),
    c("01-15 09:30", "01-15 08:30", NA, "07-15 08:30", "01-15 16:00")
  )
})

test_that("nested types stay as lists", {
  out <- trino_cast_column(list(list(1L, 2L), NULL), "array(integer)")
  expect_type(out, "list")
  expect_identical(out[[1]], list(1L, 2L))
  expect_null(out[[2]])
})

test_that("a type the package does not know is kept as text, row by row", {
  out <- suppressWarnings(
    trino_cast_column(list("a", list(x = 1L), NULL, 2L), "hyperdimensional")
  )
  expect_identical(out, c("a", "{\"x\":1}", NA, "2"))
})

# Every value below was recorded from Trino 483 (dev/record-fixtures.R), so the
# payload is the one the package really has to read.

# The IEEE 754 bits of a double, as Trino's to_hex(to_ieee754_64()) prints them.
double_bits <- function(x) {
  vapply(x, function(v) {
    if (is.na(v) && !is.nan(v)) {
      return(NA_character_)
    }
    toupper(paste(writeBin(v, raw(), size = 8L, endian = "big"), collapse = ""))
  }, character(1L))
}

test_that("recorded BIGINT and DOUBLE values arrive exactly as in Trino", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_warning(
    out <- DBI::dbGetQuery(con, trino_fixture_sql("numbers")),
    "-9223372036854775808 has no integer64 representation"
  )
  expect_identical(nrow(out), 14L)

  # Trino printed the reference columns itself. Row 10 is the lowest BIGINT,
  # which bit64 cannot hold.
  expect_s3_class(out$b, "integer64")
  expect_identical(as.character(out$b)[-10L], out$b_text[-10L])
  expect_true(is.na(out$b[[10L]]))
  expect_identical(double_bits(out$d), out$d_bits)
})

test_that("recorded BIGINT values are exact as text and rounded as doubles", {
  proc <- local_trino_app()

  as_text <- DBI::dbGetQuery(
    local_trino_con(proc, bigint = "character"),
    trino_fixture_sql("numbers")
  )
  expect_identical(as_text$b, as_text$b_text)

  as_double <- DBI::dbGetQuery(
    local_trino_con(proc, bigint = "numeric"),
    trino_fixture_sql("numbers")
  )
  expect_type(as_double$b, "double")

  # Trino's own text is the reference, read back by R's string parser. That
  # parser is exact up to 15 digits, but on platforms where `long double` is
  # a plain double (macOS on Apple silicon) it drifts by an ulp or two on
  # longer ones: it reads -9223372036854775808 as -9223372036854777856, while
  # the column, parsed from JSON, holds -2^63 exactly.
  long <- nchar(as_double$b_text) > 15L
  expect_identical(as_double$b[!long], as.numeric(as_double$b_text[!long]))
  expect_equal(
    as_double$b[long], as.numeric(as_double$b_text[long]),
    tolerance = 1e-15
  )
  expect_identical(as_double$b[[10L]], -2^63)
})

test_that("a recorded row of every type converts to the documented R type", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  out <- DBI::dbGetQuery(con, trino_fixture_sql("types"))
  expect_identical(nrow(out), 2L)
  row <- out[1L, ]

  expect_identical(row$flag, TRUE)
  expect_identical(row$tiny, 7L)
  expect_identical(row$small, 3L)
  expect_identical(row$n, 42L)
  expect_identical(as.character(row$big), "9007199254740993")
  expect_identical(row$r, 1.5)
  expect_identical(row$dbl, 0.1)
  expect_identical(row$dec, 12.34)
  expect_identical(row$bigdec, 12345678901234567.89)
  expect_identical(row$txt, "hello")
  expect_identical(row$ch, "abc")
  expect_identical(row$bin[[1]], as.raw(c(1L, 2L, 255L)))
  expect_identical(row$d, as.Date("2026-01-15"))
  expect_identical(row$t3, "10:30:00.123")
  expect_identical(row$t6, "10:30:00.123456")
  expect_identical(row$ids, "3 00:00:00.000")
  expect_identical(row$iym, "0-2")
  expect_identical(row$arr[[1]], list(1L, 2L, 3L))
  expect_identical(row$mp[[1]], list(a = 1L, b = 2L))
  expect_identical(row$rw[[1]], list(1L, "x"))
  expect_identical(row$js, "{\"k\":1}")
  expect_identical(row$uid, "12151fd2-7586-11e9-8f9e-2a86e4085a59")
  expect_identical(row$ip, "10.0.0.1")
  expect_identical(row$utf8, "ñandú 漢字")
})

test_that("recorded timestamps keep their microseconds and their instant", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  row <- DBI::dbGetQuery(con, trino_fixture_sql("types"))[1L, ]
  noon <- as.numeric(as.POSIXct("2026-01-15 10:30:00", tz = "UTC"))

  # The capability header makes Trino send timestamp(6) at full precision.
  expect_equal(as.numeric(row$ts3) - noon, 0.123, tolerance = 1e-6)
  expect_equal(as.numeric(row$ts6) - noon, 0.123456, tolerance = 1e-7)
  # Europe/Madrid is UTC+1 in January; +02:00 is two hours ahead of UTC.
  expect_equal(as.numeric(row$tsz) - noon, -3600 + 0.123456, tolerance = 1e-7)
  expect_equal(as.numeric(row$tsoff) - noon, -7200)
  expect_identical(attr(row$tsz, "tzone"), "UTC")
})

test_that("a recorded row of NULLs is NA in every column", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  row <- DBI::dbGetQuery(con, trino_fixture_sql("types"))[2L, ]
  nested <- c("bin", "arr", "mp", "rw")
  for (col in setdiff(names(row), c("i", nested))) {
    expect_true(is.na(row[[col]]), info = col)
  }
  for (col in nested) {
    expect_null(row[[col]][[1]], info = col)
  }
})

test_that("bigint = \"numeric\" is honoured end to end", {
  proc <- local_trino_app()
  con <- local_trino_con(proc, bigint = "numeric")

  out <- DBI::dbGetQuery(con, trino_fixture_sql("types"))
  expect_type(out$big, "double")
})

test_that("an unknown column type warns once per result, not once per chunk", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  res <- DBI::dbSendQuery(con, "SELECT oddtype")
  withr::defer(try(DBI::dbClearResult(res), silent = TRUE))

  warnings <- testthat::capture_warnings({
    while (!DBI::dbHasCompleted(res)) DBI::dbFetch(res, n = 1)
  })
  expect_identical(
    warnings,
    "Unknown Trino type 'hyperdimensional'; returning it as character."
  )
})
