# ABOUTME: Singleton factory for creating IR nodes with hash consing deduplication
# ABOUTME: Ensures identical computation graphs share node instances
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::NodeFactory {

    # Static imports for all node types (eliminates need for dynamic loading)
    use Chalk::Bootstrap::IR::Node::Start;
    use Chalk::Bootstrap::IR::Node::Return;
    use Chalk::Bootstrap::IR::Node::Constant;
    use Chalk::Bootstrap::IR::Node::Constructor;

    # Singleton instance
    my $instance;

    # Cache mapping hash keys to nodes for deduplication
    field $node_cache = {};

    # Define input parameter names for each operation type (in order)
    # Constructor uses compound keys: "Constructor:Class" format
    my %INPUT_SPECS = (
        Start => [],
        Return => ['value'],
        Constant => [],  # Constant has attributes, not inputs
        'Constructor:Symbol'     => ['type', 'value', 'quantifier'],
        'Constructor:Expression' => ['elements'],
        'Constructor:Rule'       => ['name', 'expressions'],
    );

    # Get singleton instance
    sub instance {
        $instance //= Chalk::Bootstrap::IR::NodeFactory->new;
        return $instance;
    }

    # Reset singleton and cache for testing (prevents cross-test contamination)
    # Call at the beginning of each test file to ensure clean state
    sub reset_for_testing {
        $instance = undef;
        return;
    }

    # Create or retrieve a node
    # $operation: string like 'Constant', 'Constructor', etc.
    # %params: named parameters (inputs and attributes)
    method make($operation, %params) {
        # For Constructor, use compound key for INPUT_SPECS lookup
        my $lookup_key = $operation;
        if ($operation eq 'Constructor') {
            my $class = $params{class}
                or die "Constructor requires 'class' parameter";
            $lookup_key = "Constructor:$class";
        }

        # Get input specification for this operation
        my $input_names = $INPUT_SPECS{$lookup_key}
            or die "Unknown operation: $lookup_key";

        # Separate inputs from attributes
        my @inputs;
        for my $name ($input_names->@*) {
            push @inputs, delete $params{$name};
        }
        my %attributes = %params;

        # Generate hash key for deduplication
        my $key = $self->_make_key($operation, \@inputs, \%attributes);

        # Return cached node if exists
        return $node_cache->{$key} if exists $node_cache->{$key};

        # Create new node (node classes loaded statically at compile time)
        # Constructor is a special case - class is always Constructor, not derived from operation
        my $node_class = "Chalk::Bootstrap::IR::Node::$operation";
        my $node = $node_class->new(
            id => $key,
            inputs => \@inputs,
            %attributes,
        );

        # Register this node as a consumer of its inputs
        for my $input (@inputs) {
            if (!defined $input) {
                next;
            }
            elsif (ref($input) eq 'ARRAY') {
                # Handle array of nodes
                for my $element ($input->@*) {
                    $element->add_consumer($node) if defined $element;
                }
            }
            else {
                # Single node
                $input->add_consumer($node);
            }
        }

        # Cache and return
        $node_cache->{$key} = $node;
        return $node;
    }

    # Return the number of nodes currently in the cache
    method node_count() {
        return scalar keys $node_cache->%*;
    }

    # Return a sorted arrayref of all node IDs in the cache
    method all_node_ids() {
        return [ sort keys $node_cache->%* ];
    }

    # Retrieve a node by its ID, or undef if not found
    method get_node($id) {
        return $node_cache->{$id};
    }

    # Remove a node from the cache by its ID
    # Dies if the node still has consumers to protect hash consing invariant
    method remove_node($id) {
        my $node = $node_cache->{$id};
        if (defined $node && scalar($node->consumers()->@*) > 0) {
            die "Cannot remove node '$id' that still has consumers";
        }
        delete $node_cache->{$id};
        return;
    }

    # Generate deterministic hash key from operation, inputs, and attributes
    method _make_key($operation, $inputs, $attributes) {
        my @parts = ($operation);

        # Add input IDs in source order
        if ($inputs) {
            for my $input ($inputs->@*) {
                if (!defined $input) {
                    push @parts, 'undef';
                }
                elsif (ref($input) eq 'ARRAY') {
                    # Handle array of nodes (e.g., elements in Constructor:Expression)
                    my @ids = map { defined($_) ? $_->id : 'undef' } $input->@*;
                    push @parts, '[' . join(',', @ids) . ']';
                }
                else {
                    # Single node
                    push @parts, $input->id;
                }
            }
        }

        # Add attributes in alphabetical order
        for my $key (sort keys %$attributes) {
            my $value = $attributes->{$key};
            my $value_str = defined($value) ? $value : 'undef';
            push @parts, "$key=$value_str";
        }

        return join('|', @parts);
    }
}
