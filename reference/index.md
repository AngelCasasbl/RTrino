# Package index

## Connect

Open a connection to a Trino coordinator, choose how to authenticate and
how to verify its certificate.

- [`Trino()`](https://angelcasasbl.github.io/RTrino/reference/Trino.md)
  : Instantiate the Trino driver
- [`dbConnect(`*`<TrinoDriver>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbConnect-TrinoDriver-method.md)
  : Connect to a Trino cluster
- [`trino_auth_basic()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  [`trino_auth_jwt()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  [`trino_auth_oauth2()`](https://angelcasasbl.github.io/RTrino/reference/trino_auth.md)
  : Authentication methods for Trino
- [`trino_ssl()`](https://angelcasasbl.github.io/RTrino/reference/trino_ssl.md)
  : TLS options for a Trino connection
- [`dbDisconnect(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbDisconnect-TrinoConnection-method.md)
  : Disconnect from Trino
- [`dbIsValid(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbIsValid-TrinoConnection-method.md)
  [`dbIsValid(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbIsValid-TrinoConnection-method.md)
  : Is this connection or result still usable?
- [`dbGetInfo(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbGetInfo-TrinoConnection-method.md)
  : Metadata about a Trino connection

## Run queries

Submit SQL and pull the rows back, in one go or in chunks.

- [`dbGetQuery(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbGetQuery-TrinoConnection-character-method.md)
  : Run a query and return all of its rows
- [`dbSendQuery(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbSendQuery-TrinoConnection-character-method.md)
  : Submit a statement to Trino
- [`dbSendStatement(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbSendStatement-TrinoConnection-character-method.md)
  : Submit a statement that changes something
- [`dbExecute(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbExecute-TrinoConnection-character-method.md)
  : Execute a statement that returns no rows
- [`dbFetch(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbFetch-TrinoResult-method.md)
  : Fetch rows from a Trino result
- [`dbHasCompleted(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbHasCompleted-TrinoResult-method.md)
  : Have all rows of a result been consumed?
- [`dbClearResult(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbClearResult-TrinoResult-method.md)
  : Release a Trino result
- [`dbBind(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbBind-TrinoResult-method.md)
  : Parameters are not supported

## Tables

Inspect, create, fill and drop tables.

- [`dbListTables(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbListTables-TrinoConnection-method.md)
  : List the tables in the connection's schema
- [`dbListFields(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbListFields-TrinoConnection-character-method.md)
  [`dbListFields(`*`<TrinoConnection>`*`,`*`<Id>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbListFields-TrinoConnection-character-method.md)
  [`dbListFields(`*`<TrinoConnection>`*`,`*`<ANY>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbListFields-TrinoConnection-character-method.md)
  : List a table's columns
- [`dbExistsTable(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbExistsTable-TrinoConnection-character-method.md)
  [`dbExistsTable(`*`<TrinoConnection>`*`,`*`<Id>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbExistsTable-TrinoConnection-character-method.md)
  [`dbExistsTable(`*`<TrinoConnection>`*`,`*`<ANY>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbExistsTable-TrinoConnection-character-method.md)
  : Does a table exist?
- [`dbCreateTable(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbCreateTable-TrinoConnection-method.md)
  : Create a table
- [`dbAppendTable(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbAppendTable-TrinoConnection-method.md)
  : Insert rows into an existing table
- [`dbWriteTable(`*`<TrinoConnection>`*`,`*`<ANY>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbWriteTable-TrinoConnection-ANY-method.md)
  [`dbWriteTable(`*`<TrinoConnection>`*`,`*`<Id>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbWriteTable-TrinoConnection-ANY-method.md)
  : Write a table
- [`dbRenameTable()`](https://angelcasasbl.github.io/RTrino/reference/dbRenameTable.md)
  : Rename a table
- [`dbRemoveTable(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbRemoveTable-TrinoConnection-character-method.md)
  [`dbRemoveTable(`*`<TrinoConnection>`*`,`*`<Id>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbRemoveTable-TrinoConnection-character-method.md)
  [`dbRemoveTable(`*`<TrinoConnection>`*`,`*`<ANY>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbRemoveTable-TrinoConnection-character-method.md)
  : Drop a table

## Transactions

- [`dbBegin(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbBegin-TrinoConnection-method.md)
  [`dbCommit(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbBegin-TrinoConnection-method.md)
  [`dbRollback(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbBegin-TrinoConnection-method.md)
  : Start, commit and roll back a transaction

## Quoting and types

Turn R values into Trino SQL, and Trino types into R types.

- [`dbQuoteIdentifier(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbQuoteIdentifier-TrinoConnection-character-method.md)
  [`dbQuoteIdentifier(`*`<TrinoConnection>`*`,`*`<SQL>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbQuoteIdentifier-TrinoConnection-character-method.md)
  [`dbQuoteString(`*`<TrinoConnection>`*`,`*`<character>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbQuoteIdentifier-TrinoConnection-character-method.md)
  [`dbQuoteString(`*`<TrinoConnection>`*`,`*`<SQL>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbQuoteIdentifier-TrinoConnection-character-method.md)
  : Quote identifiers and strings for Trino
- [`dbQuoteLiteral(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbQuoteLiteral-TrinoConnection-method.md)
  : Quote R values as Trino literals
- [`dbDataType(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/dbDataType-TrinoConnection-method.md)
  : Map an R type to a Trino type
- [`trino_type_to_r()`](https://angelcasasbl.github.io/RTrino/reference/trino_type_to_r.md)
  : Map a Trino type to the name of an R type

## dplyr and dbplyr

The SQL dialect that lets `dplyr` pipelines run in Trino.

- [`simulate_trino()`](https://angelcasasbl.github.io/RTrino/reference/simulate_trino.md)
  : A Trino connection that never talks to a server

- [`sql_dialect.TrinoConnection()`](https://angelcasasbl.github.io/RTrino/reference/sql_dialect.TrinoConnection.md)
  : SQL dialect for Trino

- [`sql_translation.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_translation.sql_dialect_trino.md)
  : Function translations for Trino

- [`sql_escape_date.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_escape_date.sql_dialect_trino.md)
  [`sql_escape_datetime.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_escape_date.sql_dialect_trino.md)
  : Literal dates and date-times in dplyr pipelines

- [`sql_query_explain.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_query_explain.sql_dialect_trino.md)
  : Explain a Trino query

- [`sql_query_save.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_query_save.sql_dialect_trino.md)
  [`sql_table_analyze.sql_dialect_trino()`](https://angelcasasbl.github.io/RTrino/reference/sql_query_save.sql_dialect_trino.md)
  : Saving a query as a table

- [`db_copy_to.TrinoConnection()`](https://angelcasasbl.github.io/RTrino/reference/db_copy_to.TrinoConnection.md)
  :

  [`copy_to()`](https://dplyr.tidyverse.org/reference/copy_to.html) for
  Trino

- [`dbplyr_edition.TrinoConnection()`](https://angelcasasbl.github.io/RTrino/reference/dbplyr_edition.TrinoConnection.md)
  : dbplyr edition used by Trino connections

## Classes

- [`show(`*`<TrinoDriver>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoDriver-class.md)
  [`dbIsValid(`*`<TrinoDriver>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoDriver-class.md)
  [`dbGetInfo(`*`<TrinoDriver>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoDriver-class.md)
  [`dbUnloadDriver(`*`<TrinoDriver>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoDriver-class.md)
  : Trino driver class
- [`show(`*`<TrinoConnection>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoConnection-class.md)
  : Trino connection class
- [`show(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  [`dbGetStatement(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  [`dbGetRowCount(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  [`dbGetRowsAffected(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  [`dbColumnInfo(`*`<TrinoResult>`*`)`](https://angelcasasbl.github.io/RTrino/reference/TrinoResult-class.md)
  : Trino result class
- [`RTrino`](https://angelcasasbl.github.io/RTrino/reference/RTrino-package.md)
  [`RTrino-package`](https://angelcasasbl.github.io/RTrino/reference/RTrino-package.md)
  : RTrino: 'DBI' Backend for 'Trino'
