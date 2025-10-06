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

            # Check for single-quoted heredoc: <<'DELIMITER'
            if ($line =~ /^(.*?)(<<'([^']+)')(.*)$/) {
                my ($prefix, $heredoc_marker, $delimiter, $suffix) = ($1, $2, $3, $4);

                # Collect heredoc content until we find the terminator
                my @heredoc_content;
                my $j = $i + 1;
                my $found_terminator = 0;

                while ($j < @lines) {
                    if ($lines[$j] eq $delimiter) {
                        $found_terminator = 1;
                        last;
                    }
                    push @heredoc_content, $lines[$j];
                    $j++;
                }

                if ($found_terminator) {
                    # Transform to q{...}
                    my $content = join("\n", @heredoc_content);
                    my $transformed = "${prefix}q{${content}}${suffix}";

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

    method map_line($output_line) {
        return $line_map[$output_line] // $output_line;
    }
}

1;
