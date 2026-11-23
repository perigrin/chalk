# ABOUTME: Two evals whose Regions name one entry node (a try whose body begins with a try or
# ABOUTME: an eval) are refused by name: T2 keys an eval by its entry and kept only one of them.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

# RE-AUDIT 2026-11-23, section 3 H (probe red08): a try makes no node where it
# begins, so a try or an eval that begins its body is entered at the same node
# as it; Builder's eval_at, keyed by that node, kept one of the two. The
# outer catch was lost: `try { try { die "i\n" } catch ($e) { $x.=1; die "o\n"
# } } catch ($e) { $x.=2 }` died "o" where perl prints 012, and with no die at
# all `try { try { $x=1 } catch ($e) {} } catch ($e) {}` printed nothing.
my $GAP = qr/two evals entered at one node/;
for my $case (
    [ q{use feature "try"; no warnings; my $x=0; try { try { die "i\n" } catch ($e) { $x.=1; die "o\n" } } catch ($e) { $x.=2 } print "$x\n";}, $GAP, 'a catch rethrowing to an outer try' ],
    [ q{use feature "try"; no warnings; my $x=0; try { eval { die "i\n" }; $x.=1; die "o\n" } catch ($e) { $x.=2 } print "$x\n";}, $GAP, 'an eval beginning a try body' ],
    [ q{use feature "try"; no warnings; my $x=0; try { try { $x=1 } catch ($e) { $x=9 } } catch ($e) { $x.=2 } print "$x\n";}, $GAP, 'nested tries that never die' ],
    [ q{use feature "try"; no warnings; my $x=0; try { $x=5; eval { die "i\n" }; $x.=1; die "o\n" } catch ($e) { $x.=2 } print "$x\n";}, undef, 'an eval after a statement of the try body' ],
) {
    my ( $src, $name, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    if ($name) { is( $v, 'REFUSED', "$what: refused" ) or diag "$v $why"; like( $why, $name, "$what: by name" ) }
    else       { is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why" }
}

done_testing;
