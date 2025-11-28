# ABOUTME: Semantic action for RangeOp - range and flip-flop operator
# ABOUTME: Handles '..' (range in list context, flip-flop in scalar context) with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::RangeOp :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node;
    

    method evaluate($context) {
        # RangeOp -> Expression WS_OPT '..' WS_OPT Expression

        # For binary operation: check child(2) for the operator
        # Grammar is: Expression WS_OPT '..' WS_OPT Expression
        # So operator is at index 2
        my @children = $context->children->@*;
        return $context->child(0) unless defined $children[2];
        my $op_child = $children[2]->extract;
        return $context->child(0) unless defined $op_child;

        # Stringify operator (may be Token object or plain string)
        my $operator = "$op_child";
        return $context->child(0) unless $operator eq '..';

        # Get left (child 0) and right (child 4)
        my $left = $context->child(0);
        my $right = $context->child(4);

        # Validate that we got IR nodes
        return $left unless (ref($left) && $left->can('id'));
        return $left unless (ref($right) && $right->can('id'));

        # Create Range node directly
        # Note: In Perl, .. is a range operator in list context and
        # a flip-flop operator in scalar/boolean context
        my $start_ref = { op => 'NodeRef', node_id => $left->id };
        my $end_ref   = { op => 'NodeRef', node_id => $right->id };

        my $attributes = {
            start => $start_ref,
            end   => $end_ref,
            type  => 'list',
        };

        my $node_id = "range_" . $left->id . "_" . $right->id . "_list";
        return Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'Range',
            inputs     => [ $left->id, $right->id ],
            attributes => $attributes,
        );
    }
}

1;
