# ABOUTME: Compilation error class for formatted error reporting with source location
# ABOUTME: Provides rich error messages with context, hints, and source code display
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::Error::CompilationError {
    use overload '""' => 'as_string', fallback => 1;

    field $message      :param :reader;
    field $source_info  :param :reader = undef;
    field $hints        :param :reader = undef;
    field $source_lines :param :reader = undef;
    field $severity     :param :reader = 'error';

    # Format error for display
    method format() {
        my @lines;

        # Add severity and message
        my $severity_label = uc($severity);
        push @lines, "$severity_label: $message";

        # Add source location if available
        if ($source_info) {
            my $location = $source_info->to_string();
            push @lines, "  --> $location";

            # Add source context if available
            if ($source_lines) {
                push @lines, $self->_format_source_context();
            }
        }

        # Add hints if available
        if ($hints && $hints->@*) {
            push @lines, "";
            for my $hint ($hints->@*) {
                push @lines, "  hint: $hint";
            }
        }

        return join("\n", @lines);
    }

    # Format source code context with caret indicators
    method _format_source_context() {
        my @context_lines;

        my $start_line = $source_info->start_line;
        my $end_line   = $source_info->end_line;
        my $start_col  = $source_info->start_col;
        my $end_col    = $source_info->end_col;

        # Calculate line number width for padding
        my $line_num_width = length($end_line);

        # Show source lines
        my @lines = $source_lines->@*;
        for my $i (0 .. $#lines) {
            my $line_num = $i + 1;
            next if $line_num < $start_line - 1 || $line_num > $end_line + 1;

            my $line = $lines[$i];
            my $padded_num = sprintf("%${line_num_width}d", $line_num);

            if ($line_num >= $start_line && $line_num <= $end_line) {
                # This is an error line - show with caret
                push @context_lines, "  $padded_num | $line";

                # Add caret line
                if ($start_line == $end_line) {
                    # Single line error
                    my $spaces = ' ' x ($start_col - 1);
                    my $carets = '^' x ($end_col - $start_col + 1);
                    my $padding = ' ' x ($line_num_width + 3);
                    push @context_lines, "$padding$spaces$carets";
                } elsif ($line_num == $start_line) {
                    # First line of multi-line error
                    my $spaces = ' ' x ($start_col - 1);
                    my $carets = '^' x (length($line) - $start_col + 1);
                    my $padding = ' ' x ($line_num_width + 3);
                    push @context_lines, "$padding$spaces$carets";
                } elsif ($line_num == $end_line) {
                    # Last line of multi-line error
                    my $carets = '^' x $end_col;
                    my $padding = ' ' x ($line_num_width + 3);
                    push @context_lines, "$padding$carets";
                } else {
                    # Middle lines
                    my $carets = '^' x length($line);
                    my $padding = ' ' x ($line_num_width + 3);
                    push @context_lines, "$padding$carets";
                }
            } else {
                # Context line
                push @context_lines, "  $padded_num | $line";
            }
        }

        return @context_lines;
    }

    # Stringify to message for simple error display
    method as_string($other = undef, $swap = undef) {
        my $result = $message;

        if ($source_info) {
            my $location = $source_info->to_string();
            $result = sprintf("%s at %s", $message, $location);
        }

        # Add hints if available
        if ($hints && $hints->@*) {
            $result .= "\n";
            for my $hint ($hints->@*) {
                $result .= "\nhint: $hint";
            }
        }

        return $result;
    }
}

1;
