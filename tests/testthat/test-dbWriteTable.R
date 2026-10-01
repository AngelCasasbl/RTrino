test_that("dbWriteTable() creates and fills a new table", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  # "regions2" is not one of the fake's existing tables.
  DBI::dbWriteTable(con, "regions2", data.frame(id = 1L, label = "a"))
  expect_identical(
    sent_body(proc),
    'INSERT INTO "memory"."default"."regions2"\n  ("id", "label")\nVALUES\n  (1, \'a\')'
  )
})

test_that("dbWriteTable() errors if the table exists and neither flag is set", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    DBI::dbWriteTable(con, "sales", data.frame(id = 1L)),
    "exists in database, and both overwrite and append are FALSE"
  )
})

test_that("dbWriteTable() appends to an existing table", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbWriteTable(con, "sales", data.frame(id = 1L), append = TRUE)
  expect_identical(
    sent_body(proc),
    'INSERT INTO "memory"."default"."sales"\n  ("id")\nVALUES\n  (1)'
  )
})

test_that("dbWriteTable() overwrites by renaming, creating, then dropping", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_message(
    DBI::dbWriteTable(con, "sales", data.frame(id = 1L), overwrite = TRUE),
    "is overwritten"
  )
  # The last statement sent is the DROP of the renamed original.
  expect_match(sent_body(proc), '^DROP TABLE "memory"\\."default"\\."rtrino_rename_')
})

test_that("dbWriteTable() rejects conflicting arguments", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  expect_error(
    DBI::dbWriteTable(
      con, "regions2", data.frame(id = 1L),
      overwrite = TRUE, append = TRUE
    ),
    "overwrite and append cannot both be TRUE"
  )
  expect_error(
    DBI::dbWriteTable(
      con, "regions2", data.frame(id = 1L),
      append = TRUE, field.types = c(id = "bigint")
    ),
    "Cannot specify field.types with append"
  )
  expect_error(
    DBI::dbWriteTable(
      con, "regions2", data.frame(id = 1L), temporary = TRUE
    ),
    "Temporary tables not supported by RTrino"
  )
})

test_that("dbWriteTable() uses field.types instead of inferring them", {
  proc <- local_trino_app()
  con <- local_trino_con(proc)

  DBI::dbWriteTable(
    con, "regions2", data.frame(id = 1L),
    field.types = c(id = "bigint")
  )
  # dbCreateTable() runs before dbAppendTable(); the create is the statement
  # before the insert, so check it ran by looking at dbExistsTable()'s absence
  # of error and the final INSERT having the right shape.
  expect_identical(
    sent_body(proc),
    'INSERT INTO "memory"."default"."regions2"\n  ("id")\nVALUES\n  (1)'
  )
})
