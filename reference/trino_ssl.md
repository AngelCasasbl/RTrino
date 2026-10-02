# TLS options for a Trino connection

Collects the TLS settings applied to every request made on a connection.
Pass the result as the `ssl_options` argument of
[`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Usage

``` r
trino_ssl(verify = TRUE, ca_bundle = NULL)
```

## Arguments

- verify:

  Whether to verify the server's certificate. Defaults to `TRUE`.

- ca_bundle:

  Path to a PEM file holding the certificate authorities to trust, or
  `NULL` to use the system store.

## Value

A list of TLS options.

## Details

A cluster whose certificate is signed by an internal authority does not
need verification turned off: point `ca_bundle` at the authority's PEM
file and certificates keep being checked. `verify = FALSE` accepts any
certificate, including an attacker's, and so
[`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html) warns
once when it opens a connection with it.

## Examples

``` r
# Secure default
trino_ssl()
#> <trino_ssl_options>
#>   verify: TRUE
#>   ca_bundle: <system>

# Trust an internal certificate authority
if (FALSE) { # \dontrun{
trino_ssl(ca_bundle = "/etc/ssl/certs/internal-ca.pem")
} # }
```
