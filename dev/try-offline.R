# Exercise every public function of RTrino without a Trino cluster.
#
# The package's own test fixture is a fake coordinator that speaks enough of
# Trino's client protocol to drive the whole API, so this script reuses it and
# walks through the package the way a user would.
#
#   Rscript dev/try-offline.R
#
# The fake server chooses its answer from the SQL text, so the statements below
# are the ones it knows about: "SELECT 1", "SELECT * FROM big" (paginated),
# "SELECT slow" (queued), "SELECT types" (one row of every type),
# "SELECT fail", "SELECT cancel", SHOW TABLES and DESCRIBE.

pkgload::load_all(".", quiet = TRUE)
library(DBI)

source("tests/testthat/helper-trino.R")

say <- function(...) cat("\n== ", ..., "\n", sep = "")

proc <- webfakes::new_app_process(trino_fake_app())
on.exit(proc$stop(), add = TRUE)
url <- httr2::url_parse(proc$url())

say("Fake coordinator at ", proc$url())

# ---------------------------------------------------------------- connecting --
con <- dbConnect(
  Trino(),
  host = paste0(url$scheme, "://", url$hostname),
  port = as.integer(url$port),
  user = "tester",
  catalog = "memory",
  schema = "default"
)
on.exit(try(dbDisconnect(con), silent = TRUE), add = TRUE)

say("dbConnect / dbIsValid / dbGetInfo")
print(con)
cat("valid:", dbIsValid(con), "\n")
str(dbGetInfo(con))

# ------------------------------------------------------------------ querying --
say("dbGetQuery")
print(dbGetQuery(con, "SELECT 1"))

say("dbSendQuery + dbFetch(n = -1), following nextUri across 4 pages")
res <- dbSendQuery(con, "SELECT * FROM big")
print(res)
print(dbFetch(res))
cat("rows fetched:", dbGetRowCount(res), " completed:", dbHasCompleted(res), "\n")
dbClearResult(res)

say("chunked dbFetch(n = 3)")
res <- dbSendQuery(con, "SELECT * FROM big")
repeat {
  chunk <- dbFetch(res, n = 3)
  if (nrow(chunk) == 0L) break
  cat("chunk of", nrow(chunk), ":", paste(chunk$n, collapse = ", "), "\n")
  if (dbHasCompleted(res)) break
}
dbClearResult(res)

say("dbColumnInfo")
res <- dbSendQuery(con, "SELECT 1")
invisible(dbFetch(res))
print(dbColumnInfo(res))
dbClearResult(res)

say("a query that stays QUEUED for a few pages before returning rows")
print(dbGetQuery(con, "SELECT slow"))

say("an empty result keeps its schema")
empty <- dbGetQuery(con, "SELECT n, label FROM t LIMIT 0")
print(empty)
cat("columns:", paste(names(empty), collapse = ", "),
    "| types:", paste(vapply(empty, function(x) class(x)[[1]], ""), collapse = ", "),
    "\n")

# --------------------------------------------------------------------- types --
say("every Trino type, converted")
types <- dbGetQuery(con, "SELECT types")
for (nm in names(types)) {
  value <- types[[nm]]
  shown <- if (is.list(value)) format(value[[1]]) else format(value)
  cat(sprintf("  %-6s %-10s %s\n", nm, class(value)[[1]],
              paste(shown, collapse = " ")))
}

say("BIGINT precision: integer64 (default) vs numeric")
cat("integer64:", as.character(types$big), "\n")
con_num <- dbConnect(
  Trino(),
  host = paste0(url$scheme, "://", url$hostname),
  port = as.integer(url$port),
  catalog = "memory", schema = "default", bigint = "numeric"
)
cat("numeric:  ", format(dbGetQuery(con_num, "SELECT types")$big, digits = 22), "\n")
dbDisconnect(con_num)

say("the type map on its own")
for (t in c("boolean", "bigint", "decimal(38,9)", "varchar(10)", "varbinary",
            "date", "timestamp(3) with time zone", "array(row(a integer))")) {
  cat(sprintf("  %-28s -> %s\n", t, trino_type_to_r(t)))
}
cat("  unknown type: ")
print(tryCatch(trino_type_to_r("hyperdimensional"), warning = conditionMessage))

# ------------------------------------------------------------- introspection --
say("dbListTables / dbExistsTable / dbListFields")
print(dbListTables(con))
cat("sales exists:", dbExistsTable(con, "sales"),
    "| nope exists:", dbExistsTable(con, "nope"), "\n")
print(dbListFields(con, "sales"))

say("quoting")
cat(as.character(dbQuoteIdentifier(con, "my column")), "\n")
cat(as.character(dbQuoteIdentifier(con, 'we"ird')), "\n")
cat(as.character(dbQuoteString(con, "O'Brien")), "\n")

# -------------------------------------------------------------------- errors --
say("error handling")
cat("FAILED query:   ")
cat(conditionMessage(tryCatch(dbGetQuery(con, "SELECT fail"),
                              error = identity)), "\n")
cat("CANCELED query: ")
cat(conditionMessage(tryCatch(dbGetQuery(con, "SELECT cancel"),
                              error = identity)), "\n")
cat("unreachable:    ")
cat(conditionMessage(tryCatch(
  dbConnect(Trino(), host = "http://127.0.0.1", port = 1L,
            catalog = "hive", schema = "default"),
  error = identity
)), "\n")
cat("missing catalog: ")
cat(conditionMessage(tryCatch(
  dbConnect(Trino(), schema = "default"),
  error = identity
)), "\n")

# ---------------------------------------------------------------------- auth --
say("authentication closures")
secured <- webfakes::new_app_process(
  trino_fake_app(require_auth = "Bearer demo-token")
)
on.exit(secured$stop(), add = TRUE)
surl <- httr2::url_parse(secured$url())

con_jwt <- dbConnect(
  Trino(),
  host = paste0(surl$scheme, "://", surl$hostname),
  port = as.integer(surl$port),
  catalog = "memory", schema = "default",
  auth = trino_auth_jwt("demo-token")
)
cat("with the right JWT:", dbIsValid(con_jwt),
    "| rows:", nrow(dbGetQuery(con_jwt, "SELECT 1")), "\n")
dbDisconnect(con_jwt)

cat("without credentials: ")
cat(conditionMessage(tryCatch(
  dbConnect(Trino(),
            host = paste0(surl$scheme, "://", surl$hostname),
            port = as.integer(surl$port),
            catalog = "memory", schema = "default"),
  error = identity
)), "\n")

cat("credentials stay in the closure: ")
basic <- trino_auth_basic("angel", "s3cret")
cat(get("password", envir = environment(basic)),
    "(only reachable through the closure)\n")

# ----------------------------------------------------------------------- TLS --
say("TLS options")
print(trino_ssl())
print(trino_ssl(verify = FALSE))
cat("applying verify = FALSE warns: ")
cat(conditionMessage(tryCatch(
  trino_ssl_options(httr2::request("https://x"), trino_ssl(verify = FALSE)),
  warning = identity
)), "\n")

# -------------------------------------------------------------------- dplyr ---
if (requireNamespace("dbplyr", quietly = TRUE) &&
      packageVersion("dbplyr") >= "2.6.0" &&
      requireNamespace("dplyr", quietly = TRUE)) {
  say("dplyr / dbplyr")
  library(dplyr)

  dialect <- dbplyr::sql_dialect(con)
  cat("dialect:", class(dialect)[[1]], "\n")

  lazy <- tbl(con, dbplyr::sql("SELECT * FROM sales")) |>
    filter(n > 1) |>
    group_by(label) |>
    summarise(total = sum(n, na.rm = TRUE))
  cat("\ngenerated SQL:\n")
  print(dbplyr::sql_render(lazy, con = con))

  cat("\ntranslations:\n")
  for (e in rlang::exprs(as.character(x), as.numeric(x), paste0(a, b),
                         grepl("a", x), gsub("a", "b", x), median(x))) {
    cat(sprintf("  %-22s -> %s\n", deparse(e),
                as.character(dbplyr::translate_sql(!!e, con = con,
                                                   window = FALSE))))
  }

  cat("\ncollect():\n")
  print(tbl(con, dbplyr::sql("SELECT * FROM big")) |> collect())

  cat("\nEXPLAIN:\n")
  print(dbplyr::sql_query_explain(dialect, dbplyr::sql("SELECT 1")))
} else {
  say("dplyr / dbplyr skipped (needs dplyr and dbplyr >= 2.6.0)")
}

# --------------------------------------------------------------- disconnect ---
say("dbDisconnect")
dbDisconnect(con)
cat("valid after disconnect:", dbIsValid(con), "\n")
cat("using it anyway: ")
cat(conditionMessage(tryCatch(dbGetQuery(con, "SELECT 1"),
                              error = identity)), "\n")

say("done")
