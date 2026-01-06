# ABOUTME: Semantic action for Program - creates Start/Stop control flow nodes
# ABOUTME: Wraps entire program with proper CFG entry/exit points for Sea of Nodes IR
# ABOUTME: Per Chapter 18: Program always returns Stop which collects all returns

use 5.42.0;
use experimental 'class';
use Chalk::Grammar::Chalk::Type::Undef;


class Chalk::Grammar::Chalk::Rule::Program :isa(Chalk::GrammarRule) {

    method evaluate($context) {
        # Get scope from environment
        my $scope = $context->env->{scope};
        die "Program: scope required in evaluation context" unless $scope;

        # Create Start node (program entry point)
        my $start = Chalk::IR::Node::Start->new(label => 'main');

        # Update scope immutably with new control and $ctrl binding
        # Per Simple Chapter 4: "we track the current in-scope control node via the name $ctrl"
        $scope = $scope->with_control($start);
        $scope = $scope->with_binding('$ctrl', $start);
        $context->env->{scope} = $scope;

        # Find StatementList in children
        # Program -> WS_OPT StatementList WS_OPT
        my @children = $context->children->@*;
        my @statements;

        for my $child_ctx (@children) {
            next unless $child_ctx && $child_ctx->can('focus');
            my $focus = $child_ctx->focus;
            # StatementList returns an arrayref of statements
            if (ref($focus) eq 'ARRAY') {
                @statements = $focus->@*;
                last;
            }
        }

        # Fallback: if no statements from focus, check direct child evaluation
        # This handles cases where StatementList result is accessed via child()
        if (@statements == 0) {
            for my $i (0 .. $#children) {
                my $child = $context->child($i);
                if (ref($child) eq 'ARRAY') {
                    @statements = @$child;
                    last;
                }
            }
        }

        # CRITICAL FIX for Issue #195: Wire up control flow for ALL statements sequentially
        # Due to bottom-up parsing, child statements may have been created with incorrect control.
        # We need to rewire controls so each statement uses the previous statement's output as control.
        # This ensures that: my $x = 10; if ($x > 5) { return 1; } return 0;
        # correctly wires the final "return 0;" to use the if-statement's IfFalse output as control.
        my $current_ctrl = $start;
        my @rewired_statements;
        my @early_returns;  # Issue #195: Collect early returns from control flow statements

        for my $stmt (@statements) {
            if (blessed($stmt) && $stmt->can('with_control')) {
                # Rewire this statement to use current control
                my $rewired = $stmt->with_control($current_ctrl);
                push @rewired_statements, $rewired;

                # Issue #195: Collect early returns from Proj nodes (from ConditionalStatement)
                if ($rewired->can('early_returns') && $rewired->early_returns) {
                    push @early_returns, $rewired->early_returns->@*;
                }

                # Determine what control to use for the next statement
                # Control flow nodes (Region, Proj for IfFalse, etc.) pass their output as control
                # Other nodes (Store, Return) become the control predecessor
                if (blessed($rewired) && $rewired->can('op')) {
                    my $op = $rewired->op;
                    if ($op eq 'Proj' || $op eq 'Region' || $op eq 'If') {
                        # Control flow node - use it as control for next statement
                        $current_ctrl = $rewired;
                    } else {
                        # Regular statement - also becomes control for next
                        $current_ctrl = $rewired;
                    }
                } else {
                    $current_ctrl = $rewired;
                }
            } elsif (blessed($stmt) && $stmt->can('id')) {
                # Node without with_control() - just add it
                push @rewired_statements, $stmt;

                # Only update control for actual control/statement nodes, not value expressions
                # Value nodes (Constant, Parm, etc.) don't affect control flow
                my $op = $stmt->can('op') ? $stmt->op : '';
                unless ($op eq 'Constant' || $op eq 'Parm' || $op eq 'UnboundVariable') {
                    $current_ctrl = $stmt;
                }

                # Issue #195: Also check for early returns on non-rewired nodes
                if ($stmt->can('early_returns') && $stmt->early_returns) {
                    push @early_returns, $stmt->early_returns->@*;
                }
            } else {
                # Non-node - this is a bug in the grammar rules
                my $desc = ref($stmt) || (defined $stmt ? "'$stmt'" : 'undef');
                die "Program: expected IR node in statement list, got: $desc";
            }

            if ($ENV{CHALK_DEBUG_PROGRAM}) {
                my $stmt_id = blessed($stmt) && $stmt->can('id') ? $stmt->id : 'unknown';
                my $ctrl_id = blessed($current_ctrl) && $current_ctrl->can('id') ? $current_ctrl->id : "$current_ctrl";
                warn "[DEBUG] Program: processed stmt=$stmt_id, next_ctrl=$ctrl_id\n";
            }
        }

        # Use rewired statements for the rest of processing
        @statements = @rewired_statements;
        my $final_control = $current_ctrl;

        # Per Chapter 18: Always create Stop to collect all returns
        # This ensures proper graph traversal for XS target and other backends
        use Chalk::IR::Node::Stop;
        my $stop = Chalk::IR::Node::Stop->new(inputs => [], returns => []);

        # Add early returns to Stop first
        for my $early_ret (@early_returns) {
            $stop->add_return($early_ret);
        }

        # Collect FunctionDef nodes and add to Stop for graph traversal
        # This makes function bodies reachable for XS code generation
        for my $stmt (@statements) {
            if (blessed($stmt) && $stmt->can('op') && $stmt->op eq 'FunctionDef') {
                $stop->add_function($stmt);
            }
        }

        # Collect ClassDef nodes and add to Stop for XS class generation
        # This makes class definitions reachable for XS target
        for my $stmt (@statements) {
            if (blessed($stmt) && $stmt->can('op') && $stmt->op eq 'ClassDef') {
                $stop->add_class($stmt);
            }
        }

        # Get last statement for return value
        my $last_stmt = @statements ? $statements[-1] : undef;
        my $return_value;

        if ($last_stmt && blessed($last_stmt) && $last_stmt->can('op')) {
            my $op = $last_stmt->op;

            if ($op eq 'Return') {
                # Last statement is already a Return - add to Stop
                $stop->add_return($last_stmt);
                return $stop;
            } else {
                # Expression statement - use as return value
                # In SSA, assignments return RHS values (no Store nodes)
                $return_value = $last_stmt;
            }
        }

        # Default return value (undef constant)
        $return_value //= Chalk::IR::Node::Constant->new(
            type  => Chalk::Grammar::Chalk::Type::Undef->new(),
            value => undef,
        );

        # Create implicit Return node for expressions/stores
        my $final_return = Chalk::IR::Node::Return->new(
            control => $final_control,
            value   => $return_value,
        );

        # Add implicit return to Stop
        $stop->add_return($final_return);

        return $stop;
    }
}

1;
