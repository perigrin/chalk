# ABOUTME: main is a package like any other: the loader builds main's Class from its record on the
# ABOUTME: wire, its symbols (imports and all) among it. Needs B::SoN's main package record.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
require Chalk::CodeGen::Pipeline;

sub mop_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my (undef, undef, $mop, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, sub { () }, program_mode => 1);
    die "load: $err" if $err;
    return $mop;
}

# pvm 316: `$main::{floor}` after `use POSIX` is main's stash -- its Class.
{
    my $main = mop_of(qq{use POSIX;\nour \$answer = 42;\nprint floor(2.5), \$answer, "\\n";\n})->for_class('main');
    ok($main && $main->knows_symbols, 'main\'s Class knows its symbols');
    is($main->has_symbol('floor'), 1, 'an import is one');
    is($main->symbol('floor')->{code_from}, 'POSIX', '... from POSIX');
    is($main->has_symbol('answer'), 1, 'an our is one');
    is($main->has_symbol('nosuch'), 0, 'what nothing made is not');
    is($main->has_symbol('SIG'), undef, 'what the toolchain made is not answered');
}

# pvm 317: `use POSIX ()` imports nothing.
is(mop_of(qq{use POSIX ();\nprint POSIX::floor(2.5), "\\n";\n})->for_class('main')->has_symbol('floor'), 0, 'use POSIX () makes no floor');

done_testing;
