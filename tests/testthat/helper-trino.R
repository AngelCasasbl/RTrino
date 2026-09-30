# A fake Trino coordinator.
#
# The whole suite runs against this instead of a real cluster, so the tests are
# offline and deterministic. The app speaks enough of Trino's client protocol
# to exercise the parts of the package that matter: the /v1/info probe, the
# initial POST /v1/statement, the nextUri chain (including pages that carry no
# rows, as a queued query does), the terminal FAILED and CANCELED states, and
# the DELETE that cancels a running query.
#
# Each response's shape is chosen by the SQL text, so a test asks for the
# scenario it wants by the statement it sends.
#
# Two kinds of scenario:
#
# * Recorded ones, replayed from tests/testthat/fixtures/*.jsonl, which
#   dev/record-fixtures.R captured from a real Trino. Their pages are sent
#   byte for byte, so they carry what Trino actually puts on the wire: BIGINT
#   and DOUBLE as JSON numbers, columns described before any row arrives,
#   updateType and updateCount. Anything about how values are encoded is
#   tested against these, never against a payload made up here. A test sends
#   the recorded statement, from `trino_fixture_sql()`.
# * Synthetic ones, built below, for the protocol's control flow: pagination,
#   queued and stalled queries, failures, cancellation.
#
# Everything the handlers need is defined inside `trino_fake_app()`: webfakes
# runs the app in a separate process by serialising it, which carries the
# handlers' own environment but nothing else from this file.

trino_fixture_dir <- function() {
  testthat::test_path("fixtures")
}

# name -> list(sql, pages), read once per app.
trino_read_fixtures <- function() {
  files <- list.files(trino_fixture_dir(), pattern = "\\.jsonl$",
                      full.names = TRUE)
  fixtures <- lapply(files, function(path) {
    lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
    meta <- jsonlite::parse_json(lines[[1L]])
    list(sql = meta$sql, pages = lines[-1L])
  })
  names(fixtures) <- sub("\\.jsonl$", "", basename(files))
  fixtures
}

# The statement a recorded fixture answers.
trino_fixture_sql <- function(name) {
  fixture <- trino_read_fixtures()[[name]]
  if (is.null(fixture)) stop("No recorded fixture named ", name)
  fixture$sql
}

trino_fake_app <- function(require_auth = NULL) {
  `%|N|%` <- function(x, y) if (is.null(x)) y else x

  fixtures <- trino_read_fixtures()
  fixture_for <- function(sql) {
    for (name in names(fixtures)) {
      if (identical(fixtures[[name]]$sql, sql)) return(name)
    }
    NULL
  }

  # One recorded page, pointing its nextUri at the page after it.
  send_fixture_page <- function(res, name, page, base) {
    pages <- fixtures[[name]]$pages
    next_uri <- paste0(base, "/v1/statement/fixture/", name, "/", page + 1L)
    body <- sub("{{next}}", next_uri, pages[[page]], fixed = TRUE)
    res$set_status(200L)$set_type("application/json")$send(body)
  }

  # webfakes gives the full request URL, which is the only place the ephemeral
  # port the server picked is visible; nextUri must carry it.
  fake_base_url <- function(req) {
    sub("/v1/.*$", "", req$url)
  }

  header <- function(req, name) {
    hit <- req$headers[grepl(paste0("^", name, "$"), names(req$headers),
                             ignore.case = TRUE)]
    if (length(hit) == 0L) "" else as.character(hit[[1L]])
  }

  # Map a statement to the scenario that drives the response.
  scenario_for <- function(raw) {
    sql <- toupper(raw)
    # Table names are matched against `raw`: Trino's identifiers are
    # case-sensitive in a string literal, and the fixture has to be too.
    if (grepl("^SHOW TABLES", sql)) {
      "tables"
    } else if (grepl("^DESCRIBE", sql)) {
      "describe"
    } else if (grepl("INFORMATION_SCHEMA.TABLES", sql, fixed = TRUE)) {
      # dbExistsTable(): the fake schema holds `sales` and `regions`, and the
      # catalog `nowhere` does not exist. The names are compared through
      # lower(), as the real query does.
      if (grepl('"nowhere"', raw, fixed = TRUE)) {
        "no_catalog"
      } else if (grepl("'sales'", tolower(raw), fixed = TRUE) ||
                   grepl("'regions'", tolower(raw), fixed = TRUE)) {
        "count_one"
      } else {
        "count_zero"
      }
    } else if (grepl("LIMIT 0", sql)) {
      "empty"
    } else if (grepl("FAIL", sql)) {
      "failed"
    } else if (grepl("CANCEL", sql)) {
      "canceled"
    } else if (grepl("BIG", sql)) {
      "paged"
    } else if (grepl("SLOW", sql)) {
      "queued"
    } else if (grepl("STALLED", sql)) {
      "stalled"
    } else if (grepl("ODDTYPE", sql)) {
      "oddtype"
    } else {
      "simple"
    }
  }

  int_col <- function(name) {
    list(
      name = name, type = "integer",
      typeSignature = list(rawType = "integer")
    )
  }
  # count(*) is a BIGINT on a real cluster.
  bigint_col <- function(name) {
    list(
      name = name, type = "bigint",
      typeSignature = list(rawType = "bigint")
    )
  }
  chr_col <- function(name) {
    list(
      name = name, type = "varchar(20)",
      typeSignature = list(rawType = "varchar")
    )
  }
  odd_columns <- list(list(
    name = "x", type = "hyperdimensional",
    typeSignature = list(rawType = "hyperdimensional")
  ))

  # One page of one scenario. Page 1 is the answer to the POST.
  fake_page <- function(scenario, page, base) {
    uri <- function(next_page) {
      paste0(base, "/v1/statement/", scenario, "/", next_page)
    }
    id <- paste0("20260917_000000_00000_", scenario)
    finished <- function(columns = NULL, data = NULL) {
      list(id = id, stats = list(state = "FINISHED"), columns = columns,
           data = data)
    }
    running <- function(next_page, columns = NULL, data = NULL) {
      list(
        id = id,
        stats = list(state = if (page == 1L) "QUEUED" else "RUNNING"),
        nextUri = uri(next_page),
        columns = columns,
        data = data
      )
    }

    switch(
      scenario,
      simple = if (page == 1L) {
        running(2L)
      } else {
        finished(
          columns = list(int_col("n"), chr_col("label")),
          data = list(list(1L, "one"), list(2L, "two"))
        )
      },
      empty = if (page == 1L) {
        running(2L)
      } else {
        finished(columns = list(int_col("n"), chr_col("label")))
      },
      paged = if (page == 1L) {
        running(2L)
      } else if (page < 5L) {
        running(
          page + 1L,
          columns = list(int_col("n")),
          data = lapply(seq_len(2L), function(i) list((page - 2L) * 2L + i))
        )
      } else {
        finished(
          columns = list(int_col("n")),
          data = list(list(7L), list(8L))
        )
      },
      queued = if (page < 4L) {
        running(page + 1L)
      } else {
        finished(columns = list(int_col("n")), data = list(list(42L)))
      },
      # Fifteen pages with no rows: enough to exhaust the pause-free pages and
      # exercise the backoff that guards against a server stuck in that state.
      stalled = if (page < 16L) {
        running(page + 1L)
      } else {
        finished(columns = list(int_col("n")), data = list(list(1L)))
      },
      failed = if (page == 1L) {
        running(2L)
      } else {
        list(
          id = id,
          stats = list(state = "FAILED"),
          error = list(
            message = "line 1:8: Column 'nope' cannot be resolved",
            errorCode = 47L,
            errorName = "COLUMN_NOT_FOUND",
            errorType = "USER_ERROR"
          )
        )
      },
      canceled = if (page == 1L) {
        running(2L)
      } else {
        list(id = id, stats = list(state = "CANCELED"))
      },
      count_one = if (page == 1L) {
        running(2L)
      } else {
        finished(columns = list(bigint_col("n")), data = list(list(1L)))
      },
      count_zero = if (page == 1L) {
        running(2L)
      } else {
        finished(columns = list(bigint_col("n")), data = list(list(0L)))
      },
      no_catalog = if (page == 1L) {
        running(2L)
      } else {
        list(
          id = id,
          stats = list(state = "FAILED"),
          error = list(
            message = "line 1:27: Catalog 'nowhere' not found",
            errorCode = 44L,
            errorName = "CATALOG_NOT_FOUND",
            errorType = "USER_ERROR"
          )
        )
      },
      # A type the package does not know, over two pages of one row each.
      oddtype = if (page == 1L) {
        running(2L)
      } else if (page == 2L) {
        running(3L, columns = odd_columns, data = list(list("a")))
      } else {
        finished(columns = odd_columns, data = list(list("b")))
      },
      tables = if (page == 1L) {
        running(2L)
      } else {
        finished(
          columns = list(chr_col("Table")),
          data = list(list("sales"), list("regions"))
        )
      },
      describe = if (page == 1L) {
        running(2L)
      } else {
        finished(
          columns = list(
            chr_col("Column"), chr_col("Type"),
            chr_col("Extra"), chr_col("Comment")
          ),
          data = list(
            list("id", "bigint", "", ""),
            list("region", "varchar", "", "")
          )
        )
      },
      stop("Unknown fake scenario: ", scenario)
    )
  }

  app <- webfakes::new_app()
  app$locals$last_headers <- NULL
  app$locals$last_body <- NULL
  app$locals$deleted <- character()
  app$locals$flaky <- 0L

  app$use(webfakes::mw_text(type = "text/plain"))

  # Only the protocol endpoints are recorded: the introspection endpoint below
  # is itself a request, and would otherwise overwrite what a test wants to see.
  app$use(function(req, res) {
    if (startsWith(req$path, "/v1/")) {
      app$locals$last_headers <- req$headers
    }
    "next"
  })

  # The app runs in its own process, so tests read back what the client sent
  # over HTTP rather than by inspecting `app$locals` directly.
  app$get("/test/last-request", function(req, res) {
    res$set_status(200L)$send_json(
      list(
        headers = as.list(app$locals$last_headers %|N|% list()),
        body = app$locals$last_body %|N|% "",
        deleted = app$locals$deleted
      ),
      auto_unbox = TRUE
    )
  })

  # One app serves every test; each starts from a clean slate.
  app$post("/test/reset", function(req, res) {
    app$locals$last_headers <- NULL
    app$locals$last_body <- NULL
    app$locals$deleted <- character()
    app$locals$flaky <- 0L
    res$set_status(204L)$send("")
  })

  if (!is.null(require_auth)) {
    app$use(function(req, res) {
      if (!identical(header(req, "authorization"), require_auth)) {
        res$set_status(401L)$send_json(
          list(message = "Unauthorized"),
          auto_unbox = TRUE
        )
        return()
      }
      "next"
    })
  }

  app$get("/v1/info", function(req, res) {
    res$set_status(200L)$send_json(
      list(
        nodeVersion = list(version = "451"),
        environment = "test",
        starting = FALSE
      ),
      auto_unbox = TRUE
    )
  })

  app$post("/v1/statement", function(req, res) {
    sql <- req$text %|N|% ""
    app$locals$last_body <- sql
    # A load balancer's 502 on the first attempt, then the real answer.
    if (grepl("FLAKY", toupper(sql)) && app$locals$flaky == 0L) {
      app$locals$flaky <- 1L
      return(res$set_status(502L)$send("Bad Gateway"))
    }
    # A coordinator that stops answering.
    if (grepl("HANG", toupper(sql))) {
      Sys.sleep(3)
    }
    recorded <- fixture_for(sql)
    if (!is.null(recorded)) {
      return(send_fixture_page(res, recorded, 1L, fake_base_url(req)))
    }
    res$set_status(200L)$send_json(
      fake_page(scenario_for(sql), 1L, fake_base_url(req)),
      auto_unbox = TRUE,
      null = "null"
    )
  })

  app$get("/v1/statement/fixture/:name/:page", function(req, res) {
    send_fixture_page(
      res,
      req$params$name,
      as.integer(req$params$page),
      fake_base_url(req)
    )
  })

  app$delete("/v1/statement/fixture/:name/:page", function(req, res) {
    app$locals$deleted <- c(app$locals$deleted, req$params$name)
    res$set_status(204L)$send("")
  })

  app$get("/v1/statement/:scenario/:page", function(req, res) {
    res$set_status(200L)$send_json(
      fake_page(
        req$params$scenario,
        as.integer(req$params$page),
        fake_base_url(req)
      ),
      auto_unbox = TRUE,
      null = "null"
    )
  })

  app$delete("/v1/statement/:scenario/:page", function(req, res) {
    app$locals$deleted <- c(app$locals$deleted, req$params$scenario)
    res$set_status(204L)$send("")
  })

  app
}

# The fake coordinators, one per authentication setting, shared by the whole
# test run and reset before each test. Starting an R process for every test
# made the suite slow, and on a loaded machine a start would now and then
# time out.
trino_apps <- new.env(parent = emptyenv())

local_trino_app <- function(require_auth = NULL) {
  key <- if (is.null(require_auth)) "open" else require_auth
  proc <- trino_apps[[key]]
  if (is.null(proc) || !identical(proc$get_state(), "live")) {
    proc <- webfakes::new_app_process(
      trino_fake_app(require_auth),
      process_timeout = 60000L
    )
    trino_apps[[key]] <- proc
    withr::defer(proc$stop(), envir = testthat::teardown_env())
  }
  httr2::req_perform(
    httr2::req_method(httr2::request(proc$url("/test/reset")), "POST")
  )
  proc
}

local_trino_con <- function(proc, ..., .local_envir = parent.frame()) {
  url <- httr2::url_parse(proc$url())
  con <- DBI::dbConnect(
    RTrino::Trino(),
    host = paste0(url$scheme, "://", url$hostname),
    port = as.integer(url$port),
    user = "tester",
    catalog = "memory",
    schema = "default",
    ...
  )
  withr::defer(
    suppressWarnings(try(DBI::dbDisconnect(con), silent = TRUE)),
    envir = .local_envir
  )
  con
}
