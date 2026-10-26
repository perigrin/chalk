# ABOUTME: an element store in a loop whose container is made by the pass (an element read
# ABOUTME: at the loop key) is lowered in the body: B::SoN -> chalk -> lli == perl.
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

# A body store's container was lowered in the preheader as if the same every
# pass; one read at the pass's key reached the loop's phi before the loop
# existed: "Phi node encountered ... before its enclosing structure".
for my $c (
    [ q{my %v = (a => {n => "x"}, b => {n => "y"}); my @l; for my $k (sort keys %v) { my $s = $v{$k}{n}; $v{$k}{n} = "z"; if ($k) { push @l, "$s" } } print "@l\n";} ],
    [ q{my @r = ([1], [2]); for my $i (0, 1) { my $row = $r[$i]; $row->[0] *= 10 } print join(",", map { $_->[0] } @r), "\n";} ],
    # ITS AGGREGATE is the same every pass: made in the body it was made again
    # after the loop, and the stores were lost ("1,2" for "10,20").
    [ q{my @r = ([1], [2]); for my $i (0, 1) { $r[$i][0] *= 10 } print join(",", map { $_->[0] } @r), "\n";} ],
    # IN A LOOP IN THE LOOP, or an arm: its aggregate likewise (older: "0 0;0 0").
    [ q{my @m = ([0, 0], [0, 0]); for my $i (0, 1) { for my $j (0, 1) { $m[$i][$j] = $i + $j } } print join(";", map { "@$_" } @m), "\n";} ],
    [ q{my @r = ([1], [2]); for my $i (0, 1) { if ($i) { $r[$i][0] = 9 } } print join(",", map { $_->[0] } @r), "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A read through a reference waiting while a store goes through it: refused.
{
    my $src = q{my %v = (a => {n => "x"}); my @l; for my $k (sort keys %v) { my $info = $v{$k}; my $s = $info->{n}; $info->{n} = "z"; push @l, $s } print "@l $v{a}{n}\n";};
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/GAP:/, "refused by name: $src") }
}

done_testing;
