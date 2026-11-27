# ABOUTME: `@$r` or `@{$h{a}}` as an item of a list a `my` array or hash is made from is its elements
# ABOUTME: where the item stands, not where the list is first used. B::SoN -> chalk -> lli == perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);
use Chalk::CodeGen::Harness::AuditProbe qw(run_probe);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

# Fifth final audit, Q13: `my %h = (a=>[1,2]); my @l = (@{$h{a}}, 0); push
# @{$h{a}}, 3; print "@l\n"` printed `1 2 3 0` for `1 2 0`. B::SoN pins the
# deref (it may die) and names its version; T2 made it there as the array
# itself, and the list flattened it where the list was first used, after the push.
sub verdict ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src;
    close $fh;
    return run_probe($pl);
}

for my $src (
    q{my %h = (a=>[1,2]); my @l = (@{$h{a}}, 0); push @{$h{a}}, 3; print "@l\n";},                                       # vq49
    q{my $o = [1]; sub c { push @$o, 9; 0 } my @l = (@$o, c()); print "@l\n";},                                          # vq43
    q{my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); $h{a}[0] = 9; print "@l\n";},                                          # vq53
    q{my %h = (a=>[1,2]); my @l = (@{$h{a}}, "x"); pop @{$h{a}}; print "@l\n";},                                          # vq55
    q{my %h = (a=>[1,2], b=>{c=>3}); my @l = (@{$h{a}}, %{$h{b}}); push @{$h{a}}, 3; print "@l\n";},                      # vq52
    q{my %h = (a=>[1,2]); my @l = (@{$h{a}}, scalar(@{$h{a}})); push @{$h{a}}, 3; print "@l\n";},                         # vq77
    q{my %h = (a=>[1,2]); my @l = (@{$h{a}}); push @{$h{a}}, 3; print "@l\n";},
    q{my $r = [1,2]; my @l = (@$r, 0); push @$r, 3; print "@l\n";},
) {
    my ( $v, $why ) = verdict($src)->@*;
    is( $v, 'SAME', "perl's answer: $src" ) or diag $why;
}

done_testing;
