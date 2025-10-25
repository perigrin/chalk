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

        # Get all statements from children
        my @children = $context->children->@*;
        my $current_control = $start->id;

        # Wire up all statements with control flow
        for my $child (@children) {
            next unless blessed($child) && $child->can('inputs');

            # Check if this statement needs control wiring
            if ($child->inputs->[0] && $child->inputs->[0] eq '__CONTROL_PLACEHOLDER__') {
                $builder->set_node_control($child, $current_control);
            }

            # Update control for next statement
            $current_control = $child->id;
        }

        # Create Return node (program exit point)
        # For now, programs return undef (void)
        my $undef_value = $builder->build_constant_node(undef);
        my $return = $builder->build_return_node($undef_value, $current_control);

        # Return the entire program as a block
        return $return;
    }
}

1;
