# ABOUTME: Semantic action for ConditionalStatement - builds If/IfTrue/IfFalse/Region IR structure
# ABOUTME: Handles if/elsif/else control flow with proper Region merging and Phi nodes

use 5.42.0;
use experimental qw(class);

class Chalk::Grammar::Chalk::Rule::ConditionalStatement :isa(Chalk::GrammarRule) {
    # Helper to describe a value for error messages
    my sub _describe_value($val) {
        return 'undef' unless defined $val;
        return ref($val) if blessed($val);
        return ref($val) if ref($val);
        return "'$val'";
    }

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

        # Get scope from context for control flow tracking
        my $pre_scope = $context->env->{scope};
        if (!$pre_scope) {
            warn "[DEBUG] ConditionalStatement: no scope, returning undef\n" if $ENV{CHALK_DEBUG_TRACKING};
            return undef;
        }

        # Save current control
        my $entry_control = $pre_scope->current_control;

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
        # Use duck typing (check for id capability) rather than inheritance
        # since IR node classes may not share a common base class
        unless (blessed($condition) && $condition->can('id')) {
            my $desc = _describe_value($condition);
            die "ConditionalStatement: condition must be an IR node with id(), got: $desc\n" .
                "  This usually means Expression/ComparisonOp failed to build an IR node.\n";
        }
        warn "[DEBUG] ConditionalStatement: condition node id=", $condition->id, "\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Build If node directly (content-addressable ID based on condition)
        # Pass condition object reference for graph traversal
        # CRITICAL: inputs array must contain string IDs, not object references
        # (CEKDataflow uses inputs for dependency scheduling)
        my $entry_ctrl_id = (blessed($entry_control) && $entry_control->can('id'))
            ? $entry_control->id
            : $entry_control;
        my $if_node_id = "if_" . $condition->id;
        # Issue #195 fix: Pass control object reference for graph traversal
        my $entry_ctrl_obj = (blessed($entry_control) && $entry_control->can('id'))
            ? $entry_control
            : undef;
        my $if_node = Chalk::IR::Node::If->new(
            id           => $if_node_id,
            inputs       => [ $entry_ctrl_id, $condition->id ],
            condition_id => $condition->id,
            condition    => $condition,
            control      => $entry_ctrl_obj,
        );
        $if_node->record_transform(
            'ir_construction',
            'ConditionalStatement::evaluate',
            context => "condition_id=" . $condition->id
        );

        # Build IfTrue Proj node
        # Pass source object reference for graph traversal
        my $if_true_id = "proj_${if_node_id}_0_IfTrue";
        my $if_true = Chalk::IR::Node::Proj->new(
            id     => $if_true_id,
            inputs => [ $if_node->id ],
            index  => 0,
            label  => 'IfTrue',
            source => $if_node,
        );
        $if_true->record_transform(
            'ir_construction',
            'ConditionalStatement::evaluate',
            context => "source_id=${if_node_id}, index=0, label=IfTrue"
        );

        # IfFalse Proj is created later, after rewiring true branch,
        # so we can pass early_returns at construction (immutability)
        my $if_false_id = "proj_${if_node_id}_1_IfFalse";
        my $if_false;  # Will be created after true branch rewiring

        # CRITICAL FIX: WS_OPT nodes may be absent, so we can't use fixed indices.
        # Search for the Block child after the ')' terminal.
        my $true_block_ctx;
        my $found_rparen = 0;
        for my $i (0..$#children) {
            my $child_ctx = $children[$i];
            my $child_val = $child_ctx->extract;

            # Mark when we've passed the ')'
            if (defined($child_val) && "$child_val" eq ')') {
                $found_rparen = 1;
                next;
            }

            # After ')', the first Block rule is the true branch
            if ($found_rparen && $child_ctx->rule && $child_ctx->rule->isa('Chalk::Grammar::Chalk::Rule::Block')) {
                $true_block_ctx = $child_ctx;
                last;
            }
        }

        if (!$true_block_ctx) {
            warn "[DEBUG] ConditionalStatement: no true_block_ctx found\n" if $ENV{CHALK_DEBUG_TRACKING};
            return undef;
        }

        # Evaluate true branch with child scope
        my $true_scope = $pre_scope->child_scope()->with_control($if_true->id);
        $context->env->{scope} = $true_scope;

        # Must call evaluate() on the rule to get the block hash!
        my $true_block_rule = $true_block_ctx->rule;
        my $true_block = $true_block_rule ? $true_block_rule->evaluate($true_block_ctx) : $true_block_ctx->extract;
        if (!(ref($true_block) eq 'HASH' && $true_block->{type} eq 'block')) {
            return undef;
        }
        warn "[DEBUG] ConditionalStatement: true_block has ", scalar(@{$true_block->{statements}}), " statements\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Wire up true branch statements with IfTrue control
        # Use object references (not IDs) for graph traversal
        # CRITICAL: Always rewire control due to bottom-up parsing order
        # (ReturnStatement evaluates before ConditionalStatement sets up scopes)
        my $current_ctrl = $if_true;
        my $true_last_stmt;
        my @true_early_returns;  # Collect REWIRED Returns for IfFalse
        for my $stmt ($true_block->{statements}->@*) {
            if ($stmt->can('with_control')) {
                my $rewired = $stmt->with_control($current_ctrl);
                # Track rewired Returns (not original unrewired ones)
                if ($rewired->can('op') && $rewired->op eq 'Return') {
                    push @true_early_returns, $rewired;
                }
                $current_ctrl = $rewired;
                $true_last_stmt = $rewired;
            } else {
                $current_ctrl = $stmt;
                $true_last_stmt = $stmt;
            }
        }
        # Save final true scope after evaluating statements
        my $true_final_scope = $context->env->{scope};

        # Now create IfFalse Proj with early_returns (immutable construction)
        # This enables Program.pm to find Returns inside if-blocks
        $if_false = Chalk::IR::Node::Proj->new(
            id            => $if_false_id,
            inputs        => [ $if_node->id ],
            index         => 1,
            label         => 'IfFalse',
            source        => $if_node,
            early_returns => (@true_early_returns ? \@true_early_returns : undef),
        );
        $if_false->record_transform(
            'ir_construction',
            'ConditionalStatement::evaluate',
            context => "source_id=${if_node_id}, index=1, label=IfFalse" .
                       (@true_early_returns ? ", early_returns=" . scalar(@true_early_returns) : "")
        );

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
        my $false_final_scope;

        # Search for 'else' keyword and then the false branch Block
        my $found_else = 0;
        my $false_block_ctx;
        for my $i (0..$#children) {
            my $child_ctx = $children[$i];
            my $child_val = $child_ctx->extract;

            # Mark when we find 'else'
            if (defined($child_val) && "$child_val" eq 'else') {
                $found_else = 1;
                next;
            }

            # After 'else', the first Block rule is the false branch
            if ($found_else && $child_ctx->rule && $child_ctx->rule->isa('Chalk::Grammar::Chalk::Rule::Block')) {
                $false_block_ctx = $child_ctx;
                last;
            }
        }

        if ($false_block_ctx) {
                # Evaluate false branch with child scope
                my $false_scope = $pre_scope->child_scope()->with_control($if_false->id);
                $context->env->{scope} = $false_scope;

                # Must call evaluate() on the rule to get the block hash!
                my $false_block_rule = $false_block_ctx->rule;
                my $else_block = $false_block_rule ? $false_block_rule->evaluate($false_block_ctx) : $false_block_ctx->extract;

                if (ref($else_block) eq 'HASH' && $else_block->{type} eq 'block') {
                    # Use object references (not IDs) for graph traversal
                    # CRITICAL: Always rewire control due to bottom-up parsing order
                    $current_ctrl = $if_false;
                    for my $stmt ($else_block->{statements}->@*) {
                        if ($stmt->can('with_control')) {
                            my $rewired = $stmt->with_control($current_ctrl);
                            $current_ctrl = $rewired;
                            $false_last_stmt = $rewired;
                        } else {
                            $current_ctrl = $stmt;
                            $false_last_stmt = $stmt;
                        }
                    }
                    # Save final false scope after evaluating statements
                    $false_final_scope = $context->env->{scope};

                    # Check if false branch ends with return
                    $false_ends_with_return = ($false_last_stmt && $false_last_stmt->op eq 'Return');
                    # Region always takes Proj nodes as inputs, not statement nodes
                    $false_control = $if_false->id;
                } else {
                    $false_control = $if_false->id;
                    $false_final_scope = $false_scope;
                }
        } else {
            # No else branch - false path just falls through
            $false_control = $if_false->id;
            $false_final_scope = $pre_scope->child_scope()->with_control($if_false->id);
        }

        # Build Region to merge control paths ONLY if not both branches terminate with return
        # Per Sea of Nodes: "If both branches return, they bypass Region merging and feed into Stop"
        my $region;
        if ($true_ends_with_return && defined($false_control) && $false_ends_with_return) {
            # Both branches terminate with return - create Stop node instead of Region
            # Per Sea of Nodes chapter 5: "StopNodes only have ReturnNode inputs"
            my $stop_id = "stop_" . join("_", $true_last_stmt->id, $false_last_stmt->id);
            my $stop = Chalk::IR::Node::Stop->new(
                id      => $stop_id,
                inputs  => [ $true_last_stmt->id, $false_last_stmt->id ],
                returns => [ $true_last_stmt, $false_last_stmt ],
            );
            $stop->record_transform(
                'ir_construction',
                'ConditionalStatement::evaluate',
                context => "return_inputs=" . join(", ", $true_last_stmt->id, $false_last_stmt->id)
            );

            # Return the Stop node as the final node of this statement
            return $stop;
        } elsif ($true_ends_with_return && !$false_block_ctx) {
            # True branch returns, no else block - false path just falls through
            # Don't create Region - pass IfFalse directly as control
            # This allows subsequent statements to check IfFalse's activation state
            # (IfFalse returns 0 when condition is true, 1 when false)
            my $new_scope = $pre_scope->with_control($if_false->id);
            $context->env->{scope} = $new_scope;

            # IfFalse already has early_returns set at construction (immutable)
            # Program.pm will collect them for building the final Stop node
            return $if_false;
        } elsif ($false_ends_with_return && !scalar(@{$true_block->{statements} // []})) {
            # False branch returns, true branch is empty - true path just falls through
            # Create single-input Region from IfTrue only
            my $region_id = "region_" . $if_true->id;
            $region = Chalk::IR::Node::Region->new(
                id     => $region_id,
                inputs => [ $if_true->id ],
            );
            $region->record_transform(
                'ir_construction',
                'ConditionalStatement::evaluate',
                context => "inputs=" . $if_true->id
            );
            my $new_scope = $pre_scope->with_control($region->id);
            $context->env->{scope} = $new_scope;

            # Return the Region as this statement's result
            return $region;
        } else {
            # At least one branch continues - create Region
            # CRITICAL: Only include control from branches that DON'T end with return
            # Per Issue #155: branches ending with Return go to Stop, not Region
            my @region_inputs;
            push @region_inputs, $true_control unless $true_ends_with_return;
            push @region_inputs, $false_control unless $false_ends_with_return;

            my $region_id = "region_" . join("_", @region_inputs);
            $region = Chalk::IR::Node::Region->new(
                id     => $region_id,
                inputs => \@region_inputs,
            );
            $region->record_transform(
                'ir_construction',
                'ConditionalStatement::evaluate',
                context => "inputs=" . join(", ", @region_inputs)
            );

            # Merge branch scopes to generate Phi nodes for modified variables
            my $merged_scope = $pre_scope->merge_scopes($true_final_scope, $false_final_scope, $region);
            $context->env->{scope} = $merged_scope;

            # Return the Region node (represents the merge point)
            return $region;
        }
    }
}

1;
