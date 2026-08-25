# ABOUTME: A DefinedOr over a statically-decided element read folds to one arm.
# ABOUTME: The proof is a Chalk IR fact, so the backend never sees the merge.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::Bootstrap::Optimizer::DefinedOrFold;

# `$a[9] // 42` on a three-element literal array is STATICALLY 42. The read
# provably misses, so the `//` has a compile-time answer and there is no merge
# to lower -- no phi to type, no arm to box or unbox, no Slot-versus-Int
# decision. The whole question disappears before the backend runs.
#
# WHY THIS IS A PASS AND NOT A LOADER FIXUP. The proof (_static_miss) reads the
# container node and the index node and answers from the graph alone: it is a
# Chalk IR fact, not a serialization or lowering concern. The loader's job is a
# well-typed graph (docs/plans/2026-08-24-loader-analysis-pipeline.md); folding
# a decided branch is an optimizer's.
#
# WHY IT MATTERS BEYOND TIDINESS. Lowering the un-folded merge means reconciling
# a %Slot arm with an i64 arm, and there are only three ways to do that:
#
#   (1) unbox the Slot to the other arm's type -- requires knowing the payload
#       type AND that the payload really is that type. The Slot node carries
#       neither, so this is the one option that can be WRONG. Measured: it
#       emits `phi %Str [ i64 ... ]` for a Str-element array.
#   (2) box the other arm into a %Slot -- always sound, costs a box.
#   (3) prove one arm dead and fold -- this pass.
#
# (3) is the cheapest and is available whenever the index is a literal over a
# literal aggregate, which is every such case in the corpus today.

sub build_case ($index_value, @elements) {
    my $f = Chalk::IR::NodeFactory->new;
    my @elems = map {
        my $n = $f->make('Constant', value => $_, const_type => 'integer');
        $n->set_representation('Int');
        $n;
    } @elements;

    my $arr = $f->make('ArrayRef', inputs => [@elems]);
    $arr->set_representation('ArrayRef');

    my $idx = $f->make('Constant', value => $index_value, const_type => 'integer');
    $idx->set_representation('Int');

    my $sub = $f->make('Subscript', inputs => [$arr, $idx]);

    my $rhs = $f->make('Constant', value => '42', const_type => 'integer');
    $rhs->set_representation('Int');

    my $dor = $f->make('DefinedOr', inputs => [$sub, $rhs]);
    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    my $g   = Chalk::IR::Graph->new(start => $arr, returns => [$ret]);

    return ($g, $f, $dor, $sub, $rhs, @elems);
}

subtest 'a provable MISS folds to the RHS' => sub {
    # $a[9] on three elements: the read misses, so the value is the RHS.
    my ($g, $f, $dor, $sub, $rhs) = build_case('9', 1, 2, 3);
    Chalk::Bootstrap::Optimizer::DefinedOrFold->new->run($g, $f);

    my ($ret) = $g->returns->@*;
    is $ret->inputs->[0]->id, $rhs->id,
        'the Return now reads the RHS directly';
    isnt $ret->inputs->[0]->operation, 'DefinedOr',
        'the merge is gone, not merely retyped';
};

subtest 'a provable HIT folds to the element' => sub {
    # $a[1] on three elements: the read succeeds, so the RHS is dead. The
    # OTHER polarity -- a fold that only handled misses would silently leave
    # this one to the backend, which is where the unsound unboxing lives.
    my ($g, $f, $dor, $sub, $rhs, @elems) = build_case('1', 1, 2, 3);
    Chalk::Bootstrap::Optimizer::DefinedOrFold->new->run($g, $f);

    my ($ret) = $g->returns->@*;
    is $ret->inputs->[0]->id, $elems[1]->id,
        'the Return reads element 1 directly';
};

subtest 'a DYNAMIC index is left alone' => sub {
    # No proof, no fold. The merge survives for the backend to lower -- by
    # boxing, per (2). Folding here would be inventing a decision.
    my $f = Chalk::IR::NodeFactory->new;
    my @elems = map {
        my $n = $f->make('Constant', value => $_, const_type => 'integer');
        $n->set_representation('Int'); $n;
    } (1, 2, 3);
    my $arr = $f->make('ArrayRef', inputs => [@elems]);
    $arr->set_representation('ArrayRef');

    # A PadAccess index is not a Constant, so nothing is statically decidable.
    my $idx = $f->make('PadAccess', targ => 1, varname => '$i', inputs => []);
    $idx->set_representation('Int');

    my $sub = $f->make('Subscript', inputs => [$arr, $idx]);
    my $rhs = $f->make('Constant', value => '42', const_type => 'integer');
    $rhs->set_representation('Int');
    my $dor = $f->make('DefinedOr', inputs => [$sub, $rhs]);
    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    my $g   = Chalk::IR::Graph->new(start => $arr, returns => [$ret]);

    Chalk::Bootstrap::Optimizer::DefinedOrFold->new->run($g, $f);

    is $g->returns->[0]->inputs->[0]->operation, 'DefinedOr',
        'the merge survives when nothing was proven';
};

subtest 'the pass declares its contract' => sub {
    my $p = Chalk::Bootstrap::Optimizer::DefinedOrFold->new;
    is $p->name,  'DefinedOrFold', 'it names itself';
    is $p->scope, 'graph',         'it operates per graph';
};

done_testing;
