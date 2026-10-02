#' Map an R type to a Trino type
#'
#' The inverse of [trino_type_to_r()]: used by [dbCreateTable()] to pick a
#' column type when the caller does not give one explicitly.
#'
#' @param dbObj A [TrinoConnection-class] object.
#' @param obj An R vector, or a data frame (one call per column).
#' @param ... Unused, for compatibility with the generic.
#' @return A string naming a Trino type.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#' DBI::dbDataType(con, 1L)
#' DBI::dbDataType(con, Sys.Date())
#' DBI::dbDataType(con, data.frame(id = 1L, label = "a"))
#' DBI::dbDisconnect(con)
setMethod("dbDataType", "TrinoConnection", function(dbObj, obj, ...) {
  trino_data_type(obj)
})

#' @noRd
trino_data_type <- function(obj) {
  if (is.data.frame(obj)) {
    return(vapply(obj, trino_data_type, character(1L)))
  }
  if (is.factor(obj)) {
    return("varchar")
  }
  if (inherits(obj, "Date")) {
    return("date")
  }
  if (inherits(obj, "POSIXt")) {
    return("timestamp(6)")
  }
  if (bit64::is.integer64(obj)) {
    return("bigint")
  }
  if (is.logical(obj)) {
    return("boolean")
  }
  if (is.integer(obj)) {
    return("integer")
  }
  if (is.double(obj)) {
    return("double")
  }
  if (is.character(obj)) {
    return("varchar")
  }
  if (is.list(obj) && all(vapply(obj, is.raw, logical(1L)))) {
    return("varbinary")
  }
  warning(
    sprintf("Unknown R type '%s'; mapping it to varchar.", class(obj)[[1L]]),
    call. = FALSE
  )
  "varchar"
}
