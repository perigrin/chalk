#!/usr/bin/env perl
# ABOUTME: Profile Chalk parser performance with detailed instrumentation
# ABOUTME: Tracks operations, timing, chart growth, and rule usage during parsing

use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Time::HiRes qw(time);

# Profile data collection
my %profile = (
    predict_count => 0,
    complete_count => 0,
    scan_count => 0,
    leo_count => 0,
    items_created => 0,
    predict_time => 0,
    complete_time => 0,
    scan_time => 0,
    chart_size_at_pos => {},
    items_at_pos => {},
    rule_usage => {},
    sample_positions => [],
);

# Monkey-patch the parser to add instrumentation
{
    package Chalk::Parser;
    use Time::HiRes qw(time);

    my $original_predict = \&predict;
    my $original_complete = \&complete;
    my $original_scan = \&scan;
    my $original_process_position = \&process_position_string;

    no warnings 'redefine';

    *predict = sub {
        my $start = time();
        my $result = $original_predict->(@_);
        $profile{predict_time} += (time() - $start);
        $profile{predict_count}++;
        return $result;
    };

    *complete = sub {
        my $start = time();
        my $result = $original_complete->(@_);
        $profile{complete_time} += (time() - $start);
        $profile{complete_count}++;
        return $result;
    };

    *scan = sub {
        my $start = time();
        my $result = $original_scan->(@_);
        $profile{scan_time} += (time() - $start);
        $profile{scan_count}++;
        $profile{items_created}++;
        return $result;
    };

    *process_position_string = sub {
        my ($self, $pos, $chart, $input_string) = @_;

        # Sample at key positions
        if ($pos % 500 == 0 || $pos < 100 || $pos == length($input_string)) {
            my @agenda = $chart->items_ending_at($pos);

            $profile{items_at_pos}{$pos} = scalar @agenda;

            push @{$profile{sample_positions}}, {
                pos => $pos,
                items_in_agenda => scalar @agenda,
            };
        }

        return $original_process_position->(@_);
    };
}

# Track rule usage by patching EarleyChart
{
    package Chalk::EarleyChart;
    my $original_add_element = \&add_element;

    no warnings 'redefine';
    *add_element = sub {
        my ($self, $item, $element) = @_;
        $profile{items_created}++;
        if ($item->can('rule')) {
            my $rule_id = $item->rule->id;
            $profile{rule_usage}{$rule_id}++;
        }
        return $original_add_element->(@_);
    };
}

# Track Leo item creation
{
    package Chalk::LeoItem;
    my $original_new = \&new;

    no warnings 'redefine';
    *new = sub {
        $profile{leo_count}++;
        return $original_new->(@_);
    };
}

print "=== PROFILING CHALK PARSER ON lex.t ===\n\n";

# Test on progressively larger portions
my @test_lines = (26, 50, 100, 150, 200);
my @lines = do { local (@ARGV, $/) = 'perl-tests/base/lex.t'; split /\n/, <> };

for my $n (@test_lines) {
    print "Testing lines 1-$n...\n";

    # Reset profile for this test
    %profile = (
        predict_count => 0,
        complete_count => 0,
        scan_count => 0,
        leo_count => 0,
        items_created => 0,
        predict_time => 0,
        complete_time => 0,
        scan_time => 0,
        chart_size_at_pos => {},
        items_at_pos => {},
        rule_usage => {},
        sample_positions => [],
    );

    my $code = join("\n", @lines[0..$n-1]);
    my $code_length = length($code);

    my $parser = Chalk::Parser->new(
        grammar => $Chalk::Grammar::Perl::chalk_grammar,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );
    local $SIG{__WARN__} = sub { };  # Suppress warnings

    my $start = time();
    my $result = $parser->parse_string($code);
    my $elapsed = time() - $start;

    # Print report
    print_report($n, $code_length, $elapsed, $result);
    print "\n" . ("=" x 80) . "\n\n";

    last if $elapsed > 30;  # Stop if test takes more than 30 seconds
}

sub print_report {
    my ($lines, $chars, $elapsed, $result) = @_;

    my $total_ops = $profile{predict_count} + $profile{complete_count} + $profile{scan_count};
    my $total_time = $profile{predict_time} + $profile{complete_time} + $profile{scan_time};

    printf qq{
RESULTS:
  Lines: %d
  Characters: %d
  Parse result: %s
  Total time: %.3f seconds

OPERATION COUNTS:
  Predictions:  %8d (%.1f%%)
  Completions:  %8d (%.1f%%)
  Scans:        %8d (%.1f%%)
  Leo Items:    %8d
  Items Created:%8d
  Total Ops:    %8d

TIMING (seconds):
  Predict:      %8.3f (%.1f%%)
  Complete:     %8.3f (%.1f%%)
  Scan:         %8.3f (%.1f%%)
  Total:        %8.3f

AVERAGES:
  Time per predict:  %.6f ms
  Time per complete: %.6f ms
  Time per scan:     %.6f ms
  Time per op:       %.6f ms
  Ops per second:    %.0f

CHART GROWTH:
  Positions sampled: %d
  Max items at position: %d

TOP 10 MOST USED RULES:
%s

SAMPLE POSITIONS (selected):
%s
},
        $lines,
        $chars,
        $result ? "SUCCESS" : "FAILED",
        $elapsed,

        $profile{predict_count},
        $total_ops ? 100 * $profile{predict_count} / $total_ops : 0,
        $profile{complete_count},
        $total_ops ? 100 * $profile{complete_count} / $total_ops : 0,
        $profile{scan_count},
        $total_ops ? 100 * $profile{scan_count} / $total_ops : 0,
        $profile{leo_count},
        $profile{items_created},
        $total_ops,

        $profile{predict_time},
        $total_time ? 100 * $profile{predict_time} / $total_time : 0,
        $profile{complete_time},
        $total_time ? 100 * $profile{complete_time} / $total_time : 0,
        $profile{scan_time},
        $total_time ? 100 * $profile{scan_time} / $total_time : 0,
        $total_time,

        $profile{predict_count} ? 1000 * $profile{predict_time} / $profile{predict_count} : 0,
        $profile{complete_count} ? 1000 * $profile{complete_time} / $profile{complete_count} : 0,
        $profile{scan_count} ? 1000 * $profile{scan_time} / $profile{scan_count} : 0,
        $total_ops ? 1000 * $total_time / $total_ops : 0,
        $elapsed ? $total_ops / $elapsed : 0,

        scalar @{$profile{sample_positions}},
        (scalar keys %{$profile{items_at_pos}} ? (sort { $b <=> $a } values %{$profile{items_at_pos}})[0] : 0),

        format_top_rules(),
        format_samples(),
    ;
}

sub format_top_rules {
    my @sorted = sort { $profile{rule_usage}{$b} <=> $profile{rule_usage}{$a} }
                 keys %{$profile{rule_usage}};
    my @top10 = @sorted[0 .. (($#sorted < 9) ? $#sorted : 9)];
    return join("\n", map {
        sprintf("  Rule %s: %d times", $_, $profile{rule_usage}{$_})
    } @top10) || "  (none)";
}

sub format_samples {
    my @samples = @{$profile{sample_positions}};
    # Show first 5 and last 5
    my @to_show = @samples < 10 ? @samples : (@samples[0..4], @samples[-5..-1]);
    return join("\n", map {
        sprintf("  Pos %5d: items=%5d", $_->{pos}, $_->{items_in_agenda})
    } @to_show) || "  (none)";
}
