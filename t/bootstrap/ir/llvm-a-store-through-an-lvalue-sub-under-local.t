# ABOUTME: `f() = v` through an :lvalue sub that returns a package scalar stores into the scalar the
# ABOUTME: name holds where the store runs -- a `local`'s or a glob bind's. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Fifth final audit, Q9: `our $x = 1; sub f :lvalue { $x } { local $x = 2;
# f() = 5; print $x } print "$x\n"` printed `25` for `51`: the store went to
# the scalar the name held before the `local`, by its static address.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $src (
    q{our $x = 1; sub f :lvalue { $x } { local $x = 2; f() = 5; print $x } print "$x\n";},             # va69, vm63
    q{our $x = 1; sub f :lvalue { $x } sub g { local $x = 2; f() = 5; $x } print g(), "$x\n";},        # vm66
    q{our $x = 1; sub f :lvalue { $x } { local $x; f() = 5; } print "$x\n";},                          # vm69
    q{our $x = 1; sub f :lvalue { $x } f() = 5; print "$x\n";},
) {
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}
# (a glob bind of the name: perl's answer, or refused by name -- never another)
for my $src ( q{our $x = 1; our $y = 2; *x = \$y; sub f :lvalue { $x } f() = 5; print "$x$y\n";} ) {
    like( verdict($src)->[0], qr/\A(?:SAME|REFUSED)\z/, "not wrong: $src" );
}

done_testing;
