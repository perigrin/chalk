#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
	require './charset_tools.pl';
}
skip_all_without_perlio();

no utf8; # needed for use utf8 not griping about the raw octets


plan(tests => 62);

$| = 1;

my $a_file = tempfile();

open(F,"+>:utf8",$a_file);
