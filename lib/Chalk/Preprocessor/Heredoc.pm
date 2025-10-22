# ABOUTME: Grammar-based heredoc preprocessor for Chalk::Parser
# ABOUTME: Uses mini-grammar to correctly parse heredoc markers in code context
use 5.42.0;
use utf8;
use open qw(:std :utf8);

use experimental qw(class builtin keyword_any keyword_all);
#use Chalk::Parser;

class Chalk::Preprocessor::Heredoc {
    field $input :param :reader;
    field $output :reader = '';
    field @line_map :reader;

    method transform() {
        my $newline_pattern = qr/\n/;
        my @lines = split $newline_pattern, $input, -1;
        my @output_lines;
        my %line_mapping;
        my $output_line_num = 0;

        for my $i (0..$#lines) {
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
                            my $delim_pattern = qr/^\s*\Q$hd->{delimiter}\E$/;
                            $line_matches = ($lines[$j] =~ $delim_pattern);
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
                            my $inner_preprocessor = Chalk::Preprocessor::Heredoc->new(input => $content);
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
                        my $marker = $part->{marker};
                        my $replacement = $part->{replacement};
                        my $pos = index($transformed, $marker);
                        if ($pos >= 0) {
                            substr($transformed, $pos, length($marker), $replacement);
                        }
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
        my $single_quote_pattern = qr/((?<!<)'(?:[^'\\]|\\.)*')/;
        my $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $single_quote_pattern) {
            my $match = $1;
            my $match_start = $search_pos + $-[0];
            my $match_end = $match_start + length($match);
            $search_pos = $match_end;
            push @excluded_ranges, [$match_start, $match_end];
        }

        # Find double-quoted string ranges
        my $double_quote_pattern = qr/("(?:[^"\\]|\\.)*")/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $double_quote_pattern) {
            my $match = $1;
            my $match_start = $search_pos + $-[0];
            my $match_end = $match_start + length($match);
            $search_pos = $match_end;
            push @excluded_ranges, [$match_start, $match_end];
        }

        # Find comment range (everything after # to end of line)
        # But only if the # is not inside a string
        my $comment_pattern = qr/(#)/;
        if ($working_line =~ $comment_pattern) {
            my $comment_pos = $-[0];  # Start position of the match
            # Check if this # is inside an already-excluded string
            my $in_string = 0;
            for my $range (@excluded_ranges) {
                if ($comment_pos >= $range->[0] && $comment_pos < $range->[1]) {
                    $in_string = 1;
                    last;
                }
            }
            # Only exclude as comment if not inside a string
            push @excluded_ranges, [$comment_pos, length($working_line)] unless $in_string;
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
        my $hd_sq_indent_pat = qr/(<<~'([^']+)')/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_sq_indent_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 1, is_indented => 1 };
        }
        my $hd_dq_indent_pat = qr/(<<~"([^"]+)")/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_dq_indent_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 0, is_indented => 1 };
        }
        my $hd_esc_indent_pat = qr/(<<~\\(\w+))/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_esc_indent_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 1, is_indented => 1 };
        }
        my $hd_bare_indent_pat = qr/(<<~(\w+))/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_bare_indent_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 0, is_indented => 1 };
        }
        my $hd_sq_pat = qr/(<<'([^']+)')/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_sq_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 1, is_indented => 0 };
        }
        my $hd_dq_pat = qr/(<<"([^"]+)")/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_dq_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 0, is_indented => 0 };
        }
        my $hd_esc_pat = qr/(<<\\(\w+))/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_esc_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 1, is_indented => 0 };
        }
        my $hd_bare_pat = qr/(<<(\w+))/;
        $search_pos = 0;
        while (substr($working_line, $search_pos) =~ $hd_bare_pat) {
            my $match_pos = $search_pos + $-[0];
            my $matched_marker = $1;
            my $matched_delim = $2;
            $search_pos = $match_pos + length($matched_marker);
            next if $is_excluded->($match_pos);
            push @markers, { marker => $matched_marker, delimiter => $matched_delim, is_single_quoted => 0, is_indented => 0 };
        }

        return @markers;
    }

    method strip_indentation(@lines) {
        return () unless @lines;

        my $min_indent = undef;
        my $empty_line_pat = qr/^\s*$/;
        my $leading_space_pat = qr/^(\s+)/;
        for my $line (@lines) {
            next if $line =~ $empty_line_pat;

            if ($line =~ $leading_space_pat) {
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
            if ($line =~ $empty_line_pat) {
                push @stripped, $line;
            } else {
                my $stripped_line = $line;
                if (length($stripped_line) >= $min_indent) {
                    $stripped_line = substr($stripped_line, $min_indent);
                }
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
            my ($open, $close) = $pair->@*;
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

