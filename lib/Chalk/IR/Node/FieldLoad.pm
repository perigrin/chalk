# ABOUTME: Loads a field value from an object in the heap
# ABOUTME: Uses heap ID and field name to retrieve field from discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::FieldLoad :isa(Chalk::IR::Node::Base) {
    field $mem_id :param :reader = undef;  # Previous memory state (for peephole optimization)
    field $object_id :param :reader;
    field $field_id :param :reader;
    field $field_index :param :reader = undef;  # For XS ObjectFIELDS[index] access
    field $alias_class :param :reader = undef;

    method op() { 'FieldLoad' }

    method to_hash() {
        my %attrs = (
            object_id => $object_id,
            field_id => $field_id,
        );
        $attrs{mem_id} = $mem_id if defined $mem_id;
        $attrs{field_index} = $field_index if defined $field_index;
        $attrs{alias_class} = $alias_class if defined $alias_class;

        return {
            id     => $self->id,
            op     => 'FieldLoad',
            inputs => $self->inputs,
            attributes => \%attrs,
        };
    }

    method compute($graph) {
        use Chalk::IR::Type::Memory;
        return Chalk::IR::Type::Memory->new(
            alias_class => $alias_class,
        );
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

    # Peephole optimization for FieldLoad
    # Implements Load-after-Store forwarding following Simple's chapter10 design
    method peephole($graph = undef) {
        return $self unless $graph;
        return $self unless defined $mem_id;

        # Get the previous memory state
        my $prev_mem = $graph->get_node($mem_id);
        return $self unless $prev_mem;

        # Load-after-Store forwarding:
        # If previous memory is a FieldStore to the same object and field,
        # we can forward the stored value directly (eliminate the load)
        if ($prev_mem->isa('Chalk::IR::Node::FieldStore') &&
            $prev_mem->object_id == $object_id &&
            defined $alias_class &&
            defined $prev_mem->alias_class &&
            $alias_class == $prev_mem->alias_class) {

            # Forward the stored value
            return $graph->get_node($prev_mem->value_id);
        }

        return $self;
    }
}

1;
