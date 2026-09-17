#' Metadata about a Trino connection
#'
#' Reports the connection's settings plus the coordinator's version, read from
#' `/v1/info`. If that endpoint cannot be reached, `db.version` is `NA` rather
#' than an error, so the rest of the metadata stays available.
#'
#' @param dbObj A [TrinoConnection-class] object.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A list with `db.version`, `host`, `port`, `user`, `catalog` and
#'   `schema`.
#' @export
#' @examples
#' \dontrun{
#' DBI::dbGetInfo(con)
#' }
setMethod("dbGetInfo", "TrinoConnection", function(dbObj, ...) {
  trino_check_valid(dbObj)
  version <- tryCatch(
    {
      info <- trino_parse_response(
        trino_perform(dbObj, trino_url(dbObj, "/v1/info"), "GET")
      )
      info$nodeVersion$version %||% NA_character_
    },
    error = function(e) NA_character_
  )

  list(
    db.version = version,
    host = dbObj@host,
    port = dbObj@port,
    user = dbObj@user,
    catalog = dbObj@catalog,
    schema = dbObj@schema
  )
})
