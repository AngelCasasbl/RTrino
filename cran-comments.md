## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

* Local Windows 11, R 4.6.1 (`R CMD check --as-cran`)

## Examples

Most examples need a running 'Trino' coordinator, so they are wrapped in
`@examplesIf nzchar(Sys.getenv("RTRINO_TEST_URL"))` and are skipped on CRAN.
They are run in full against a 'Trino' 483 container on every push to the
package's GitHub repository.

Three examples remain in `\dontrun{}` because they need things that cannot
exist on a check machine: a cluster that authenticates with a password
(`trino_auth`, `dbConnect`) and the PEM file of an internal certificate
authority (`trino_ssl`).

## Tests

The test suite runs offline, against a local fake coordinator (via
'webfakes') that replays responses recorded from a real 'Trino'. The
integration tests that need a real coordinator are skipped on CRAN.
