FROM devel AS custom-test
COPY xbase/test/smoke/ /smoke_test/
COPY .base/dist/test/bats/smoke/shared/ /smoke_test/
