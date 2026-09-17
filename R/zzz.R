#' Register the dbplyr methods when dbplyr is available
#'
#' dbplyr is a soft dependency: `Rtrino` is a complete DBI backend without it.
#' Registering the methods lazily means the package loads on a machine with no
#' dbplyr installed and picks the methods up as soon as dbplyr is loaded.
#'
#' @noRd
.onLoad <- function(libname, pkgname) {
  s3_register("dbplyr::dbplyr_edition", "TrinoConnection")
  s3_register("dbplyr::sql_dialect", "TrinoConnection")
  s3_register("dbplyr::sql_translation", "sql_dialect_trino")
  s3_register("dbplyr::sql_query_explain", "sql_dialect_trino")
  invisible()
}

#' Register an S3 method for a generic in a suggested package
#'
#' The standard compatibility helper shipped by rlang for exactly this case:
#' register the method now if the other package is already loaded, and
#' otherwise hook its load. Vendored here because `rlang::s3_register()` is not
#' part of rlang's exported interface.
#'
#' @param generic `"pkg::generic"`, as a string.
#' @param class The class to register the method for.
#' @param method The method, or `NULL` to look up `generic.class` in this
#'   package's namespace.
#' @return Nothing, called for its side effect.
#' @noRd
s3_register <- function(generic, class, method = NULL) {
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
    method_fn <- get_method(method)
    registerS3method(generic, class, method_fn, envir = envir)
  }

  setHook(packageEvent(package, "onLoad"), function(...) register())

  if (isNamespaceLoaded(package)) {
    register()
  }

  invisible()
}
