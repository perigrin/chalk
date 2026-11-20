# ABOUTME: Scalar::Util's reftype: what a reference refers to, whatever it is blessed into,
# ABOUTME: and undef for what is no reference: B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# REFTYPE WAS NOT LOWERED AT ALL ("Call builtin reftype", audit probe cr3).
# It is ref() with the class taken away: ARRAY for `bless [], "K"`, where
# ref() says K. A bless does not change it, so it is no read of the class;
# it still carries the memory version B::SoN reads it at, which is not an
# operand.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $case (
    [ q{use Scalar::Util "reftype"; print reftype(bless [], "K"), "\n";}, 'a blessed array' ],
    [ q{use Scalar::Util qw(reftype); my $h = {}; my $a = [1]; my $c = sub { 1 }; my $x = 1; my $s = \$x; print join(" ", reftype($h), reftype($a), reftype($c), reftype($s)), "\n";},
        'a hash, an array, a sub, a scalar' ],
    [ q{use Scalar::Util qw(reftype); my $n = 5; my $t = "s"; print defined reftype($n) ? "d" : "u", defined reftype($t) ? "d" : "u", defined reftype(undef) ? "d" : "u", "\n";},
        'no reference: undef' ],
    [ q{use Scalar::Util qw(reftype); my $v = @ARGV ? [] : "plain"; my $k = reftype($v) // "none"; print "$k\n";}, 'undef falls to a //' ],
    [ q{use Scalar::Util qw(blessed reftype); my $o = []; my $a = blessed($o) // "u"; my $t = reftype($o); bless $o, "K"; print "$a $t ", blessed($o), " ", reftype($o), "\n";},
        'either side of a bless (cr3)' ],
    [ q{use Scalar::Util qw(reftype); package P { sub new { bless { k => 1 }, shift } } my $o = P->new; print ref($o), " ", reftype($o), " ", (reftype($o) eq "HASH" ? "is" : "not"), "\n";},
        'an object: its class and its kind' ],
    [ q{use Scalar::Util qw(reftype); my $x = 1; my $r = \$x; my $rr = \$r; print reftype($rr), " ", reftype($r), " ", ref($rr), " ", ref($r), "\n";},
        'a reference to a reference is a REF, to reftype and to ref' ],
    [ q{use Scalar::Util qw(reftype); my $q = qr/a+/; print reftype($q), " ", ref($q), "\n";}, 'a qr// is a REGEXP' ],
    [ q{use Scalar::Util qw(reftype); sub kind { my $r = shift; return reftype($r) // "-" } print join(",", map { kind($_) } [], {}, 3, sub { 2 }), "\n";},
        'in a sub, over a list' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "$what: perl's output" ) or diag "$v $why";
}

done_testing;
