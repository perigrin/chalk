# ABOUTME: `local @a` / `local %h` swap the aggregate the name holds: a read of the name is of the one
# ABOUTME: it holds where the read runs, a reference keeps the one it was taken of. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Fifth final audit, Q7: `our %h = (a=>1); { local %h = (b=>2); print keys %h }
# print keys %h` printed `b;b` for `b;a` -- the read of %h's name, made once
# (memoized) inside the scope, was the second read too; and `my $r = \@a`
# before `local @a` referred to the local's array, the reference made where
# it was first used (`3;3` for `1 2 3;1 2 3`).
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

# (lowered: perl's answer)
for my $src (
    q{our %h = (a=>1); { local %h = (b=>2); print join(",", sort keys %h), ";" } print join(",", sort keys %h), "\n";},   # va04
    q{our %h = (a=>1); { local %h; print scalar(keys %h); $h{b} = 1 } print join(",", sort keys %h), "\n";},             # va58
    q{our @a = (1,2,3); sub f { local @a = @a[0,1]; push @a, 9; "@a" } print f(), "|@a\n";},                            # va13
    q{our %h = (a=>1); { local %h = (%h, b=>2); print scalar(keys %h) } print scalar(keys %h), "\n";},                   # vm07
    q{our @a = (1,2); { local @a = (3); print "@a;" } print "@a\n";},
) {
    is( verdict($src)->[0], 'SAME', "perl's answer: $src" );
}

# (a reference to the name's aggregate, taken where the wire does not say:
# refused by name)
for my $src (
    q{our @a = (1,2,3); my $r = \@a; { local @a = (3); print "@$r;" } print "@$r\n";},              # vm40
    q{our %h = (a=>1); my $r = \%h; { local %h = (b=>2); print join(",", keys %$r) } print join(",", keys %$r), "\n";},   # vm16
    q{our @a = (1,2,3); my $r; { local @a = (3); $r = \@a; } print "@$r|@a\n";},                     # vm42
) {
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'REFUSED', "refused: $src" );
    like( $why, qr/a reference to a package (?:array or hash|aggregate) a `local` swaps/, '...by name' );
}

done_testing;
