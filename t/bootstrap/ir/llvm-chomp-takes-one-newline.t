# ABOUTME: chomp is its string without one trailing newline (its value: how many it took),
# ABOUTME: chop without its last character: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

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


# Chomp had no lowering (pvm 137).
for my $c (
    [ q{use v5.42; no warnings; sub g ($x) { die "bad $x\n" if $x > 1; return $x } sub h ($x) { my $r = "n"; try { g($x); } catch ($e) { chomp $e; $r = "c:$e"; } return $r } $@ = "before"; print h(1), " ", h(2), " [$@]\n";} ],
    # chop's value is the character it took off, not a count (final audit, class F)
    [ q{my $s="abc"; my $c=chop $s; print "$c $s\n";} ],
    [ q{my $s="ab\n"; my $c=chomp($s); my $d=chop($s); print "$c$d$s\n";} ],
    [ q{my $s="abc"; my $o=""; while (length $s) { $o.=chop $s; } print "$o [$s]\n";} ],
    [ q{our $s="abc"; my $c=chop $s; print "$c $s\n";} ],
    [ q{my $s="x"; my $c=chop $s; my $d=chop $s; print "[$c][$d][$s]\n";} ],
) {
    my ($src) = @$c;
    my $want = qx($^X -e '$src');
    my $got = eval { through_llvm($src) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
