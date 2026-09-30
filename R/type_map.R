#' Reduce a Trino type to its bare name
#'
#' Strips the parameters a Trino type carries, so that `"varchar(10)"`,
#' `"decimal(38,9)"` and `"timestamp(6) with time zone"` become `"varchar"`,
#' `"decimal"` and `"timestamp with time zone"`. Parameter lists can nest
#' (`"array(row(a integer))"`), so they are removed by scanning the string and
#' tracking depth rather than with a regular expression.
#'
#' @param type A Trino type name.
#' @return A lower-case string.
#' @noRd
trino_raw_type <- function(type) {
  chars <- strsplit(tolower(type), "", fixed = TRUE)[[1L]]
  depth <- 0L
  keep <- logical(length(chars))
  for (i in seq_along(chars)) {
    ch <- chars[[i]]
    if (ch == "(") {
      depth <- depth + 1L
    } else if (ch == ")") {
      depth <- max(0L, depth - 1L)
    } else if (depth == 0L) {
      keep[[i]] <- TRUE
    }
  }
  trimws(gsub("[[:space:]]+", " ", paste(chars[keep], collapse = "")))
}

#' Map a Trino type to the name of an R type
#'
#' Reports the R type a column of the given Trino type is converted to. Mostly
#' useful for documentation and testing; [dbFetch()] converts columns through
#' `trino_cast_column()`.
#'
#' @param type A Trino type name, with or without parameters, as a single
#'   string.
#' @param bigint How `BIGINT` is handled; see [dbConnect()].
#'
#' @return A string naming an R class.
#' @export
#' @examples
#' trino_type_to_r("varchar(10)")
#' trino_type_to_r("bigint")
#' trino_type_to_r("bigint", bigint = "numeric")
#' trino_type_to_r("timestamp(3) with time zone")
trino_type_to_r <- function(type,
                            bigint = c("integer64", "numeric", "character")) {
  type <- trino_check_string(type, "type")
  bigint <- match.arg(bigint)
  switch(
    trino_raw_type(type),
    # The type of a bare NULL, as in SELECT NULL.
    unknown = ,
    boolean = "logical",
    tinyint = ,
    smallint = ,
    integer = ,
    int = "integer",
    bigint = bigint,
    real = ,
    double = ,
    `double precision` = ,
    decimal = "numeric",
    varchar = ,
    char = ,
    json = ,
    uuid = ,
    ipaddress = ,
    time = ,
    `time with time zone` = ,
    `interval day to second` = ,
    `interval year to month` = "character",
    varbinary = "raw",
    date = "Date",
    timestamp = ,
    `timestamp with time zone` = "POSIXct",
    array = ,
    map = ,
    row = "list",
    {
      warning(
        sprintf("Unknown Trino type '%s'; returning it as character.", type),
        call. = FALSE
      )
      "character"
    }
  )
}

#' Convert one column of a Trino payload to an R vector
#'
#' Works on the whole column at once: the values that are not `NULL` are
#' flattened with a single `unlist()` and converted in one call, rather than
#' one R call per cell.
#'
#' Numbers never go through text. `trino_parse_response()` hands a `BIGINT`
#' over as an R integer, an exact double or, beyond 2^53, a string of digits,
#' and a `DOUBLE` as a double or, for `NaN` and the infinities, a string;
#' flattening such a mix with `unlist()` would print the numbers with 15
#' significant digits (`3e+09`), so each kind is converted on its own.
#'
#' @param values A list with one element per row; `NULL` marks a SQL `NULL`.
#' @param type The column's Trino type.
#' @param bigint How `BIGINT` is handled; see [dbConnect()].
#' @param timezone Session time zone, used for `TIMESTAMP` columns.
#' @param target The R type to produce, as returned by [trino_type_to_r()].
#'   Computed from `type` unless the caller already knows it.
#'
#' @return A vector, or a list for the nested types.
#' @noRd
trino_cast_column <- function(values, type, bigint = "integer64",
                              timezone = "UTC",
                              target = trino_type_to_r(type, bigint)) {
  # A list column keeps NULL entries as-is: there is no NA placeholder that
  # would round-trip an absent ARRAY or ROW.
  if (target == "list") {
    return(values)
  }
  if (target == "raw") {
    return(lapply(values, function(x) {
      if (is.null(x)) NULL else jsonlite::base64_dec(x)
    }))
  }

  present <- lengths(values) > 0L
  given <- values[present]
  fill <- function(missing, x) {
    out <- rep(missing, length(values))
    out[present] <- x
    out
  }

  switch(
    target,
    integer64 = fill(bit64::NA_integer64_, trino_as_integer64(given)),
    numeric = fill(NA_real_, trino_as_double(given)),
    logical = fill(NA, as.logical(unlist(given, use.names = FALSE))),
    integer = fill(NA_integer_, as.integer(unlist(given, use.names = FALSE))),
    Date = trino_parse_distinct(
      fill(NA_character_, trino_as_text(given)),
      function(x) as.Date(x, format = "%Y-%m-%d")
    ),
    POSIXct = trino_cast_timestamp(
      fill(NA_character_, trino_as_text(given)),
      type,
      timezone
    ),
    character = if (trino_raw_type(type) == "bigint") {
      fill(NA_character_, trino_bigint_text(given))
    } else {
      fill(NA_character_, trino_as_text(given))
    },
    fill(NA_character_, trino_as_text(given))
  )
}

#' Parse each distinct value once
#'
#' Parsing dates and times goes through `strptime()`, which costs far more per
#' value than finding the distinct ones; a column of dates typically repeats a
#' few thousand values over any number of rows.
#'
#' @param x A character vector.
#' @param parse A vectorised parser.
#' @return `parse(x)`.
#' @noRd
trino_parse_distinct <- function(x, parse) {
  values <- unique(x)
  if (length(values) == length(x)) {
    return(parse(x))
  }
  parse(values)[match(x, values)]
}

#' Split a list of scalars into the numbers and the strings
#'
#' @param x A list of non-`NULL` scalars.
#' @return A logical vector, `TRUE` where the element is a string.
#' @noRd
trino_is_text <- function(x) {
  vapply(x, is.character, logical(1L), USE.NAMES = FALSE)
}

#' Convert the values of a floating-point or decimal column to doubles
#'
#' A `DOUBLE` arrives as the double its JSON text denotes, which is kept
#' bit for bit; `NaN`, `Infinity` and `-Infinity` arrive as strings, and a
#' `DECIMAL` always does.
#'
#' @param x A list of non-`NULL` scalars.
#' @return A double vector.
#' @noRd
trino_as_double <- function(x) {
  flat <- unlist(x, use.names = FALSE)
  if (!is.character(flat)) {
    return(as.double(flat))
  }
  text <- trino_is_text(x)
  out <- numeric(length(x))
  out[text] <- as.double(unlist(x[text], use.names = FALSE))
  out[!text] <- as.double(unlist(x[!text], use.names = FALSE))
  out
}

#' Convert the values of a `BIGINT` column to `integer64`
#'
#' Exact for every `BIGINT` but one: bit64 reserves the lowest 64-bit integer,
#' -9223372036854775808, as its `NA`, so that value is returned as `NA` with a
#' warning that says so.
#'
#' @param x A list of non-`NULL` scalars: integers, doubles holding an integer
#'   up to 2^53, and strings of digits beyond that.
#' @return An `integer64` vector.
#' @noRd
trino_as_integer64 <- function(x) {
  if (length(x) == 0L) {
    return(bit64::integer64())
  }
  flat <- unlist(x, use.names = FALSE)
  if (is.character(flat)) {
    text <- trino_is_text(x)
    digits <- unlist(x[text], use.names = FALSE)
    numbers <- unlist(x[!text], use.names = FALSE)
  } else {
    text <- logical(length(x))
    digits <- character()
    numbers <- flat
  }

  # jsonlite's parser overflows on the lowest BIGINT and hands it over as the
  # double -2^63, the only double below -2^53 a BIGINT column can yield: any
  # other value that far out arrives as a string of digits.
  lowest_number <- numbers < -2^53
  lowest_text <- digits == "-9223372036854775808"
  if (any(lowest_number) || any(lowest_text)) {
    warning(
      "BIGINT -9223372036854775808 has no integer64 representation (bit64 ",
      "uses it for NA) and is returned as NA. Connect with ",
      "`bigint = \"character\"` to keep it.",
      call. = FALSE
    )
    numbers[lowest_number] <- NA
    digits[lowest_text] <- NA_character_
  }

  out <- bit64::integer64(length(x))
  out[text] <- bit64::as.integer64(digits)
  out[!text] <- bit64::as.integer64(numbers)
  out
}

#' Render the values of a `BIGINT` column as their exact digits
#'
#' @inheritParams trino_as_integer64
#' @return A character vector.
#' @noRd
trino_bigint_text <- function(x) {
  # "%.0f" prints a double that holds an integer with every digit, where
  # as.character() would switch to scientific notation.
  digits <- function(v) sprintf("%.0f", as.double(v))
  flat <- unlist(x, use.names = FALSE)
  if (!is.character(flat)) {
    return(digits(flat))
  }
  text <- trino_is_text(x)
  out <- character(length(x))
  out[text] <- unlist(x[text], use.names = FALSE)
  out[!text] <- digits(unlist(x[!text], use.names = FALSE))
  out
}

#' Flatten the values of a textual column
#'
#' Every type converted from text arrives as a JSON string. A type this
#' package does not know may not, so anything that is not a single string is
#' rendered back to JSON rather than flattened into the wrong rows.
#'
#' @param x A list of non-`NULL` values.
#' @return A character vector.
#' @noRd
trino_as_text <- function(x) {
  # One level only: a nested value then leaves `flat` a list, not a string.
  flat <- unlist(x, recursive = FALSE, use.names = FALSE)
  if (is.character(flat) && length(flat) == length(x)) {
    return(flat)
  }
  vapply(
    x,
    function(v) {
      if (is.character(v) && length(v) == 1L) {
        v
      } else {
        as.character(jsonlite::toJSON(v, auto_unbox = TRUE, digits = NA))
      }
    },
    character(1L),
    USE.NAMES = FALSE
  )
}

#' Convert Trino timestamp strings to `POSIXct`
#'
#' Trino renders `TIMESTAMP` as `"2026-01-15 10:30:00.123"` and
#' `TIMESTAMP WITH TIME ZONE` as the same followed by either a zone name
#' (`"Europe/Madrid"`) or an offset (`"+02:00"`). `POSIXct` carries a single
#' `tzone`, so zoned values are resolved to their true instant, one call per
#' distinct zone, and the vector is then presented in the session time zone.
#'
#' @param x Character vector of timestamps.
#' @param type The column's Trino type.
#' @param timezone Session time zone.
#' @return A `POSIXct` vector.
#' @noRd
trino_cast_timestamp <- function(x, type, timezone) {
  format <- "%Y-%m-%d %H:%M:%OS"
  if (trino_raw_type(type) == "timestamp") {
    return(trino_parse_distinct(x, function(v) {
      as.POSIXct(v, tz = timezone, format = format)
    }))
  }
  trino_parse_distinct(x, function(v) {
    trino_cast_zoned_timestamp(v, timezone, format)
  })
}

#' Convert `TIMESTAMP WITH TIME ZONE` strings to `POSIXct`
#'
#' @param x Character vector of timestamps, each with its zone.
#' @param timezone Session time zone.
#' @param format The `strptime()` format of the date and time.
#' @return A `POSIXct` vector.
#' @noRd
trino_cast_zoned_timestamp <- function(x, timezone, format) {
  x <- trimws(x)
  # Date and time, then the zone if there is one.
  pattern <- "^(\\S+ \\S+)(?: (\\S+))?$"
  stamp <- sub(pattern, "\\1", x, perl = TRUE)
  zone <- sub(pattern, "\\2", x, perl = TRUE)
  zone[!is.na(x) & !nzchar(zone)] <- timezone

  instants <- rep(NA_real_, length(x))
  offset <- !is.na(zone) & grepl("^[+-][0-9]{2}:?[0-9]{2}$", zone)
  if (any(offset)) {
    digits <- gsub("[^0-9]", "", zone[offset])
    seconds <- as.numeric(substr(digits, 1L, 2L)) * 3600 +
      as.numeric(substr(digits, 3L, 4L)) * 60
    sign <- ifelse(startsWith(zone[offset], "-"), 1, -1)
    local <- as.POSIXct(stamp[offset], tz = "UTC", format = format)
    instants[offset] <- as.numeric(local) + sign * seconds
  }
  named <- !is.na(zone) & !offset
  for (z in unique(zone[named])) {
    at <- named & zone == z
    instants[at] <- as.numeric(as.POSIXct(stamp[at], tz = z, format = format))
  }

  as.POSIXct(instants, tz = timezone, origin = "1970-01-01")
}
