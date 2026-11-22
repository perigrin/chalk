# ABOUTME: An object whose class may reach a DESTROY or AUTOLOAD, and a `my` aggregate a sub also
# ABOUTME: reaches read whole before a call, are refused by name, never answered wrong (audit 2026-11-22).
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# W8: the refusal matched a bless whose constant class was the DESTROY's own
# package; one reached by @ISA or AUTOLOAD printed nothing for it. W10: a
# `my` array a closure or sub also reaches, flattened beside a call that
# grows it, was read after the call.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $case (
    [ q{package B1; sub DESTROY { print "d\n" } package K; our @ISA = ("B1"); package main; { my $x = bless {}, "K"; } print "e\n";}, 'aum62: DESTROY by inheritance' ],
    [ q{package P; sub AUTOLOAD { print "auto\n" } package main; { my $x = bless {}, "P"; } print "e\n";}, 'aum61: DESTROY through AUTOLOAD' ],
    [ q{my @a=(1); my $f = sub { push @a, 2; 0 }; my @c = (@a, $f->()); print "@c\n";}, 'aum40: a closure grows it' ],
    [ q{my @a=(1); sub w { push @a, 2; 0 } my @c = (@a, w(), @a); print "@c\n";}, 'aum42: a named sub grows it' ],
    [ q{my %h=(a=>1); my $f = sub { $h{b} = 2; 0 }; my @c = (%h, $f->()); print scalar(@c), "\n";}, 'aum43: a hash' ],
) {
    my ( $src, $what ) = @$case;
    my ( $v, $why ) = verdict($src)->@*;
    like( $v, qr/\A(?:SAME|REFUSED)\z/, "$what: perl's output, or refused by name" ) or diag "$v $why";
}

done_testing;
