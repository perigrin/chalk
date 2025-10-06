# ABOUTME: Preprocessor for Chalk::Parser to transform heredoc syntax to q{}/qq{}
# ABOUTME: Enables heredoc support without complex grammar rules via source transformation
package Chalk::Preprocessor;
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);

class Chalk::Preprocessor {
    field $input :param :reader;
    field $output :reader = '';
    field @line_map :reader;  # Maps output lines to input lines

    method transform() {
        $self->transform_heredocs();
    }

    method transform_heredocs() {
        my @lines = split /\n/, $input, -1;
        my @output_lines;
        my %line_mapping;
        my $input_line_num = 0;
        my $output_line_num = 0;

        # Process each line looking for heredoc declarations
        for (my $i = 0; $i < @lines; $i++) {
            $input_line_num = $i + 1;
            my $line = $lines[$i];

            my $matched = 0;
            my $is_single_quoted = 0;
            my $is_indented = 0;
            my $prefix = '';
            my $delimiter = '';
            my $suffix = '';

            # Check for indented single-quoted heredoc: <<~'DELIMITER'
            if ($line =~ /^(.*?)(<<~'([^']+)')(.*)$/) {
                ($prefix, $delimiter, $suffix) = ($1, $3, $4);
                $is_single_quoted = 1;
                $is_indented = 1;
                $matched = 1;
            }
            # Check for indented double-quoted heredoc: <<~"DELIMITER"
            elsif ($line =~ /^(.*?)(<<~"([^"]+)")(.*)$/) {
                ($prefix, $delimiter, $suffix) = ($1, $3, $4);
                $is_single_quoted = 0;
                $is_indented = 1;
                $matched = 1;
            }
            # Check for indented bare heredoc: <<~DELIMITER
            elsif ($line =~ /^(.*?)(<<~(\w+))(.*)$/) {
                ($prefix, $delimiter, $suffix) = ($1, $3, $4);
                $is_single_quoted = 0;
                $is_indented = 1;
                $matched = 1;
            }
            # Check for single-quoted heredoc: <<'DELIMITER'
            elsif ($line =~ /^(.*?)(<<'([^']+)')(.*)$/) {
                ($prefix, $delimiter, $suffix) = ($1, $3, $4);
                $is_single_quoted = 1;
                $matched = 1;
            }
            # Check for double-quoted heredoc: <<"DELIMITER"
            elsif ($line =~ /^(.*?)(<<"([^"]+)")(.*)$/) {
                ($prefix, $delimiter, $suffix) = ($1, $3, $4);
                $is_single_quoted = 0;
                $matched = 1;
            }
            # Check for bare heredoc: <<DELIMITER
            elsif ($line =~ /^(.*?)(<<(\w+))(.*)$/) {
                ($prefix, $delimiter, $suffix) = ($1, $3, $4);
                $is_single_quoted = 0;
                $matched = 1;
            }

            if ($matched) {
                # Collect heredoc content until we find the terminator
                my @heredoc_content;
                my $j = $i + 1;
                my $found_terminator = 0;

                while ($j < @lines) {
                    # For indented heredocs, the terminator can have leading whitespace
                    # For non-indented heredocs, terminator must be exact match
                    my $line_matches_delimiter = 0;
                    if ($is_indented) {
                        # Match terminator with optional leading whitespace
                        $line_matches_delimiter = ($lines[$j] =~ /^\s*\Q$delimiter\E$/);
                    } else {
                        # Exact match only
                        $line_matches_delimiter = ($lines[$j] eq $delimiter);
                    }

                    if ($line_matches_delimiter) {
                        $found_terminator = 1;
                        last;
                    }
                    push @heredoc_content, $lines[$j];
                    $j++;
                }

                if ($found_terminator) {
                    # Handle indentation stripping if <<~ was used
                    if ($is_indented) {
                        @heredoc_content = $self->strip_indentation(@heredoc_content);
                    }

                    # Transform to q{...} or qq{...}
                    my $content = join("\n", @heredoc_content);
                    my $quote_op = $is_single_quoted ? 'q' : 'qq';
                    my $transformed = "${prefix}${quote_op}{${content}}${suffix}";

                    push @output_lines, $transformed;
                    $line_mapping{$output_line_num} = $input_line_num;
                    $output_line_num++;

                    # Skip the heredoc content and terminator
                    $i = $j;
                } else {
                    # No terminator found, keep line as-is
                    push @output_lines, $line;
                    $line_mapping{$output_line_num} = $input_line_num;
                    $output_line_num++;
                }
            } else {
                # Not a heredoc line, keep as-is
                push @output_lines, $line;
                $line_mapping{$output_line_num} = $input_line_num;
                $output_line_num++;
            }
        }

        # Join output lines
        $output = join("\n", @output_lines);

        # Store line mapping
        @line_map = map { $line_mapping{$_} // $_ } 0..$#output_lines;
    }

    method strip_indentation(@lines) {
        return () unless @lines;

        # Find minimum indentation (count leading whitespace)
        my $min_indent = undef;
        for my $line (@lines) {
            # Skip empty lines when calculating minimum indentation
            next if $line =~ /^\s*$/;

            if ($line =~ /^(\s+)/) {
                my $indent = length($1);
                $min_indent = $indent if !defined($min_indent) || $indent < $min_indent;
            } else {
                # Line with no leading whitespace means min_indent is 0
                $min_indent = 0;
                last;
            }
        }

        # If all lines were empty or no indentation found, return as-is
        return @lines unless defined($min_indent) && $min_indent > 0;

        # Strip the minimum indentation from all lines
        my @stripped;
        for my $line (@lines) {
            if ($line =~ /^\s*$/) {
                # Keep empty lines as-is
                push @stripped, $line;
            } else {
                # Remove exactly $min_indent characters from the beginning
                my $stripped_line = $line;
                $stripped_line =~ s/^\s{$min_indent}//;
                push @stripped, $stripped_line;
            }
        }

        return @stripped;
    }

    method map_line($output_line) {
        return $line_map[$output_line] // $output_line;
    }
}

1;
