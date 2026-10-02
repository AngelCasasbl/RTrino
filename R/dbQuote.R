#' Quote identifiers and strings for Trino
#'
#' Trino follows the SQL standard: identifiers are wrapped in double quotes
#' with embedded double quotes doubled, and string literals are wrapped in
#' single quotes with embedded single quotes doubled. A value that is already
#' [DBI::SQL()] is returned unchanged rather than quoted a second time.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param x A character vector, or an identifier for `dbQuoteIdentifier()`.
#' @param ... Unused, for compatibility with the generic.
#' @return A [DBI::SQL] object.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#' DBI::dbQuoteIdentifier(con, "my column")
#' DBI::dbQuoteString(con, "O'Brien")
#' DBI::dbDisconnect(con)
setMethod(
  "dbQuoteIdentifier", c("TrinoConnection", "character"),
  function(conn, x, ...) {
    if (anyNA(x)) {
      stop("Cannot quote NA as an identifier.", call. = FALSE)
    }
    quoted <- paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
    DBI::SQL(quoted, names = names(x))
  }
)

#' @rdname dbQuoteIdentifier-TrinoConnection-character-method
#' @export
setMethod(
  "dbQuoteIdentifier", c("TrinoConnection", "SQL"),
  function(conn, x, ...) x
)

#' @rdname dbQuoteIdentifier-TrinoConnection-character-method
#' @export
setMethod(
  "dbQuoteString", c("TrinoConnection", "character"),
  function(conn, x, ...) {
    out <- paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
    out[is.na(x)] <- "NULL"
    DBI::SQL(out, names = names(x))
  }
)

#' @rdname dbQuoteIdentifier-TrinoConnection-character-method
#' @export
setMethod(
  "dbQuoteString", c("TrinoConnection", "SQL"),
  function(conn, x, ...) x
)

#' Quote R values as Trino literals
#'
#' Turns R values into SQL literals Trino accepts where a value of the matching
#' type is expected. Used by [DBI::sqlInterpolate()] and `glue::glue_sql()`, and
#' so the way to put values into a statement, since RTrino has no parameter
#' binding. Missing values become `NULL`.
#'
#' * character and factor: `'text'`, with embedded quotes doubled;
#' * logical: `TRUE` or `FALSE`;
#' * integer and `integer64`: the integer's digits;
#' * double: a `DOUBLE` literal that reads back as the same double, such as
#'   `0.30000000000000004E0`, or `nan()`, `infinity()` or `-infinity()`;
#' * `Date`: `DATE '2026-01-15'`;
#' * `POSIXct`: `TIMESTAMP '2026-01-15 10:30:00.123456'`, the instant as a
#'   wall-clock time in the connection's `session.timezone`, which is how Trino
#'   reads it back;
#' * a list of raw vectors: `X'0102FF'`.
#'
#' Other classes are quoted by DBI's default method.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param x A vector to quote.
#' @param ... Unused, for compatibility with the generic.
#' @return A [DBI::SQL] object.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#' DBI::dbQuoteLiteral(con, as.Date("2026-01-15"))
#' DBI::sqlInterpolate(
#'   con, "SELECT * FROM orders WHERE orderdate >= ?since AND urgent = ?flag",
#'   since = as.Date("2026-01-01"), flag = TRUE
#' )
#' DBI::dbDisconnect(con)
setMethod("dbQuoteLiteral", "TrinoConnection", function(conn, x, ...) {
  if (methods::is(x, "SQL")) {
    return(x)
  }
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (is.character(x)) {
    return(dbQuoteString(conn, x))
  }

  missing <- is.na(x)
  if (inherits(x, "Date")) {
    out <- trino_date_literal(x)
  } else if (inherits(x, "POSIXt")) {
    x <- as.POSIXct(x)
    out <- trino_timestamp_literal(x, conn@session.timezone)
  } else if (is.logical(x)) {
    out <- ifelse(x, "TRUE", "FALSE")
  } else if (bit64::is.integer64(x) || is.integer(x)) {
    out <- as.character(x)
  } else if (is.double(x) && !inherits(x, "difftime")) {
    out <- trino_double_literal(x)
    # NaN is a value, not a missing one.
    missing <- missing & !is.nan(x)
  } else {
    return(methods::callNextMethod())
  }

  out[missing] <- "NULL"
  DBI::SQL(out, names = names(x))
})

#' Trino literals for dates, timestamps and doubles
#'
#' Shared by `dbQuoteLiteral()` and by the dbplyr escapes, so a value is
#' written the same way whichever path puts it into a query. Missing values
#' are left for the caller to turn into `NULL`.
#'
#' A `POSIXct` is written as a plain `TIMESTAMP` in the session time zone, to
#' the microsecond: Trino reads such a literal in the session time zone, both
#' when comparing it with a `TIMESTAMP WITH TIME ZONE` and when storing it in a
#' `TIMESTAMP` column, which RTrino then reads back in that same zone.
#'
#' @param x A vector of the matching class.
#' @param timezone The session time zone.
#' @return A character vector.
#' @name trino_literals
#' @noRd
trino_date_literal <- function(x) {
  paste0("DATE '", format(x, "%Y-%m-%d"), "'")
}

#' @rdname trino_literals
#' @noRd
trino_timestamp_literal <- function(x, timezone) {
  seconds <- as.numeric(x)
  whole <- floor(seconds)
  micros <- round((seconds - whole) * 1e6)
  carry <- !is.na(micros) & micros >= 1e6
  whole[carry] <- whole[carry] + 1
  micros[carry] <- 0

  stamp <- format(
    as.POSIXct(whole, origin = "1970-01-01", tz = "UTC"),
    "%Y-%m-%d %H:%M:%S",
    tz = timezone
  )
  fraction <- ifelse(
    is.na(micros) | micros == 0,
    "",
    sprintf(".%06d", as.integer(micros))
  )
  paste0("TIMESTAMP '", stamp, fraction, "'")
}

#' @rdname trino_literals
#' @noRd
trino_double_literal <- function(x) {
  # The shortest of 15, 16 or 17 significant digits that reads back as the
  # same double, with an exponent so that Trino types it as DOUBLE rather
  # than DECIMAL.
  finite <- is.finite(x)
  shown <- formatC(x[finite], digits = 15L, format = "g")
  for (digits in c(16L, 17L)) {
    inexact <- as.numeric(shown) != x[finite]
    shown[inexact] <- formatC(x[finite][inexact], digits = digits, format = "g")
  }
  shown <- toupper(trimws(shown))
  plain <- !grepl("E", shown, fixed = TRUE)
  shown[plain] <- paste0(shown[plain], "E0")

  out <- rep(NA_character_, length(x))
  out[finite] <- shown
  out[is.nan(x)] <- "nan()"
  out[x %in% Inf] <- "infinity()"
  out[x %in% -Inf] <- "-infinity()"
  out
}
