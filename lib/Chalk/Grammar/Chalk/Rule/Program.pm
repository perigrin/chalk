# ABOUTME: Semantic action for Program - creates Start/Return control flow nodes
# ABOUTME: Wraps entire program with proper CFG entry/exit points for Sea of Nodes IR

use 5.42.0;
use experimental 'class';
use builtin qw(blessed);

class Chalk::Grammar::Chalk::Rule::Program :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        my $builder = $context->env->{ir_builder};
        return undef unless $builder;

        # Create Start node (program entry point)
        my $start = $builder->build_start_node('main');
        $builder->set_control($start->id);

        # Get statements from StatementList child
        # Program -> WS_OPT StatementList WS_OPT
        # StatementList should be at child(1), but if WS_OPT is collapsed, might be child(0)
        my @children = $context->children->@*;
        my $stmt_list_ctx;

        # Find the StatementList child (it will have an array or node as focus)
        for my $child_ctx (@children) {
            next unless $child_ctx && $child_ctx->can('focus');
            my $focus = $child_ctx->focus;
            # StatementList returns an arrayref of statements
            if (ref($focus) eq 'ARRAY') {
                $stmt_list_ctx = $child_ctx;
                last;
            }
        }

        my @statements;
        if ($stmt_list_ctx) {
            my $stmt_list = $stmt_list_ctx->focus;
            @statements = ref($stmt_list) eq 'ARRAY' ? $stmt_list->@* : ();
        }

        my $current_control = $start->id;

        # Wire up all statements with control flow
        for my $stmt (@statements) {
            next unless blessed($stmt) && $stmt->can('inputs');

            # Check if this statement needs control wiring
            if ($stmt->inputs->[0] && $stmt->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                $builder->set_node_control($stmt, $current_control);
            }

            # Update control for next statement
            $current_control = $stmt->id;
        }

        # Check if last statement is a Return
        # If so, use it; otherwise create a default Return(undef)
        if (@statements && blessed($statements[-1]) && $statements[-1]->can('op') && $statements[-1]->op eq 'Return') {
            # Last statement is already a Return - use it
            return $statements[-1];
        } else {
            # No Return found - create default Return(undef)
            my $undef_value = $builder->build_constant_node(undef);
            my $return = $builder->build_return_node($undef_value, $current_control);
            return $return;
        }
    }
}

1;
