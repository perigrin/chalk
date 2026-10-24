# ABOUTME: A list assignment into variables kept in memory stores each its own value,
# ABOUTME: pairwise, all read before any is stored -- B::SoN -> chalk -> lli == perl.
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

# THE WIRE COUNTS THE TARGETS. A list assign into variables handed to a
# call reaches chalk as Assign(t1, t2, v1, v2) with `targets => 2`, and the
# loader dropped the count: lowered as `t1 = t2`, `my ($aliased,
# $untouched) = (1, 1)` stored $untouched's undef into $aliased (pvm
# subroutines.md printed "1 " for "2 1").
for my $case (
    [ q{sub f { $_[0] } my ($a, $b) = (1, 2); print f($a), f($b), " $a $b\n";}, "12 1 2\n", 'two targets' ],
    [ q{sub f { $_[0] } my ($a, $b) = (1, 2); ($a, $b) = ($b, $a); print f($a), f($b), "\n";}, "21\n", 'a swap reads before it stores' ],
    [ q{sub f { $_[0] } my ($a, $b, $c) = (1, 2); print f($a), f($b), defined(f($c)) ? "d" : "u", "\n";}, "12u\n", 'a target past the values is undef' ],
) {
    my ($src, $want, $name) = @$case;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

done_testing;
