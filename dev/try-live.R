# Exercise RTrino against a real Trino cluster.
#
# Start one locally with Docker (the image ships a `memory` catalog and the
# `tpch` connector, which is all this script needs):
#
#   docker run --rm -d -p 8080:8080 --name trino trinodb/trino
#   # it takes ~30s to come up; the coordinator answers /v1/info when ready
#
# Then:
#
#   Rscript dev/try-live.R
#
# Point it somewhere else with environment variables:
#
#   TRINO_HOST      default http://localhost
#   TRINO_PORT      default 8080
#   TRINO_USER      default your OS user
#   TRINO_CATALOG   default memory
#   TRINO_SCHEMA    default default
#   TRINO_PASSWORD  set to use basic auth
#   TRINO_TOKEN     set to use a bearer JWT
#   TRINO_CA_BUNDLE set to trust an internal certificate authority
#
# Stop the container afterwards with `docker stop trino`.

library(RTrino)
library(DBI)

say <- function(...) cat("\n== ", ..., "\n", sep = "")

host <- Sys.getenv("TRINO_HOST", "http://localhost")
port <- as.integer(Sys.getenv("TRINO_PORT", "8080"))
user <- Sys.getenv("TRINO_USER", unset = Sys.info()[["user"]])
catalog <- Sys.getenv("TRINO_CATALOG", "memory")
schema <- Sys.getenv("TRINO_SCHEMA", "default")

# Whichever credential is in the environment, in order of preference.
auth <- if (nzchar(Sys.getenv("TRINO_TOKEN"))) {
  trino_auth_jwt(Sys.getenv("TRINO_TOKEN"))
} else if (nzchar(Sys.getenv("TRINO_PASSWORD"))) {
  trino_auth_basic(user, Sys.getenv("TRINO_PASSWORD"))
} else {
  NULL
}

ssl <- if (nzchar(Sys.getenv("TRINO_CA_BUNDLE"))) {
  trino_ssl(ca_bundle = Sys.getenv("TRINO_CA_BUNDLE"))
} else {
  trino_ssl()
}

say("connecting to ", host, ":", port, " as ", user)
con <- dbConnect(
  Trino(),
  host = host,
  port = port,
  user = user,
  catalog = catalog,
  schema = schema,
  auth = auth,
  ssl_options = ssl
)
on.exit(try(dbDisconnect(con), silent = TRUE), add = TRUE)

print(con)
cat("server version:", dbGetInfo(con)$db.version, "\n")

# ---------------------------------------------------------------- one-liners --
say("scalars and types straight from the engine")
print(dbGetQuery(con, "
  SELECT
    true                                          AS flag,
    CAST(3 AS smallint)                           AS small,
    42                                            AS n,
    CAST(9007199254740993 AS bigint)              AS big,
    CAST(1.5 AS double)                           AS dbl,
    CAST(12.34 AS decimal(10,2))                  AS dec,
    'hello'                                       AS txt,
    from_base64('AQL/')                           AS bin,
    DATE '2026-01-15'                             AS d,
    TIME '10:30:00'                               AS t,
    TIMESTAMP '2026-01-15 10:30:00'               AS ts,
    TIMESTAMP '2026-01-15 10:30:00 Europe/Madrid' AS tsz,
    ARRAY[1, 2, 3]                                AS arr,
    MAP(ARRAY['a'], ARRAY[1])                     AS mp,
    JSON '{\"k\": 1}'                             AS js,
    UUID '12151fd2-7586-11e9-8f9e-2a86e4085a59'   AS uid,
    CAST(NULL AS varchar)                         AS nil
"))

say("BIGINT precision")
exact <- dbGetQuery(con, "SELECT CAST(9007199254740993 AS bigint) AS id")$id
cat("integer64 (default):", as.character(exact), "\n")

con_num <- dbConnect(
  Trino(), host = host, port = port, user = user,
  catalog = catalog, schema = schema, auth = auth, ssl_options = ssl,
  bigint = "numeric"
)
lossy <- dbGetQuery(con_num, "SELECT CAST(9007199254740993 AS bigint) AS id")$id
cat("numeric:            ", format(lossy, digits = 22),
    if (lossy != 9007199254740993) "  <- the double cannot hold it" else "", "\n")
dbDisconnect(con_num)

# ------------------------------------------------------------ a real dataset --
say("a few thousand rows from tpch, paginated")
res <- dbSendQuery(con, "
  SELECT orderkey, custkey, orderstatus, totalprice, orderdate
  FROM tpch.sf1.orders
  LIMIT 5000
")
rows <- 0L
chunks <- 0L
repeat {
  chunk <- dbFetch(res, n = 1000)
  if (nrow(chunk) == 0L) break
  rows <- rows + nrow(chunk)
  chunks <- chunks + 1L
  if (dbHasCompleted(res)) break
}
cat("fetched", rows, "rows in", chunks, "calls\n")
print(dbColumnInfo(res))
dbClearResult(res)

say("the same query in one go")
orders <- dbGetQuery(con, "
  SELECT orderstatus, count(*) AS orders, sum(totalprice) AS revenue
  FROM tpch.sf1.orders
  GROUP BY orderstatus
  ORDER BY revenue DESC
")
print(orders)

# -------------------------------------------------- writing and introspecting --
say("create a table, inspect it, read it back, drop it")
table_name <- paste0("rtrino_demo_", format(Sys.time(), "%H%M%S"))

dbExecute(con, sprintf(
  "CREATE TABLE %s.%s.%s (id bigint, region varchar, amount double)",
  catalog, schema, table_name
))
dbExecute(con, sprintf(
  "INSERT INTO %s.%s.%s VALUES (1, 'north', 10.5), (2, 'south', 20.25)",
  catalog, schema, table_name
))

cat("tables in", paste0(catalog, ".", schema), ":\n")
print(head(dbListTables(con), 20))
cat("exists:", dbExistsTable(con, table_name), "\n")
cat("fields:", paste(dbListFields(con, table_name), collapse = ", "), "\n")
print(dbGetQuery(con, sprintf("SELECT * FROM %s ORDER BY id", table_name)))

# ---------------------------------------------------------------- cancelling --
say("abandoning a long query cancels it on the server")
res <- dbSendQuery(con, "SELECT count(*) FROM tpch.sf1000.lineitem")
cat("submitted, clearing without fetching...\n")
dbClearResult(res)
cat("cleared; the coordinator received the DELETE\n")

# -------------------------------------------------------------------- errors --
say("error handling")
cat("bad column:  ")
cat(conditionMessage(tryCatch(
  dbGetQuery(con, "SELECT no_such_column FROM tpch.sf1.orders"),
  error = identity
)), "\n")
cat("bad syntax:  ")
cat(conditionMessage(tryCatch(
  dbGetQuery(con, "SELCT 1"),
  error = identity
)), "\n")

# --------------------------------------------------------------------- dplyr --
if (requireNamespace("dbplyr", quietly = TRUE) &&
      packageVersion("dbplyr") >= "2.6.0" &&
      requireNamespace("dplyr", quietly = TRUE)) {
  say("dplyr against tpch")
  library(dplyr)

  pipeline <- tbl(con, dbplyr::in_catalog("tpch", "sf1", "orders")) |>
    filter(orderdate >= as.Date("1995-01-01")) |>
    group_by(orderstatus) |>
    summarise(
      orders = n(),
      revenue = sum(totalprice, na.rm = TRUE),
      typical = median(totalprice)
    ) |>
    arrange(desc(revenue))

  cat("generated SQL:\n")
  print(dbplyr::sql_render(pipeline, con = con))
  cat("\nresult:\n")
  print(collect(pipeline))

  cat("\nexplain:\n")
  explain(pipeline)
} else {
  say("dplyr skipped (needs dplyr and dbplyr >= 2.6.0)")
}

say("cleaning up")
dbExecute(con, sprintf("DROP TABLE %s.%s.%s", catalog, schema, table_name))
cat("dropped", table_name, "\n")
dbDisconnect(con)
cat("disconnected; valid:", dbIsValid(con), "\n")

say("done")
