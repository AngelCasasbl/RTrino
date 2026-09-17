#' Fetch rows from a Trino result
#'
#' Pulls rows from the cursor, following Trino's `nextUri` chain as needed, and
#' converts each column to its R type according to the column's declared Trino
#' type and the connection's `bigint` setting.
#'
#' @param res A [TrinoResult-class] object.
#' @param n Number of rows to fetch. `-1` (the default) fetches every remaining
#'   row, paginating until the query finishes. A positive `n` returns at most
#'   that many rows, pulling as many pages as needed and keeping the remainder
#'   buffered on the cursor for the next call.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A [tibble][tibble::tibble]. Once the result is exhausted, a zero-row
#'   tibble with the right columns and types.
#' @export
#' @examples
#' \dontrun{
#' res <- DBI::dbSendQuery(con, "SELECT * FROM sales")
#' while (!DBI::dbHasCompleted(res)) {
#'   chunk <- DBI::dbFetch(res, n = 1000)
#'   # process chunk
#' }
#' DBI::dbClearResult(res)
#' }
setMethod("dbFetch", "TrinoResult", function(res, n = -1, ...) {
  if (!dbIsValid(res)) {
    stop("Invalid TrinoResult: the result has been cleared.", call. = FALSE)
  }
  trino_check_valid(res@connection)

  n <- if (identical(n, Inf)) -1L else as.integer(n)
  if (length(n) != 1L || is.na(n) || (n < 0L && n != -1L)) {
    stop("`n` must be a non-negative whole number or -1.", call. = FALSE)
  }

  state <- res@state
  exhausted <- isTRUE(state$completed) && length(state$data) == 0L
  if (exhausted && state$rows_fetched > 0L) {
    warning("Result set already exhausted.", call. = FALSE)
  }

  trino_drain(res, n)

  take <- if (n < 0L) length(state$data) else min(n, length(state$data))
  rows <- state$data[seq_len(take)]
  state$data <- if (take < length(state$data)) {
    state$data[-seq_len(take)]
  } else {
    list()
  }
  state$rows_fetched <- state$rows_fetched + length(rows)

  trino_rows_to_tibble(rows, state$columns, res@connection)
})

#' Turn Trino's row-major payload into a tibble
#'
#' Trino sends each row as a JSON array, so the rows are transposed into
#' columns before the declared type of each column is applied.
#'
#' @param rows A list of rows, each a list of values.
#' @param columns Trino's column metadata, or `NULL` for a statement that
#'   returned no description.
#' @param conn The [TrinoConnection-class] the rows came from.
#' @return A tibble.
#' @noRd
trino_rows_to_tibble <- function(rows, columns, conn) {
  if (is.null(columns) || length(columns) == 0L) {
    return(tibble::tibble())
  }

  col_names <- vapply(columns, function(x) x$name, character(1L))
  col_types <- vapply(columns, function(x) x$type, character(1L))

  cols <- lapply(seq_along(columns), function(j) {
    values <- lapply(rows, function(row) row[[j]])
    trino_cast_column(
      values,
      col_types[[j]],
      bigint = conn@bigint,
      timezone = conn@session.timezone
    )
  })

  names(cols) <- trino_unique_names(col_names)
  tibble::as_tibble(cols)
}

#' Make column names unique without renaming the unique ones
#'
#' Trino will happily return `SELECT a, a` with two identically named columns;
#' a tibble will not.
#'
#' @param x Character vector of column names.
#' @return A character vector of the same length.
#' @noRd
trino_unique_names <- function(x) {
  if (!anyDuplicated(x)) {
    return(x)
  }
  make.unique(x, sep = "_")
}
