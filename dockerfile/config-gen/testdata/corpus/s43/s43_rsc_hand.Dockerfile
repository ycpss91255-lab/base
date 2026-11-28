FROM devel AS devel-test
COPY test/smoke/test_helper.bash test/smoke/own.bats /smoke_test/
