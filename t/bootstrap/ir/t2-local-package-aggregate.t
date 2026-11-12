# ABOUTME: `local @a` / `local %h` through T2: the old aggregate's reference saved,
# ABOUTME: a fresh one in the global until the scope ends, the old one bound back.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $src (
    # chalk printed "5 5" for perl's "5 1" when the restore only rebound a name.
    q{our @a = (1); sub g { local @a = (5); return "@a" } print g(), " @a\n";},
    q{our @a = (1); { local @a = (5); print "@a " } print "@a\n";},
    q{our %h = (k => 1); sub g { local %h = (k => 2); return $h{k} } print g(), $h{k}, "\n";},
    # A READER IN ANOTHER SUB sees the local inside the scope, the old one after.
    q{our @a = (1, 2); sub n { scalar @a } sub g { local @a = (7); return n() } print g(), n(), "\n";},
    # A REFERENCE TO THE OLD ONE keeps its contents through the local.
    q{our @a = (1); my $r = \@a; sub g { local @a = (9); return "@$r @a" } print g(), " @a\n";},
    # Carp's shape: a local list from a call, pushed onto, read in a callee.
    q{our @L; sub c { join ",", @L } sub g { local @L = (1, 2); push @L, 3; return c() } print g(), "[", c(), "]\n";},
) {
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
