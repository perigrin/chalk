# ABOUTME: an arm with statements before its `next` or `last` jumps where that says -- the
# ABOUTME: latch with the values it left, or the exit: B::SoN -> chalk -> lli == perl.
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

# The back-edge is the step over the latch's merge (`$i += 2` of the Phi of
# `$i` and `$i - 1`); the latch Phi was looked for only as the back-edge
# itself, and lowering the step met it first: "Phi node encountered ...
# before its enclosing structure" (pvm 097).
for my $c (
    [ q{my @o; for (my $i = 0; $i < 5; $i += 2) { if ($i == 2) { $i--; next } push @o, $i } print "@o\n";} ],
    [ q{my @p = qw(a %x b c); my @o; for (my $i = 0; $i < @p; $i += 2) { my $k = $p[$i]; if ($k =~ /^%/) { push @o, "s"; $i--; next } push @o, "$k=" . $p[$i + 1] } print "@o\n";} ],
    [ q{my $n = 0; for (my $i = 0; $i < 10; $i++) { if ($i % 3 == 0) { $i += 1; next } $n += $i } print "$n\n";} ],
    # A `last` after a statement: the exit Region's input is that statement,
    # not the arm's Proj, so the arm was taken for an ordinary one and the
    # loop ran on (`a B c` for perl's `a B` -- silently wrong).
    [ q{my @o; for my $x (qw(a b c)) { if ($x eq "b") { push @o, "B"; last } push @o, $x } print "@o\n";} ],
    [ q{my $s = ""; my $i = 0; while ($i < 9) { $i++; if ($i == 4) { $s .= "!"; last } $s .= $i } print "$s\n";} ],
    [ q{my @o; for my $x (qw(a b c d)) { if ($x eq "b") { push @o, "B"; next } if ($x eq "c") { push @o, "C"; last } push @o, $x } print "@o\n";} ],
    # A loop, or an if, inside the arm before its `next`: the arm's end is
    # past that structure's merge (pvm 155).
    [ q{my $o = ""; for my $p (0 .. 3) { if ($p == 2) { for my $k (1 .. 2) { $o .= "<$k>" } next } $o .= $p } print "$o\n";} ],
    [ q{my $p = 0; my $o = ""; while ($p < 6) { if ($p == 2) { if (length($o) < 5) { $o .= "!" } $p += 2; next } $o .= $p; $p++ } print "$o\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
