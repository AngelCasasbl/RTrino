#' SQL dialect for Trino
#'
#' Describes Trino to `dbplyr` so that `dplyr` verbs on a
#' [TrinoConnection-class] are translated to SQL Trino accepts. Registered as
#' an S3 method for `dbplyr::sql_dialect()`, the extension point introduced in
#' dbplyr 2.6.0, which separates the SQL dialect from the connection
#' mechanism.
#'
#' Trino quotes identifiers with double quotes (the SQL standard), supports the
#' `WINDOW` clause, accepts `AS` before a table alias, and does not allow
#' `table.*` prefixes on a star selection.
#'
#' @param con A [TrinoConnection-class] object.
#' @return A `dbplyr` SQL dialect object.
#' @keywords internal
#' @export
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
#' @export
dbplyr_edition.TrinoConnection <- function(con) 2L

#' Function translations for Trino
#'
#' Extends dbplyr's base translation with the Trino spellings of the
#' operations whose ANSI defaults Trino does not accept: casts name Trino
#' types, regular expressions use `regexp_like`/`regexp_replace`, and quantiles
#' use `approx_percentile`, which is the percentile Trino offers over an
#' arbitrary number of rows.
#'
#' @param con A Trino SQL dialect object.
#' @return A `dbplyr` SQL variant.
#' @keywords internal
#' @export
sql_translation.sql_dialect_trino <- function(con) {
  dbplyr::sql_variant(
    scalar = dbplyr::sql_translator(
      .parent = dbplyr::base_scalar,
      as.character = dbplyr::sql_cast("VARCHAR"),
      as.integer = dbplyr::sql_cast("INTEGER"),
      as.integer64 = dbplyr::sql_cast("BIGINT"),
      as.numeric = dbplyr::sql_cast("DOUBLE"),
      as.double = dbplyr::sql_cast("DOUBLE"),
      as.logical = dbplyr::sql_cast("BOOLEAN"),
      as.Date = dbplyr::sql_cast("DATE"),
      # paste()/paste0() are left to dbplyr's base translation, which already
      # emits CONCAT_WS with the separator and the identifiers quoted.
      grepl = function(pattern, x, ...) {
        dbplyr::sql_glue("REGEXP_LIKE({x}, {pattern})")
      },
      gsub = function(pattern, replacement, x, ...) {
        dbplyr::sql_glue("REGEXP_REPLACE({x}, {pattern}, {replacement})")
      },
      sub = function(pattern, replacement, x, ...) {
        dbplyr::sql_glue("REGEXP_REPLACE({x}, {pattern}, {replacement}, 1)")
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
