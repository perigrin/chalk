# ABOUTME: Semantic action for Program - creates Start/Return control flow nodes
# ABOUTME: Wraps entire program with proper CFG entry/exit points for Sea of Nodes IR

use 5.42.0;
use experimental 'class';
use Scalar::Util qw(blessed);

class Chalk::Grammar::Chalk::Rule::Program :isa(Chalk::GrammarRule) {
    use Chalk::IR::Node::Start;
    use Chalk::IR::Node::Return;
    use Chalk::IR::Node::Constant;

    method evaluate($context) {
        # Get scope from environment
        my $scope = $context->env->{scope};
        return undef unless $scope;

        # Create Start node (program entry point)
        my $start = Chalk::IR::Node::Start->new(label => 'main');

        # Update scope immutably with new control
        $scope = $scope->with_control($start);
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

        # CRITICAL FIX for Issue #195: Wire up control flow for ALL statements sequentially
        # Due to bottom-up parsing, child statements may have been created with incorrect control.
        # We need to rewire controls so each statement uses the previous statement's output as control.
        # This ensures that: my $x = 10; if ($x > 5) { return 1; } return 0;
        # correctly wires the final "return 0;" to use the if-statement's IfFalse output as control.
        my $current_ctrl = $start;
        my @rewired_statements;

        for my $stmt (@statements) {
            if (blessed($stmt) && $stmt->can('with_control')) {
                # Rewire this statement to use current control
                my $rewired = $stmt->with_control($current_ctrl);
                push @rewired_statements, $rewired;

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
                # Node without with_control() - just add it and use it as control
                push @rewired_statements, $stmt;
                $current_ctrl = $stmt;
            } else {
                # Non-node (shouldn't happen but handle gracefully)
                push @rewired_statements, $stmt;
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

        # Get last statement for return value
        my $last_stmt = @statements ? $statements[-1] : undef;
        my $return_value;

        if ($ENV{CHALK_DEBUG_PROGRAM}) {
            my $ctrl_id = blessed($final_control) && $final_control->can('id') ? $final_control->id : "$final_control";
            warn "[DEBUG] Program: final_control after rewiring = $ctrl_id\n";
        }

        if ($last_stmt && blessed($last_stmt) && $last_stmt->can('op')) {
            my $op = $last_stmt->op;

            if ($op eq 'Return') {
                # Last statement is already a Return - use the rewired version
                return $last_stmt;
            } elsif ($op eq 'Store') {
                # Last statement is a Store - return the stored value
                $return_value = $last_stmt->value;
                $final_control = $last_stmt;
            } else {
                # Other expression - use as return value
                $return_value = $last_stmt;
            }
        }

        # Default return value (undef constant)
        $return_value //= Chalk::IR::Node::Constant->new(
            type  => 'Undef',
            value => 'undef',
        );

        # Create Return node
        return Chalk::IR::Node::Return->new(
            control => $final_control,
            value   => $return_value,
        );
    }
}

1;
