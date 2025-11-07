# ABOUTME: CEK machine with dataflow scheduling for Sea of Nodes IR execution
# ABOUTME: Implements Control-Environment-Kontinuation model with promise-style dependencies
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::Interpreter::Environment;

class Chalk::Interpreter::CEKDataflow {
    field $graph :param :reader;

    # CEK State Components
    field $environment;    # Environment with discrete contexts
    field $ready_queue;    # Dataflow ready queue
    field $kontinuation;   # Control flow continuation

    ADJUST {
        # Initialize CEK components
        $ready_queue = [];
        $kontinuation = undef;
        # Environment will be initialized when Environment class is implemented
        $environment = undef;
    }

    method execute() {
        # Initialize CEK components
        $environment = Chalk::Interpreter::Environment->new();

        # Get all nodes from the graph
        my $nodes = $graph->nodes;

        # Track which nodes have been computed
        my %computed;

        # Build waiting map: tracks unmet dependencies for each node
        my %waiting;
        foreach my $node_id (keys %$nodes) {
            my $node = $nodes->{$node_id};
            my $inputs = $node->inputs;

            if (@$inputs == 0) {
                # No dependencies, ready to execute immediately
                push @$ready_queue, $node_id;
            } else {
                # Has dependencies, track them
                $waiting{$node_id} = { map { $_ => 1 } @$inputs };
            }
        }

        # Process nodes in dataflow order
        my $result;
        while (@$ready_queue) {
            my $node_id = shift @$ready_queue;
            my $node = $nodes->{$node_id};

            # Create context closure for node execution
            my $context = sub ($key) {
                if ($key =~ /^node:(.+)$/) {
                    return $environment->lookup_node($1);
                }
                elsif ($key eq 'env:') {
                    return $environment;
                }
                return undef;
            };

            # Execute node - Start and Constant don't take context parameter
            my $value;
            if ($node->op eq 'Start' || $node->op eq 'Constant') {
                $value = $node->execute();
            } else {
                $value = $node->execute($context);
            }

            # Store result in environment
            $environment->set_node($node_id, $value);
            $computed{$node_id} = 1;

            # Check if this was the Return node (terminal)
            if ($node->op eq 'Return') {
                $result = $value;
                last;
            }

            # Update waiting nodes - check if any become ready
            foreach my $waiting_id (keys %waiting) {
                # Remove this node from waiting list
                delete $waiting{$waiting_id}{$node_id};

                # If all dependencies satisfied, add to ready queue
                if (keys %{$waiting{$waiting_id}} == 0) {
                    push @$ready_queue, $waiting_id;
                    delete $waiting{$waiting_id};
                }
            }
        }

        return $result;
    }

    # Snapshot/restore functionality for Phase 4
    method snapshot_execution_state($computed, $waiting) {
        # Create a complete snapshot of execution state
        # Captures environment + execution state (ready queue, computed, waiting)
        return {
            environment => $environment->snapshot(),
            ready_queue => [ @$ready_queue ],
            computed => { %$computed },
            waiting => {
                map { $_ => { %{$waiting->{$_}} } } keys %$waiting
            },
            kontinuation => $kontinuation,
        };
    }

    method restore_from_snapshot($snapshot) {
        # Restore execution state from a snapshot
        # Returns the restored state as ($environment, $ready_queue, $computed, $waiting, $kontinuation)
        my $restored_env = $environment->restore_from_snapshot($snapshot->{environment});

        my $restored_ready_queue = [ @{$snapshot->{ready_queue}} ];

        my $restored_computed = { %{$snapshot->{computed}} };

        my $restored_waiting = {
            map { $_ => { %{$snapshot->{waiting}{$_}} } }
            keys %{$snapshot->{waiting}}
        };

        my $restored_kontinuation = $snapshot->{kontinuation};

        return (
            $restored_env,
            $restored_ready_queue,
            $restored_computed,
            $restored_waiting,
            $restored_kontinuation
        );
    }
}

1;

__END__

=head1 NAME

Chalk::Interpreter::CEKDataflow - CEK machine with dataflow scheduling

=head1 SYNOPSIS

    use Chalk::Interpreter::CEKDataflow;
    use Chalk::IR::Graph;

    my $graph = Chalk::IR::Graph->new();
    # ... build graph ...

    my $interpreter = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interpreter->execute();

=head1 DESCRIPTION

This interpreter implements a CEK (Control-Environment-Kontinuation) machine
with dataflow scheduling for executing Sea of Nodes IR graphs. It unifies three
execution models:

=over 4

=item * CEK Machine: Explicit state (Control, Environment, Kontinuation)

=item * Functional Context: Immutable closure-based state management

=item * Dataflow Scheduling: Promise-style execution when dependencies resolve

=back

=head1 ARCHITECTURE

=head2 Discrete Context Architecture

The environment consists of discrete, independent contexts:

=over 4

=item * Node context: Computation results for each IR node

=item * Variable context: Variable bindings (lexical scope)

=item * Heap structures: Each array/hash/object is its own context

=back

This provides perfect isolation, actor model readiness, and natural distribution.

=head2 Execution Model

1. Initialize ready queue with nodes that have no dependencies
2. While ready queue is not empty:
   - Dequeue a ready node
   - Execute the node operation
   - Store result in environment
   - Check dependent nodes; add ready ones to queue
3. Return final result from Return node

=head1 METHODS

=head2 new(graph => $graph)

Constructor. Takes a Sea of Nodes IR graph.

=head2 execute()

Execute the graph using CEK dataflow scheduling. Returns the final result.

=head1 STATUS

Phase 1 implementation in progress. Currently supports:

=over 4

=item * Basic object construction

=item * CEK state initialization

=back

Not yet implemented:

=over 4

=item * Environment class integration

=item * Core operations (Const, Add, Sub, Mul, Div)

=item * Ready queue scheduling

=item * Control flow (If, Region, Phi)

=item * Heap operations

=back

=cut
