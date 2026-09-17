# Compare three ways of answering "does this table exist?" on a real cluster.
#
# The three candidates do the same number of round trips, so the question is
# how much work the coordinator does and how many rows cross the wire. That
# depends on how many tables the schema holds, so the benchmark creates tables
# in the `memory` catalog and re-measures as the schema grows.
#
#   docker run --rm -d -p 8080:8080 --name trino trinodb/trino
#   Rscript dev/bench-dbExistsTable.R
#
# Environment variables:
#   TRINO_HOST     default http://localhost
#   TRINO_PORT     default 8080
#   TRINO_USER     default your OS user
#   TRINO_CATALOG  default memory      (must allow CREATE TABLE)
#   TRINO_SCHEMA   default default
#   TRINO_PASSWORD / TRINO_TOKEN / TRINO_CA_BUNDLE as in dev/try-live.R
#   BENCH_SIZES    schema sizes to test, e.g. "10,100,500" (default "10,100,500")
#   BENCH_REPS     timed repetitions per measurement (default 15)
#
# Nothing is left behind: every table it creates is dropped at the end, even
# if the script fails.

library(RTrino)
library(DBI)

host <- Sys.getenv("TRINO_HOST", "http://localhost")
port <- as.integer(Sys.getenv("TRINO_PORT", "8080"))
user <- Sys.getenv("TRINO_USER", unset = Sys.info()[["user"]])
catalog <- Sys.getenv("TRINO_CATALOG", "memory")
schema <- Sys.getenv("TRINO_SCHEMA", "default")
sizes <- as.integer(strsplit(Sys.getenv("BENCH_SIZES", "10,100,500"), ",")[[1]])
reps <- as.integer(Sys.getenv("BENCH_REPS", "15"))

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

con <- dbConnect(
  Trino(),
  host = host, port = port, user = user,
  catalog = catalog, schema = schema, auth = auth, ssl_options = ssl
)

created <- character()
on.exit({
  if (length(created)) {
    cat("\ndropping", length(created), "benchmark tables...\n")
    for (t in created) {
      try(dbExecute(con, sprintf(
        "DROP TABLE IF EXISTS %s.%s.%s", catalog, schema, t
      )), silent = TRUE)
    }
  }
  try(dbDisconnect(con), silent = TRUE)
}, add = TRUE)

# ---------------------------------------------------------- the three variants --
# Each takes an unqualified table name and returns TRUE or FALSE. They are
# plain functions rather than S4 methods so all three can coexist here.

# What RTrino does today: list the schema, match in R.
by_show_tables <- function(con, name) {
  out <- dbGetQuery(con, paste0(
    "SHOW TABLES FROM ",
    dbQuoteIdentifier(con, con@catalog), ".",
    dbQuoteIdentifier(con, con@schema)
  ))
  name %in% (if (nrow(out) == 0L) character() else as.character(out[[1L]]))
}

# What RPresto does: count matching rows in information_schema.columns.
# Literals are quoted here, unlike the original, so the comparison measures
# the query shape rather than the escaping bug.
by_info_columns <- function(con, name) {
  out <- dbGetQuery(con, paste0(
    "SELECT count(*) AS n FROM ",
    dbQuoteIdentifier(con, con@catalog), ".information_schema.columns",
    " WHERE table_schema = ", dbQuoteString(con, con@schema),
    " AND table_name = ", dbQuoteString(con, name)
  ))
  as.numeric(out$n) > 0
}

# The proposal: same idea, against the lighter information_schema table.
by_info_tables <- function(con, name) {
  out <- dbGetQuery(con, paste0(
    "SELECT count(*) AS n FROM ",
    dbQuoteIdentifier(con, con@catalog), ".information_schema.tables",
    " WHERE table_schema = ", dbQuoteString(con, con@schema),
    " AND table_name = ", dbQuoteString(con, name)
  ))
  as.numeric(out$n) > 0
}

variants <- list(
  "SHOW TABLES + %in%" = by_show_tables,
  "information_schema.columns" = by_info_columns,
  "information_schema.tables" = by_info_tables
)

# ------------------------------------------------------------------- measuring --
# Wall clock, because that is what a caller waits for: it covers the
# coordinator's planning, the pagination round trips and the conversion in R.
time_calls <- function(f, con, name, reps) {
  f(con, name) # warm up: first call pays for connector metadata caching
  times <- numeric(reps)
  for (i in seq_len(reps)) {
    start <- proc.time()[["elapsed"]]
    f(con, name)
    times[[i]] <- proc.time()[["elapsed"]] - start
  }
  times
}

summarise <- function(times) {
  c(
    median = stats::median(times),
    min = min(times),
    max = max(times)
  ) * 1000
}

make_tables <- function(con, n, prefix) {
  names <- sprintf("%s_%04d", prefix, seq_len(n))
  for (nm in names) {
    dbExecute(con, sprintf(
      "CREATE TABLE IF NOT EXISTS %s.%s.%s (id bigint)", catalog, schema, nm
    ))
  }
  names
}

prefix <- paste0("bench_", format(Sys.time(), "%H%M%S"))
baseline <- length(dbListTables(con))

cat("cluster:      ", host, ":", port, "\n", sep = "")
cat("schema:       ", catalog, ".", schema, "\n", sep = "")
cat("tables before:", baseline, "\n")
cat("repetitions:  ", reps, " per measurement\n", sep = "")
cat("\nTimes in milliseconds.\n")

results <- list()

for (size in sizes) {
  want <- size - (length(dbListTables(con)) - baseline)
  if (want > 0L) {
    cat("\ncreating", want, "tables to reach", size, "...\n")
    created <- c(created, make_tables(con, want, paste0(prefix, "_", size)))
  }
  total <- length(dbListTables(con))

  cat("\n== schema holds ", total, " tables ==\n", sep = "")
  cat(sprintf("%-28s %10s %10s %10s   %s\n",
              "variant", "median", "min", "max", "answer"))

  # A name that exists and one that does not: the information_schema variants
  # short-circuit on a miss, the listing variant cannot.
  for (target in c(existing = created[[length(created)]], missing = "no_such_table_xyz")) {
    label <- if (identical(target, "no_such_table_xyz")) "miss" else "hit"
    for (nm in names(variants)) {
      f <- variants[[nm]]
      answer <- f(con, target)
      s <- summarise(time_calls(f, con, target, reps))
      cat(sprintf("%-28s %10.1f %10.1f %10.1f   %s (%s)\n",
                  nm, s[["median"]], s[["min"]], s[["max"]], answer, label))
      results[[length(results) + 1L]] <- data.frame(
        tables = total, variant = nm, case = label,
        median_ms = s[["median"]], min_ms = s[["min"]], max_ms = s[["max"]]
      )
    }
  }

  # The reason for whatever the numbers say.
  rows <- nrow(dbGetQuery(con, paste0(
    "SHOW TABLES FROM ", dbQuoteIdentifier(con, catalog), ".",
    dbQuoteIdentifier(con, schema)
  )))
  cat("  rows transferred: SHOW TABLES ", rows,
      " vs information_schema 1\n", sep = "")
}

cat("\n== all measurements ==\n")
all <- do.call(rbind, results)
print(all, row.names = FALSE)

# How each variant scales: slope of median time against schema size.
cat("\n== scaling (median ms per table added, on the 'hit' case) ==\n")
hits <- all[all$case == "hit", ]
for (nm in names(variants)) {
  v <- hits[hits$variant == nm, ]
  if (nrow(v) >= 2L) {
    slope <- stats::coef(stats::lm(median_ms ~ tables, data = v))[["tables"]]
    cat(sprintf("%-28s %+.4f ms/table\n", nm, slope))
  }
}

cat("\nA variant whose slope is flat answers in constant time;",
    "\none whose slope rises pays for every table in the schema.\n")
