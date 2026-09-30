# Record the responses of a real Trino cluster as test fixtures.
#
# The offline test suite replays these through its fake coordinator, so the
# tests see what Trino actually sends: BIGINT and DOUBLE as JSON numbers,
# columns that arrive a few pages into the query, updateCount on the last
# pages of an INSERT, and so on. A fake that invents its own payloads cannot
# catch a client that misreads them.
#
#   docker run --rm -d -p 8080:8080 --name trino trinodb/trino
#   Rscript dev/record-fixtures.R
#
# Environment variables:
#   TRINO_HOST  default http://localhost
#   TRINO_PORT  default 8080
#
# Each fixture is written to tests/testthat/fixtures/<name>.jsonl: a first
# line with the statement and the server version, then one line per page.
# Every page keeps the `columns`, `data` and `updateCount` members byte for
# byte, as Trino sent them; `stats` and `error` are cut down to the fields the
# client reads, and `nextUri` becomes a `{{next}}` placeholder the fake server
# fills in.

host <- Sys.getenv("TRINO_HOST", "http://localhost")
port <- Sys.getenv("TRINO_PORT", "8080")
base <- paste0(sub("/+$", "", host), ":", port)
out_dir <- file.path("tests", "testthat", "fixtures")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# The headers RTrino sends (see R/request_headers.R), so that what is recorded
# is what the package receives.
headers <- list(
  "X-Trino-User" = "rtrino",
  "X-Trino-Catalog" = "memory",
  "X-Trino-Schema" = "default",
  "X-Trino-Source" = "RTrino",
  "X-Trino-Time-Zone" = "UTC",
  "X-Trino-Language" = "en-US",
  "X-Trino-Client-Capabilities" = "PARAMETRIC_DATETIME",
  "Accept" = "application/json"
)

statements <- list(
  # BIGINT around 2^31 and 2^53 and at its limits, DOUBLE values whose
  # shortest decimal form needs 17 digits, subnormals and the non-finite
  # values Trino sends as strings. Trino renders the reference columns itself:
  # the exact digits of each BIGINT and the IEEE 754 bits of each DOUBLE.
  numbers = "SELECT id, b, CAST(b AS varchar) AS b_text, d,
  to_hex(to_ieee754_64(d)) AS d_bits
FROM (
  VALUES
    (1, BIGINT '0', DOUBLE '0'),
    (2, BIGINT '-1', -0.0E0),
    (3, BIGINT '2147483647', 0.1E0 + 0.2E0),
    (4, BIGINT '2147483648', 1E0 / 3E0),
    (5, BIGINT '3000000000', 1E300),
    (6, BIGINT '9007199254740992', 4.9E-324),
    (7, BIGINT '9007199254740993', 1E16),
    (8, BIGINT '-9007199254740993', 1E20),
    (9, BIGINT '9223372036854775807', 123456789.123456789E0),
    (10, BIGINT '-9223372036854775808', -2.5E-8),
    (11, BIGINT '44995000000', nan()),
    (12, BIGINT '1', infinity()),
    (13, BIGINT '2', -infinity()),
    (14, NULL, NULL)
) AS t (id, b, d)
ORDER BY id",

  # One row of every type the package maps, then a row of NULLs.
  types = "SELECT * FROM (
  VALUES (
    1, true, TINYINT '7', SMALLINT '3', 42, BIGINT '9007199254740993',
    REAL '1.5', DOUBLE '0.1', DECIMAL '12.34', DECIMAL '12345678901234567.89',
    'hello', CHAR 'abc', from_base64('AQL/'), DATE '2026-01-15',
    TIME '10:30:00.123', TIME '10:30:00.123456',
    TIMESTAMP '2026-01-15 10:30:00.123',
    TIMESTAMP '2026-01-15 10:30:00.123456',
    TIMESTAMP '2026-01-15 10:30:00.123456 Europe/Madrid',
    TIMESTAMP '2026-01-15 10:30:00 +02:00',
    INTERVAL '3' DAY, INTERVAL '2' MONTH,
    ARRAY[1, 2, 3], MAP(ARRAY['a', 'b'], ARRAY[1, 2]),
    CAST(ROW(1, 'x') AS ROW(a integer, b varchar)),
    JSON '{\"k\": 1}', UUID '12151fd2-7586-11e9-8f9e-2a86e4085a59',
    IPADDRESS '10.0.0.1', U&'\\00F1and\\00FA \\6F22\\5B57'
  ), (
    2, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL, NULL, NULL
  )
) AS t (
  i, flag, tiny, small, n, big, r, dbl, dec, bigdec, txt, ch, bin, d, t3, t6,
  ts3, ts6, tsz, tsoff, ids, iym, arr, mp, rw, js, uid, ip, utf8
)
ORDER BY i",

  # Real tpch rows, with the columns Trino describes before any row arrives.
  nation = "SELECT nationkey, name, regionkey FROM tpch.tiny.nation ORDER BY nationkey",
  empty = "SELECT orderkey, orderstatus, totalprice FROM tpch.tiny.orders WHERE false",
  failed = "SELECT no_such_column FROM tpch.tiny.nation",

  # A statement's life cycle: DDL without a count, DML and CTAS with one.
  create_table = "CREATE TABLE memory.default.rtrino_fixture (id bigint, label varchar)",
  insert = "INSERT INTO memory.default.rtrino_fixture VALUES (1, 'one'), (2, 'two')",
  ctas = "CREATE TABLE memory.default.rtrino_fixture_copy AS SELECT * FROM memory.default.rtrino_fixture",
  drop_table = "DROP TABLE memory.default.rtrino_fixture"
)
cleanup <- c(
  "DROP TABLE IF EXISTS memory.default.rtrino_fixture",
  "DROP TABLE IF EXISTS memory.default.rtrino_fixture_copy"
)

# ------------------------------------------------------------- raw JSON --
# The members of a JSON object, each as the exact text of its value. Parsing
# with jsonlite and printing back would reformat the numbers, which is the
# very thing the fixtures are for.
json_members <- function(text) {
  chars <- strsplit(text, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  i <- 1L
  skip_ws <- function() {
    while (i <= n && chars[[i]] %in% c(" ", "\n", "\r", "\t")) i <<- i + 1L
  }
  # Index of the closing quote of the string starting at `from`.
  string_end <- function(from) {
    j <- from + 1L
    while (chars[[j]] != "\"") j <- j + if (chars[[j]] == "\\") 2L else 1L
    j
  }
  # Index of the last character of the value starting at `from`.
  value_end <- function(from) {
    ch <- chars[[from]]
    if (ch == "\"") {
      return(string_end(from))
    }
    if (ch %in% c("{", "[")) {
      depth <- 0L
      j <- from
      repeat {
        c <- chars[[j]]
        if (c == "\"") {
          j <- string_end(j)
        } else if (c %in% c("{", "[")) {
          depth <- depth + 1L
        } else if (c %in% c("}", "]")) {
          depth <- depth - 1L
          if (depth == 0L) return(j)
        }
        j <- j + 1L
      }
    }
    j <- from
    while (j < n && !chars[[j + 1L]] %in% c(",", "}", " ", "\n")) j <- j + 1L
    j
  }

  skip_ws()
  stopifnot(chars[[i]] == "{")
  i <- i + 1L
  members <- character()
  repeat {
    skip_ws()
    if (chars[[i]] == "}") break
    key_end <- string_end(i)
    key <- paste(chars[(i + 1L):(key_end - 1L)], collapse = "")
    i <- key_end + 1L
    skip_ws()
    stopifnot(chars[[i]] == ":")
    i <- i + 1L
    skip_ws()
    end <- value_end(i)
    members[[key]] <- paste(chars[i:end], collapse = "")
    i <- end + 1L
    skip_ws()
    if (chars[[i]] == ",") i <- i + 1L
  }
  members
}

reduce_page <- function(text) {
  m <- json_members(text)
  out <- character()
  out[["id"]] <- m[["id"]]
  if (!is.na(m["nextUri"])) out[["nextUri"]] <- "\"{{next}}\""
  for (raw in c("columns", "data")) {
    if (!is.na(m[raw])) out[[raw]] <- m[[raw]]
  }
  stats <- jsonlite::parse_json(m[["stats"]])
  out[["stats"]] <- jsonlite::toJSON(list(state = stats$state), auto_unbox = TRUE)
  if (!is.na(m["error"])) {
    err <- jsonlite::parse_json(m[["error"]])
    out[["error"]] <- jsonlite::toJSON(
      err[c("message", "errorCode", "errorName", "errorType")],
      auto_unbox = TRUE
    )
  }
  for (raw in c("updateType", "updateCount")) {
    if (!is.na(m[raw])) out[[raw]] <- m[[raw]]
  }
  page <- paste0(
    "{", paste0("\"", names(out), "\":", out, collapse = ","), "}"
  )
  stopifnot(jsonlite::validate(page))
  page
}

# ------------------------------------------------------------- recording --
request <- function(url, method = "GET", body = NULL) {
  req <- httr2::request(url)
  req <- httr2::req_method(req, method)
  req <- httr2::req_headers(req, !!!headers)
  if (!is.null(body)) req <- httr2::req_body_raw(req, body, type = "text/plain")
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  httr2::resp_body_string(httr2::req_perform(req), encoding = "UTF-8")
}

run <- function(sql) {
  pages <- request(paste0(base, "/v1/statement"), "POST", sql)
  repeat {
    last <- jsonlite::parse_json(pages[[length(pages)]])
    if (is.null(last$nextUri)) break
    pages <- c(pages, request(last$nextUri))
  }
  pages
}

info <- jsonlite::parse_json(request(paste0(base, "/v1/info")))
version <- info$nodeVersion$version
cat("recording against Trino", version, "at", base, "\n")

for (sql in cleanup) invisible(run(sql))

for (name in names(statements)) {
  sql <- statements[[name]]
  pages <- vapply(run(sql), reduce_page, character(1L), USE.NAMES = FALSE)
  meta <- jsonlite::toJSON(
    list(name = name, sql = sql, trino = version),
    auto_unbox = TRUE
  )
  path <- file.path(out_dir, paste0(name, ".jsonl"))
  con <- file(path, open = "w", encoding = "UTF-8")
  writeLines(c(meta, pages), con, useBytes = TRUE)
  close(con)
  cat(sprintf("  %-13s %2d pages  %s\n", name, length(pages), path))
}

for (sql in cleanup) invisible(run(sql))
