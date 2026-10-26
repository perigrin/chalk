# ABOUTME: an element store under an if/next inside a loop writes the aggregate declared
# ABOUTME: before the loop -- one aggregate, made once: B::SoN -> chalk -> lli == perl.
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

# A named aggregate declared before a loop (`my @o = (0)`, unpinned) was
# first lowered where an arm's store pre-lowered its container -- inside the
# loop body -- so each pass made a fresh @o, the store went there, and the
# read after the loop saw the original: 0 for perl's 2 (silently wrong).
for my $c (
    [ q{my @o = (0); for my $x (qw(a b c)) { next if $x eq "b"; $o[0] += 1 } print $o[0], "\n";} ],
    [ q{my %o = (n => 0); for my $x (qw(a b c)) { next if $x eq "b"; $o{n} += 1 } print $o{n}, "\n";} ],
    [ q{my @o = (0); for my $x (qw(a b c)) { if ($x eq "b") { $o[0] += 10 } else { $o[0] += 1 } } print $o[0], "\n";} ],
    [ q{my @o = (0); my $i = 0; while ($i < 3) { $i++; next if $i == 2; $o[0] += 1 } print $o[0], "\n";} ],
    [ q{sub f { my @o = (0); for my $x (@_) { next if $x eq "b"; $o[0] += 1 } $o[0] } print f(qw(a b c)), f(qw(b)), "\n";} ],
    # A loop that FILLS an array (push) carries memory now; the array walked
    # after it is no drained one (pvm 123 went GAP when the producer added it).
    [ q{package F { sub new { bless { n => { a => 1, b => 2, c => 3 } }, shift } sub get { $_[0]{n}{$_[1]} } sub drop { delete $_[0]{n}{$_[1]} } } my $f = F->new; my @dead; for my $k (sort keys $f->{n}->%*) { push @dead, $k unless $k eq "b" } my @got; for my $d (@dead) { push @got, $f->get($d); $f->drop($d) } print "@got ", join(",", sort keys $f->{n}->%*), "\n";} ],
    # Not hoisted: the empty list a grep collects into is new each pass (pvm 159).
    [ q{my $out = ""; for my $k (qw(x y)) { my @p = grep { $_ ne "b" } qw(a b c); next unless @p; $out .= "$k@p " } print "$out\n";} ],
    [ q{my $n = length("ab"); my @o = ($n); for my $x (qw(a b c)) { next if $x eq "b"; $o[0] += 1 } print $o[0], "\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# Declared INSIDE the loop it is pinned there and is not hoisted: perl's
# fresh @o each pass, or refused -- never one @o shared across passes.
{
    my $src = q{for my $x (qw(a b c)) { my @o = (0); next if $x eq "b"; $o[0] += 1; print $o[0] } print "\n";};
    my $got = eval { through_llvm($src) };
    ok(( defined $got && $got eq "11\n" ) || $@ =~ /GAP/, "a my \@o inside the loop: perl's answer or refused")
        or diag "got: " . ( $got // "undef" ) . " $@";
}

done_testing;
