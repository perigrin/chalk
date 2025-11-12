# ABOUTME: Semantic action for ConditionalStatement - builds If/IfTrue/IfFalse/Region IR structure
# ABOUTME: Handles if/elsif/else control flow with proper Region merging and Phi nodes

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::ConditionalStatement :isa(Chalk::GrammarRule) {
    # Child index constants for ConditionalStatement grammar structure
    # Grammar: ConditionalKeyword WS_OPT ( WS_OPT Expression WS_OPT ) WS_OPT Block [WS_OPT 'else' WS_OPT Block]
    # NOTE: WS_OPT nodes may not be present in children array when empty
    # Actual observed structure: [if, undef, '(', Expression, ')', undef, Block] for simple if
    use constant {
        CHILD_KEYWORD       => 0,   # 'if' keyword
        CHILD_LPAREN        => 2,   # '(' terminal
        CHILD_CONDITION     => 3,   # Expression node
        CHILD_RPAREN        => 4,   # ')' terminal
        CHILD_TRUE_BLOCK    => 6,   # Block for true branch
        CHILD_ELSE_KEYWORD  => 8,   # 'else' keyword (if present)
        CHILD_FALSE_BLOCK   => 10,  # Block for false/else branch (if present)
    };

    method evaluate($context) {
        warn "[DEBUG] ConditionalStatement.evaluate() called\n" if $ENV{CHALK_DEBUG_TRACKING};

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

        if ($ENV{CHALK_DEBUG_TRACKING}) {
            warn "[DEBUG] ConditionalStatement: ", scalar(@children), " children\n";
            for my $i (0..$#children) {
                my $child = $context->child($i);
                my $desc = defined($child) ? (blessed($child) ? ref($child) : (ref($child) || $child)) : 'undef';
                warn "[DEBUG]   child[$i]: $desc\n";
            }
        }

        my $builder = $context->env->{ir_builder};
        if (!$builder) {
            warn "[DEBUG] ConditionalStatement: no builder, returning undef\n" if $ENV{CHALK_DEBUG_TRACKING};
            return undef;
        }

        # Save current control
        my $entry_control = $builder->current_control;

        # Find 'if' keyword position (should be at start)
        my $keyword_index = 0;

        # Parse: ConditionalKeyword WS_OPT ( WS_OPT Expression WS_OPT ) WS_OPT Block
        # Actual observed structure:
        # child[0]: ConditionalKeyword ('if')
        # child[1]: undef (WS_OPT)
        # child[2]: '(' terminal
        # child[3]: Expression IR node
        # child[4]: undef (WS_OPT)
        # child[5]: ')' terminal
        # child[6]: undef (WS_OPT)
        # child[7]: Block (HASH with statements)

        my $condition = $context->child(CHILD_CONDITION);
        unless ($condition isa Chalk::IR::Node::Base) {
            warn "[DEBUG] ConditionalStatement: condition not an IR node, returning undef. condition=", (defined $condition ? ref($condition) || $condition : 'undef'), "\n" if $ENV{CHALK_DEBUG_TRACKING};
            return undef;
        }
        warn "[DEBUG] ConditionalStatement: condition node id=", $condition->id, "\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Build If node
        my $if_node = $builder->build_if_node($condition);
        my $if_true = $builder->build_if_true_node($if_node);
        my $if_false = $builder->build_if_false_node($if_node);

        # Start tracking variable modifications in branches
        # Guard ensures cleanup even if exception occurs during branch evaluation
        my $tracking_guard = $builder->begin_branch_tracking('true', 'false');

        # Get true branch context WITHOUT evaluating yet
        my $true_block_ctx = $context->child_context(CHILD_TRUE_BLOCK);
        if (!$true_block_ctx) {
            warn "[DEBUG] ConditionalStatement: no true_block_ctx, returning undef\n" if $ENV{CHALK_DEBUG_TRACKING};
            return undef;
        }

        # NOW evaluate true branch with tracking active
        $builder->set_branch('true');
        my $true_block = $true_block_ctx->extract;
        if (!(ref($true_block) eq 'HASH' && $true_block->{type} eq 'block')) {
            warn "[DEBUG] ConditionalStatement: true_block not a block hash. ref=", ref($true_block), ", type=", (ref($true_block) eq 'HASH' ? ($true_block->{type} // 'undef') : 'N/A'), "\n" if $ENV{CHALK_DEBUG_TRACKING};
            return undef;
        }
        warn "[DEBUG] ConditionalStatement: true_block has ", scalar(@{$true_block->{statements}}), " statements\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Wire up true branch statements with IfTrue control
        my $current_ctrl = $if_true->id;
        my $true_last_stmt;
        for my $stmt ($true_block->{statements}->@*) {
            if ($stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                $builder->set_node_control($stmt, $current_ctrl);
            }
            $current_ctrl = $stmt->id;  # Next statement uses this as control
            $true_last_stmt = $stmt;
        }
        # Check if true branch ends with return
        my $true_ends_with_return = ($true_last_stmt && $true_last_stmt->op eq 'Return');
        # Region always takes Proj nodes as inputs, not statement nodes
        my $true_control = $if_true->id;

        # Check for else/elsif
        # For if-else: ConditionalKeyword WS_OPT ( WS_OPT Expression WS_OPT ) WS_OPT Block WS_OPT 'else' WS_OPT Block
        # child[7] is true block, child[8] is WS_OPT, child[9] is 'else', child[10] is WS_OPT, child[11] is else block
        my $false_control;
        my $false_ends_with_return = 0;
        my $false_last_stmt;

        if (@children > CHILD_ELSE_KEYWORD) {
            my $next_keyword = $children[CHILD_ELSE_KEYWORD]->extract;
            if (defined($next_keyword) && $next_keyword eq 'else') {
                # Get false branch context WITHOUT evaluating yet
                my $false_block_ctx = $context->child_context(CHILD_FALSE_BLOCK);

                # NOW evaluate false branch with tracking active
                $builder->set_branch('false');
                my $else_block = $false_block_ctx ? $false_block_ctx->extract : undef;

                if (ref($else_block) eq 'HASH' && $else_block->{type} eq 'block') {
                    $current_ctrl = $if_false->id;
                    for my $stmt ($else_block->{statements}->@*) {
                        if ($stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                            $builder->set_node_control($stmt, $current_ctrl);
                        }
                        $current_ctrl = $stmt->id;
                        $false_last_stmt = $stmt;
                    }
                    # Check if false branch ends with return
                    $false_ends_with_return = ($false_last_stmt && $false_last_stmt->op eq 'Return');
                    # Region always takes Proj nodes as inputs, not statement nodes
                    $false_control = $if_false->id;
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

        # Build Region to merge control paths ONLY if not both branches terminate with return
        # Per Sea of Nodes: "If both branches return, they bypass Region merging and feed into Stop"
        my $region;
        if ($true_ends_with_return && defined($false_control) && $false_ends_with_return) {
            # Both branches terminate with return - create Stop node instead of Region
            # Per Sea of Nodes chapter 5: "StopNodes only have ReturnNode inputs"
            my $stop = $builder->build_stop_node(undef, $true_last_stmt->id, $false_last_stmt->id);

            # End tracking without generating phi nodes (no merge point)
            my $tracking_data = $builder->end_branch_tracking();
            $tracking_guard->dismiss();

            # Return the Stop node as the final node of this statement
            return $stop;
        } else {
            # At least one branch continues - create Region
            # build_region_node signature: ($source_info, @control_inputs)
            # Pass undef for source_info, then the control inputs
            $region = $builder->build_region_node(undef, $true_control, $false_control);
            $builder->set_control($region->id);

            # End tracking and generate Phi nodes for modified variables
            my $tracking_data = $builder->end_branch_tracking();
            $tracking_guard->dismiss();  # Successful completion - no cleanup needed

            my $phi_nodes = $builder->generate_phi_nodes($region, $tracking_data, 'true', 'false');

            # Return the Region node (represents the merge point)
            return $region;
        }
    }
}

1;
