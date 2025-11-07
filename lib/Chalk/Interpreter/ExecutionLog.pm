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

        push @$entries, $entry;
        return;
    }

    method format_text() {
        # Format log as plain text
        my @lines;

        push @lines, "=== CEK Interpreter Execution Log ===";
        push @lines, "";

        foreach my $entry (@$entries) {
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
            if (@{$entry->{newly_ready}}) {
                my $ready_list = join(', ', @{$entry->{newly_ready}});
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

        foreach my $entry (@$entries) {
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
            push @lines, sprintf("  Inputs: [%s]", join(', ', @$inputs));
            push @lines, sprintf("  Result: %s", $value);

            # Show attributes for specific node types
            my $node_hash = $node->to_hash();
            if (my $attrs = $node_hash->{attributes}) {
                if (keys %$attrs) {
                    my @attr_strs = map {
                        sprintf("%s=%s", $_, $attrs->{$_} // 'undef')
                    } sort keys %$attrs;
                    push @lines, sprintf("  Attributes: %s", join(', ', @attr_strs));
                }
            }

            # Show status
            push @lines, sprintf("  Status: %s", $entry->{done} ? 'COMPLETE' : 'continuing');
            push @lines, sprintf("  Queue: %d ready, %d waiting",
                $entry->{ready_queue_size},
                $entry->{waiting_count});

            # Show newly ready nodes
            if (@{$entry->{newly_ready}}) {
                push @lines, sprintf("  Became ready: %s",
                    join(', ', @{$entry->{newly_ready}}));
            }

            push @lines, "";
        }

        push @lines, "=== End of Detailed Log ===";

        return join("\n", @lines);
    }

    method format_summary() {
        # Format a brief summary
        my $total_steps = scalar(@$entries);
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
        foreach my $entry (@$entries) {
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
        return scalar(@$entries);
    }

    method get_entry($step_number) {
        # Get a specific log entry (0-indexed)
        return undef if $step_number < 0 || $step_number >= @$entries;
        return $entries->[$step_number];
    }
}

1;

__END__

=head1 NAME

Chalk::Interpreter::ExecutionLog - Execution trace logging for CEK interpreter

=head1 SYNOPSIS

    use Chalk::Interpreter::ExecutionLog;
    use Chalk::Interpreter::CEKDataflow;

    my $log = Chalk::Interpreter::ExecutionLog->new(graph => $graph);
    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);

    $interp->initialize_stepping();

    my $step_num = 1;
    while (!$interp->is_stepping_complete()) {
        my $step_report = $interp->step();
        $log->add_step($step_num++, $step_report);
        last if $step_report->{done};
    }

    # Print formatted logs
    say $log->format_text();
    say $log->format_detailed();
    say $log->format_summary();

=head1 DESCRIPTION

This module captures and formats execution traces from the CEK interpreter's
step-by-step execution mode. It provides multiple output formats for debugging
and understanding execution flow.

=head1 METHODS

=head2 new(graph => $graph)

Constructor. Takes the IR graph being executed.

=head2 add_step($step_number, $step_report)

Add a step report from CEKDataflow->step() to the log.

=head2 format_text()

Format log as plain text with one line per step.

=head2 format_detailed()

Format log with detailed information including node inputs and attributes.

=head2 format_summary()

Format a brief summary of execution including step count and node type counts.

=head2 get_step_count()

Returns the number of steps logged.

=head2 get_entry($step_number)

Get a specific log entry (0-indexed). Returns undef if out of range.

=head1 LOG FORMATS

=head2 Text Format

Concise one-line-per-step format showing node execution order and values.

=head2 Detailed Format

Verbose format showing node inputs, attributes, and dataflow information.

=head2 Summary Format

High-level overview showing total steps, final result, and node type statistics.

=cut
