# ABOUTME: Grammar-based heredoc preprocessor for Chalk::Parser
# ABOUTME: Uses mini-grammar to correctly parse heredoc markers in code context
package Chalk::Preprocessor::HeredocV2;
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use Chalk::Preprocessor::HeredocGrammar;
use Chalk::Parser;

class Chalk::Preprocessor::HeredocV2 {
    field $input :param :reader;
    field $output :reader = '';
    field @line_map :reader;

    method transform() {
        my @lines = split /\n/, $input, -1;
        my @output_lines;
        my %line_mapping;
        my $output_line_num = 0;

        for (my $i = 0; $i < @lines; $i++) {
            my $input_line_num = $i + 1;
            my $line = $lines[$i];

            # Find heredoc markers in this line using the grammar
            my @heredocs = $self->find_heredocs_in_line($line);

            if (@heredocs) {
                # Collect content for each heredoc
                my $j = $i + 1;
                my @transformed_parts;
                my $all_found = 1;

                for my $hd (@heredocs) {
                    my @heredoc_content;
                    my $found_terminator = 0;

                    while ($j < @lines) {
                        my $line_matches = 0;
                        if ($hd->{is_indented}) {
                            $line_matches = ($lines[$j] =~ /^\s*\Q$hd->{delimiter}\E$/);
                        } else {
                            $line_matches = ($lines[$j] eq $hd->{delimiter});
                        }

                        if ($line_matches) {
                            $found_terminator = 1;
                            $j++;
                            last;
                        }
                        push @heredoc_content, $lines[$j];
                        $j++;
                    }

                    if ($found_terminator) {
                        if ($hd->{is_indented}) {
                            @heredoc_content = $self->strip_indentation(@heredoc_content);
                        }

                        my $content = join("\n", @heredoc_content);

                        # Recursively transform nested heredocs ONLY in double-quoted heredocs
                        # Single-quoted heredocs don't interpolate, so <<FOO inside them is literal
                        if (!$hd->{is_single_quoted}) {
                            my $inner_preprocessor = Chalk::Preprocessor::HeredocV2->new(input => $content);
                            $inner_preprocessor->transform();
                            $content = $inner_preprocessor->output;
                        }

                        my $quote_op = $hd->{is_single_quoted} ? 'q' : 'qq';
                        my ($open, $close) = $self->choose_delimiters($content);
                        push @transformed_parts, {
                            marker => $hd->{marker},
                            replacement => "${quote_op}${open}${content}${close}",
                        };
                    } else {
                        $all_found = 0;
                        last;
                    }
                }

                if ($all_found && @transformed_parts) {
                    # Replace markers with transformations
                    my $transformed = $line;
                    for my $part (@transformed_parts) {
                        $transformed =~ s/\Q$part->{marker}\E/$part->{replacement}/;
                    }

                    push @output_lines, $transformed;
                    $line_mapping{$output_line_num} = $input_line_num;
                    $output_line_num++;
                    $i = $j - 1;  # Skip content lines
                } else {
                    # Couldn't find terminators, keep original
                    push @output_lines, $line;
                    $line_mapping{$output_line_num} = $input_line_num;
                    $output_line_num++;
                }
            } else {
                # No heredocs, keep as-is
                push @output_lines, $line;
                $line_mapping{$output_line_num} = $input_line_num;
                $output_line_num++;
            }
        }

        $output = join("\n", @output_lines);
        @line_map = map { $line_mapping{$_} // $_ } 0..$#output_lines;
    }

    method find_heredocs_in_line($line) {
        # Scan for heredoc markers, but skip those inside strings or comments
        # Strategy: Find all heredocs first, then filter out those in strings/comments

        my @heredocs;
        my $working_line = $line;

        # First, find positions of strings and comments to exclude
        my @excluded_ranges;

        # Find single-quoted string ranges (but not heredoc markers like <<'EOF')
        while ($working_line =~ /(?<!<)'(?:[^'\\]|\\.)*'/g) {
            my $end = pos($working_line);
            my $start = $end - length($&);
            push @excluded_ranges, [$start, $end];
        }

        # Find double-quoted string ranges
        while ($working_line =~ /"(?:[^"\\]|\\.)*"/g) {
            my $end = pos($working_line);
            my $start = $end - length($&);
            push @excluded_ranges, [$start, $end];
        }

        # Find comment range (everything after # to end of line)
        if ($working_line =~ /#/) {
            push @excluded_ranges, [pos($working_line) - 1, length($working_line)];
        }

        # Helper to check if position is excluded
        my $is_excluded = sub {
            my ($pos) = @_;
            for my $range (@excluded_ranges) {
                return 1 if $pos >= $range->[0] && $pos < $range->[1];
            }
            return 0;
        };

        # Now find heredoc markers in what remains
        my @markers;

        # Order matters - check quoted forms before bare forms
        while ($working_line =~ /(<<~'([^']+)')/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 1, is_indented => 1 };
        }
        while ($working_line =~ /(<<~"([^"]+)")/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 0, is_indented => 1 };
        }
        while ($working_line =~ /(<<~\\(\w+))/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 1, is_indented => 1 };
        }
        while ($working_line =~ /(<<~(\w+))/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 0, is_indented => 1 };
        }
        while ($working_line =~ /(<<'([^']+)')/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 1, is_indented => 0 };
        }
        while ($working_line =~ /(<<"([^"]+)")/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 0, is_indented => 0 };
        }
        while ($working_line =~ /(<<\\(\w+))/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 1, is_indented => 0 };
        }
        while ($working_line =~ /(<<(\w+))/g) {
            my $pos = pos($working_line) - length($1);
            next if $is_excluded->($pos);
            push @markers, { marker => $1, delimiter => $2, is_single_quoted => 0, is_indented => 0 };
        }

        return @markers;
    }

    method strip_indentation(@lines) {
        return () unless @lines;

        my $min_indent = undef;
        for my $line (@lines) {
            next if $line =~ /^\s*$/;

            if ($line =~ /^(\s+)/) {
                my $indent = length($1);
                $min_indent = $indent if !defined($min_indent) || $indent < $min_indent;
            } else {
                $min_indent = 0;
                last;
            }
        }

        return @lines unless defined($min_indent) && $min_indent > 0;

        my @stripped;
        for my $line (@lines) {
            if ($line =~ /^\s*$/) {
                push @stripped, $line;
            } else {
                my $stripped_line = $line;
                $stripped_line =~ s/^\s{$min_indent}//;
                push @stripped, $stripped_line;
            }
        }

        return @stripped;
    }

    method choose_delimiters($content) {
        # Choose delimiters that don't conflict with the content
        # Try delimiter pairs in order of preference
        my @delimiter_pairs = (
            ['{', '}'],   # Default, most common
            ['(', ')'],   # First alternative
            ['[', ']'],   # Second alternative
            ['<', '>'],   # Third alternative
            ['|', '|'],   # Symmetric delimiter
            ['/', '/'],   # Another symmetric option
            ['#', '#'],   # Less common
            ['!', '!'],   # Even less common
            ['@', '@'],   # Rare but valid
            ['%', '%'],   # Very rare
        );

        for my $pair (@delimiter_pairs) {
            my ($open, $close) = @$pair;
            # Check if the closing delimiter appears unbalanced in content
            # For now, simple check: if close delimiter not in content, use it
            if (index($content, $close) == -1) {
                return ($open, $close);
            }
        }

        # Fallback to {} if nothing works (shouldn't happen in practice)
        return ('{', '}');
    }

    method map_line($output_line) {
        return $line_map[$output_line] // $output_line;
    }
}

1;
