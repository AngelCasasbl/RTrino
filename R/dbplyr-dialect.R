#' SQL dialect for Trino
#'
#' Describes Trino to `dbplyr` so that `dplyr` verbs on a
#' [TrinoConnection-class] are translated to SQL Trino accepts. Registered,
#' when dbplyr 2.6.0 or later is loaded, as an S3 method for
#' `dbplyr::sql_dialect()`, the extension point that version introduced, which
#' separates the SQL dialect from the connection mechanism.
#'
#' Trino quotes identifiers with double quotes (the SQL standard), supports the
#' `WINDOW` clause, accepts `AS` before a table alias, and does not allow
#' `table.*` prefixes on a star selection.
#'
#' @param con A [TrinoConnection-class] object.
#' @return A `dbplyr` SQL dialect object.
#' @keywords internal
#' @exportS3Method NULL
sql_dialect.TrinoConnection <- function(con) {
  dbplyr::new_sql_dialect(
    "trino",
    quote_identifier = function(x) dbplyr::sql_quote(x, '"'),
    has_window_clause = TRUE,
    has_table_alias_with_as = TRUE,
    has_star_table_prefix = FALSE
  )
}

#' dbplyr edition used by Trino connections
#'
#' dbplyr refuses to work with a backend that has not declared the second
#' edition of its interface, so the declaration is explicit even though every
#' method here is written against the current API.
#'
#' @param con A [TrinoConnection-class] object.
#' @return `2L`.
#' @keywords internal
#' @exportS3Method NULL
dbplyr_edition.TrinoConnection <- function(con) 2L

#' Function translations for Trino
#'
#' Extends dbplyr's base translation so that an R expression computes in
#' Trino what it computes in R, or fails, rather than quietly computing
#' something else:
#'
#' * `/` divides as a double, where Trino would truncate the quotient of two
#'   integers; `%%` takes the sign of the divisor, as in R.
#' * `as.integer()` and `as.integer64()` truncate towards zero, where a cast
#'   would round.
#' * `paste()`, `paste0()` and `str_c()` cast every argument to `VARCHAR`,
#'   which Trino's `CONCAT_WS` requires.
#' * `grepl()`, `sub()` and `gsub()` honour `fixed` and `ignore.case`, and
#'   rewrite R's `\\1` back-references into Trino's `$1`; `sub()` replaces the
#'   first match only.
#' * `days()`, `weeks()`, `months()`, `years()`, `hours()`, `minutes()` and
#'   `seconds()` build intervals, so `date + days(1)` works where `date + 1`
#'   does not.
#' * Casts name Trino types, and `median()` and `quantile()` use
#'   `approx_percentile`, which is the percentile Trino offers over an
#'   arbitrary number of rows. Null-safe comparison uses Trino's native
#'   `IS DISTINCT FROM` rather than dbplyr's portable `CASE WHEN` spelling.
#'
#' @param con A Trino SQL dialect object.
#' @return A `dbplyr` SQL variant.
#' @keywords internal
#' @exportS3Method NULL
sql_translation.sql_dialect_trino <- function(con) {
  dbplyr::sql_variant(
    scalar = dbplyr::sql_translator(
      .parent = dbplyr::base_scalar,
      `/` = function(x, y) {
        y <- trino_operand(rlang::enexpr(y), y)
        dbplyr::sql_glue("CAST({x} AS DOUBLE) / {y}")
      },
      `%%` = function(x, y) {
        x <- trino_operand(rlang::enexpr(x), x)
        y <- trino_operand(rlang::enexpr(y), y)
        # MOD() takes the sign of the dividend, R's %% that of the divisor.
        dbplyr::sql_glue(paste0(
          "CASE WHEN MOD({x}, {y}) <> 0 AND (MOD({x}, {y}) < 0) <> ({y} < 0)",
          " THEN MOD({x}, {y}) + {y} ELSE MOD({x}, {y}) END"
        ))
      },
      as.character = dbplyr::sql_cast("VARCHAR"),
      # A cast rounds; R truncates. Through DOUBLE, which holds every INTEGER
      # exactly, and through DECIMAL for BIGINT, which a double does not.
      as.integer = function(x) {
        dbplyr::sql_glue("CAST(TRUNCATE(CAST({x} AS DOUBLE)) AS INTEGER)")
      },
      as.integer64 = function(x) {
        dbplyr::sql_glue(
          "CAST(TRUNCATE(CAST({x} AS DECIMAL(38, 18))) AS BIGINT)"
        )
      },
      as.numeric = dbplyr::sql_cast("DOUBLE"),
      as.double = dbplyr::sql_cast("DOUBLE"),
      as.logical = dbplyr::sql_cast("BOOLEAN"),
      as.Date = dbplyr::sql_cast("DATE"),
      paste = trino_paste(" "),
      paste0 = trino_paste(""),
      str_c = trino_paste(""),
      grepl = function(pattern, x, ignore.case = FALSE, perl = FALSE,
                       fixed = FALSE, useBytes = FALSE) {
        trino_check_regex_args(ignore.case, perl, fixed, useBytes)
        if (fixed) {
          return(dbplyr::sql_glue("(STRPOS({x}, {pattern}) > 0)"))
        }
        pattern <- trino_regex(pattern, ignore.case)
        dbplyr::sql_glue("REGEXP_LIKE({x}, {pattern})")
      },
      gsub = function(pattern, replacement, x, ignore.case = FALSE,
                      perl = FALSE, fixed = FALSE, useBytes = FALSE) {
        trino_check_regex_args(ignore.case, perl, fixed, useBytes)
        if (fixed) {
          return(dbplyr::sql_glue("REPLACE({x}, {pattern}, {replacement})"))
        }
        pattern <- trino_regex(pattern, ignore.case)
        replacement <- trino_regex_replacement(replacement, perl)
        dbplyr::sql_glue("REGEXP_REPLACE({x}, {pattern}, {replacement})")
      },
      sub = function(pattern, replacement, x, ignore.case = FALSE,
                     perl = FALSE, fixed = FALSE, useBytes = FALSE) {
        trino_check_regex_args(ignore.case, perl, fixed, useBytes)
        # Trino replaces every match, so the first one is located and only the
        # text from there on is rewritten, with the pattern anchored to it.
        if (fixed) {
          return(dbplyr::sql_glue(paste0(
            "CASE WHEN STRPOS({x}, {pattern}) = 0 THEN {x}",
            " ELSE CONCAT(SUBSTR({x}, 1, STRPOS({x}, {pattern}) - 1),",
            " {replacement},",
            " SUBSTR({x}, STRPOS({x}, {pattern}) + LENGTH({pattern}))) END"
          )))
        }
        pattern <- trino_regex(pattern, ignore.case)
        # Used in the sql_glue() template below, where codetools cannot see
        # it, as are `args` and `interval` further down.
        # nolint start: object_usage_linter.
        anchored <- trino_regex_wrap(pattern, "\\A(?:", ")")
        # nolint end
        replacement <- trino_regex_replacement(replacement, perl)
        dbplyr::sql_glue(paste0(
          "CASE WHEN REGEXP_POSITION({x}, {pattern}) = -1 THEN {x}",
          " ELSE CONCAT(SUBSTR({x}, 1, REGEXP_POSITION({x}, {pattern}) - 1),",
          " REGEXP_REPLACE(SUBSTR({x}, REGEXP_POSITION({x}, {pattern})),",
          " {anchored}, {replacement})) END"
        ))
      },
      days = trino_period("DAY"),
      weeks = trino_period("DAY", 7L),
      months = trino_period("MONTH"),
      years = trino_period("YEAR"),
      hours = trino_period("HOUR"),
      minutes = trino_period("MINUTE"),
      seconds = trino_period("SECOND"),
      # dplyr's filter_out() reaches the backend as is_distinct_from(cond,
      # TRUE); dbplyr's portable fallback spells that as a CASE WHEN comparing
      # both sides and their nullness, which Trino writes as one operator.
      is_distinct_from = function(x, y) {
        dbplyr::sql_glue("({x}) IS DISTINCT FROM ({y})")
      },
      is_not_distinct_from = function(x, y) {
        dbplyr::sql_glue("({x}) IS NOT DISTINCT FROM ({y})")
      },
      Sys.Date = function() dbplyr::sql("CURRENT_DATE"),
      Sys.time = function() dbplyr::sql("CURRENT_TIMESTAMP")
    ),
    aggregate = dbplyr::sql_translator(
      .parent = dbplyr::base_agg,
      sd = dbplyr::sql_aggregate("STDDEV_SAMP", "sd"),
      var = dbplyr::sql_aggregate("VAR_SAMP", "var"),
      median = function(x, na.rm = FALSE) {
        dbplyr::sql_glue("APPROX_PERCENTILE({x}, 0.5)")
      },
      quantile = function(x, probs, na.rm = FALSE) {
        dbplyr::sql_glue("APPROX_PERCENTILE({x}, {probs})")
      }
    ),
    window = dbplyr::sql_translator(
      .parent = dbplyr::base_win,
      sd = dbplyr::win_aggregate("STDDEV_SAMP"),
      var = dbplyr::win_aggregate("VAR_SAMP")
    )
  )
}

#' Parenthesise an operand that is itself an arithmetic expression
#'
#' Parentheses written in R reach the translation as a call to `(`, which
#' dbplyr renders; but an operand spliced in as an expression, as in
#' `x / !!quote(b + c)`, arrives as `"b" + "c"` with none. They are restored
#' from the R expression, as dbplyr's own infix translations do.
#'
#' @param expr The operand's R expression.
#' @param sql The operand, translated.
#' @return `sql`, in parentheses if `expr` is a binary arithmetic call.
#' @noRd
trino_operand <- function(expr, sql) {
  if (rlang::is_call(expr, c("+", "-", "*", "/", "%%", "^"), n = 2L)) {
    return(dbplyr::sql(paste0("(", sql, ")")))
  }
  sql
}

#' A literal from the R code, as opposed to a column or an expression
#'
#' dbplyr hands a translation the literals of the R call as plain R values,
#' and columns and translated expressions as classed SQL.
#'
#' @param x A translated argument.
#' @return A logical scalar.
#' @noRd
trino_is_literal <- function(x) {
  is.atomic(x) && length(x) == 1L && is.null(oldClass(x))
}

#' Translation of `paste()`, `paste0()` and `str_c()`
#'
#' Trino's `CONCAT_WS` only takes `VARCHAR`, so every argument that is not a
#' string already is cast. A literal is converted in R instead, so that
#' `paste0(x, 1)` appends `"1"` as R would, not Trino's rendering of the
#' decimal `1.0`.
#'
#' @param default_sep The separator when `sep` is not given.
#' @return A translation function.
#' @noRd
trino_paste <- function(default_sep) {
  force(default_sep)
  function(..., sep = default_sep, collapse = NULL) {
    if (!is.null(collapse)) {
      stop(
        "`collapse` is not supported when paste() is translated to SQL; ",
        "use str_flatten() in summarise() instead.",
        call. = FALSE
      )
    }
    # nolint start: object_usage_linter.
    args <- lapply(list(...), function(arg) {
      if (trino_is_literal(arg)) {
        return(as.character(arg))
      }
      dbplyr::sql_glue("CAST({arg} AS VARCHAR)")
    })
    # nolint end
    dbplyr::sql_glue("CONCAT_WS({sep}, {args})")
  }
}

#' Check the arguments of `grepl()`, `sub()` and `gsub()`
#'
#' @param ignore_case,perl,fixed,use_bytes R's `ignore.case`, `perl`, `fixed`
#'   and `useBytes`.
#' @return `NULL`, invisibly; fails on an argument the translation cannot
#'   honour.
#' @noRd
trino_check_regex_args <- function(ignore_case, perl, fixed, use_bytes) {
  flags <- list(
    ignore.case = ignore_case, perl = perl, fixed = fixed, useBytes = use_bytes
  )
  for (name in names(flags)) {
    value <- flags[[name]]
    if (!is.logical(value) || length(value) != 1L || is.na(value)) {
      stop(sprintf("`%s` must be `TRUE` or `FALSE`.", name), call. = FALSE)
    }
  }
  if (use_bytes) {
    stop("`useBytes = TRUE` is not supported by Trino.", call. = FALSE)
  }
  if (fixed && ignore_case) {
    stop(
      "`fixed = TRUE` cannot be combined with `ignore.case = TRUE`; R itself ",
      "ignores `ignore.case` in that case.",
      call. = FALSE
    )
  }
  invisible()
}

#' Make a regular expression case-insensitive when asked to
#'
#' @param pattern The translated pattern: a string literal or an expression.
#' @param ignore_case Whether to ignore case.
#' @return The pattern, prefixed with the `(?i)` flag if `ignore_case`.
#' @noRd
trino_regex <- function(pattern, ignore_case) {
  if (!ignore_case) {
    return(pattern)
  }
  trino_regex_wrap(pattern, "(?i)", "")
}

#' Wrap a pattern in text, whether it is a literal or an expression
#'
#' @param pattern The translated pattern.
#' @param before,after Text to put around it.
#' @return A string literal, or SQL that concatenates.
#' @noRd
trino_regex_wrap <- function(pattern, before, after) {
  if (trino_is_literal(pattern)) {
    return(paste0(before, pattern, after))
  }
  dbplyr::sql_glue("CONCAT({before}, {pattern}, {after})")
}

#' Rewrite an R replacement string for Trino's `regexp_replace()`
#'
#' R refers to a group as `\\1` to `\\9` and treats `$` as an ordinary
#' character; Trino refers to a group as `$1` and needs `\\$` for a dollar.
#' Any other backslash escapes the character after it in both, so it is kept.
#' A digit right after a group reference is escaped, or Trino would read
#' `\\10` (group 1, then "0" in R) as group 10.
#'
#' @param x The translated replacement.
#' @param perl The `perl` argument, under which R also knows `\\U`, `\\L` and
#'   `\\E`.
#' @return A string.
#' @noRd
trino_regex_replacement <- function(x, perl) {
  if (!trino_is_literal(x) || !is.character(x)) {
    stop(
      "`replacement` must be a string, not a column or an expression: ",
      "back-references are written differently in Trino, so only a ",
      "literal can be rewritten.",
      call. = FALSE
    )
  }
  chars <- strsplit(x, "", fixed = TRUE)[[1L]]
  out <- character()
  i <- 1L
  while (i <= length(chars)) {
    ch <- chars[[i]]
    after <- if (i < length(chars)) chars[[i + 1L]] else ""
    if (ch == "$") {
      out <- c(out, "\\$")
      i <- i + 1L
    } else if (ch != "\\") {
      out <- c(out, ch)
      i <- i + 1L
    } else if (grepl("^[1-9]$", after)) {
      out <- c(out, "$", after)
      i <- i + 2L
      if (i <= length(chars) && grepl("^[0-9]$", chars[[i]])) {
        out <- c(out, "\\", chars[[i]])
        i <- i + 1L
      }
    } else if (perl && after %in% c("U", "L", "E")) {
      stop(
        "Case conversion in `replacement` (\\U, \\L, \\E) is not supported ",
        "by Trino.",
        call. = FALSE
      )
    } else if (nzchar(after)) {
      out <- c(out, "\\", after)
      i <- i + 2L
    } else {
      # R drops a trailing backslash; Trino would reject it.
      i <- i + 1L
    }
  }
  paste(out, collapse = "")
}

#' Translation of lubridate's periods to Trino intervals
#'
#' @param unit A Trino interval unit.
#' @param per How many `unit`s make one period.
#' @return A translation function of the number of periods.
#' @noRd
trino_period <- function(unit, per = 1L) {
  force(unit)
  force(per)
  function(x = 1L) {
    if (trino_is_literal(x) && is.numeric(x) && x == trunc(x)) {
      x <- as.integer(x)
    }
    # nolint start: object_usage_linter.
    interval <- dbplyr::sql(sprintf("INTERVAL '%d' %s", per, unit))
    # nolint end
    dbplyr::sql_glue("({interval} * {x})")
  }
}

#' Literal dates and date-times in dplyr pipelines
#'
#' A `Date` or `POSIXct` from R, in a pipeline such as
#' `filter(orderdate >= !!as.Date("2026-01-01"))`, becomes a typed Trino
#' literal. dbplyr's default renders it as a plain string, which Trino refuses
#' to compare with a date.
#'
#' @param con The connection or dialect being translated for.
#' @param x A `Date` or date-time vector.
#' @return SQL.
#' @keywords internal
#' @exportS3Method NULL
sql_escape_date.sql_dialect_trino <- function(con, x) {
  out <- trino_date_literal(x)
  out[is.na(x)] <- "NULL"
  dbplyr::sql(out)
}

#' @rdname sql_escape_date.sql_dialect_trino
#' @exportS3Method NULL
sql_escape_datetime.sql_dialect_trino <- function(con, x) {
  timezone <- if (isS4(con) && methods::is(con, "TrinoConnection")) {
    con@session.timezone
  } else {
    "UTC"
  }
  out <- trino_timestamp_literal(as.POSIXct(x), timezone)
  out[is.na(x)] <- "NULL"
  dbplyr::sql(out)
}

#' Saving a query as a table
#'
#' Trino has no temporary tables, so `compute()` needs `temporary = FALSE`
#' and a name, and then runs `CREATE TABLE ... AS`. `ANALYZE` is not run
#' afterwards: not every connector supports it, and where it does it scans
#' the whole new table.
#'
#' @param con The connection or dialect.
#' @param sql The query to save.
#' @param name The table to create.
#' @param temporary Whether a temporary table was asked for.
#' @param table The table that would be analysed.
#' @param ... Unused.
#' @return SQL, or `NULL` for no `ANALYZE`.
#' @keywords internal
#' @exportS3Method NULL
sql_query_save.sql_dialect_trino <- function(con, sql, name,
                                             temporary = TRUE, ...) {
  if (temporary) {
    stop(
      "Trino has no temporary tables. Save the result to a table with ",
      "compute(name = \"...\", temporary = FALSE).",
      call. = FALSE
    )
  }
  dbplyr::sql_glue2(con, "CREATE TABLE {.tbl name} AS\n{sql}")
}

#' @rdname sql_query_save.sql_dialect_trino
#' @exportS3Method NULL
sql_table_analyze.sql_dialect_trino <- function(con, table, ...) {
  NULL
}
