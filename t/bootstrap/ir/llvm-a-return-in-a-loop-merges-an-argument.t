# ABOUTME: a return from inside a loop merges with an early return of an
# ABOUTME: argument nothing typed: the merge is what its arms are.
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


# The merge was the lattice TOP, and refused (pvm 008).
for my $src (
    q{sub pick { my ($n, $label) = @_; return $label if $n < 10; for my $i (1 .. 2) { next if $i == 1; return "big-" . $i; } return "none"; } print pick(1, "s"), " ", pick(50), "\n";},
    q{use v5.36; sub pick ($n, $label = "small") { return $label if $n < 10; for my $i (1 .. 2) { next if $i == 1; return "big-" . $i; } return "none"; } print pick(1), " ", pick(50), "\n";},
    q{sub pick { my ($n, $k) = @_; return $k if $n < 10; for my $i (1 .. 3) { return $i * 2 if $i == $n - 9; } return 0; } print pick(1, 5), " ", pick(11, 5), " ", pick(40, 5), "\n";},
) {
    my $want = qx($^X -e '$src' 2>&1);
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
