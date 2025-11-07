# ABOUTME: Loads a field value from an object in the heap
# ABOUTME: Uses heap ID and field name to retrieve field from discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::FieldLoad :isa(Chalk::IR::Node::Base) {
    field $object_id :param :reader;
    field $field_id :param :reader;

    method op() { 'FieldLoad' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'FieldLoad',
            inputs => $self->inputs,
            attributes => {
                object_id => $object_id,
                field_id => $field_id,
            },
        };
    }

    method execute($context) {
        # Get the heap ID from the object node
        my $heap_id = $context->("node:$object_id");

        # Get the field name
        my $field = $context->("node:$field_id");

        # Get the environment
        my $env = $context->('env:');

        # Lookup the field value in the heap
        my $value = $env->lookup_heap($heap_id, $field);

        # Return the value (or undef if not found)
        return $value;
    }
}

1;
