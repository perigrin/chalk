# ABOUTME: T2 slice 20 -- an uncaught die: its message to STDERR (" at FILE line N.\n" added
# ABOUTME: where it has no newline), exit 255, what was printed before kept; an arm that dies ends there.
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
    [ q{sub f { my ($n) = @_; die "neg\n" if $n < 0; die "zero" if $n == 0; return $n } print f(2), "\n"; print f(0), "\n";}, 'a die with and without a newline, after output' ],
    [ q{my $x = $ENV{CHALK_NOPE} // 3; if ($x > 2) { print "big\n"; die "too big: $x\n" } print "small\n";}, 'a die in an arm, its message made at run time' ],
    [ q{sub g { my ($v) = @_; my $r = $v > 1 ? "many" : "one"; die "none\n" unless $v; return $r } print g(2), g(1), "\n"; print g(0);}, 'a die in a sub after a merge' ],
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

# A DIE AN EVAL OR A TRY CATCHES (here, or around the call): perl's output,
# or refused -- never an exit where perl catches it.
for my $src (
    q{use v5.36; no warnings; use feature "try"; try { die "y\n" } catch ($e) { print "c $e" }},
    q{use v5.36; no warnings; use feature "try"; sub f { die "z\n" } try { f() } catch ($e) { print "c $e" }},
    q{my $r = eval { die "x\n"; 1 }; print defined $r ? "ok" : "caught: $@";},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    unless (defined $ll) { pass("caught die: refused ($src)"); next }
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    is(run("timeout 20 $LLI $llp")->[0], run("$^X $pl")->[0], "caught die: perl's output ($src)");
}

done_testing;
