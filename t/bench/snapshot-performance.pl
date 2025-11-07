#!/usr/bin/env perl
# ABOUTME: Performance benchmarks for Environment snapshot/restore operations
# ABOUTME: Tests snapshot/restore at different scales to identify performance characteristics

use v5.42;
use lib 'lib';
use Time::HiRes qw(time);
use Chalk::Interpreter::Environment;
use Chalk::IR::Context;

sub benchmark_snapshot($size, $label) {
    say "\n=== Benchmarking: $label ($size bindings) ===";

    # Create environment with $size bindings
    my $env = Chalk::Interpreter::Environment->new();

    # Populate with nodes
    for my $i (1..$size) {
        $env->set_node("node_$i", $i);
    }

    # Allocate some heap structures
    my $heap_count = int($size / 10);
    for my $i (1..$heap_count) {
        my $heap_id = $env->allocate_heap_id();
        $env->set_heap($heap_id, $i, $i * 2);
    }

    # Benchmark snapshot
    my $start = time();
    my $snapshot = $env->snapshot();
    my $snapshot_time = time() - $start;

    # Benchmark restore
    $start = time();
    my $restored = $env->restore_from_snapshot($snapshot);
    my $restore_time = time() - $start;

    printf "Snapshot time:  %.6f seconds\n", $snapshot_time;
    printf "Restore time:   %.6f seconds\n", $restore_time;
    printf "Total time:     %.6f seconds\n", $snapshot_time + $restore_time;

    # Verify correctness
    my $test_key = "node_" . int($size / 2);
    my $original_val = $env->lookup_node($test_key);
    my $restored_val = $restored->lookup_node($test_key);
    die "Restore failed!" unless $original_val == $restored_val;
    say "Verification: PASSED";

    return ($snapshot_time, $restore_time);
}

# Run benchmarks
say "Snapshot/Restore Performance Benchmarks";
say "=" x 60;

my @results;
push @results, [100,    benchmark_snapshot(100,    "Small")];
push @results, [1_000,  benchmark_snapshot(1_000,  "Medium")];
push @results, [10_000, benchmark_snapshot(10_000, "Large")];

# Summary table
say "\n" . "=" x 60;
say "SUMMARY";
say "=" x 60;
printf "%-10s  %-15s  %-15s  %-15s\n", "Bindings", "Snapshot (s)", "Restore (s)", "Total (s)";
say "-" x 60;
for my $result (@results) {
    my ($size, $snap_time, $restore_time) = @$result;
    printf "%-10d  %-15.6f  %-15.6f  %-15.6f\n",
        $size, $snap_time, $restore_time, $snap_time + $restore_time;
}

# Analysis
say "\n" . "=" x 60;
say "ANALYSIS";
say "=" x 60;
my $scale_factor = $results[2]->[1] / $results[0]->[1];  # large / small
printf "100x size increase = %.1fx time increase\n", $scale_factor;
if ($scale_factor < 200) {
    say "Performance: GOOD (better than O(n^2))";
} elsif ($scale_factor < 1000) {
    say "Performance: ACCEPTABLE (approximately O(n log n))";
} else {
    say "Performance: CONCERN (worse than O(n log n))";
}
