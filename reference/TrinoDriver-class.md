# Trino driver class

An S4 class representing the Trino driver. It carries no state and
exists only as the entry point for
[`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Usage

``` r
# S4 method for class 'TrinoDriver'
show(object)

# S4 method for class 'TrinoDriver'
dbIsValid(dbObj, ...)

# S4 method for class 'TrinoDriver'
dbGetInfo(dbObj, ...)

# S4 method for class 'TrinoDriver'
dbUnloadDriver(drv, ...)
```

## Arguments

- object:

  A TrinoDriver object.

- dbObj:

  A TrinoDriver object.

- ...:

  Unused, for compatibility with the generic.

- drv:

  A TrinoDriver object.
