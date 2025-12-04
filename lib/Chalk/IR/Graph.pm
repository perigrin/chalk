# ABOUTME: Sea of Nodes IR graph container for Chalk compiler
# ABOUTME: Manages collection of IR nodes and provides JSON serialization for IR persistence
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Graph {
    use Chalk::IR::Node;

    field $nodes :reader = {};
    field $entry :reader = undef;
    field $uses = {};  # Use-def map: node_id => [user_id1, user_id2, ...]

    # Singleton instance for global graph access
    my $instance = undef;

    sub instance($class) {
        $instance //= $class->new();
        return $instance;
    }

    method add_node($node) {
        my $node_id = $node->id;

        # Add directly to graph
        $nodes->{$node_id} = $node;

        # Initialize use list for this node (empty initially)
        $uses->{$node_id} //= [];

        # Update use-def chains: for each input, add this node as a user
        for my $input_id ( $node->inputs->@* ) {
            next unless defined $input_id;  # Skip undefined inputs
            next if $input_id eq '__CONTROL_PLACEHOLDER__';  # Skip placeholders
            $uses->{$input_id} //= [];
            push $uses->{$input_id}->@*, $node_id;
        }

        # First node added becomes entry point
        $entry //= $node_id;

        return;
    }

    method get_node($id) {
        return $nodes->{$id};
    }

    method get_uses($id) {
        return $uses->{$id} // [];
    }

    # Remove a node from the graph and update use-def chains
    method remove_node($node_id) {
        my $node = $nodes->{$node_id};
        return unless $node;

        # Remove this node as a user of its inputs
        if ($node->can('inputs')) {
            for my $input_id ($node->inputs->@*) {
                next unless defined $input_id;
                next if $input_id eq '__CONTROL_PLACEHOLDER__';
                if (exists $uses->{$input_id}) {
                    $uses->{$input_id}->@* = grep { $_ ne $node_id } $uses->{$input_id}->@*;
                }
            }
        }

        # Remove this node's entry in uses (other nodes won't reference it)
        delete $uses->{$node_id};

        # Remove from graph
        delete $nodes->{$node_id};

        return;
    }

    # Kill a node with no uses, recursively killing inputs that become unused
    # This is the core of Dead Code Elimination (DCE)
    # Note: Safe against self-referential nodes - we capture input_ids before
    # calling remove_node, so if a node references itself, the recursive kill
    # call will find it already removed and return early.
    method kill($node_id) {
        my $node = $nodes->{$node_id};
        return unless $node;

        # Get inputs before removing the node
        my @input_ids;
        if ($node->can('inputs')) {
            @input_ids = grep { defined $_ && $_ ne '__CONTROL_PLACEHOLDER__' } $node->inputs->@*;
        }

        # Remove this node from the graph
        $self->remove_node($node_id);

        # Recursively kill inputs that are now unused
        for my $input_id (@input_ids) {
            my $input_uses = $self->get_uses($input_id);
            if (scalar($input_uses->@*) == 0) {
                $self->kill($input_id);
            }
        }

        return;
    }

    method node_count() {
        return scalar keys %{$nodes};
    }

    method set_entry($new_entry) {
        $entry = $new_entry;
        return;
    }

    method to_json() {
        my @node_list = map { $_->to_hash() } values %{$nodes};

        return {
            version => '1.0',
            entry   => $entry,
            nodes   => \@node_list,
        };
    }

    sub from_json( $class, $json ) {
        my $graph = $class->new();

        # Restore nodes in order
        for my $node_data ( $json->{nodes}->@* ) {
            my $node = Chalk::IR::Node->new(
                id         => $node_data->{id},
                op         => $node_data->{op},
                inputs     => $node_data->{inputs},
                attributes => $node_data->{attributes},
            );
            $graph->add_node($node);
        }

        # Set entry explicitly (in case it's not the first node)
        $graph->set_entry( $json->{entry} );

        return $graph;
    }

    # Linearize graph using topological sort
    # Returns array of nodes in execution order
    method linearize() {
        my @result;
        my %visited;
        my %in_progress;

        # Depth-first search for topological sort
        my $visit;
        $visit = sub {
            my ($node_id) = @_;
            return if $visited{$node_id};

            # Detect cycles
            die "Cycle detected at node $node_id" if $in_progress{$node_id};
            $in_progress{$node_id} = 1;

            my $node = $nodes->{$node_id};
            if ($node) {
                # Visit all dependencies (inputs) first
                for my $input_id ($node->inputs->@*) {
                    next unless defined $input_id;
                    next if $input_id eq '__CONTROL_PLACEHOLDER__';
                    $visit->($input_id);
                }
            }

            delete $in_progress{$node_id};
            $visited{$node_id} = 1;

            # Add node after all its dependencies
            push @result, $node if $node;
        };

        # Visit all nodes in the graph (not just from entry)
        # This ensures we get all nodes including those not reachable from entry
        # Parser compat: keys() requires parentheses around argument
        my @node_ids = keys($nodes->%*);
        for my $node_id (@node_ids) {
            $visit->($node_id);
        }

        return @result;
    }

    # Prune graph to only include nodes reachable from a given root node
    # This removes alternative parse trees after parser selects the winning parse
    method prune_to_reachable($root_node_id) {
        return unless defined $root_node_id;

        # Mark all nodes reachable from root by traversing backwards through inputs
        my %reachable = ();
        my @queue = ($root_node_id);

        while (@queue) {
            my $node_id = shift @queue;
            next if exists($reachable{$node_id});

            $reachable{$node_id} = 1;

            # Add all input nodes to queue
            my $node = $nodes->{$node_id};
            if ($node && $node->can('inputs')) {
                for my $input_id ($node->inputs->@*) {
                    next unless defined $input_id;
                    next if $input_id eq '__CONTROL_PLACEHOLDER__';
                    push @queue, $input_id unless exists($reachable{$input_id});
                }
            }
        }

        # Remove all unreachable nodes
        my @all_node_ids = keys %{$nodes};
        for my $node_id (@all_node_ids) {
            if (!exists($reachable{$node_id})) {
                delete $nodes->{$node_id};
                delete $uses->{$node_id};

                # Also remove from other nodes' use lists
                for my $use_list (values(%{$uses})) {
                    @$use_list = grep { $_ ne $node_id } @$use_list;
                }
            }
        }

        # Update entry point if it was pruned
        if (!exists($nodes->{$entry})) {
            $entry = $root_node_id;
        }

        return;
    }

    # Identify basic blocks from CFG nodes
    # Returns an array reference of basic blocks (arrays of CFG nodes)
    method basic_blocks() {
        my @blocks;

        # Collect all CFG nodes
        my @cfg_nodes;
        for my $node (values %{$nodes}) {
            if ($node->can('isCFG') && $node->isCFG) {
                push @cfg_nodes, $node;
            }
        }

        # For now, return a simple array of individual CFG nodes
        # Each CFG node starts its own basic block
        for my $cfg_node (@cfg_nodes) {
            push @blocks, [$cfg_node];
        }

        return \@blocks;
    }

    # Early scheduling: place unpinned data nodes at deepest input's control
    # Performs upward DFS from Stop, scheduling nodes conservatively early
    method schedule_early() {
        my %visited;
        my %schedule;  # Maps node_id -> control_node

        # Helper to check if a node is pinned (must stay at fixed location)
        my $is_pinned = sub {
            my ($node) = @_;
            return 0 unless $node;

            my $op = $node->can('op') ? $node->op : '';

            # Pinned nodes: CFG nodes, Phi nodes, Constants
            return 1 if $node->can('isCFG') && $node->isCFG;
            return 1 if $op eq 'Phi';
            return 1 if $op eq 'Constant';

            return 0;
        };

        # Upward DFS to find deepest dominating control for each node
        my $schedule_node;
        $schedule_node = sub {
            my ($node_id) = @_;
            return if $visited{$node_id};
            $visited{$node_id} = 1;

            my $node = $nodes->{$node_id};
            return unless $node;

            # First, schedule all inputs recursively
            if ($node->can('inputs')) {
                for my $input_id ($node->inputs->@*) {
                    next unless defined $input_id;
                    next if $input_id eq '__CONTROL_PLACEHOLDER__';
                    $schedule_node->($input_id);
                }
            }

            # If node is pinned, it stays where it is
            if ($is_pinned->($node)) {
                # Pinned nodes schedule themselves at their natural location
                if ($node->can('isCFG') && $node->isCFG) {
                    $schedule{$node_id} = $node_id;
                }
                return;
            }

            # For unpinned data nodes, find deepest input's control
            # The control block is determined by the input with maximum idepth
            my $deepest_ctrl = undef;
            my $max_depth = -1;

            if ($node->can('inputs')) {
                for my $input_id ($node->inputs->@*) {
                    next unless defined $input_id;
                    next if $input_id eq '__CONTROL_PLACEHOLDER__';

                    my $input_node = $nodes->{$input_id};
                    next unless $input_node;

                    # Get the control block for this input
                    my $input_ctrl = $schedule{$input_id};
                    if (defined $input_ctrl) {
                        my $ctrl_node = $nodes->{$input_ctrl};
                        if ($ctrl_node && $ctrl_node->can('idepth')) {
                            my $depth = $ctrl_node->idepth;
                            if ($depth > $max_depth) {
                                $max_depth = $depth;
                                $deepest_ctrl = $input_ctrl;
                            }
                        }
                    }
                }
            }

            # Schedule this node at the deepest control point
            if (defined $deepest_ctrl) {
                $schedule{$node_id} = $deepest_ctrl;
            }
        };

        # Start DFS from all nodes (backward traversal)
        my @node_ids = keys %{$nodes};
        for my $node_id (@node_ids) {
            $schedule_node->($node_id);
        }

        return \%schedule;
    }
}

1;
