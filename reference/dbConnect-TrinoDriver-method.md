# Connect to a Trino cluster

Creates a
[TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md).
Trino's REST API is stateless, so no session is opened on the server;
the connection object holds the coordinator address and the per-request
settings. To fail early on a wrong address or bad credentials,
[`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html) probes
`GET /v1/info` before returning.

## Usage

``` r
# S4 method for class 'TrinoDriver'
dbConnect(
  drv,
  host = "http://localhost",
  port = 8080L,
  user = trino_default_user(),
  catalog = NULL,
  schema = NULL,
  source = "RTrino",
  session.timezone = "UTC",
  bigint = c("integer64", "numeric", "character"),
  auth = NULL,
  ssl_options = trino_ssl(),
  extra.headers = list(),
  timeout = 60,
  query_max_run_time = NULL,
  allow_http_auth = FALSE,
  ...
)
```

## Arguments

- drv:

  A
  [TrinoDriver](https://angelcasasbl.github.io/RTrino/reference/TrinoDriver-class.md)
  object, from
  [`Trino()`](https://angelcasasbl.github.io/RTrino/reference/Trino.md).

- host:

  Coordinator URL. A missing scheme defaults to `http://`; a trailing
  slash is dropped. It may include the port
  (`"https://trino.example.com:8443"`), in which case `port` need not be
  given.

- port:

  Coordinator port, a whole number between 1 and 65535.

- user:

  Trino user name, sent as `X-Trino-User`.

- catalog:

  Trino catalog. Required.

- schema:

  Trino schema. Required.

- source:

  Value of the `X-Trino-Source` header; shows up in the coordinator's
  query history.

- session.timezone:

  Session time zone, used when reading `TIMESTAMP` columns.

- bigint:

  How to return `BIGINT` columns: `"integer64"` (the default, via
  `bit64`, exact except for the lowest value, -9223372036854775808,
  which bit64 reserves for `NA`), `"numeric"` (a double, exact only up
  to 2^53) or `"character"` (the exact digits).

- auth:

  An authentication closure from
  [`trino_auth_basic()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md),
  [`trino_auth_jwt()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  or
  [`trino_auth_oauth2()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md),
  or `NULL` for a cluster with no authentication.

- ssl_options:

  TLS options from
  [`trino_ssl()`](https://angelcasasbl.github.io/RTrino/reference/trino_ssl.md).

- extra.headers:

  Named list of extra HTTP headers added to every request, each a single
  string. Useful for Trino session properties set through
  `X-Trino-Session`.

- timeout:

  Seconds allowed for each HTTP request to the coordinator, not for the
  whole query; `Inf` for no limit. Connecting gives up after 10 seconds,
  or `timeout` if shorter.

- query_max_run_time:

  Longest a query may run on the cluster before Trino stops it, as a
  Trino duration such as `"30m"` or `"2h"`, or a number of seconds.
  `NULL`, the default, leaves the cluster's own limit. Sent as the
  `query_max_run_time` session property.

- allow_http_auth:

  Set to `TRUE` to send `auth` credentials to an `http://` host, which
  carries them unencrypted. Only for a connection that is encrypted by
  other means, such as an SSH tunnel.

- ...:

  Unused, for compatibility with the generic.

## Value

A
[TrinoConnection](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
object.

## Timeouts

A query is a series of HTTP requests, so two limits apply. `timeout`
bounds each request: a coordinator or network that stops answering fails
with an error instead of blocking the R session. `query_max_run_time`
bounds the query as a whole on the server: past it, Trino stops the
query and RTrino raises a `trino_query_error` whose `error_name` is
`"EXCEEDED_TIME_LIMIT"`. In a Shiny app, where a blocked session blocks
its user, set both.

## Examples

``` r
if (FALSE) { # nzchar(Sys.getenv("RTRINO_TEST_URL"))
# The examples in this package run against the coordinator that
# RTRINO_TEST_URL points at, such as "http://localhost:8080" for
# `docker run -p 8080:8080 trinodb/trino`. It has no authentication.
con <- DBI::dbConnect(
  RTrino::Trino(),
  host = Sys.getenv("RTRINO_TEST_URL"),
  catalog = "tpch", schema = "tiny"
)
con
DBI::dbDisconnect(con)

# LDAP over TLS, with limits for use in a Shiny app
if (FALSE) { # \dontrun{
con <- DBI::dbConnect(
  RTrino::Trino(),
  host    = "https://trino.example.com",
  port    = 443,
  user    = Sys.getenv("TRINO_USER"),
  catalog = "hive",
  schema  = "analytics",
  auth    = trino_auth_basic(Sys.getenv("TRINO_USER"),
                             Sys.getenv("TRINO_PASSWORD")),
  timeout = 30,
  query_max_run_time = "5m"
)
DBI::dbDisconnect(con)
} # }
}
```
