# ABOUTME: Singleton factory for creating IR nodes with hash consing deduplication
# ABOUTME: Ensures identical computation graphs share node instances
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::NodeFactory;

class Chalk::Bootstrap::IR::NodeFactory {

    # Static imports for typed node classes (new namespace)
    use Chalk::IR::Node::Start;
    use Chalk::IR::Node::Return;
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;
    use Chalk::IR::Node::Phi;
    use Chalk::IR::Node::Loop;

    # Singleton instance
    my $instance;

    # Cache mapping hash keys to nodes for deduplication
    field $node_cache = {};

    # Counter for unique CFG node IDs (CFG nodes are not hash-consed)
    field $cfg_counter = 0;

    # New-style factory used to produce typed nodes for all Constructor classes
    field $_new_factory = undef;

    # CFG operations represent control flow positions, not data values.
    # Two if-statements at different program points must be distinct objects
    # even with identical inputs, because cfg_state maps by node identity.
    my %CFG_OPS = map { $_ => 1 } qw(If Proj Region Phi Loop);

    # Define input parameter names for each Bootstrap operation type (in order).
    # Constructor classes are handled entirely by the shim and do not appear here.
    my %INPUT_SPECS = (
        Start    => [],
        Return   => ['value'],
        Constant => [],  # Constant has attributes, not inputs
        If       => ['control', 'condition'],
        Proj     => ['source'],
        Region   => ['controls'],
        Phi      => ['region', 'values'],
        Loop     => ['entry_ctrl', 'backedge_ctrl'],
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

    # Lazily initialize the new-style factory on first use
    method _ensure_new_factory() {
        $_new_factory //= Chalk::IR::NodeFactory->new();
    }

    # Create a unique CFG node via the new-style factory.
    # CFG nodes (Return, Unwind, If, Proj, Region, Loop, Start) represent
    # control-flow positions and are never deduplicated — each call returns
    # a distinct object even when inputs are identical.
    # Delegates to Chalk::IR::NodeFactory::make_cfg so that the resulting
    # nodes are Chalk::IR::Node::* instances, not Bootstrap::IR::Node::*.
    method make_cfg($operation, %params) {
        $self->_ensure_new_factory();
        return $_new_factory->make_cfg($operation, %params);
    }

    # Create or retrieve a node
    # $operation: string like 'Constant' or one of the CFG ops.
    # %params: named parameters (inputs and attributes)
    #
    # Per Phase 6, the legacy make('Constructor', class => 'X', ...)
    # translation path is gone; callers construct typed nodes
    # directly via Chalk::IR::NodeFactory->make($OpName, ...).
    method make($operation, %params) {
        my $lookup_key = $operation;

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

        # CFG nodes get unique IDs and skip the cache entirely
        my $is_cfg = $CFG_OPS{$operation};
        if ($is_cfg) {
            $cfg_counter++;
            $key = "${key}#${cfg_counter}";
        } else {
            # Return cached node if exists (data nodes only)
            return $node_cache->{$key} if exists $node_cache->{$key};
        }

        # Create new node using new-namespace typed classes
        my $node_class = "Chalk::IR::Node::$operation";
        my $node;
        if ($operation eq 'Phi') {
            # Chalk::IR::Node::Phi takes region as a named :param, not in inputs.
            # INPUT_SPECS extracts @inputs = ($region, $values_arrayref).
            my ($phi_region, $phi_values) = @inputs;
            $node = $node_class->new(
                id     => $key,
                region => $phi_region,
                inputs => defined $phi_values ? $phi_values : [],
                %attributes,
            );
        } else {
            $node = $node_class->new(
                id => $key,
                inputs => \@inputs,
                %attributes,
            );
        }

        # Register this node as a consumer of its inputs
        for my $input (@inputs) {
            if (!defined $input) {
                next;
            }
            elsif (ref($input) eq 'ARRAY') {
                # Handle array of nodes (skip plain hashrefs — not IR nodes)
                for my $element ($input->@*) {
                    next unless defined $element;
                    next if ref($element) eq 'HASH';
                    $element->add_consumer($node);
                }
            }
            else {
                # Single node
                $input->add_consumer($node);
            }
        }

        # Cache and return (CFG nodes cached under unique key, so never deduplicated)
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
                    # Handle array of nodes or plain hashrefs
                    my @ids;
                    for my $element ($input->@*) {
                        if (!defined $element) {
                            push @ids, 'undef';
                        } elsif (ref($element) eq 'HASH') {
                            # Plain hashref (e.g., attribute {name=>..., value=>...})
                            my $hkey = join(',', map {
                                my $v = defined $element->{$_} ? $element->{$_} : 'undef';
                                "$_=$v";
                            } sort keys %$element);
                            push @ids, "{$hkey}";
                        } else {
                            push @ids, $element->id;
                        }
                    }
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
