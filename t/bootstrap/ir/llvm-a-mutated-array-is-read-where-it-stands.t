# ABOUTME: An array a loop pushes to or drains is read elsewhere at its own point in the
# ABOUTME: program: before the loop, after it, or walked -- B::SoN -> chalk -> lli == perl.
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

# A DRAINED OR FILLED ARRAY MAY BE READ ELSEWHERE. The loop mutates the
# array in place, and any other use of it was refused ("a drained array is
# also read/mutated elsewhere", 7 pvm cases) for fear the use would see it
# half-mutated. A read that carries its memory version is frozen there, so
# it sees the array as it stood: such uses are lowered; others stay refused.
for my $case (
    [ q{sub twice { return $_[0] * 2 } my @r; for my $n (1 .. 3) { push @r, twice($n) } print "@r\n";}, "2 4 6\n", 'filled by a loop, read after (pvm)' ],
    [ q{sub f { my %h = (a => 1); my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $h{a} = 9; $s .= $x } print "$s|$h{a}\n" } f();}, "12|9\n", 'filled, then walked (pvm)' ],
    [ q{my @q = (1, 2, 3); my $n = scalar(@q); for (1 .. 2) { shift @q } print "$n ", scalar(@q), "\n";}, "3 1\n", 'counted before a drain and after' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
