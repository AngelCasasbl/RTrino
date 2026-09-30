#' Trino result class
#'
#' An S4 class representing the result of a statement submitted to Trino.
#'
#' Trino returns results page by page; each payload carries a `nextUri` to
#' follow until the query reaches a terminal state. Because that progress is
#' mutated as rows are fetched, and S4 slots are copy-on-modify, the mutable
#' part of the result lives in the `state` environment rather than in slots.
#' This makes `res` behave like a cursor, as DBI expects.
#'
#' @slot connection The [TrinoConnection-class] the statement was sent on.
#' @slot statement The SQL statement, as a string.
#' @slot state Environment holding the mutable cursor state: `next_uri`,
#'   `columns`, `data`, `completed`, `rows_fetched`, `query_id`, and the
#'   `update_type` and `update_count` of a statement that changes something.
#'
#' @keywords internal
#' @export
setClass(
  "TrinoResult",
  contains = "DBIResult",
  slots = c(
    connection = "TrinoConnection",
    statement = "character",
    state = "environment"
  )
)

#' Create the mutable state environment of a result
#'
#' @param next_uri URI to follow for the next page, or `NULL`.
#' @param query_id Trino query id, or `NA_character_`.
#' @return An environment.
#' @noRd
trino_result_state <- function(next_uri = NULL, query_id = NA_character_) {
  state <- new.env(parent = emptyenv())
  state$next_uri <- next_uri
  state$query_id <- query_id
  state$columns <- NULL
  state$targets <- NULL
  state$data <- list()
  state$completed <- FALSE
  state$cleared <- FALSE
  state$rows_fetched <- 0L
  state$update_type <- NULL
  state$update_count <- NULL
  state
}

#' @rdname TrinoResult-class
#' @param object A [TrinoResult-class] object.
#' @export
setMethod("show", "TrinoResult", function(object) {
  cat("<TrinoResult>\n")
  cat("  ", trino_truncate(object@statement, 60), "\n", sep = "")
  cat(
    "  rows fetched: ", object@state$rows_fetched,
    "  completed: ", object@state$completed, "\n",
    sep = ""
  )
  invisible(NULL)
})

#' @rdname TrinoResult-class
#' @param res A [TrinoResult-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @export
setMethod("dbGetStatement", "TrinoResult", function(res, ...) {
  res@statement
})

#' @rdname TrinoResult-class
#' @export
setMethod("dbGetRowCount", "TrinoResult", function(res, ...) {
  res@state$rows_fetched
})

#' @rdname TrinoResult-class
#' @export
setMethod("dbGetRowsAffected", "TrinoResult", function(res, ...) {
  state <- res@state
  if (!is.null(state$update_count)) {
    # A BIGINT: an integer, a double or, past 2^53, a string of digits.
    return(as.numeric(state$update_count))
  }
  if (is.null(state$update_type)) {
    # A query changes no rows.
    return(0)
  }
  # DDL and session statements change no rows either; a data change whose
  # count Trino has not reported (yet) is the one case that is unknown.
  dml <- c("INSERT", "DELETE", "UPDATE", "MERGE")
  if (toupper(state$update_type) %in% dml) NA_real_ else 0
})

#' @rdname TrinoResult-class
#' @export
setMethod("dbColumnInfo", "TrinoResult", function(res, ...) {
  if (!dbIsValid(res)) {
    stop("Invalid TrinoResult: the result has been cleared.", call. = FALSE)
  }
  # The columns arrive a few pages into the query, so follow it that far.
  if (dbIsValid(res@connection)) {
    trino_drain(res, 0L)
  }
  columns <- res@state$columns
  if (is.null(columns)) {
    return(tibble::tibble(name = character(), type = character()))
  }
  tibble::tibble(
    name = vapply(columns, function(x) x$name, character(1)),
    type = vapply(columns, function(x) x$type, character(1))
  )
})
