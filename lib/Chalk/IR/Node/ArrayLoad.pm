# ABOUTME: Loads a value from an array in the heap
# ABOUTME: Supports bounds checking for fixed-length arrays
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayLoad :isa(Chalk::IR::Node::Base) {
    field $array_id :param :reader = undef;     # Legacy: heap ID reference
    field $index_id :param :reader = undef;     # Legacy: index node ID
    field $array :param :reader = undef;        # NEW: array node reference
    field $index :param :reader = undef;        # NEW: index node reference
    field $bounds_check :param :reader = 0;     # NEW: enable bounds checking

    method op() { 'ArrayLoad' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ArrayLoad',
            inputs => $self->inputs,
            attributes => {
                array_id => $array_id // ($array ? $array->id : undef),
                index_id => $index_id // ($index ? $index->id : undef),
                bounds_check => $bounds_check,
            },
        };
    }

    method peephole($graph = undef) {
        # Bounds check elimination/conversion
        if ($bounds_check && defined($array) && defined($index)) {
            # Check if both array length and index are constant
            if ($array isa Chalk::IR::Node::NewArray && defined($array->length)) {
                my $len_node = $array->length;
                if ($len_node isa Chalk::IR::Node::Constant &&
                    $index isa Chalk::IR::Node::Constant) {

                    my $len = $len_node->value;
                    my $idx = $index->value;

                    # Always out of bounds - replace with Panic
                    if ($idx < 0 || $idx >= $len) {
                        use Chalk::IR::Node::Panic;
                        return Chalk::IR::Node::Panic->new(
                            inputs => [],
                            message => "Array index $idx out of bounds [0..$len)"
                        );
                    }

                    # Always in bounds - can eliminate check
                    # Return new ArrayLoad without bounds_check
                    return Chalk::IR::Node::ArrayLoad->new(
                        inputs => $self->inputs,
                        array_id => $array_id // ($array ? $array->id : undef),
                        index_id => $index_id // ($index ? $index->id : undef),
                        array => $array,
                        index => $index,
                        bounds_check => 0,
                    );
                }
            }
        }

        return $self;
    }

    method execute($context) {
        # Get the heap ID from the array node
        my $heap_id = defined($array)
            ? $context->("node:" . $array->id)
            : $context->("node:$array_id");

        # Get the index value
        my $idx = defined($index)
            ? $context->("node:" . $index->id)
            : $context->("node:$index_id");

        my $env = $context->('env:');

        # Bounds check at runtime if enabled
        if ($bounds_check) {
            my $len = $env->get_array_length($heap_id);
            if (defined($len) && ($idx < 0 || $idx >= $len)) {
                die "PANIC: Array index $idx out of bounds [0..$len)";
            }
        }

        return $env->lookup_heap($heap_id, $idx);
    }
}

1;
