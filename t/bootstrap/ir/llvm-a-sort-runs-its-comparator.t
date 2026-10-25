# ABOUTME: sort with a comparator block runs the block for each comparison, $a and $b
# ABOUTME: the two elements, and keeps equal elements in order: B::SoN -> chalk -> lli == perl.
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

# A comparator perl does not fold was refused ("sort with no folded
# comparator", pvm 088 217 162).
for my $c (
    [ q{my @a = (3, 1, 2); @a = sort { my $t = $a; $t <=> $b } @a; print "@a\n";},                          "1 2 3\n",   'a block with a lexical' ],
    [ q{my @r = ({ i => 2 }, { i => 1 }, { i => 3 }); my @s = sort { $a->{i} <=> $b->{i} } @r; print join(",", map { $_->{i} } @s), "\n";}, "1,2,3\n", 'by an element of each' ],
    [ q{my %rank = (x => 2, y => 0, z => 1); my @s = sort { $rank{$a} <=> $rank{$b} } qw(x y z); print "@s\n";}, "y z x\n", 'by a hash of each' ],
    [ q{my @w = qw(xb ya zc xa); my @s = sort { substr($a, 1) cmp substr($b, 1) } @w; print "@s\n";},    "ya xa xb zc\n", 'cmp' ],
    [ q{my @w = qw(bb a ccc dd); my @s = sort { length($a) <=> length($b) } @w; print "@s\n";},             "a bb dd ccc\n", 'equal ones keep their order' ],
) {
    my ($src, $want, $name) = @$c;
    my $got = eval { through_llvm($src) };
    is($got, $want, "$name: perl's answer") or diag $@;
}

# <=> AND cmp ARE VALUES too: -1, 0 or 1.
{
    my $got = eval { through_llvm(q{my $x = $ENV{NOPE_X} // 3; my $s = $ENV{NOPE_S} // "b"; print $x <=> 4, " ", $x <=> 3, " ", 4.5 <=> $x, " ", $s cmp "a", " ", $s cmp "bb", " ", $s cmp "b", "\n";}) };
    is($got, "-1 0 1 1 -1 0\n", "<=> and cmp: perl's answer") or diag $@;
}

done_testing;
