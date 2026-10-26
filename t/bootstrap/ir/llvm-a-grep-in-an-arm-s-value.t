# ABOUTME: an arm whose value is made by a loop (a grep, a map) inside it: the loop is
# ABOUTME: lowered where the arm's value is: B::SoN -> chalk -> lli == perl.
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

# A loop's phi has the loop for its region, not a Region with a head: read
# from an arm's value (a slice by a grep), the loop was not driven from it --
# "Phi node encountered ... before its enclosing structure" (pvm 220).
for my $c (
    [ q{sub mk { my ($op, @in) = @_; { op => $op, in => [@in] } } sub operation { $_[0]{op} } sub inputs { $_[0]{in} } sub f { my ($c) = @_; my $op = operation($c); my @in = inputs($c)->@*; my @e;   if ($op eq "A") { @e = @in } elsif ($op eq "H") { @e = @in[ grep { $_ % 2 } 0 .. $#in ] } else { return "u" } return "@e" } print f(mk("A", 1, 2)), "|", f(mk("H", "k", 1, "j", 2)), "|", f(mk("X")), "\n"; } ],
    [ q{my @in = qw(a b c d); my $c = $ENV{NOPE} ? 0 : 1; my @e = (); if ($c) { @e = @in[ grep { $_ % 2 } 0 .. $#in ] } print "@e\n";} ],
    [ q{my @in = (1, 2, 3); my @e; if (@in > 2) { @e = map { $_ * 2 } @in } else { @e = (0) } print "@e\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

# A LOOP NOT MADE YET is not driven from an early read of its phi: run out of
# place and again in place, its pushes ran twice ("A A C A C" for "A C").
# Perl's answer, or refused.
{
    my $src = q{my @dead; for my $k (qw(a b c)) { push @dead, $k unless $k eq "b" } my @got; for my $d (@dead) { push @got, uc $d } print "@got\n";};
    my $got = eval { through_llvm($src) };
    if (defined $got) { is($got, qx($^X -e '$src'), "perl's answer: $src") }
    else { like($@, qr/\S/, "refused: $src") }
}

done_testing;
