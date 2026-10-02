# Authentication methods for Trino

Each helper returns a *closure* that takes an `httr2` request and
returns it with the appropriate credentials attached. The credentials
live only in that closure's environment, so they are never written to
the global environment and never stored on the connection object in
plain sight. Pass the result as the `auth` argument of
[`dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Usage

``` r
trino_auth_basic(user, password)

trino_auth_jwt(token)

trino_auth_oauth2(client_id, client_secret, token_url, scope = NULL, ...)
```

## Arguments

- user:

  User name.

- password:

  Password. Read it from the environment
  (`Sys.getenv("TRINO_PASSWORD")`) rather than writing it in a script.

- token:

  A JWT, as a string.

- client_id:

  OAuth2 client id.

- client_secret:

  OAuth2 client secret.

- token_url:

  Token endpoint of the OAuth2 provider.

- scope:

  Optional OAuth2 scope.

- ...:

  Further arguments passed on to
  [`httr2::req_oauth_client_credentials()`](https://httr2.r-lib.org/reference/req_oauth_client_credentials.html).

## Value

A function of one argument (an `httr2` request) returning a modified
request.

## Details

- `trino_auth_basic()` — HTTP basic authentication, used by Trino's LDAP
  and password-file authenticators.

- `trino_auth_jwt()` — a bearer JWT, for service accounts and unattended
  pipelines, or for a cluster fronted by an SSO proxy that mints its own
  tokens.

- `trino_auth_oauth2()` — OAuth2 client credentials, for corporate
  identity providers such as Okta or Entra ID. `httr2` caches the token
  and renews it when it expires.

Trino rejects basic and bearer credentials over plain HTTP, so use an
`https://` host with all three.

## Examples

``` r
# Only builds the credential; nothing is sent until a connection uses it
auth <- trino_auth_basic("analyst", Sys.getenv("TRINO_PASSWORD"))

# Needs a cluster that authenticates with a password
if (FALSE) { # \dontrun{
con <- DBI::dbConnect(
  RTrino::Trino(),
  host    = "https://trino.example.com",
  port    = 443,
  user    = "analyst",
  catalog = "hive",
  schema  = "default",
  auth    = auth
)
} # }
```
