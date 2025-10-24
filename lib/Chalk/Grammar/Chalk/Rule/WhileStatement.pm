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

        # Track variables modified in loop for phi node generation
        # Save scope state before loop (for future phi node implementation)
        # my $scope_before_loop = $builder->scope;

        # Wire up body statements with IfTrue control
        # Track break and continue exits
        my @break_controls;
        my @continue_controls;
        my $current_ctrl = $if_true->id;

        for my $stmt ($body_block->{statements}->@*) {
            # Check if this is a break or continue metadata hash
            if (ref($stmt) eq 'HASH') {
                if ($stmt->{type} eq 'break') {
                    push @break_controls, $current_ctrl;
                    next;  # Don't advance control - this path exits loop
                } elsif ($stmt->{type} eq 'continue') {
                    push @continue_controls, $current_ctrl;
                    next;  # Don't advance control - this path jumps to loop start
                }
            }

            # Regular statement - wire control if needed
            if (blessed($stmt) && $stmt->can('inputs')) {
                if ($stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                    $builder->set_node_control($stmt, $current_ctrl);
                }
                $current_ctrl = $stmt->id;  # Next statement uses this as control
            }
        }

        # Build backedge: merge normal end-of-body + continue paths
        my @backedge_controls = ($current_ctrl, @continue_controls);
        if (@backedge_controls > 1) {
            # Multiple paths back to loop - need Region
            my $backedge_region = $builder->build_region_node(@backedge_controls);
            push $loop->inputs->@*, $backedge_region->id;
        } elsif (@backedge_controls == 1) {
            # Single path back
            push $loop->inputs->@*, $backedge_controls[0];
        }
        # If no backedge controls, loop has no normal exit (only break)

        # Build exit region: merge IfFalse (normal exit) + break paths
        my @exit_controls = ($if_false->id, @break_controls);
        my $exit_region;
        if (@exit_controls > 1) {
            $exit_region = $builder->build_region_node(@exit_controls);
        } else {
            $exit_region = $builder->build_region_node($exit_controls[0]);
        }
        $builder->set_control($exit_region->id);

        # TODO: Create loop phi nodes for variables modified in loop
        # Future implementation will:
        #   1. Track which variables are modified within the loop body
        #   2. For each modified variable, create a Loop Phi node at loop entry
        #   3. Wire phi inputs: [loop_control, initial_value, loop_value]
        #   4. Update scope to use phi nodes for those variables within loop

        return $exit_region;
    }
}

1;
