# ABOUTME: T2 slice 21 -- eval and try: a die in the body (or in a sub it calls, however deep)
# ABOUTME: sets $@ and goes to the eval's end; the body's value or undef; nested; uncaught still exits.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

# run($cmd) -> [stdout, stderr, exit code]
sub run ($cmd) {
    my (undef, $ef) = tempfile(UNLINK => 1);
    my $out = qx($cmd 2>$ef);
    my $code = $? >> 8;
    my $err = do { local (@ARGV, $/) = $ef; <> } // '';
    return [ $out, $err, $code ];
}

for my $case (
    [ q{sub f { my ($n) = @_; die "bad $n\n" if $n > 1; return $n * 10 } my $r = eval { f(1) + f(2) }; print defined $r ? "r=$r" : "err=$@"; my $s = eval { f(1) }; print "s=$s [$@]\n";}, 'a die in a called sub is caught; a later eval clears $@' ],
    [ q{sub g { die "deep\n" } sub f { g(); print "not here\n"; return 1 } my $r = eval { f(); 2 }; print defined $r ? "r" : "caught $@";}, 'a die two calls down unwinds both' ],
    [ q{my $r = eval { die "here\n"; 1 }; print defined $r ? "r" : "caught $@"; my $t = eval { 7 }; print "t=$t [$@]\n";}, 'a die in the body itself' ],
    [ q{use v5.36; no warnings; use feature "try"; sub f { die "z\n" } try { f() } catch ($e) { print "c $e" } print "after\n";}, 'try and catch around a call' ],
    [ q{sub f { die "uncaught\n" } my $r = eval { 1 }; print "ok $r\n"; f(); print "never\n";}, 'a die outside any eval still exits' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    ok(defined $ll && $ll =~ /^; chalk T2/m, "$name: lowered through T2") or diag $err // $units->[0]{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    my $got  = run("timeout 20 $LLI $llp");
    my $want = run("$^X $pl");
    is($got->[0], $want->[0], "$name: perl's output");
    is($got->[1], $want->[1], "$name: perl's message");
    is($got->[2], $want->[2], "$name: perl's exit code");
}

# NESTED, $@ read in both: B::SoN makes the two reads one node -- perl's
# output, or refused (never the inner's message for the outer's).
perl_or_refused(q{my $o = eval { my $i = eval { die "in\n" }; print "inner: $@"; die "out\n" }; print "outer: $@";}, "nested evals");

# A DEAD DEREF IN AN EVAL: perl still runs it and dies (not a SCALAR
# reference); T2 must not drop it -- perl's output, or refused.
perl_or_refused(q{my $x = $ENV{NO_SUCH_VAR} // [1]; my $r = eval { my $v = $$x; 1 }; print defined $r ? "ran\n" : "died\n";}, "a dead deref in an eval");

sub perl_or_refused ($src, $name) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    if (defined $ll) {
        my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        print $lf $ll; close $lf;
        is(run("timeout 20 $LLI $llp")->[0], run("$^X $pl")->[0], "$name: perl's output");
    }
    else { pass("$name: refused") }
}

done_testing;
