#' Catalogs with no real transactional storage
#'
#' `START TRANSACTION` is accepted by Trino's engine for any catalog; it is
#' the connector behind the catalog that decides whether a write inside
#' that transaction can actually be rolled back. These are the catalogs
#' Trino itself ships that never can, because they hold no real storage of
#' their own.
#'
#' @noRd
trino_nontransactional_catalogs <- c(
  "system", "memory", "tpch", "tpcds", "jmx", "blackhole"
)

#' Warn when a transaction's rollback would not mean anything
#'
#' @param conn A [TrinoConnection-class] object.
#' @return `NULL`, invisibly.
#' @noRd
trino_check_transactional_catalog <- function(conn) {
  if (tolower(conn@catalog) %in% trino_nontransactional_catalogs) {
    warning(
      "Catalog '", conn@catalog, "' has no real transactional storage; ",
      "COMMIT will succeed but ROLLBACK will not undo anything written.",
      call. = FALSE
    )
  }
  invisible(NULL)
}

#' Start, commit and roll back a transaction
#'
#' Every statement runs inside Trino's engine-level transaction mechanism:
#' `dbBegin()` sends `START TRANSACTION` and keeps the transaction id Trino
#' answers with, which is then carried on every later request until
#' [dbCommit()] or [dbRollback()] sends `COMMIT` or `ROLLBACK` and clears
#' it.
#'
#' Whether a `ROLLBACK` actually undoes a write depends on the connector
#' behind the active catalog, not on RTrino: Iceberg and Delta Lake tables
#' support it, most others (including Hive, strictly) only partially, and
#' Trino's own synthetic catalogs (`memory`, `tpch`, ...) not at all.
#' `dbBegin()` warns when the active catalog is one of the latter.
#'
#' @param conn A [TrinoConnection-class] object.
#' @param ... Unused, for compatibility with the generic.
#' @return `TRUE`, invisibly.
#' @export
#' @examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))
#' con <- DBI::dbConnect(RTrino::Trino(), host = Sys.getenv("RTRINO_TEST_URL"),
#'                       catalog = "tpch", schema = "tiny")
#'
#' # tpch holds no real storage, so dbBegin() warns that a ROLLBACK would
#' # undo nothing. On an Iceberg or Delta Lake catalog it would not.
#' DBI::dbBegin(con)
#' DBI::dbGetQuery(con, "SELECT count(*) AS n FROM nation")
#' DBI::dbCommit(con)
#'
#' DBI::dbDisconnect(con)
setMethod("dbBegin", "TrinoConnection", function(conn, ...) {
  trino_check_valid(conn)
  if (!is.null(conn@transaction$id)) {
    stop("A transaction is already in progress.", call. = FALSE)
  }
  trino_check_transactional_catalog(conn)
  dbExecute(conn, "START TRANSACTION")
  if (is.null(conn@transaction$id)) {
    stop("Trino did not start a transaction.", call. = FALSE)
  }
  invisible(TRUE)
})

#' @rdname dbBegin-TrinoConnection-method
#' @export
setMethod("dbCommit", "TrinoConnection", function(conn, ...) {
  trino_check_valid(conn)
  if (is.null(conn@transaction$id)) {
    stop("No transaction is in progress.", call. = FALSE)
  }
  dbExecute(conn, "COMMIT")
  conn@transaction$id <- NULL
  invisible(TRUE)
})

#' @rdname dbBegin-TrinoConnection-method
#' @export
setMethod("dbRollback", "TrinoConnection", function(conn, ...) {
  trino_check_valid(conn)
  if (is.null(conn@transaction$id)) {
    stop("No transaction is in progress.", call. = FALSE)
  }
  dbExecute(conn, "ROLLBACK")
  conn@transaction$id <- NULL
  invisible(TRUE)
})
