# ABOUTME: Semantic action for BitwiseOrOp - bitwise OR operator
# ABOUTME: Handles | operator with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';
use utf8;
use Chalk::IR::Node::BitOr;

class Chalk::Grammar::Chalk::Rule::BitwiseOrOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # Grammar is: BitwiseOrOp -> Expression WS_OPT %BITWISE_OR_OP% WS_OPT Expression

        # PRECEDENCE CHECK
        my $composite_elem = $context->metadata_element;
        if ($composite_elem && $composite_elem->can('elements')) {
            my @elements = $composite_elem->elements->@*;
            for my $elem (@elements) {
                if ($elem->can('valid') && !$elem->valid) {
                    return;
                }
            }
        }

        my $num_children = scalar(@{$context->children});
        my $operator_idx;

        # Find the | operator by scanning children
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);
            if ($child isa Chalk::Grammar::Token::Operator) {
                my $op_str = "$child";
                if ($op_str eq '|') {
                    $operator_idx = $i;
                    last;
                }
            }
        }

        unless (defined $operator_idx) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } @{$context->children};
            die "BitwiseOrOp matched but no | operator found in children: [@children_debug]";
        }

        # Extract left operand (first IR node before operator)
        my $left;
        for my $i (0 .. $operator_idx - 1) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $left = $child;
                last;
            }
        }

        # Extract right operand (first IR node after operator)
        my $right;
        for my $i ($operator_idx + 1 .. $num_children - 1) {
            my $child = $context->child($i);
            if (ref($child) && $child->can('id')) {
                $right = $child;
                last;
            }
        }

        unless ($left && $right) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } @{$context->children};
            die "BitwiseOrOp found | at index $operator_idx but missing operands: "
                . "left=" . (defined $left ? $left->id : '<undef>') . ", "
                . "right=" . (defined $right ? $right->id : '<undef>') . ", "
                . "children=[@children_debug]";
        }

        return Chalk::IR::Node::BitOr->new(
            left  => $left,
            right => $right
        )->peephole();
    }
}

1;
