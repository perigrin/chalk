# ABOUTME: The DefinedOr fold refuses any container whose elements are stored into.
# ABOUTME: Folding to a stale initializer is a WRONG answer, not a missed one (B5).

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Bootstrap::Optimizer::DefinedOrFold;

# `my @arr=(1,2); $arr[0]=99; my $v = $arr[0] // 5;` is 99 in perl.
#
# The fold proves a HIT by reading the literal aggregate's inputs -- which still
# hold the INITIALIZER 1, because a store writes memory, not the ArrayRef node.
# So the fold answered Constant(1) for a program whose value is 99: a silent
# miscompile, not a conservative miss.
#
# The store is a consumer-edge fact -- container -> Subscript consumer ->
# Assign whose inputs[0] IS that Subscript -- so the refusal needs no ordering
# assumption and no memory model. It pairs with _element_repr joining every
# store's rhs: the two read the SAME edges, and splitting them would leave the
# typing store-aware while the fold stayed initializer-only.

sub build ($store_it) {
    my $f = Chalk::IR::NodeFactory->new;
    my @elems = map {
        my $n = $f->make('Constant', value => $_, const_type => 'integer');
        $n->set_representation('Int');
        $n;
    } (1, 2);
    my $arr = $f->make('ArrayRef', inputs => [@elems]);
    $arr->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => '0', const_type => 'integer');
    $idx->set_representation('Int');

    if ($store_it) {
        # $arr[0] = 99 -- the lvalue Subscript hash-conses with the read below,
        # which is exactly why the read cannot be folded to the initializer.
        my $lv = $f->make('Subscript', inputs => [$arr, $idx]);
        $lv->set_representation('Int');
        my $v = $f->make('Constant', value => '99', const_type => 'integer');
        $v->set_representation('Int');
        my $as = $f->make('Assign', inputs => [$lv, $v]);
        $as->set_representation('Int');
    }

    my $read = $f->make('Subscript', inputs => [$arr, $idx]);
    my $rhs  = $f->make('Constant', value => '5', const_type => 'integer');
    $rhs->set_representation('Int');
    my $dor = $f->make('DefinedOr', inputs => [$read, $rhs]);
    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    my $g   = Chalk::IR::Graph->new(start => $arr, returns => [$ret]);

    Chalk::Bootstrap::Optimizer::DefinedOrFold->new->run($g, $f);
    return $g->returns->[0]->inputs->[0];
}

subtest 'a container that is stored into does NOT fold' => sub {
    my $got = build(1);
    is $got->operation, 'DefinedOr',
        'the merge stands -- the initializer is not the live value';
    isnt $got->operation, 'Constant',
        'and specifically it did not fold to Constant(1), which perl says is 99';
};

# BILATERAL: the refusal must be about the STORE, not about giving up on the
# fold. With no store the identical graph still folds -- otherwise this test
# would pass against a pass that folds nothing at all.
subtest 'the same container with no store still folds' => sub {
    my $got = build(0);
    is $got->operation, 'Constant', 'a store-free container folds as before';
    is $got->value, 1, 'to the element at index 0';
};

done_testing;
