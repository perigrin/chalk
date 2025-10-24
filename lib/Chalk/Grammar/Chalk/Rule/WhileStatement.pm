# ABOUTME: Semantic action for WhileStatement - builds Loop/If/Region IR structure
# ABOUTME: Handles while loop control flow with Loop nodes, lazy phis, and backedges

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);

class Chalk::Grammar::Chalk::Rule::WhileStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # WhileStatement -> 'while' WS_OPT '(' WS_OPT Expression WS_OPT ')' WS_OPT Block
        # Actual children after parsing with semantic actions:
        # Indices: 0       1     2   3        4     5     6
        # child[3] is the Expression node, child[6] is the Block

        my @children = $context->children->@*;
        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Save entry control
        my $entry_control = $builder->current_control;

        # Create Loop node with entry control
        my $loop = $builder->build_loop_node($entry_control);

        # Set current control to Loop for condition evaluation
        $builder->set_control($loop->id);

        # Get condition expression (child 3)
        my $condition = $context->child(3);
        return undef unless (blessed($condition) && $condition->can('id'));

        # Build If node for loop condition
        my $if_node = $builder->build_if_node($condition);
        my $if_true = $builder->build_if_true_node($if_node);
        my $if_false = $builder->build_if_false_node($if_node);

        # Get loop body Block (child 6)
        my $body_block = $context->child(6);
        return undef unless (ref($body_block) eq 'HASH' && $body_block->{type} eq 'block');

        # NOTE: Assignment and VariableDeclaration now use placeholder control pattern
        # Simple assignments like "$i = 5" work correctly in loops
        # Complex assignments like "$i = $i - 1" work but may use incomplete parse
        # (SPPF creates both parses, semiring currently picks incomplete one - needs optimization pass)

        # Wire up body statements with IfTrue control
        my $current_ctrl = $if_true->id;
        for my $stmt (@{$body_block->{statements}}) {
            if ($stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                $builder->set_node_control($stmt, $current_ctrl);
            }
            $current_ctrl = $stmt->id;  # Next statement uses this as control
        }

        # Add backedge from body to Loop
        # In a real implementation, this would complete the loop
        # For now, we just note where the backedge would go
        push $loop->inputs->@*, $current_ctrl;

        # IfFalse is the loop exit - create Region or just use it directly
        # For simplicity, just use IfFalse as the exit control
        $builder->set_control($if_false->id);

        # Return a Region that represents the loop exit point
        # This allows subsequent code to continue after the loop
        my $exit_region = $builder->build_region_node($if_false->id);
        $builder->set_control($exit_region->id);

        return $exit_region;
    }
}

1;
