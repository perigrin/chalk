# Tests for tr, but the test file is not utf8.

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    skip_all('ASCII sensitive') if $::IS_EBCDIC;
    set_up_inc('../lib');
}

plan tests => 2;

{ # This test is malloc sensitive.  Right now on some platforms anyway, space
  # for the final \xff needs to be mallocd, and that's what caused the
  # problem, because the '-' had already been parsed and was later added
  # without making space for it
