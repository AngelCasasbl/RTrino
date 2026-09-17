#' Fold one Trino payload into a result's state
#'
#' Every response from `/v1/statement` looks the same whether it came from the
#' initial `POST` or from following a `nextUri`: an optional `columns`
#' description, an optional `data` page, a `stats$state`, and a `nextUri` that
#' is absent once the query reaches a terminal state. This function applies one
#' such payload to the cursor state and raises the terminal failures.
#'
#' Trino's states map as follows: `QUEUED` and `PLANNING` carry no rows and are
#' simply followed; `RUNNING` may carry a partial page; `FINISHED` ends the
#' query; `FAILED` and `CANCELED` raise an error.
#'
#' @param state The result's state environment.
#' @param payload A parsed Trino response.
#' @return The number of rows added by this payload.
#' @noRd
trino_absorb_payload <- function(state, payload) {
  if (!is.null(payload$id)) {
    state$query_id <- payload$id
  }
  if (!is.null(payload$columns) && is.null(state$columns)) {
    state$columns <- payload$columns
  }

  status <- payload$stats$state %||% NA_character_

  if (identical(status, "FAILED") || !is.null(payload$error)) {
    state$next_uri <- NULL
    state$completed <- TRUE
    err <- payload$error %||% list()
    stop(
      sprintf(
        "Trino error [%s]: %s",
        err$errorName %||% err$errorCode %||% "UNKNOWN",
        err$message %||% "query failed"
      ),
      call. = FALSE
    )
  }
  if (identical(status, "CANCELED")) {
    state$next_uri <- NULL
    state$completed <- TRUE
    stop("Query was canceled", call. = FALSE)
  }

  added <- 0L
  if (length(payload$data) > 0L) {
    state$data <- c(state$data, payload$data)
    added <- length(payload$data)
  }

  state$next_uri <- payload$nextUri
  # A query is only over when the server stops handing out a nextUri: a
  # FINISHED state can still be followed by pages of buffered rows.
  if (is.null(payload$nextUri)) {
    state$completed <- TRUE
  }

  added
}

#' Fetch the next page of a result
#'
#' @param res A [TrinoResult-class] object.
#' @param attempt Zero-based poll counter, used to back off while the query is
#'   still queued or planning.
#' @return The number of rows added; `0` when the query advanced without
#'   producing rows.
#' @noRd
trino_advance <- function(res, attempt = 0L) {
  state <- res@state
  if (is.null(state$next_uri)) {
    state$completed <- TRUE
    return(0L)
  }

  # Polling a queued query in a tight loop only loads the coordinator; Trino's
  # client protocol asks for a short pause between empty pages.
  if (attempt > 0L) {
    Sys.sleep(min(0.05 * attempt, 0.5))
  }

  resp <- trino_perform(res@connection, state$next_uri, "GET")
  trino_absorb_payload(state, trino_parse_response(resp))
}

#' Drain a result until it has enough rows
#'
#' @param res A [TrinoResult-class] object.
#' @param n Number of rows wanted, or `-1` for all of them.
#' @return `res`, invisibly.
#' @noRd
trino_drain <- function(res, n) {
  state <- res@state
  attempt <- 0L
  while (!isTRUE(state$completed) && (n < 0L || length(state$data) < n)) {
    added <- trino_advance(res, attempt)
    attempt <- if (added > 0L) 0L else attempt + 1L
  }
  invisible(res)
}
