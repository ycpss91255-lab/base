FROM devel AS custom-test
COPY xbase/test/smoke/ /smoke_test/
COPY .base/test/smoke/ /smoke_test/
