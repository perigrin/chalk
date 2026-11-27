# ABOUTME: A sub call among the items of a hash literal is called for a list: its values are as many
# ABOUTME: items as it returns, none for `return` or `()`. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Fifth final audit, Q16: `sub f { return } my %h = (a => f(), b => 1)` gave
# {a => undef, b => 1} for perl's {a => "b", 1 => undef}: T2 took a call a
# hash literal holds for one scalar (its use counted as a scalar's), whatever
# it returned. And `$x ? ($x) : ()` returned in a list was one item either way.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

my $show = q{print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";};
for my $src (
    qq{sub f { return } my %h = (a => f(), b => 1); $show},                     # vs120
    qq{sub f { () } my %h = (a => f(), b => 1); $show},                         # vs126
    qq{sub f { my \@e; \@e } my %h = (a => f(), b => 1); $show},                # vs128
    qq{sub f { return (1, 2) } my %h = (a => f(), b => 1); $show},              # vs132
    qq{sub f { return unless \$_[0]; 5 } my %h = (a => f(0), b => f(1)); $show},   # vs131
    qq{sub f { 7 } my %h = (a => f(), b => 1); $show},
    q{sub f { return } my $r = {a => f(), b => 1}; print join(",", map { "$_=" . ($r->{$_} // "u") } sort keys %$r), "\n";},   # vs133
) {
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}
# (a sub returning a choice of a list and a value: refused by name)
for my $src (
    q{sub f { my $x = shift; $x ? ($x) : () } my @l = (f(0), f(2), f(0)); print "@l\n";},                                  # vs149
    q{sub f { my $x = shift; $x ? ($x) : () } my $s = f(0); print defined $s ? "d" : "u", "\n";},
) {
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'REFUSED', "refused: $src" );
    like( $why, qr/returns a choice of a list and a value/, '...by name' );
}

done_testing;
