# ABOUTME: Semantic action for ShiftOp - bitwise shift operators
# ABOUTME: Handles << and >> operators with precedence validated by Precedence semiring

use 5.42.0;
use experimental 'class';
use utf8;
use Chalk::IR::Node::BitShiftLeft;
use Chalk::IR::Node::BitShiftRight;

class Chalk::Grammar::Chalk::Rule::ShiftOp :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # Grammar is: ShiftOp -> Expression WS_OPT %SHIFT_OP% WS_OPT Expression

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
        my $operator;

        # Find the << or >> operator by scanning children
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);
            if ($child isa Chalk::Grammar::Token::Operator) {
                my $op_str = "$child";
                if ($op_str eq '<<' || $op_str eq '>>') {
                    $operator = $op_str;
                    $operator_idx = $i;
                    last;
                }
            }
        }

        unless (defined $operator_idx) {
            my @children_debug = map { defined $_ ? "$_" : '<undef>' } @{$context->children};
            die "ShiftOp matched but no << or >> operator found in children: [@children_debug]";
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
            die "ShiftOp found $operator at index $operator_idx but missing operands: "
                . "left=" . (defined $left ? $left->id : '<undef>') . ", "
                . "right=" . (defined $right ? $right->id : '<undef>') . ", "
                . "children=[@children_debug]";
        }

        if ($operator eq '<<') {
            return Chalk::IR::Node::BitShiftLeft->new(
                left  => $left,
                right => $right
            )->peephole();
        }
        else {
            return Chalk::IR::Node::BitShiftRight->new(
                left  => $left,
                right => $right
            )->peephole();
        }
    }
}

1;
