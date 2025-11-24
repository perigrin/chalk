# ABOUTME: Control flow builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for if/loop/phi nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::If;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Stop;
use Chalk::IR::Node::Loop;

class Chalk::IR::Builder::Control {

    method build_if_node($builder, $condition_node) {
        my $node_id = $builder->next_node_id();
        my $if_node = Chalk::IR::Node::If->new(
            id           => $node_id,
            inputs       => [ $builder->current_control, $condition_node->id ],
            condition_id => $condition_node->id,
        );
        $builder->graph->add_node($if_node);

        # Record transformation
        $if_node->record_transform(
            'ir_construction',
            'Builder::build_if_node',
            context => "condition_id=" . $condition_node->id
        );

        return $if_node;
    }

    method build_if_true_node($builder, $if_node) {
        # Proj index 0 = true branch
        my $if_true = $builder->build_proj_node( $if_node, 0, 'IfTrue' );
        return $if_true;
    }

    method build_if_false_node($builder, $if_node) {
        # Proj index 1 = false branch
        my $if_false = $builder->build_proj_node( $if_node, 1, 'IfFalse' );
        return $if_false;
    }

    method build_region_node($builder, $source_info = undef, @control_inputs) {
        # Validate control flow merge if source_info provided
        if ( defined($source_info) ) {
            $builder->validator->validate_control_merge( \@control_inputs,
                $source_info );
        }

        my $node_id = $builder->next_node_id();
        my $region  = Chalk::IR::Node::Region->new(
            id          => $node_id,
            inputs      => \@control_inputs,
            source_info => $source_info,
        );
        $builder->graph->add_node($region);

        # Record transformation
        $region->record_transform(
            'ir_construction',
            'Builder::build_region_node',
            context => "inputs=" . join( ", ", @control_inputs )
        );

        return $region;
    }

    method build_phi_node($builder, $region_node, @value_inputs) {
        my $node_id = $builder->next_node_id();
        my $phi     = Chalk::IR::Node::Phi->new(
            id        => $node_id,
            inputs    => [ $region_node->id, @value_inputs ],
            region_id => $region_node->id,
        );
        $builder->graph->add_node($phi);

        # Record transformation
        $phi->record_transform( 'ir_construction', 'Builder::build_phi_node',
                context => "region_id="
              . $region_node->id
              . ", value_inputs="
              . join( ", ", @value_inputs ) );

        return $phi;
    }

    method build_stop_node($builder, $source_info = undef, @return_inputs) {
        my $node_id = $builder->next_node_id();
        my $stop    = Chalk::IR::Node::Stop->new(
            id          => $node_id,
            inputs      => \@return_inputs,
            source_info => $source_info,
        );
        $builder->graph->add_node($stop);

        # Record transformation
        $stop->record_transform(
            'ir_construction',
            'Builder::build_stop_node',
            context => "return_inputs=" . join( ", ", @return_inputs )
        );

        return $stop;
    }

    # Loop control flow nodes
    method build_loop_node($builder, $entry_control = undef) {
        my $ctrl = $entry_control // $builder->current_control
          // '__CONTROL_PLACEHOLDER__';
        my $node_id = $builder->next_node_id();
        my $loop    = Chalk::IR::Node::Loop->new(
            id     => $node_id,
            inputs => [$ctrl],    # Entry control; backedge added later
        );
        $builder->graph->add_node($loop);

        # Record transformation
        $loop->record_transform( 'ir_construction', 'Builder::build_loop_node',
            context => "entry_control=$ctrl" );

        return $loop;
    }

    method build_loop_phi_node($builder, $loop_node, $initial_value, $loop_value = undef) {
        # Loop phi starts with control and initial value
        # Loop value added later (lazy phi pattern)
        my @inputs = ( $loop_node->id, $initial_value );
        push( @inputs, $loop_value ) if defined($loop_value);

        my $node_id = $builder->next_node_id();
        my $phi     = Chalk::IR::Node::Phi->new(
            id        => $node_id,
            inputs    => \@inputs,
            region_id => $loop_node->id,
        );
        $builder->graph->add_node($phi);

        # Record transformation
        my $loop_val_str = defined($loop_value) ? $loop_value : "undef";
        $phi->record_transform(
            'ir_construction',
            'Builder::build_loop_phi_node',
            context => "loop_id="
              . $loop_node->id
              . ", initial=$initial_value, loop=$loop_val_str"
        );

        return $phi;
    }

    # Function call nodes
    method build_call_node($builder, $function_name, $source_info = undef, @arg_nodes) {
        # Validate arity if source_info provided
        if ( defined($source_info) ) {
            my $arg_count = scalar(@arg_nodes);
            $builder->validator->validate_call_arity( $function_name, $arg_count,
                $source_info );
        }

        # Call: control, memory, arguments...
        # For now, use current_control for both control and memory
        my $attributes = { function => $function_name };
        my $node_id    = $builder->next_node_id();
        my $call       = Chalk::IR::Node->new(
            id     => $node_id,
            op     => 'Call',
            inputs =>
              [ $builder->current_control, $builder->current_control, map { $_->id } @arg_nodes ],
            attributes  => $attributes,
            source_info => $source_info,
        );
        $builder->graph->add_node($call);

        # Record transformation
        my $arg_ids = join( ", ", map { $_->id } @arg_nodes );
        $call->record_transform(
            operation   => 'ir_construction',
            rule_name   => 'Builder::build_call_node',
            description => "function=$function_name, args=[$arg_ids]"
        );

        return $call;
    }

    # Loop depth tracking methods
    method begin_loop_tracking($builder) {
        # Increment loop depth when entering a loop
        $builder->_increment_loop_depth();

        # Push a new set to track modified variables at this loop depth
        push $builder->loop_modified_vars->@*, {};
        return;
    }

    method end_loop_tracking($builder) {
        # Decrement loop depth when exiting a loop
        if ( $builder->loop_depth > 0 ) {
            $builder->_decrement_loop_depth();

            # Pop the modified variables set for this loop
            pop $builder->loop_modified_vars->@*
              if scalar( $builder->loop_modified_vars->@* ) > 0;
        }
        return;
    }
}

1;
