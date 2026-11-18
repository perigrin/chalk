# ABOUTME: a package scalar a code ref's call writes inside a block eval is read after the
# ABOUTME: eval as that call left it: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli: its stdout, or
# T2's refusal.
sub through_llvm ($pl) {
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    return ( undef, "load: $err" ) if $err;
    return ( undef, "lower: $units->[0]{err}" ) unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx(timeout 20 $LLI $ll 2>&1);
    return ( undef, "lli exited " . ($? >> 8) . ": $out" ) if $?;
    return ( $out, undef );
}

# A CALL THROUGH A CODE REF RUNS A SUB, which may store into any package
# scalar: the eval's join merges memory past it. T1 read that merge as a
# value Phi (only a named call or a method versioned memory), so the read of
# $C after the eval was made at its first use -- after `$C = $save` -- and
# read the restored 0: a silent wrong answer (Test::Chalk's subtest, run in an
# eval, counted no tests).
for my $case (
    [ q{our $C; sub inc { $C = $C + 1 }
        sub st { my ($code) = @_; my $save = $C; $C = 0; my $ran = eval { $code->(); 1 }; my $n = $C + 0; $C = $save; print $n, "\n"; return $ran }
        st(sub { inc(); inc() });},
      'a read after the eval, then a store' ],
    [ q{package T; our $C; sub inc { $C = $C + 1 }
        sub st { my ($code) = @_; my $save = $C; $C = 0; my $ran = eval { $code->(); 1 }; my $n = $C + 0; $C = $save; print $n, "\n"; return $ran }
        package main; T::st(sub { T::inc(); T::inc() }); T::st(sub { T::inc(); die "x\n" }); print $T::C + 0, "\n";},
      'a die in the code ref' ],
    [ q{our $C; sub inc { $C = $C + 1 } sub st { my ($code) = @_; $C = 0; my $ran = eval { $code->(); 1 }; print $C + 0, "\n" } st(sub { inc(); inc() });},
      'the read alone' ],
) {
    my ($src, $name) = @$case;
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my ($got, $why) = through_llvm($pl);
    my $want = qx($^X $pl 2>/dev/null);
    is($got, $want, "$name: perl's answer") or diag $why // '';
}

done_testing;
