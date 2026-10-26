# ABOUTME: && and || test a Scalar, Str or Num left side by perl's truth and yield the
# ABOUTME: operand they stop at: B::SoN -> chalk -> lli == perl.
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

# A Scalar left side of && was refused ("And (&&) LHS operand has
# repr=Scalar", pvm 254 255).
for my $c (
    [ q{my $a = $ARGV[0] // 1; my $b = $ARGV[1] // 0; my $and = ($a && $b); my $or = ($a || $b); print "[$and][$or]\n";} ],
    [ q{my $a = $ARGV[0] // 1; my $tight = $a && 9; print "$tight\n";} ],
    [ q{my $s = $ENV{NOPE} // "0"; my $t = $s || "dflt"; my $u = $s && "x"; print "[$t][$u]\n";} ],
    [ q{my $a = $ARGV[0] // 1; my $b = $ARGV[1] // 0; my $x = ($a xor $b); my $y = ($a xor $a); print "[$x][$y]\n";} ],
    [ q{my $n = $ENV{NOPE} // 0.5; my $r = $n && "y"; print "[$r]\n";} ],
    # One right side two && share (a folded `2 < 1`) is made in each one's
    # own block: cached from the first, the second's use was not dominated.
    [ q{my @a = (1); my @b = (); my $c = @a; my $d = @b; my $v = ($c > 0) && (2 < 1); my $w = ($d < 1) && (2 < 1); my $x = ($d > 0) || (2 < 1); my $y = ($c < 1) || (2 < 1); print "[$v][$w][$x][$y]\n";} ],
    # An Int and a Boolean side: the merge is the Scalar either is.
    [ q{my @a = (1); my @b = (); my $c = scalar(@a); my $d = scalar(@b); my $v = $c && (2 < 1); my $w = $d && (2 < 1); my $x = $c || (2 < 1); my $y = $d || (1 < 2); my $z = $d || (2 < 1); print "[$v][$w][$x][$y][$z]\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
