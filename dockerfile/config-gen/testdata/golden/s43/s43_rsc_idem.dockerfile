FROM devel AS devel-test
COPY test/bats/smoke/shared/ /smoke_test/
COPY test/bats/smoke/devel-test/ /smoke_test/
