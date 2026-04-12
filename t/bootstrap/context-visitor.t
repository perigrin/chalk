# ABOUTME: Tests for Context visitor methods: walk, walk_all, walk_acc.
# ABOUTME: RED phase — these tests must fail until the methods are implemented.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';
use Chalk::Bootstrap::Context;
use Scalar::Util 'refaddr';

# Build the standard test tree used by most subtests:
#
#   multiply (focus=undef)
#   ├── leaf_a (focus="alpha", rule="Scan")
#   └── multiply (focus=undef)
#       ├── leaf_b (focus="beta",  rule="Scan")
#       └── leaf_c (focus="gamma", rule="Complete")
sub build_tree {
    my $leaf_a = Chalk::Bootstrap::Context->new(
        focus    => "alpha",
        rule     => "Scan",
        position => 0,
    );
    my $leaf_b = Chalk::Bootstrap::Context->new(
        focus    => "beta",
        rule     => "Scan",
        position => 1,
    );
    my $leaf_c = Chalk::Bootstrap::Context->new(
        focus    => "gamma",
        rule     => "Complete",
        position => 2,
    );
    my $inner = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$leaf_b, $leaf_c],
        position => 1,
    );
    my $root = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$leaf_a, $inner],
        position => 0,
    );
    return ($root, $leaf_a, $leaf_b, $leaf_c, $inner);
}

subtest 'walk finds first matching leaf' => sub {
    my ($root) = build_tree();
    my $result = $root->walk(sub ($n) { $n->extract() });
    is $result, "alpha", 'walk returns the first focused leaf value (left-to-right)';
};

subtest 'walk with predicate returns first match' => sub {
    my ($root) = build_tree();
    my $result = $root->walk(sub ($n) {
        my $f = $n->extract();
        $n->rule() eq 'Complete' ? $f : undef;
    });
    is $result, "gamma", 'walk skips non-matching leaves and returns first match';
};

subtest 'walk returns undef when no match' => sub {
    my ($root) = build_tree();
    my $result = $root->walk(sub ($n) { undef });
    is $result, undef, 'walk returns undef when callback never returns a defined value';
};

subtest 'walk with reverse finds rightmost first' => sub {
    my ($root) = build_tree();
    my $result = $root->walk(sub ($n) { $n->extract() }, reverse => true);
    is $result, "gamma", 'walk with reverse => true returns rightmost leaf first';
};

subtest 'walk_all collects all results' => sub {
    my ($root) = build_tree();
    my @results = $root->walk_all(sub ($n) { $n->extract() });
    is_deeply \@results, ["alpha", "beta", "gamma"],
        'walk_all returns all focused leaf values in left-to-right order';
};

subtest 'walk_all with filter' => sub {
    my ($root) = build_tree();
    my @results = $root->walk_all(sub ($n) {
        my $f = $n->extract();
        $n->rule() eq 'Scan' ? $f : undef;
    });
    is_deeply \@results, ["alpha", "beta"],
        'walk_all with filter returns only matching leaves';
};

subtest 'walk_all with reverse' => sub {
    my ($root) = build_tree();
    my @results = $root->walk_all(sub ($n) { $n->extract() }, reverse => true);
    is_deeply \@results, ["gamma", "beta", "alpha"],
        'walk_all with reverse => true returns leaves right-to-left';
};

subtest 'walk_acc accumulates' => sub {
    my ($root) = build_tree();
    my $result = $root->walk_acc('', sub ($acc, $n) { $acc . $n->extract() });
    is $result, "alphabetagamma",
        'walk_acc threads accumulator through all focused leaves left-to-right';
};

subtest 'walk_acc with reverse' => sub {
    my ($root) = build_tree();
    my $result = $root->walk_acc('', sub ($acc, $n) { $acc . $n->extract() }, reverse => true);
    is $result, "gammabetaalpha",
        'walk_acc with reverse => true accumulates right-to-left';
};

subtest 'walk on a single focused node (no children)' => sub {
    my $leaf = Chalk::Bootstrap::Context->new(
        focus    => "solo",
        rule     => "Scan",
        position => 0,
    );
    my $result = $leaf->walk(sub ($n) { $n->extract() });
    is $result, "solo", 'walk on a leaf node returns its focus value';
};

subtest 'walk does not recurse into focused nodes children' => sub {
    # A focused node with children that also have focuses.
    # walk should return the parent focused node, not descend into its children.
    my $inner_child = Chalk::Bootstrap::Context->new(
        focus    => "inner",
        rule     => "Scan",
        position => 1,
    );
    my $outer = Chalk::Bootstrap::Context->new(
        focus    => "outer",
        rule     => "Complete",
        position => 0,
        children => [$inner_child],
    );
    my $root = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$outer],
        position => 0,
    );
    my @results = $root->walk_all(sub ($n) { $n->extract() });
    is_deeply \@results, ["outer"],
        'walk stops at focused node and does not recurse into its children';
};

done_testing();
