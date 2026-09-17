# RTrino

<!-- badges: start -->
<!-- badges: end -->

A [DBI](https://dbi.r-dbi.org) backend for [Trino](https://trino.io), the
distributed SQL query engine (the successor of PrestoSQL).

`RTrino` talks to a Trino coordinator over its HTTP REST API, so there is no
client library to install and nothing to compile. Its architecture follows
[RPresto](https://github.com/prestodb/RPresto), rebuilt on
[httr2](https://httr2.r-lib.org) and on the `sql_dialect()` extension point
introduced in dbplyr 2.6.0.

## Installation

```r
# install.packages("pak")
pak::pak("AngelCasasbl/RTrino")
```

## Usage

```r
library(DBI)
library(RTrino)

con <- dbConnect(
  Trino(),
  host    = "https://trino.example.com",
  port    = 443,
  user    = Sys.getenv("TRINO_USER"),
  catalog = "hive",
  schema  = "analytics",
  auth    = trino_auth_basic(Sys.getenv("TRINO_USER"), Sys.getenv("TRINO_PASSWORD"))
)

dbGetQuery(con, "SELECT region, sum(amount) AS total FROM sales GROUP BY region")

library(dplyr)
tbl(con, "sales") |>
  filter(year == 2026) |>
  group_by(region) |>
  summarise(total = sum(amount, na.rm = TRUE)) |>
  collect()

dbDisconnect(con)
```

See `vignette("getting-started", package = "RTrino")` for authentication,
certificate authorities, chunked fetching and the `dplyr` translations.

## What it does

* Connects over HTTP or HTTPS and probes `/v1/info`, so a bad address or a
  rejected credential fails at `dbConnect()` rather than at your first query.
* Follows Trino's `nextUri` pagination, and handles every state the protocol
  can report (`QUEUED`, `PLANNING`, `RUNNING`, `FINISHED`, `FAILED`,
  `CANCELED`).
* Maps Trino types to R types, with `BIGINT` returned as exact
  `bit64::integer64` by default.
* Cancels a query on the server when its result is cleared while still running.
* Authenticates with basic credentials, a bearer JWT or OAuth2 client
  credentials — each held in a closure, never in a global variable.
* Trusts an internal certificate authority without turning verification off.
* Translates `dplyr` pipelines to Trino SQL when dbplyr (>= 2.6.0) is
  installed.

## Authentication

| Method | Helper | Typical use |
|---|---|---|
| Basic | `trino_auth_basic(user, password)` | LDAP, password file |
| Bearer JWT | `trino_auth_jwt(token)` | service accounts, pipelines |
| OAuth2 client credentials | `trino_auth_oauth2(client_id, client_secret, token_url)` | corporate SSO; the token is renewed automatically |

## Development

R 4.1.0 or newer. The test suite runs offline against a fake Trino coordinator
built with [webfakes](https://webfakes.r-lib.org), so no cluster is needed:

```r
devtools::test()
devtools::check()
```

## License

BSD 3-Clause. See [LICENSE.md](LICENSE.md).
