FROM devel AS custom-test
COPY .base/dist/test/bats/smoke/shared/ /smoke_test/
