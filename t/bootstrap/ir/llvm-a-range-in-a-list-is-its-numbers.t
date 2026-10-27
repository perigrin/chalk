# ABOUTME: A range with integer bounds in a list is each of its numbers, in order, and
# ABOUTME: none when it runs backwards: B::SoN -> chalk -> lli == perl.
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

# A RANGE IN A LIST FLATTENS to its numbers. Its bounds known only when the
# program runs, `my @c = (1 .. $n)` was refused ("a list with a List in it",
# pvm 076); a range of integers needs no runtime, only a loop.
for my $case (
    [ q{my $n = $ENV{NO_SUCH_VAR} // 4; my @c = (1 .. $n); print scalar(@c), " @c\n";}, "4 1 2 3 4\n", 'a range to a variable' ],
    [ q{my $n = $ENV{NO_SUCH_VAR} // 3; my @c = (0, 2 .. $n, 9); print "@c\n";}, "0 2 3 9\n", 'a range among other elements' ],
    [ q{my $n = $ENV{NO_SUCH_VAR} // 0; my @c = (1 .. $n); print scalar(@c), "[@c]\n";}, "0[]\n", 'a range that runs backwards is empty' ],
    [ q{sub range_of { my ($n) = @_; return 0 unless $n; my @c = (1 .. $n); return scalar(@c) } print range_of(0), " ", range_of(4), "\n";}, "0 4\n", 'in a sub (pvm 076)' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# A RANGE OF STRINGS counts by perl's string increment ('aa' .. 'ad'), not
# as numbers (llvm-a-range-of-strings.t has the increment's edges).
{
    my $got = eval { through_llvm(q{my $e = $ENV{NO_SUCH_VAR} // "ad"; my @c = ("aa" .. $e); print "@c\n";}) };
    is($got, "aa ab ac ad\n", 'a range of strings counts by string increment') or diag $@;
}

done_testing;
