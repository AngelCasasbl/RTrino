#' Internal state computed once, when the package loads
#'
#' @noRd
the <- new.env(parent = emptyenv())

#' The dbplyr methods, as `c(generic, class)`
#'
#' dbplyr is a soft dependency: `RTrino` is a complete DBI backend without it.
#' The methods implement the `sql_dialect()` extension point of dbplyr 2.6.0,
#' so they are registered only with that version or a later one, when dbplyr
#' is loaded. A `NAMESPACE` directive cannot be made conditional that way: one
#' naming `sql_dialect()` makes an older dbplyr, which lacks that generic,
#' fail to load at all.
#'
#' @noRd
trino_dbplyr_methods <- list(
  c("dbplyr_edition", "TrinoConnection"),
  c("sql_dialect", "TrinoConnection"),
  c("db_copy_to", "TrinoConnection"),
  c("sql_translation", "sql_dialect_trino"),
  c("sql_query_explain", "sql_dialect_trino"),
  c("sql_escape_date", "sql_dialect_trino"),
  c("sql_escape_datetime", "sql_dialect_trino"),
  c("sql_query_save", "sql_dialect_trino"),
  c("sql_table_analyze", "sql_dialect_trino")
)

#' @noRd
.onLoad <- function(libname, pkgname) {
  # R hands `.onLoad()` the package's real name, so the User-Agent and the
  # version reported by `dbGetInfo()` cannot drift from it the way a hardcoded
  # string can.
  version <- tryCatch(
    as.character(utils::packageVersion(pkgname)),
    error = function(e) "unknown"
  )
  the$package <- pkgname
  the$version <- version
  the$user_agent <- paste0(pkgname, "/", version)

  for (method in trino_dbplyr_methods) {
    s3_register(
      paste0("dbplyr::", method[[1L]]),
      method[[2L]],
      min_version = "2.6.0"
    )
  }
  invisible()
}

#' Register an S3 method for a generic in a suggested package
#'
#' The compatibility helper rlang ships for exactly this case: register the
#' method now if the other package is already loaded, and otherwise when it
#' is. Vendored here because `rlang::s3_register()` is not part of rlang's
#' exported interface. A method is skipped, rather than failing the other
#' package's load, when that package is older than `min_version` or lacks the
#' generic.
#'
#' @param generic `"pkg::generic"`, as a string.
#' @param class The class to register the method for.
#' @param method The method, or `NULL` to look up `generic.class` in this
#'   package's namespace.
#' @param min_version The oldest version of the other package to register
#'   the method with, or `NULL` for any.
#' @return Nothing, called for its side effect.
#' @noRd
s3_register <- function(generic, class, method = NULL, min_version = NULL) {
  stopifnot(is.character(generic), length(generic) == 1L)
  stopifnot(is.character(class), length(class) == 1L)

  pieces <- strsplit(generic, "::", fixed = TRUE)[[1L]]
  stopifnot(length(pieces) == 2L)
  package <- pieces[[1L]]
  generic <- pieces[[2L]]

  caller <- parent.frame()

  get_method_env <- function() {
    top <- topenv(caller)
    if (isNamespace(top)) {
      asNamespace(environmentName(top))
    } else {
      caller
    }
  }
  get_method <- function(method) {
    if (is.null(method)) {
      get(paste0(generic, ".", class), envir = get_method_env())
    } else {
      method
    }
  }

  register <- function(...) {
    envir <- asNamespace(package)
    if (!is.null(min_version) &&
          utils::packageVersion(package) < min_version) {
      return(invisible())
    }
    if (!exists(generic, envir = envir, inherits = FALSE)) {
      return(invisible())
    }
    registerS3method(generic, class, get_method(method), envir = envir)
  }

  setHook(packageEvent(package, "onLoad"), function(...) register())

  if (isNamespaceLoaded(package)) {
    register()
  }

  invisible()
}
