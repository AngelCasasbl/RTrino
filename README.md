# RTrino

<!-- badges: start -->
<!-- badges: end -->

A [DBI](https://dbi.r-dbi.org) backend for [Trino](https://trino.io), the
distributed SQL query engine (the successor of PrestoSQL).

`RTrino` talks to a Trino coordinator over its HTTP REST API, so there is no
client library to install and nothing to compile. It is built on
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
* Maps Trino types to R types without losing precision: `BIGINT` comes back
  as exact `bit64::integer64` by default, `DOUBLE` bit for bit, and
  timestamps to the microsecond.
* Reports the rows a statement changed from `dbExecute()`, and accepts table
  names as strings, `DBI::Id()` or quoted identifiers.
* Cancels a query on the server when its result is cleared while still running.
* Bounds each HTTP request with a `timeout`, and a query's run time on the
  cluster with `query_max_run_time`.
* Authenticates with basic credentials, a bearer JWT or OAuth2 client
  credentials — each held in a closure, never in a global variable — and
  refuses to send them over plain HTTP.
* Trusts an internal certificate authority without turning verification off.
* Translates `dplyr` pipelines to Trino SQL when dbplyr (>= 2.6.0) is
  installed, so that an expression computes in Trino what it computes in R.

## What it does not do

* Parameter binding: put values into a statement with `DBI::sqlInterpolate()`,
  which quotes them as typed Trino literals. Passing `params` is an error.
* Uploading data frames: `dbWriteTable()`, `dbAppendTable()`,
  `dbCreateTable()` and `copy_to()` fail with a message that says so. Create
  and fill tables with SQL through `dbExecute()`.
* Transactions: each statement is committed when it finishes.

The vignette lists the few places where a `dplyr` translation cannot match R,
such as `round()` on halves and the approximate `median()`.

## Authentication

| Method | Helper | Typical use |
|---|---|---|
| Basic | `trino_auth_basic(user, password)` | LDAP, password file |
| Bearer JWT | `trino_auth_jwt(token)` | service accounts, pipelines |
| OAuth2 client credentials | `trino_auth_oauth2(client_id, client_secret, token_url)` | corporate SSO; the token is renewed automatically |

## Development

R 4.1.0 or newer. The test suite runs offline against a fake Trino coordinator
built with [webfakes](https://webfakes.r-lib.org), so no cluster is needed.
The fake replays responses recorded from a real Trino
(`tests/testthat/fixtures`, captured with `dev/record-fixtures.R`), so the
tests read the payloads a cluster really sends:

```r
devtools::test()
devtools::check()
```

With a Trino at hand, the integration tests in `tests/testthat/test-live.R`
also run: they compare every value with Trino's own rendering of it, and run
the SQL of the `dplyr` translations against what R computes on the same rows.

```r
# docker run --rm -d -p 8080:8080 --name trino trinodb/trino
Sys.setenv(RTRINO_TEST_URL = "http://localhost:8080")
devtools::test()
```

## License

BSD 3-Clause. See [LICENSE.md](LICENSE.md).
