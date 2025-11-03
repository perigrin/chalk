# ABOUTME: Variable read node for accessing variables from lexical context
# ABOUTME: Reads variable value from builder's context using lexical: namespace
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::VariableRead :isa(Chalk::IR::Node::Base) {
    field $var_label :param :reader;  # Full label like "lexical:$x"

    method op() { 'VariableRead' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'VariableRead',
            inputs => $self->inputs,
            attributes => {
                var_label => $var_label,
            },
        };
    }

    method execute($context) {
        # Lookup in context using the variable label
        my $node_id = $context->($var_label);

        # Resolve the node ID to get the actual value
        my $value = $context->("node:$node_id");

        return $value;
    }
}

1;
