FROM devel AS devel-test
COPY .base/dist/test/bats/smoke/shared/ /smoke_test/
