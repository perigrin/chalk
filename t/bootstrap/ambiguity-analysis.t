# ABOUTME: Tests for the AmbiguityAnalysis test-support module.
# ABOUTME: Validates ambiguity_sites walker and classify_site shape-based classifier.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::Boolean;
use AmbiguityAnalysis qw(ambiguity_sites classify_site);

my $sr = Chalk::Bootstrap::Semiring::Boolean->new();

# Test 1: unambiguous Context returns no sites.
# A bare one() has no children and no ambiguous annotation.
{
    my @sites = ambiguity_sites($sr->one());
    is(scalar @sites, 0, 'ambiguity_sites on one() returns empty');
}

# Test 2: zero Context returns no sites.
{
    my @sites = ambiguity_sites($sr->zero());
    is(scalar @sites, 0, 'ambiguity_sites on zero() returns empty');
}

# Test 3: non-Context input returns no sites (no die, no warning).
{
    my @sites = ambiguity_sites(undef);
    is(scalar @sites, 0, 'ambiguity_sites on undef returns empty');

    @sites = ambiguity_sites(42);
    is(scalar @sites, 0, 'ambiguity_sites on scalar returns empty');
}

# Test 4: a multiply-composed Context (two children, focus=true, NO
# ambiguous annotation) returns no sites.
{
    my $one = $sr->one();
    my $mul = $sr->multiply($one, $one);
    my @sites = ambiguity_sites($mul);
    is(scalar @sites, 0, 'ambiguity_sites on multiply(one, one) returns empty');
}

# Test 5: an add-composed Context (two non-zero children, ambiguous annotation)
# returns one site with context/left/right pointing at the wrapper and its kids.
{
    my $left  = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $right = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $amb   = $sr->add($left, $right);

    my @sites = ambiguity_sites($amb);
    is(scalar @sites, 1, 'ambiguity_sites on add(L, R) returns one site');
    is($sites[0]{context}, $amb,   'site context is the ambiguous wrapper');
    is($sites[0]{left},    $left,  'site left is the left derivation');
    is($sites[0]{right},   $right, 'site right is the right derivation');
}

# Test 6: nested ambiguity — walker descends through ambiguous nodes.
# add(add(a, b), c) should report TWO sites: the outer and the inner.
{
    my $a = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $b = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $c = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);

    my $ab  = $sr->add($a, $b);
    my $abc = $sr->add($ab, $c);

    my @sites = ambiguity_sites($abc);
    is(scalar @sites, 2, 'nested ambiguity reports two sites');
    # Outer first (root-relative pre-order); inner second.
    is($sites[0]{context}, $abc, 'first site is outer wrapper');
    is($sites[1]{context}, $ab,  'second site is inner wrapper');
}

# Test 7: ambiguity nested inside a multiply node is still discovered.
# multiply(one, add(a, b)) wraps the ambiguity inside a non-ambiguous
# structural node. The walker must descend into multiply nodes too.
{
    my $one = $sr->one();
    my $a = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $b = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $amb = $sr->add($a, $b);
    my $mul = $sr->multiply($one, $amb);

    my @sites = ambiguity_sites($mul);
    is(scalar @sites, 1, 'ambiguity_sites descends into multiply structural nodes');
    is($sites[0]{context}, $amb, 'found site is the inner add wrapper');
}

done_testing();
