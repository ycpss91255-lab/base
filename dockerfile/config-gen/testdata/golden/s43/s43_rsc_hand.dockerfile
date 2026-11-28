FROM devel AS devel-test
COPY test/bats/smoke/shared/test_helper.bash test/bats/smoke/devel-test/own.bats /smoke_test/
