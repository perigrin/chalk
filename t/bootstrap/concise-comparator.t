# ABOUTME: Tests for ConciseTree::Comparator structural comparison with normalization.
# ABOUTME: Covers identical trees, differing ops, normalization of pad slots and nextstate details.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::ConciseOp;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Comparator;

my $comp = Chalk::Bootstrap::ConciseTree::Comparator->new();
isa_ok($comp, 'Chalk::Bootstrap::ConciseTree::Comparator');

# Helper to build a tree from a list of [name, arity, type_info?, private?]
my sub make_tree(@specs) {
    my $tree = Chalk::Bootstrap::ConciseTree->new();
    for my $spec (@specs) {
        $tree->push_op(Chalk::Bootstrap::ConciseOp->new(
            name      => $spec->[0],
            arity     => $spec->[1],
            type_info => $spec->[2],
            private   => $spec->[3] // '',
        ));
    }
    return $tree;
}

# --- Identical trees match ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['nextstate', ';', 'main 3 -e:1'],
        ['const', '$', 'IV 42'],
        ['padsv_store', '1', '$x:3,4', '/LVINTRO'],
        ['leave', '@', '1 ref'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['nextstate', ';', 'main 3 -e:1'],
        ['const', '$', 'IV 42'],
        ['padsv_store', '1', '$x:3,4', '/LVINTRO'],
        ['leave', '@', '1 ref'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok($result->{match}, 'identical trees match');
    is(scalar $result->{differences}->@*, 0, 'no differences for identical trees');
}

# --- Different op count ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['leave', '@'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['stub', '0'],
        ['leave', '@'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok(!$result->{match}, 'different op count does not match');
    ok(scalar $result->{differences}->@* > 0, 'has differences');
    like($result->{differences}->[0], qr/count/i, 'difference mentions count');
}

# --- Different op names ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['const', '$', 'IV 42'],
        ['leave', '@'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['const', '$', 'PV "hello"'],
        ['leave', '@'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok(!$result->{match}, 'different const types do not match');
}

# --- Different arity ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['padsv', '0', '$x'],
        ['leave', '@'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['padsv', '1', '$x'],
        ['leave', '@'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok(!$result->{match}, 'different arity does not match');
}

# --- Normalization: pad slot numbers stripped ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['padsv_store', '1', '$x:3,4', '/LVINTRO'],
        ['leave', '@', '1 ref'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['padsv_store', '1', '$x:10,11', '/LVINTRO'],
        ['leave', '@', '2 ref'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok($result->{match}, 'pad slot numbers are normalized away');
}

# --- Normalization: nextstate details stripped ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['nextstate', ';', 'main 3 -e:1'],
        ['leave', '@'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['nextstate', ';', 'main 5 -e:2'],
        ['leave', '@'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok($result->{match}, 'nextstate details are normalized away');
}

# --- Normalization: leave ref count stripped ---
{
    my $tree1 = make_tree(
        ['enter', '0'],
        ['leave', '@', '1 ref'],
    );
    my $tree2 = make_tree(
        ['enter', '0'],
        ['leave', '@', '3 ref'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok($result->{match}, 'leave ref counts are normalized away');
}

# --- Normalization: aassign targ stripped ---
{
    my $tree1 = make_tree(
        ['aassign', '2', 't15'],
    );
    my $tree2 = make_tree(
        ['aassign', '2', 't42'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok($result->{match}, 'aassign targ numbers are normalized away');
}

# --- Private flags ARE significant ---
{
    my $tree1 = make_tree(
        ['padsv', '0', '$x'],
    );
    my $tree2 = make_tree(
        ['padsv', '0', '$x', '/LVINTRO'],
    );

    my $result = $comp->compare($tree1, $tree2);
    ok(!$result->{match}, 'private flags are structurally significant');
}

# --- Empty trees match ---
{
    my $tree1 = Chalk::Bootstrap::ConciseTree->new();
    my $tree2 = Chalk::Bootstrap::ConciseTree->new();

    my $result = $comp->compare($tree1, $tree2);
    ok($result->{match}, 'empty trees match');
}

# --- normalize returns a new tree ---
{
    my $tree = make_tree(
        ['padsv_store', '1', '$x:3,4', '/LVINTRO'],
    );
    my $normalized = $comp->normalize($tree);
    isa_ok($normalized, 'Chalk::Bootstrap::ConciseTree', 'normalize returns ConciseTree');
    is($normalized->op_count(), 1, 'normalized tree has same op count');
    # Original should be unchanged
    like($tree->ops()->[0]->type_info(), qr/:3,4/, 'original tree unchanged');
    # Normalized should have slot numbers removed
    unlike($normalized->ops()->[0]->type_info(), qr/:\d+,\d+/, 'normalized tree has no slot numbers');
}

done_testing;
