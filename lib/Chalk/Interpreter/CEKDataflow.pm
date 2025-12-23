# ABOUTME: CESK-style interpreter with dataflow scheduling for Sea of Nodes IR execution
# ABOUTME: Uses Store semantics (S) for node values; replaces tree-walking Control with ready queue
use 5.42.0;
use experimental qw(class);
use utf8;

use Chalk::Interpreter::Environment;

class Chalk::Interpreter::CEKDataflow {
    field $graph :param :reader;
    field $max_iterations :param = 10000;  # Safety limit for loop iterations

    # Architecture: CESK-style machine with dataflow scheduling
    #
    # Traditional CEK/CESK machines use "Control" (C) as a pointer into the AST,
    # walking the expression tree depth-first. This interpreter replaces tree-walking
    # with dataflow scheduling: instead of "what expression am I evaluating now?",
    # we ask "which nodes have all dependencies satisfied?"
    #
    # Components:
    #   - $ready_queue replaces Control: nodes ready to execute (dependencies met)
    #   - $environment (E): maps node IDs to computed values (Store semantics)
    #   - $kontinuation (K): control flow continuation
    #   - $waiting: tracks unmet dependencies for each node
    #
    # This is a natural fit for Sea of Nodes IR where data flows between graph nodes.

    field $environment;    # Environment/Store: maps node IDs to computed values
    field $ready_queue;    # Dataflow ready queue (replaces tree-walking Control)
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

        # Track iterations per loop node
        my %loop_iterations;

        # Build waiting map: tracks unmet dependencies for each node
        my %waiting;
        foreach my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            my $inputs = $node->inputs;

            if ($inputs->@* == 0) {
                # No dependencies, ready to execute immediately
                push $ready_queue->@*, $node_id;
            } else {
                # Special case for Loop nodes: only wait for entry input (index 0) initially
                # The backedge (index 1) creates a circular dependency that's resolved during iteration
                if ($node->op eq 'Loop') {
                    # Only wait for first input (entry control)
                    if ($inputs->@* > 0) {
                        $waiting{$node_id} = { $inputs->[0] => 1 };
                    }
                }
                # Special case for Phi nodes in loops: skip backedge input (last input)
                # Phi inputs: [region_id, entry_value, backedge_value, ...]
                # The backedge value creates a circular dependency
                elsif ($node->op eq 'Phi' && $node->can('region_id')) {
                    my $region_id = $node->region_id;
                    my $region_node = $nodes->{$region_id};
                    if ($region_node && $region_node->op eq 'Loop') {
                        # For Loop Phis, only wait for region and entry value (first 2 inputs)
                        # Skip backedge value (input[2] and beyond)
                        my @init_deps = $inputs->@[0..1];  # region_id and entry value
                        $waiting{$node_id} = { map { $_ => 1 } @init_deps };
                    } else {
                        # Regular Phi (non-Loop), wait for all inputs
                        $waiting{$node_id} = { map { $_ => 1 } $inputs->@* };
                    }
                } else {
                    # Has dependencies, track them
                    $waiting{$node_id} = { map { $_ => 1 } $inputs->@* };
                }
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
                elsif ($key eq 'graph:') {
                    return $graph;
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

            # Special handling for Return with inactive control:
            # Don't mark as computed so it can be re-evaluated when control changes
            if ($node->op eq 'Return' && !defined($value)) {
                # Re-add to waiting with uncomputed dependencies
                my $inputs = $node->inputs;
                my %deps;
                for my $input_id ($inputs->@*) {
                    unless ($computed{$input_id}) {
                        $deps{$input_id} = 1;
                    }
                }
                if (keys %deps) {
                    $waiting{$node_id} = \%deps;
                }
                # Don't mark as computed - will re-execute when deps change
            } else {
                $computed{$node_id} = 1;
            }

            # Handle Loop iteration
            if ($node->op eq 'Loop') {
                my $active_idx = $value;  # Loop.execute returns active path index

                if ($active_idx > 0) {
                    # Backedge is active - need to iterate
                    $loop_iterations{$node_id}++;
                    if ($loop_iterations{$node_id} > $max_iterations) {
                        die "Loop exceeded iteration limit ($max_iterations iterations)";
                    }

                    # Latch Loop Phi values (like Simple's latchLoopPhis)
                    # Compute all Phi values FIRST using previous iteration values
                    # This breaks the circular dependency: Phi <- Add <- Phi
                    my @phi_nodes;
                    my @phi_values;
                    for my $pid (keys $nodes->%*) {
                        my $pnode = $nodes->{$pid};
                        if ($pnode->op eq 'Phi' && $pnode->can('region_id') && $pnode->region_id eq $node_id) {
                            push @phi_nodes, $pid;
                            # Phi uses Loop's active_input_index to select value
                            # Index 0 = entry (input[1]), Index 1+ = backedge (input[2+])
                            my $phi_inputs = $pnode->inputs;
                            my $value_idx = $active_idx + 1;  # inputs[0] is region_id
                            if ($value_idx < scalar($phi_inputs->@*)) {
                                my $value_id = $phi_inputs->[$value_idx];
                                my $phi_val = $environment->lookup_node($value_id);
                                push @phi_values, $phi_val;
                            }
                        }
                    }
                    # Store all Phi values atomically (prevents read-before-write issues)
                    for my $i (0..$#phi_nodes) {
                        $environment->set_node($phi_nodes[$i], $phi_values[$i]);
                        $computed{$phi_nodes[$i]} = 1;
                    }

                    # Reset non-Phi loop body nodes for re-execution
                    # Two-pass approach: first delete ALL from computed, then calculate deps
                    # This ensures correct dependency tracking (not using stale computed state)
                    my @body_nodes = $self->find_loop_body_nodes($node_id);

                    # Pass 1: Delete all non-Phi body nodes from computed
                    for my $body_id (@body_nodes) {
                        my $body_node = $nodes->{$body_id};
                        next if $body_node->op eq 'Phi';
                        delete $computed{$body_id};
                    }

                    # Pass 2: Calculate dependencies and queue
                    for my $body_id (@body_nodes) {
                        my $body_node = $nodes->{$body_id};
                        next if $body_node->op eq 'Phi';

                        # Re-calculate waiting dependencies
                        my $inputs = $body_node->inputs;
                        if ($inputs->@* > 0) {
                            my %deps;
                            for my $input_id ($inputs->@*) {
                                # Only wait on inputs that aren't computed
                                unless ($computed{$input_id}) {
                                    $deps{$input_id} = 1;
                                }
                            }
                            if (keys %deps) {
                                $waiting{$body_id} = \%deps;
                            } else {
                                # All deps satisfied, add to ready queue
                                push $ready_queue->@*, $body_id;
                            }
                        } else {
                            push $ready_queue->@*, $body_id;
                        }
                    }

                    # Also reset Return nodes that depend on body nodes
                    # This ensures Return re-evaluates when exit control becomes active
                    my %body_set = map { $_ => 1 } @body_nodes;
                    for my $nid (keys $nodes->%*) {
                        my $n = $nodes->{$nid};
                        next unless $n->op eq 'Return';
                        my $ninputs = $n->inputs;
                        # Check if Return depends on any body node
                        my $depends_on_body = 0;
                        for my $input_id ($ninputs->@*) {
                            if ($body_set{$input_id}) {
                                $depends_on_body = 1;
                                last;
                            }
                        }
                        if ($depends_on_body) {
                            # Reset Return so it re-evaluates with new control value
                            delete $computed{$nid};
                            # Remove from ready_queue if present (prevents duplicate execution)
                            $ready_queue->@* = grep { $_ ne $nid } $ready_queue->@*;
                            my %deps;
                            for my $input_id ($ninputs->@*) {
                                unless ($computed{$input_id}) {
                                    $deps{$input_id} = 1;
                                }
                            }
                            if (keys %deps) {
                                $waiting{$nid} = \%deps;
                            } else {
                                # Only re-queue Return if its control is active (exit path)
                                # If control is inactive (0), the loop is still iterating
                                my $control_id = $ninputs->[0];  # Return's first input is control
                                my $control_val = $environment->lookup_node($control_id);
                                if ($control_val) {
                                    push $ready_queue->@*, $nid;
                                }
                                # If control inactive, don't queue - loop continues until exit
                            }
                        }
                    }
                }
            }

            # Check if this was a Return node (potential terminal)
            # Only stop if the Return returned a value (active path)
            # Inactive paths return undef and execution should continue
            if ($node->op eq 'Return') {
                if (defined($value)) {
                    $result = $value;
                    $found_return = 1;
                    last;
                }
                # Inactive Return - continue execution to find active path
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

            # Check if this is an active Proj that's a backedge to a Loop
            # This check happens AFTER waiting nodes are updated
            if ($node->op eq 'Proj' && $value == 1) {
                # Find any Loop nodes that have this Proj as a backedge input
                for my $potential_loop_id (keys $nodes->%*) {
                    my $potential_loop = $nodes->{$potential_loop_id};
                    next unless $potential_loop->op eq 'Loop';

                    my $loop_inputs = $potential_loop->inputs;
                    # Check if this Proj is a backedge (input[1] or later)
                    for my $i (1 .. $#$loop_inputs) {
                        if ($loop_inputs->[$i] eq $node_id) {
                            # This Proj is a backedge to this Loop
                            # Deactivate the entry path so Loop will see backedge as active path
                            my $entry_id = $loop_inputs->[0];
                            $environment->set_node($entry_id, 0);
                            # Re-queue the Loop for execution
                            push $ready_queue->@*, $potential_loop_id;
                            last;
                        }
                    }
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
            elsif ($key eq 'graph:') {
                return $graph;
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

    method find_loop_body_nodes($loop_id) {
        # Find all nodes that are part of the loop body
        # These are nodes that need to be re-executed on each iteration
        my $nodes = $graph->nodes;
        my %body_nodes;
        my @to_process;

        # Start with Phi nodes attached to this Loop
        for my $node_id (keys $nodes->%*) {
            my $node = $nodes->{$node_id};
            if ($node->op eq 'Phi') {
                # Check if this Phi is attached to our Loop
                if ($node->can('region_id') && $node->region_id eq $loop_id) {
                    $body_nodes{$node_id} = 1;
                    push @to_process, $node_id;
                }
            }
        }

        # Also include nodes that depend on the Loop node itself (control path)
        # This catches If nodes that use Loop as control input
        for my $node_id (keys $nodes->%*) {
            next if $body_nodes{$node_id};
            next if $node_id eq $loop_id;
            my $node = $nodes->{$node_id};
            my $inputs = $node->inputs;
            if (grep { $_ eq $loop_id } $inputs->@*) {
                # This node depends on the Loop control
                next if $node->op eq 'Return';
                next if $node->op eq 'Stop';
                next if $node->op eq 'Phi';  # Phi already handled above
                $body_nodes{$node_id} = 1;
                push @to_process, $node_id;
            }
        }

        # Find dependents of body nodes (nodes that use their outputs)
        while (@to_process) {
            my $current_id = shift @to_process;
            for my $node_id (keys $nodes->%*) {
                next if $body_nodes{$node_id};  # Already found
                next if $node_id eq $loop_id;   # Never include the Loop itself in its body
                my $node = $nodes->{$node_id};
                my $inputs = $node->inputs;
                if (grep { $_ eq $current_id } $inputs->@*) {
                    # This node depends on a loop body node
                    # Only include if it's not a control flow exit (Return, etc.)
                    next if $node->op eq 'Return';
                    next if $node->op eq 'Stop';
                    $body_nodes{$node_id} = 1;
                    push @to_process, $node_id;
                }
            }
        }

        return keys %body_nodes;
    }
}

1;
