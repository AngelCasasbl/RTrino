#' Trino driver class
#'
#' An S4 class representing the Trino driver. It carries no state and exists
#' only as the entry point for [DBI::dbConnect()].
#'
#' @keywords internal
#' @export
setClass("TrinoDriver", contains = "DBIDriver")

#' Instantiate the Trino driver
#'
#' Creates the driver object passed as the first argument to
#' [DBI::dbConnect()]. The call has no side effects and always succeeds.
#'
#' @return A [TrinoDriver-class] object.
#' @export
#' @examples
#' drv <- Trino()
#' drv
Trino <- function() {
  new("TrinoDriver")
}

#' @rdname TrinoDriver-class
#' @param object A [TrinoDriver-class] object.
#' @export
setMethod("show", "TrinoDriver", function(object) {
  cat("<TrinoDriver>\n")
  invisible(NULL)
})

#' @rdname TrinoDriver-class
#' @param dbObj A [TrinoDriver-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @export
setMethod("dbIsValid", "TrinoDriver", function(dbObj, ...) TRUE)

#' @rdname TrinoDriver-class
#' @export
setMethod("dbGetInfo", "TrinoDriver", function(dbObj, ...) {
  list(
    driver.version = as.character(utils::packageVersion("Rtrino")),
    client.version = as.character(utils::packageVersion("Rtrino"))
  )
})

#' @rdname TrinoDriver-class
#' @param drv A [TrinoDriver-class] object.
#' @export
setMethod("dbUnloadDriver", "TrinoDriver", function(drv, ...) invisible(TRUE))
