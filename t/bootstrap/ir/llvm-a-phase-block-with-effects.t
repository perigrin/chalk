# ABOUTME: A BEGIN or END block with effects of its own is refused, not dropped; a
# ABOUTME: `use` -- only a require and an import -- leaves the program as it was.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

# THE LOADER READ ONLY `methods`, so B::SoN's `phase_blocks` were dropped: a
# program with `BEGIN { print }` and `END { print }` printed only its main
# line (pvm corpus compile-phase.md). Until BEGIN and END run in their places,
# such a program is refused.
{
    my $got = eval { through_llvm(q{END { print "end\n" } BEGIN { print "begin\n" } print "main\n";}) };
    ok(!defined $got, 'a BEGIN and an END that print are not lowered') or diag "got: $got";
    like($@, qr/^load: .*BEGIN or END block/, 'refused, naming the phase block');
}

# A `use` IS A BEGIN BLOCK TOO, of a require and an import, and the program
# around it still lowers.
is(eval { through_llvm(q{use strict; no warnings 'once'; use List::Util qw(sum); print "ok\n";}) } // "died: $@",
    "ok\n", 'a program with use and no statements still lowers');

# A `use` WITH A VERSION calls VERSION, and loaded before the guard: it is a
# `use` still (review of 59e7b915, I4).
is(eval { through_llvm(q{use Scalar::Util 1.0 (); print "ok\n";}) } // "died: $@",
    "ok\n", 'a use with a version still lowers');

# ONLY A `use` IS LET THROUGH, not a call that happens to be named import or
# require: the program's own import printed, and was dropped (I5).
my $setup = do {
    my ($fh, $f) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh qq{print "setup\\n"; 1;\n};
    close $fh;
    $f;
};
for my $case (
    [ q{package Foo; sub import { print "imported\n" } package main; BEGIN { Foo->import } print "main\n";}, 'a BEGIN calling an import of its own' ],
    [ qq{BEGIN { require "$setup" } print "main\\n";}, 'a BEGIN requiring a file by path' ],
) {
    my ($src, $name) = @$case;
    my $got = eval { through_llvm($src) };
    ok(!defined $got, "$name: not lowered") or diag "got: $got";
    like($@, qr/^load: .*(?:BEGIN or END block|GAP)/, "$name: refused, naming why");
}

done_testing;
