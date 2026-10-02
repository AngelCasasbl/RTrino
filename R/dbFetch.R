#' Fetch rows from a Trino result
#'
#' Pulls rows from the cursor, following Trino's `nextUri` chain as needed, and
#' converts each column to its R type according to the column's declared Trino
#' type and the connection's `bigint` setting.
#'
#' @param res A [TrinoResult-class] object.
#' @param n Number of rows to fetch. `-1` or `Inf` (the default is `-1`)
#'   fetches every remaining row, paginating until the query finishes. A
#'   positive `n` returns at most that many rows, pulling as many pages as
#'   needed and keeping the remainder buffered on the cursor for the next call.
#'   `0` returns no rows but the result's columns, with their types.
#' @param ... Unused, for compatibility with the generic.
#'
#' @return A [tibble][tibble::tibble]. Once the result is exhausted, a zero-row
#'   tibble with the right columns and types.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#' res <- DBI::dbSendQuery(con, "SELECT * FROM orders")
#' while (!DBI::dbHasCompleted(res)) {
#'   chunk <- DBI::dbFetch(res, n = 4000)
#'   # process chunk; here, just count its rows
#'   cat(nrow(chunk), "rows\n")
#' }
#' DBI::dbClearResult(res)
#' DBI::dbDisconnect(con)
setMethod("dbFetch", "TrinoResult", function(res, n = -1, ...) {
  if (!dbIsValid(res)) {
    stop("Invalid TrinoResult: the result has been cleared.", call. = FALSE)
  }
  trino_check_valid(res@connection)
  n <- trino_check_fetch_n(n)

  state <- res@state
  exhausted <- isTRUE(state$completed) && length(state$data) == 0L
  if (exhausted && state$rows_fetched > 0L) {
    warning("Result set already exhausted.", call. = FALSE)
  }

  trino_drain(res, n)

  take <- if (n < 0L) length(state$data) else min(n, length(state$data))
  rows <- state$data[seq_len(take)]
  # Not `data[-seq_len(take)]` unconditionally: with `take` zero that is
  # `data[integer(0)]`, which would drop every buffered row.
  if (take > 0L) {
    state$data <- state$data[-seq_len(take)]
  }
  state$rows_fetched <- state$rows_fetched + length(rows)

  trino_rows_to_tibble(
    rows,
    state$columns,
    res@connection,
    targets = trino_result_targets(res)
  )
})

#' Validate the `n` argument of `dbFetch()`
#'
#' @param n Value to check.
#' @return `n` as an integer, `-1L` meaning every remaining row.
#' @noRd
trino_check_fetch_n <- function(n) {
  bad <- function() {
    stop("`n` must be a non-negative whole number or -1.", call. = FALSE)
  }
  if (!is.numeric(n) || length(n) != 1L || is.na(n)) {
    bad()
  }
  if (n == -1 || identical(n, Inf) || n >= .Machine$integer.max) {
    return(-1L)
  }
  if (n < 0 || n != trunc(n)) {
    bad()
  }
  as.integer(n)
}

#' The R type of each column of a result
#'
#' Resolved once per result and kept on the cursor, so a column of a type this
#' package does not know warns once rather than once per fetched chunk.
#'
#' @param res A [TrinoResult-class] object.
#' @return A character vector, or `NULL` while the columns are unknown.
#' @noRd
trino_result_targets <- function(res) {
  state <- res@state
  if (is.null(state$targets) && !is.null(state$columns)) {
    state$targets <- vapply(
      state$columns,
      function(x) trino_type_to_r(x$type, res@connection@bigint),
      character(1L)
    )
  }
  state$targets
}

#' Turn Trino's row-major payload into a tibble
#'
#' Trino sends each row as a JSON array. `rbind()` lays the rows out as a
#' matrix of cells in a single call, keeping the `NULL`s, so each column is
#' then one subset handed whole to `trino_cast_column()`.
#'
#' @param rows A list of rows, each a list of values.
#' @param columns Trino's column metadata, or `NULL` for a statement that
#'   returned no description.
#' @param conn The [TrinoConnection-class] the rows came from.
#' @param targets The R type of each column, if already resolved.
#' @return A tibble.
#' @noRd
trino_rows_to_tibble <- function(rows, columns, conn, targets = NULL) {
  if (is.null(columns) || length(columns) == 0L) {
    return(tibble::tibble())
  }

  col_names <- vapply(columns, function(x) x$name, character(1L))
  col_types <- vapply(columns, function(x) x$type, character(1L))
  if (is.null(targets)) {
    targets <- vapply(col_types, trino_type_to_r, character(1L),
                      bigint = conn@bigint, USE.NAMES = FALSE)
  }

  cells <- if (length(rows) > 0L) do.call(rbind, rows) else NULL
  cols <- lapply(seq_along(columns), function(j) {
    trino_cast_column(
      if (is.null(cells)) list() else cells[, j],
      col_types[[j]],
      bigint = conn@bigint,
      timezone = conn@session.timezone,
      target = targets[[j]]
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
