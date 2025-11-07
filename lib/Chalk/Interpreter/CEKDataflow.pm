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

    # Step-by-step execution state (Phase 4 Task 2)
    field $computed;       # Hash of computed nodes
    field $waiting;        # Hash of waiting dependencies
    field $result;         # Final result value
    field $step_initialized;  # Whether stepping has been initialized

    ADJUST {
        # Initialize CEK components
        $ready_queue = [];
        $kontinuation = undef;
        $environment = undef;

        # Initialize stepping state
        $computed = undef;
        $waiting = undef;
        $result = undef;
        $step_initialized = 0;
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
        foreach my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            my $inputs = $node->inputs;

            if ($inputs->@* == 0) {
                # No dependencies, ready to execute immediately
                push $ready_queue->@*, $node_id;
            } else {
                # Has dependencies, track them
                $waiting{$node_id} = { map { $_ => 1 } $inputs->@* };
            }
        }

        # Process nodes in dataflow order
        my $result;
        my $found_return = 0;
        while ($ready_queue->@*) {
            my $node_id = shift $ready_queue->@*;
            my $node = $nodes->{$node_id};

            # Create context closure for node execution
            my $context = sub ($key) {
                if ($key =~ qr/^node:(.+)$/) {
                    my $node_id = $1;
                    return $environment->lookup_node($node_id);
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
                $found_return = 1;
                last;
            }

            # Update waiting nodes - check if any become ready
            foreach my $waiting_id (keys %waiting) {
                # Remove this node from waiting list
                delete $waiting{$waiting_id}->{$node_id};

                # If all dependencies satisfied, add to ready queue
                if (keys $waiting{$waiting_id}->%* == 0) {
                    push $ready_queue->@*, $waiting_id;
                    delete $waiting{$waiting_id};
                }
            }
        }

        # Validate that execution found a Return node
        die "CEKDataflow: No Return node found in IR graph - execution completed without result"
            unless $found_return;

        return $result;
    }

    # Snapshot/restore functionality for Phase 4
    method snapshot_execution_state($computed, $waiting) {
        # Create a complete snapshot of execution state
        # Captures environment + execution state (ready queue, computed, waiting)
        return {
            environment => $environment->snapshot(),
            ready_queue => [ $ready_queue->@* ],
            computed => { $computed->%* },
            waiting => {
                map { $_ => { $waiting->{$_}->%* } } keys $waiting->%*
            },
            kontinuation => $kontinuation,
        };
    }

    method restore_from_snapshot($snapshot) {
        # Restore execution state from a snapshot
        # Returns the restored state as ($environment, $ready_queue, $computed, $waiting, $kontinuation)
        my $restored_env = $environment->restore_from_snapshot($snapshot->{environment});

        my $restored_ready_queue = [ @{$snapshot->{ready_queue}} ];

        my $restored_computed = { $snapshot->{computed}->%* };

        my $restored_waiting = {
            map { $_ => { $snapshot->{waiting}->{$_}->%* } }
            keys $snapshot->{waiting}->%*
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

    # Step-by-step execution mode (Phase 4 Task 2)
    method initialize_stepping() {
        # Initialize for step-by-step execution
        $environment = Chalk::Interpreter::Environment->new();
        $computed = {};
        $waiting = {};
        $result = undef;
        $step_initialized = 1;

        # Get all nodes from the graph
        my $nodes = $graph->nodes;

        # Build waiting map: tracks unmet dependencies for each node
        foreach my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            my $inputs = $node->inputs;

            if ($inputs->@* == 0) {
                # No dependencies, ready to execute immediately
                push $ready_queue->@*, $node_id;
            } else {
                # Has dependencies, track them
                $waiting->{$node_id} = { map { $_ => 1 } $inputs->@* };
            }
        }

        return;
    }

    method step() {
        # Execute one step (one node) of the interpreter
        # Returns a hash with step information

        die "Must call initialize_stepping() first" unless $step_initialized;

        # Check if execution is complete
        if ($ready_queue->@* == 0) {
            return {
                done => 1,
                node_id => undef,
                value => $result,
                ready_queue_size => 0,
                waiting_count => scalar(keys $waiting->%*),
            };
        }

        # Get next node from ready queue
        my $node_id = shift $ready_queue->@*;
        my $nodes = $graph->nodes;
        my $node = $nodes->{$node_id};

        # Create context closure for node execution
        my $context = sub ($key) {
            if ($key =~ qr/^node:(.+)$/) {
                my $node_id = $1;
                return $environment->lookup_node($node_id);
            }
            elsif ($key eq 'env:') {
                return $environment;
            }
            return undef;
        };

        # Execute node
        my $value;
        if ($node->op eq 'Start' || $node->op eq 'Constant') {
            $value = $node->execute();
        } else {
            $value = $node->execute($context);
        }

        # Store result in environment
        $environment->set_node($node_id, $value);
        $computed->{$node_id} = 1;

        # Check if this was the Return node (terminal)
        my $is_return = 0;
        if ($node->op eq 'Return') {
            $result = $value;
            $is_return = 1;
        }

        # Update waiting nodes - check if any become ready
        my @newly_ready;
        foreach my $waiting_id (keys $waiting->%*) {
            # Remove this node from waiting list
            delete $waiting->{$waiting_id}->{$node_id};

            # If all dependencies satisfied, add to ready queue
            if (keys $waiting->{$waiting_id}->%* == 0) {
                push $ready_queue->@*, $waiting_id;
                push @newly_ready, $waiting_id;
                delete $waiting->{$waiting_id};
            }
        }

        return {
            done => $is_return,
            node_id => $node_id,
            node_op => $node->op,
            value => $value,
            ready_queue_size => scalar($ready_queue->@*),
            waiting_count => scalar(keys $waiting->%*),
            newly_ready => \@newly_ready,
        };
    }

    method is_stepping_complete() {
        # Check if step-by-step execution is complete
        return $ready_queue->@* == 0 && scalar(keys $waiting->%*) == 0;
    }

    method get_step_state() {
        # Get current state for inspection
        return {
            ready_queue => [ $ready_queue->@* ],
            waiting => { map { $_ => { $waiting->{$_}->%* } } keys $waiting->%* },
            computed => { $computed->%* },
            result => $result,
        };
    }
}

1;
