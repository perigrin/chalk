# ABOUTME: Semantic action for WhileStatement - builds Loop/If/Region IR structure
# ABOUTME: Handles while loop control flow with Loop nodes, lazy phis, and backedges

use 5.42.0;
use experimental qw(class);

class Chalk::Grammar::Chalk::Rule::WhileStatement :isa(Chalk::GrammarRule) {
    # Helper to describe a value for error messages
    my sub _describe_value($val) {
        return 'undef' unless defined $val;
        return ref($val) if blessed($val);
        return ref($val) if ref($val);
        return "'$val'";
    }

    method evaluate($context) {
        # WhileStatement -> 'while' WS_OPT '(' WS_OPT Expression WS_OPT ')' WS_OPT Block
        # Actual children after parsing with semantic actions:
        # Indices: 0       1     2   3        4     5     6
        # child[3] is the Expression node, child[6] is the Block

        my @children = $context->children->@*;

        # Get scope from context for control flow tracking
        my $pre_scope = $context->env->{scope};
        die "WhileStatement: no scope in context - scope must be initialized before parsing\n"
            unless $pre_scope;

        # Save entry control
        my $entry_control = $pre_scope->current_control;

        # Create Loop node with entry control directly
        my $ctrl = $entry_control // '__CONTROL_PLACEHOLDER__';
        my $loop_id = "loop_${ctrl}";
        my $loop = Chalk::IR::Node::Loop->new(
            id     => $loop_id,
            inputs => [$ctrl],    # Entry control; backedge added later
        );
        $loop->record_transform(
            'ir_construction',
            'WhileStatement::evaluate',
            context => "entry_control=$ctrl"
        );

        # Set current control to Loop for condition evaluation (immutably)
        my $loop_scope = $pre_scope->with_control($loop->id);
        $context->env->{scope} = $loop_scope;

        # Get condition expression (child 3)
        my $condition = $context->child(3);
        unless (blessed($condition) && $condition->can('id')) {
            my $desc = _describe_value($condition);
            die "WhileStatement: condition must be an IR node with id(), got: $desc\n" .
                "  This usually means Expression failed to build an IR node for the while condition.\n";
        }

        # Build If node for loop condition directly
        my $if_node_id = "if_" . $condition->id;
        my $if_node = Chalk::IR::Node::If->new(
            id           => $if_node_id,
            inputs       => [ $loop->id, $condition->id ],
            condition_id => $condition->id,
        );
        $if_node->record_transform(
            'ir_construction',
            'WhileStatement::evaluate',
            context => "condition_id=" . $condition->id
        );

        # Build Proj nodes for true/false branches directly
        my $if_true_id = "proj_${if_node_id}_0_IfTrue";
        my $if_true = Chalk::IR::Node::Proj->new(
            id     => $if_true_id,
            inputs => [ $if_node->id ],
            index  => 0,
            label  => 'IfTrue',
        );
        $if_true->record_transform(
            'ir_construction',
            'WhileStatement::evaluate',
            context => "source_id=${if_node_id}, index=0, label=IfTrue"
        );

        my $if_false_id = "proj_${if_node_id}_1_IfFalse";
        my $if_false = Chalk::IR::Node::Proj->new(
            id     => $if_false_id,
            inputs => [ $if_node->id ],
            index  => 1,
            label  => 'IfFalse',
        );
        $if_false->record_transform(
            'ir_construction',
            'WhileStatement::evaluate',
            context => "source_id=${if_node_id}, index=1, label=IfFalse"
        );

        # Get loop body Block (child 6)
        my $body_block = $context->child(6);
        unless (ref($body_block) eq 'HASH' && $body_block->{type} eq 'block') {
            my $desc = _describe_value($body_block);
            die "WhileStatement: body_block must be a HASH with type='block', got: $desc\n" .
                "  This usually means Block.pm failed to return the expected structure.\n";
        }

        # NOTE: Assignment and VariableDeclaration now use placeholder control pattern
        # Simple assignments like "$i = 5" work correctly in loops
        # Complex assignments like "$i = $i - 1" work but may use incomplete parse
        # (SPPF creates both parses, semiring currently picks incomplete one - needs optimization pass)

        # Create child scope for loop body
        my $body_scope = $pre_scope->child_scope()->with_control($if_true->id);
        $context->env->{scope} = $body_scope;

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
                    my $rewired = $stmt->with_control($current_ctrl);
                    $current_ctrl = $rewired->id;
                } else {
                    $current_ctrl = $stmt->id;  # Next statement uses this as control
                }
            }
        }
        # Save final body scope after processing statements
        my $body_final_scope = $context->env->{scope};

        # Build backedge: merge normal end-of-body + continue paths
        my @backedge_controls = ($current_ctrl, @continue_controls);
        if (@backedge_controls > 1) {
            # Multiple paths back to loop - need Region
            my $backedge_region_id = "region_" . join("_", @backedge_controls);
            my $backedge_region = Chalk::IR::Node::Region->new(
                id     => $backedge_region_id,
                inputs => \@backedge_controls,
            );
            $backedge_region->record_transform(
                'ir_construction',
                'WhileStatement::evaluate',
                context => "backedge_inputs=" . join(", ", @backedge_controls)
            );
            push $loop->inputs->@*, $backedge_region->id;
        } elsif (@backedge_controls == 1) {
            # Single path back
            push $loop->inputs->@*, $backedge_controls[0];
        }
        # If no backedge controls, loop has no normal exit (only break)

        # Generate phi nodes for all loop-modified variables using Scope merge
        # This captures variables that changed during loop execution
        my $merged_scope = $pre_scope->merge_scopes($pre_scope, $body_final_scope, $loop);

        # Build exit region: merge IfFalse (normal exit) + break paths
        my @exit_controls = ($if_false->id, @break_controls);
        my $exit_region;
        if (@exit_controls > 1) {
            my $exit_region_id = "region_" . join("_", @exit_controls);
            $exit_region = Chalk::IR::Node::Region->new(
                id     => $exit_region_id,
                inputs => \@exit_controls,
            );
            $exit_region->record_transform(
                'ir_construction',
                'WhileStatement::evaluate',
                context => "exit_inputs=" . join(", ", @exit_controls)
            );
        } else {
            my $exit_region_id = "region_" . $exit_controls[0];
            $exit_region = Chalk::IR::Node::Region->new(
                id     => $exit_region_id,
                inputs => [ $exit_controls[0] ],
            );
            $exit_region->record_transform(
                'ir_construction',
                'WhileStatement::evaluate',
                context => "exit_inputs=" . $exit_controls[0]
            );
        }

        # Update scope immutably with new control
        my $exit_scope = $merged_scope->with_control($exit_region->id);
        $context->env->{scope} = $exit_scope;

        return $exit_region;
    }
}

1;
