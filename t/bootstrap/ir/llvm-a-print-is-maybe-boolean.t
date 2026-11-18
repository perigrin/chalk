# ABOUTME: a Print stamped Maybe[Boolean] (perl's print: true, or undef when it fails)
# ABOUTME: is kept by the loader and lowered as perl answers through T2, or refused by its reason.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;
require Chalk::CodeGen::Pipeline;

sub run ($cmd) {
    my $out = qx($cmd 2>/dev/null);
    return $out . 'exit ' . ( $? >> 8 );
}

# T2 REFUSES THESE, by its reason (only the retired fallback lowered them):
# the value of a print to a handle opened nowhere, read. Never a wrong answer.
my %T2_REFUSES = map { ( $_ => 'a print to a handle opened nowhere, its value read' ) } (
    q{my $r = print NOWHERE "x"; print defined $r && $r ? "t" : "f", "\n";},
    q{my $r = print NOWHERE "x"; print defined($r) ? "d" : "u", "\n";},
    q{my $r = print NOWHERE "x"; my $x = defined $r && $r; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print NOWHERE "x"; my $x = defined $r ? $r : !1; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print NOWHERE "x"; if (defined $r) { print "[$r]\n" } print "end\n";},
    q{my $r = print NOWHERE "x"; my $x = !defined $r || $r; print defined($x) ? "d" : "u", "[$x]\n";},
);

for my $src (
    q{my $ok = print "x\n"; print "[$ok]\n";},
    q{my $r = print NOWHERE "x"; print defined $r && $r ? "t" : "f", "\n";},
    q{my $r = print NOWHERE "x"; print defined($r) ? "d" : "u", "\n";},
    q{my $n = print("a") + 1; print "$n\n";},
    q{print "x" and print "y\n";},
    q{my $ok = print ""; print $ok ? "yes\n" : "no\n";},
    # a defined guard narrows its arm (B::SoN stamps these Boolean)
    q{my $r = print NOWHERE "x"; my $x = defined $r && $r; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print ""; my $x = defined $r && $r; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print NOWHERE "x"; my $x = defined $r ? $r : !1; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print ""; my $x = defined $r ? $r : !1; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print NOWHERE "x"; if (defined $r) { print "[$r]\n" } print "end\n";},
    q{my $r = print ""; if (defined $r) { print "[$r]\n" } print "end\n";},
    q{my $r = print NOWHERE "x"; my $x = !defined $r || $r; print defined($x) ? "d" : "u", "[$x]\n";},
    q{my $r = print ""; my $x = !defined $r || $r; print defined($x) ? "d" : "u", "[$x]\n";},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) { my $g = $graphs->{'main::__PROGRAM__'} or return (); ([ 'main::__PROGRAM__', $g->returns->[0] ]) };
    my ($units, $graphs, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    my @prints = grep { $_->operation eq 'Print' } map { $_->nodes->@* } values %{ $graphs // {} };
    ok( @prints && !grep( { ( $_->stamp // '' ) ne 'Maybe[Boolean]' } @prints ), "$src: the loader keeps Maybe[Boolean]" );
    my $ll = !$err && $units->[0]{ok} ? $units->[0]{ll} : undef;
    if (my $why = $T2_REFUSES{$src}) {
        ok(!defined $ll, "$src: T2 lowers no module for it");
        like($err // $units->[0]{err} // '', qr/GAP: T2: out of its slices \(\Q$why\E\)/, "$src: refused by T2's reason");
        next;
    }
    ok(defined $ll, "$src: lowered") or diag $err // $units->[0]{err};
    next unless defined $ll;
    my ($lf, $llp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $ll; close $lf;
    is( run("timeout 20 $LLI $llp"), run("$^X $pl"), "$src: perl's answer" );
}

done_testing;
