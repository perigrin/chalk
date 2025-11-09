# ABOUTME: Semantic action for ConditionalStatement - builds If/IfTrue/IfFalse/Region IR structure
# ABOUTME: Handles if/elsif/else control flow with proper Region merging and Phi nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ConditionalStatement :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        # ConditionalStatement has several alternatives:
        # 1. if (expr) block
        # 2. if (expr) block else block
        # 3. if (expr) block elsif (expr) block
        # 4. if (expr) block elsif (expr) block else block

        # NOTE: This uses a "placeholder control" pattern to work around bottom-up parsing.
        # Child statements (like Return) create nodes with placeholder control inputs.
        # This semantic action then wires up the actual control edges by:
        # 1. Getting Block metadata (statements array with placeholder control)
        # 2. Replacing placeholders with actual control nodes (IfTrue/IfFalse)
        # 3. Building Region to merge control paths

        my @children = $context->children->@*;
        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Save current control
        my $entry_control = $builder->current_control;

        # Find 'if' keyword position (should be at start)
        my $keyword_index = 0;

        # Parse: ConditionalKeyword WS_OPT ( WS_OPT Expression WS_OPT ) WS_OPT Block
        # Actual children after parsing with semantic actions:
        # Indices: 0                  1      2   3      4          5      6   7      8
        # child[0] is ConditionalKeyword, child[4] is Expression, child[8] is Block

        my $condition = $context->child(4);  # Expression node
        return undef unless (blessed($condition) && $condition->can('id'));

        # Build If node
        my $if_node = $builder->build_if_node($condition);
        my $if_true = $builder->build_if_true_node($if_node);
        my $if_false = $builder->build_if_false_node($if_node);

        # Start tracking variable modifications in branches
        $builder->begin_branch_tracking('true', 'false');

        # Evaluate true branch with tracking
        $builder->set_branch('true');
        my $true_block = $context->child(8);
        return undef unless (ref($true_block) eq 'HASH' && $true_block->{type} eq 'block');

        # Wire up true branch statements with IfTrue control
        my $current_ctrl = $if_true->id;
        for my $stmt ($true_block->{statements}->@*) {
            if ($stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                $builder->set_node_control($stmt, $current_ctrl);
            }
            $current_ctrl = $stmt->id;  # Next statement uses this as control
        }
        my $true_control = $current_ctrl;

        # Check for else/elsif
        my $false_control;

        if (@children > 10) {
            my $next_keyword = $children[10]->extract;
            if (defined($next_keyword) && $next_keyword eq 'else') {
                # Evaluate false branch with tracking
                $builder->set_branch('false');

                # Get else block and wire up with IfFalse control
                my $else_block = $context->child(12);
                if (ref($else_block) eq 'HASH' && $else_block->{type} eq 'block') {
                    $current_ctrl = $if_false->id;
                    for my $stmt ($else_block->{statements}->@*) {
                        if ($stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                            $builder->set_node_control($stmt, $current_ctrl);
                        }
                        $current_ctrl = $stmt->id;
                    }
                    $false_control = $current_ctrl;
                } else {
                    $false_control = $if_false->id;
                }
            }
            else {
                # No else - false path just falls through
                $false_control = $if_false->id;
            }
        }
        else {
            # No else branch - false path just falls through
            $false_control = $if_false->id;
        }

        # Build Region to merge control paths
        my $region = $builder->build_region_node($true_control, $false_control);
        $builder->set_control($region->id);

        # End tracking and generate Phi nodes for modified variables
        my $tracking_data = $builder->end_branch_tracking();
        my $phi_nodes = $builder->generate_phi_nodes($region, $tracking_data, 'true', 'false');

        # Return the Region node (represents the merge point)
        return $region;
    }
}

1;
