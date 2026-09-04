# ABOUTME: A TernaryExpr's repr is the join of its two ARMS -- the condition is
# ABOUTME: not a value the expression can yield, so it must not enter the join.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::IR::Analysis;
require Chalk::IR::Serialize::JSON;
require Chalk::IR::NodeFactory;

# `$c ? $a : $b` NEVER evaluates to `$c`. But the propagation pass collects ALL
# of a node's inputs (Serialize/JSON.pm:1537) and a TernaryExpr's inputs are
# (cond, then, else) -- documented producer-side as "inputs[1]=true,
# inputs[2]=false" (FromOptree.pm:4154). So the Boolean condition enters the join,
# and since Boolean is off the Int<:Num<:Str chain no candidate dominates:
#
#     join(Boolean, None, Int) = undef        <- what runs today
#     join(None, Int)       = Int          <- arms only
#
# The PRODUCER already gets this right: FromOptree.pm:4145 joins
# $true_val->stamp with $false_val->stamp and never the condition. This is the
# chalk loader disagreeing with the producer about the same rule.

sub ternary_with ( $cond_repr, $then_repr, $else_repr ) {
    my $f = Chalk::IR::NodeFactory->new;

    # DISTINCT values so the three Constants cannot hash-cons into one node --
    # a collapsed input list would make this test pass for the wrong reason.
    my $i  = 0;
    my @in = map {
        my $n = $f->make( 'Constant', const_type => 'integer', value => ++$i );
        $n->set_stamp($_);
        $n;
    } ( $cond_repr, $then_repr, $else_repr );

    my $t = $f->make( 'TernaryExpr', inputs => \@in );
    Chalk::IR::Analysis::_propagate_computed_reprs(
        { g => _graph_of( $t, @in ) } );
    return $t->stamp;
}

# Minimal graph wrapper: the pass walks $g->nodes.
sub _graph_of ( @nodes ) {
    require Chalk::IR::Graph;
    my $g = Chalk::IR::Graph->new;
    $g->merge($_) for @nodes;
    return $g;
}

subtest 'the condition does not enter the join' => sub {
    is ternary_with( 'Boolean', 'Int', 'Int' ), 'Int',
        'Boolean condition over two Int arms types Int, not undef';
};

subtest 'the arms still decide the type' => sub {
    is ternary_with( 'Boolean', 'Int', 'Str' ), 'Str',
        'Int|Str arms widen to Str';
};

# The g-case shape: one arm typed, one not yet inferred (a recursive Call
# seeded to the bottom type). Bottom is the join identity, so the known arm wins.
subtest 'a bottom arm contributes no constraint' => sub {
    is ternary_with( 'Boolean', 'None', 'Int' ), 'Int',
        'None|Int arms type Int -- the g-case';
};

done_testing;
