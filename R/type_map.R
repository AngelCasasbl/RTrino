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
#' @param type A Trino type name, with or without parameters.
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
  bigint <- match.arg(bigint)
  switch(
    trino_raw_type(type),
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
    `time with time zone` = "character",
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
#' @param values A list with one element per row; `NULL` marks a SQL `NULL`.
#' @param type The column's Trino type.
#' @param bigint How `BIGINT` is handled; see [dbConnect()].
#' @param timezone Session time zone, used for `TIMESTAMP` columns.
#'
#' @return A vector, or a list for the nested types.
#' @noRd
trino_cast_column <- function(values, type, bigint = "integer64",
                              timezone = "UTC") {
  target <- trino_type_to_r(type, bigint)

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

  chr <- vapply(
    values,
    function(x) if (is.null(x)) NA_character_ else as.character(x)[[1L]],
    character(1L)
  )

  switch(
    target,
    logical = as.logical(chr),
    integer = as.integer(chr),
    numeric = as.numeric(chr),
    integer64 = bit64::as.integer64(chr),
    character = chr,
    Date = as.Date(chr),
    POSIXct = trino_cast_timestamp(chr, type, timezone),
    chr
  )
}

#' Convert Trino timestamp strings to `POSIXct`
#'
#' Trino renders `TIMESTAMP` as `"2026-01-15 10:30:00.123"` and
#' `TIMESTAMP WITH TIME ZONE` as the same followed by either a zone name
#' (`"Europe/Madrid"`) or an offset (`"+02:00"`). `POSIXct` carries a single
#' `tzone`, so zoned values are resolved to their true instant individually and
#' the vector is then presented in the session time zone.
#'
#' @param x Character vector of timestamps.
#' @param type The column's Trino type.
#' @param timezone Session time zone.
#' @return A `POSIXct` vector.
#' @noRd
trino_cast_timestamp <- function(x, type, timezone) {
  if (trino_raw_type(type) == "timestamp") {
    return(as.POSIXct(x, tz = timezone, format = "%Y-%m-%d %H:%M:%OS"))
  }

  zone <- sub("^.*[[:space:]]", "", trimws(x))
  has_zone <- grepl("[[:space:]]", trimws(x)) & grepl("[A-Za-z/+-]", zone)
  stamp <- ifelse(has_zone, trimws(substr(x, 1L, nchar(x) - nchar(zone))), x)

  instants <- vapply(
    seq_along(x),
    function(i) {
      if (is.na(x[[i]])) {
        return(NA_real_)
      }
      z <- if (has_zone[[i]]) zone[[i]] else timezone
      offset <- regmatches(z, regexpr("^[+-][0-9]{2}:?[0-9]{2}$", z))
      if (length(offset) == 1L) {
        parsed <- as.POSIXct(
          stamp[[i]],
          tz = "UTC", format = "%Y-%m-%d %H:%M:%OS"
        )
        sign <- if (substr(offset, 1L, 1L) == "-") 1 else -1
        digits <- gsub("[^0-9]", "", offset)
        seconds <- as.numeric(substr(digits, 1L, 2L)) * 3600 +
          as.numeric(substr(digits, 3L, 4L)) * 60
        return(as.numeric(parsed) + sign * seconds)
      }
      as.numeric(as.POSIXct(
        stamp[[i]],
        tz = z, format = "%Y-%m-%d %H:%M:%OS"
      ))
    },
    numeric(1L)
  )

  as.POSIXct(instants, tz = timezone, origin = "1970-01-01")
}
