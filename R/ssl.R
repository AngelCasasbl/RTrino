#' TLS options for a Trino connection
#'
#' Collects the TLS settings applied to every request made on a connection.
#' Pass the result as the `ssl_options` argument of [dbConnect()].
#'
#' A cluster whose certificate is signed by an internal authority does not need
#' verification turned off: point `ca_bundle` at the authority's PEM file and
#' certificates keep being checked. `verify = FALSE` accepts any certificate,
#' including an attacker's, and so warns every time it is applied.
#'
#' @param verify Whether to verify the server's certificate. Defaults to `TRUE`.
#' @param ca_bundle Path to a PEM file holding the certificate authorities to
#'   trust, or `NULL` to use the system store.
#'
#' @return A list of TLS options.
#' @export
#' @examples
#' # Secure default
#' trino_ssl()
#'
#' # Trust an internal certificate authority
#' \dontrun{
#' trino_ssl(ca_bundle = "/etc/ssl/certs/internal-ca.pem")
#' }
trino_ssl <- function(verify = TRUE, ca_bundle = NULL) {
  if (!is.logical(verify) || length(verify) != 1L || is.na(verify)) {
    stop("`verify` must be `TRUE` or `FALSE`.", call. = FALSE)
  }
  if (!is.null(ca_bundle)) {
    ca_bundle <- trino_check_string(ca_bundle, "ca_bundle")
    if (!file.exists(ca_bundle)) {
      stop(sprintf("CA bundle not found: %s", ca_bundle), call. = FALSE)
    }
  }
  structure(
    list(verify = verify, ca_bundle = ca_bundle),
    class = "trino_ssl_options"
  )
}

#' Apply TLS options to a request
#'
#' @param req An `httr2` request.
#' @param ssl_opts Options as returned by [trino_ssl()].
#' @return The modified request.
#' @noRd
trino_ssl_options <- function(req, ssl_opts) {
  if (isFALSE(ssl_opts$verify)) {
    warning(
      "SSL verification disabled - not recommended for production",
      call. = FALSE
    )
    return(httr2::req_options(req, ssl_verifypeer = 0L, ssl_verifyhost = 0L))
  }
  if (!is.null(ssl_opts$ca_bundle)) {
    req <- httr2::req_options(req, cainfo = ssl_opts$ca_bundle)
  }
  req
}

#' @export
print.trino_ssl_options <- function(x, ...) {
  cat("<trino_ssl_options>\n")
  cat("  verify: ", x$verify, "\n", sep = "")
  cat("  ca_bundle: ", x$ca_bundle %||% "<system>", "\n", sep = "")
  invisible(x)
}
