# ABOUTME: Captures and formats step-by-step execution traces for debugging
# ABOUTME: Provides human-readable logs of CEK interpreter execution flow
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Interpreter::ExecutionLog {
    field $entries :reader;     # Array of log entries
    field $graph :param;        # IR graph being executed

    ADJUST {
        $entries = [];
    }

    method add_step($step_number, $step_report) {
        # Add a step report to the log
        my $entry = {
            step => $step_number,
            node_id => $step_report->{node_id},
            node_op => $step_report->{node_op},
            value => $step_report->{value},
            done => $step_report->{done},
            ready_queue_size => $step_report->{ready_queue_size},
            waiting_count => $step_report->{waiting_count},
            newly_ready => $step_report->{newly_ready} // [],
        };

        push $entries->@*, $entry;
        return;
    }

    method format_text() {
        # Format log as plain text
        my @lines;

        push @lines, "=== CEK Interpreter Execution Log ===";
        push @lines, "";

        foreach my $entry ($entries->@*) {
            my $step = $entry->{step};
            my $node_id = $entry->{node_id} // '(none)';
            my $op = $entry->{node_op} // 'N/A';
            my $value = defined($entry->{value}) ? $entry->{value} : 'undef';
            my $done = $entry->{done} ? 'DONE' : 'continue';

            push @lines, sprintf("Step %d: %s (%s) => %s  [%s]",
                $step, $node_id, $op, $value, $done);

            # Show queue status
            push @lines, sprintf("  Ready: %d nodes, Waiting: %d nodes",
                $entry->{ready_queue_size},
                $entry->{waiting_count});

            # Show newly ready nodes
            if ($entry->{newly_ready}->@*) {
                my $ready_list = join(', ', $entry->{newly_ready}->@*);
                push @lines, "  Newly ready: $ready_list";
            }

            push @lines, "";
        }

        push @lines, "=== End of Execution Log ===";

        return join("\n", @lines);
    }

    method format_detailed() {
        # Format log with more detail including node inputs
        my @lines;
        my $nodes = $graph->nodes;

        push @lines, "=== CEK Interpreter Detailed Execution Log ===";
        push @lines, "";

        foreach my $entry ($entries->@*) {
            my $step = $entry->{step};
            my $node_id = $entry->{node_id};

            unless ($node_id) {
                push @lines, sprintf("Step %d: Execution complete", $step);
                push @lines, sprintf("  Final value: %s", $entry->{value} // 'undef');
                push @lines, "";
                next;
            }

            my $node = $nodes->{$node_id};
            my $op = $entry->{node_op};
            my $value = defined($entry->{value}) ? $entry->{value} : 'undef';
            my $inputs = $node->inputs;

            push @lines, sprintf("Step %d: Execute %s", $step, $node_id);
            push @lines, sprintf("  Operation: %s", $op);
            push @lines, sprintf("  Inputs: [%s]", join(', ', $inputs->@*));
            push @lines, sprintf("  Result: %s", $value);

            # Show attributes for specific node types
            my $node_hash = $node->to_hash();
            if (my $attrs = $node_hash->{attributes}) {
                if (keys $attrs->%*) {
                    my @attr_strs = map {
                        sprintf("%s=%s", $_, $attrs->{$_} // 'undef')
                    } sort keys $attrs->%*;
                    push @lines, sprintf("  Attributes: %s", join(', ', @attr_strs));
                }
            }

            # Show status
            push @lines, sprintf("  Status: %s", $entry->{done} ? 'COMPLETE' : 'continuing');
            push @lines, sprintf("  Queue: %d ready, %d waiting",
                $entry->{ready_queue_size},
                $entry->{waiting_count});

            # Show newly ready nodes
            if ($entry->{newly_ready}->@*) {
                push @lines, sprintf("  Became ready: %s",
                    join(', ', $entry->{newly_ready}->@*));
            }

            push @lines, "";
        }

        push @lines, "=== End of Detailed Log ===";

        return join("\n", @lines);
    }

    method format_summary() {
        # Format a brief summary
        my $total_steps = scalar($entries->@*);
        my $final_entry = $entries->[-1];

        my @lines;
        push @lines, "=== Execution Summary ===";
        push @lines, sprintf("Total steps: %d", $total_steps);

        if ($final_entry) {
            push @lines, sprintf("Final result: %s",
                defined($final_entry->{value}) ? $final_entry->{value} : 'undef');
            push @lines, sprintf("Status: %s",
                $final_entry->{done} ? 'Completed' : 'Incomplete');
        }

        # Count node types executed
        my %op_counts;
        foreach my $entry ($entries->@*) {
            if (my $op = $entry->{node_op}) {
                $op_counts{$op}++;
            }
        }

        if (keys %op_counts) {
            push @lines, "";
            push @lines, "Node types executed:";
            foreach my $op (sort keys %op_counts) {
                push @lines, sprintf("  %s: %d", $op, $op_counts{$op});
            }
        }

        return join("\n", @lines);
    }

    method get_step_count() {
        return scalar($entries->@*);
    }

    method get_entry($step_number) {
        # Get a specific log entry (0-indexed)
        return undef if $step_number < 0 || $step_number >= $entries->@*;
        return $entries->[$step_number];
    }
}

1;

