# ABOUTME: CallEnd node for call completion projections
# ABOUTME: Sea of Nodes Chapter 18 - projects control, memory, and return value
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Node::Proj;

class Chalk::IR::Node::CallEnd {
    field $call :param :reader;         # The Call node this completes
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    # Cached projection nodes
    field $_ctrl_proj = undef;
    field $_mem_proj = undef;
    field $_ret_proj = undef;

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method inputs() {
        my @inputs;
        push @inputs, $call->id if defined $call && $call->can('id');
        return \@inputs;
    }

    method op() { 'CallEnd' }

    method to_hash() {
        my $call_id = (defined $call && $call->can('id')) ? $call->id : undef;

        return {
            id     => $self->id,
            op     => 'CallEnd',
            inputs => $self->inputs,
            attributes => {
                call_id => $call_id,
            },
        };
    }

    method execute($context) {
        # CallEnd provides projections:
        # - Control: execution continues after call
        # - Memory: memory state after call
        # - Return value: the function's return value

        # Get the Call node's descriptor (func_name, args, rpc)
        my $call_result = $context->("node:" . $call->id);
        return undef unless defined $call_result && ref($call_result) eq 'HASH';

        my $func_name = $call_result->{func_name};
        return undef unless defined $func_name;

        # Look up function in registry
        my $registry = $context->("function_registry:");
        return undef unless defined $registry;

        my $func_def = $registry->lookup($func_name);
        return undef unless defined $func_def;

        # Get function parameters and body
        my $parameters = $func_def->parameters // [];
        my $body_node = $func_def->body_node;
        return undef unless defined $body_node;

        # Get argument values from call descriptor
        my $args = $call_result->{args} // [];

        # Get environment for variable binding
        my $env = $context->("env:");
        return undef unless defined $env;

        # Bind parameters to arguments in environment
        for my $i (0 .. $#$parameters) {
            my $param_name = $parameters->[$i];
            my $arg_value = $args->[$i];
            $env->set_variable($param_name, $arg_value);
        }

        # Execute the function body
        # The body_node should be a Return or block node
        # For now, use simple recursive evaluation
        return $self->_evaluate_node($body_node, $context, $env);
    }

    method _evaluate_node($node, $context, $env) {
        # Recursively evaluate a node tree
        return undef unless defined $node;

        # Handle hash refs (e.g., from Block semantic action returning children)
        if (ref($node) eq 'HASH') {
            # Try to find an IR node in the hash
            if (exists $node->{_body_node}) {
                return $self->_evaluate_node($node->{_body_node}, $context, $env);
            }
            # Block with statements array
            if ($node->{type} eq 'block' && exists $node->{statements}) {
                my $result;
                for my $stmt ($node->{statements}->@*) {
                    $result = $self->_evaluate_node($stmt, $context, $env);
                }
                return $result;
            }
            # Return the hash as-is if it's a result
            return $node;
        }

        # Handle array refs
        if (ref($node) eq 'ARRAY') {
            # Evaluate each element and return the last result
            my $result;
            for my $elem ($node->@*) {
                $result = $self->_evaluate_node($elem, $context, $env);
            }
            return $result;
        }

        # Handle scalar values
        return $node unless ref($node) && blessed($node) && $node->can('execute');

        # Handle IR nodes
        my $op = $node->can('op') ? $node->op : '';

        # Return nodes return their value
        if ($op eq 'Return') {
            my $value_node = $node->can('value_node') ? $node->value_node : $node->can('value') ? $node->value : undef;
            return $self->_evaluate_node($value_node, $context, $env);
        }

        # Constant nodes return their value
        if ($op eq 'Constant') {
            return $node->execute();
        }

        # VariableRead nodes look up variables
        if ($op eq 'VariableRead') {
            my $var_name = $node->can('name') ? $node->name : undef;
            return $env->lookup_variable($var_name) if defined $var_name;
            return $node->execute($context);
        }

        # For other nodes, try to execute them directly
        return $node->execute($context);
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # CallEnd cannot be optimized away (side effect barrier)
        return $self;
    }

    method record_transform(@args) {
        return;
    }

    # Projection accessors for control, memory, and return value
    # Returns cached Proj nodes (created on first access)
    method ctrl_proj() {
        return $_ctrl_proj if defined $_ctrl_proj;
        $_ctrl_proj = Chalk::IR::Node::Proj->new(
            inputs => [ $self->id ],
            index  => 0,
            label  => 'ctrl',
            source => $self,
        );
        return $_ctrl_proj;
    }

    method mem_proj() {
        return $_mem_proj if defined $_mem_proj;
        $_mem_proj = Chalk::IR::Node::Proj->new(
            inputs => [ $self->id ],
            index  => 1,
            label  => 'mem',
            source => $self,
        );
        return $_mem_proj;
    }

    method ret_proj() {
        return $_ret_proj if defined $_ret_proj;
        $_ret_proj = Chalk::IR::Node::Proj->new(
            inputs => [ $self->id ],
            index  => 2,
            label  => 'ret',
            source => $self,
        );
        return $_ret_proj;
    }
}

1;
