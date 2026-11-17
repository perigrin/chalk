# ABOUTME: A call perl's own op calls in scalar context (B::SoN's want=scalar) is a scalar
# ABOUTME: wherever B::SoN folded its value: `my $l = $n->name; push @f, $l` pushes one value.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

my @same = (
    [ q{package Node { sub new { my ($c, %a) = @_; bless {%a}, $c } sub kind { $_[0]{kind} } sub owner { $_[0]{owner} } sub name { $_[0]{name} } } sub matching { my ($loop, $nodes) = @_; my @found; for my $n (@$nodes) { next unless defined $n && $n->can('kind'); next unless $n->kind eq 'Phi'; my $owner = $n->owner; next unless defined $owner && $owner->name eq $loop->name; my $label = $n->name; if (defined $label) { push @found, $label; } } return join(",", @found); } my $loop = Node->new(name => 'L'); my @nodes = (Node->new(kind => 'Phi', owner => $loop, name => 'a'), undef, Node->new(kind => 'X'), Node->new(kind => 'Phi', owner => Node->new(name => 'M'), name => 'b'), Node->new(kind => 'Phi', owner => $loop)); print matching($loop, \@nodes), "\n";},
      'a method value tested and pushed' ],
    [ q{package N { sub new { bless { n => $_[1] }, $_[0] } sub name { $_[0]{n} } } my @f; for my $n (N->new("a"), N->new(undef), N->new("b")) { my $l = $n->name; push @f, $l if defined $l; push @f, length($l // "") } print "@f\n";},
      'a method value pushed and measured' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

done_testing;
