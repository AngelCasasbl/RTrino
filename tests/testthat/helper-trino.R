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
# Everything the handlers need is defined inside `trino_fake_app()`: webfakes
# runs the app in a separate process by serialising it, which carries the
# handlers' own environment but nothing else from this file.

trino_fake_app <- function(require_auth = NULL) {
  `%|N|%` <- function(x, y) if (is.null(x)) y else x

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
      # catalog `nowhere` does not exist.
      if (grepl('"nowhere"', raw, fixed = TRUE)) {
        "no_catalog"
      } else if (grepl("'sales'", raw, fixed = TRUE) ||
                   grepl("'regions'", raw, fixed = TRUE)) {
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
    } else if (grepl("TYPES", sql)) {
      "types"
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
  chr_col <- function(name) {
    list(
      name = name, type = "varchar(20)",
      typeSignature = list(rawType = "varchar")
    )
  }

  type_columns <- function() {
    types <- c(
      flag = "boolean",
      small = "smallint",
      n = "integer",
      big = "bigint",
      dbl = "double",
      dec = "decimal(10,2)",
      txt = "varchar(10)",
      bin = "varbinary",
      d = "date",
      t = "time(3)",
      ts = "timestamp(3)",
      tsz = "timestamp(3) with time zone",
      arr = "array(integer)",
      mp = "map(varchar, integer)",
      js = "json",
      uid = "uuid",
      nil = "varchar(5)"
    )
    lapply(names(types), function(nm) {
      list(
        name = nm, type = types[[nm]],
        typeSignature = list(rawType = types[[nm]])
      )
    })
  }

  type_row <- function() {
    list(
      TRUE,
      3L,
      7L,
      "9007199254740993",
      1.5,
      "12.34",
      "hello",
      jsonlite::base64_enc(as.raw(c(1L, 2L, 255L))),
      "2026-01-15",
      "10:30:00.000",
      "2026-01-15 10:30:00.000",
      "2026-01-15 10:30:00.000 UTC",
      list(1L, 2L, 3L),
      list(a = 1L),
      "{\"k\": 1}",
      "f79a24f4-0b3a-4a1b-9f61-4f2f3a9c1d5e",
      NULL
    )
  }

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
        finished(columns = list(int_col("n")), data = list(list(1L)))
      },
      count_zero = if (page == 1L) {
        running(2L)
      } else {
        finished(columns = list(int_col("n")), data = list(list(0L)))
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
      types = if (page == 1L) {
        running(2L)
      } else {
        finished(columns = type_columns(), data = list(type_row()))
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
    res$set_status(200L)$send_json(
      fake_page(scenario_for(sql), 1L, fake_base_url(req)),
      auto_unbox = TRUE,
      null = "null"
    )
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

# Start the fake server for the duration of the calling test file.
local_trino_app <- function(require_auth = NULL, .local_envir = parent.frame()) {
  webfakes::local_app_process(
    trino_fake_app(require_auth),
    .local_envir = .local_envir
  )
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
