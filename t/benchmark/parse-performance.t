# ABOUTME: Parse performance benchmark comparing pure-Perl and XS Earley parser.
# ABOUTME: Skipped unless CHALK_BENCHMARK=1. Measures single-file detail + multi-file throughput.
use 5.42.0;
use utf8;
use Test::More;
use Time::HiRes qw(time);

unless ($ENV{CHALK_BENCHMARK}) {
    plan skip_all => 'Set CHALK_BENCHMARK=1 to run benchmarks';
}

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::NodeFactory;
# === Grammar pipeline setup (shared by all benchmarks) ===

diag '';
diag '=== Parse Performance Benchmark ===';
diag '';

my $setup_t0 = time();
my $raw_ir = perl_pipeline();
die "perl_pipeline returned undef" unless defined $raw_ir;

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Benchmark/g;
eval "$generated; 1" or die "Grammar eval failed: $@";

no strict 'refs';
my $grammar = Chalk::Grammar::Perl::Benchmark::grammar();
use strict 'refs';
die "Grammar not defined" unless defined $grammar;

my $setup_time = time() - $setup_t0;
diag sprintf("Grammar setup: %.2fs", $setup_time);
diag '';

# === Helper: parse a file and return timing + stats ===

sub parse_file_timed($grammar_ref, $file) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;
    close $fh;

    my $bytes = length($source);
    my $lines = () = $source =~ /\n/g;

    my $parser = build_perl_ir_parser($grammar_ref, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();

    my $t0 = time();
    my $result = $parser->parse_value($source);
    my $elapsed = time() - $t0;

    my $earley = $parser;
    my $scan = $earley->scan_stats();
    my $gc   = $earley->gc_stats();

    return {
        file    => $file,
        bytes   => $bytes,
        lines   => $lines,
        elapsed => $elapsed,
        success => defined($result) ? true : false,
        scan_stats  => { $scan->%* },
        gc_stats    => { $gc->%* },
    };
}

# === Mode 1: Single-file detail ===

subtest 'Single-file detail: Boolean.pm' => sub {
    my $file = 'lib/Chalk/Bootstrap/Semiring/Boolean.pm';
    unless (-f $file) {
        fail("$file not found");
        return;
    }

    my $r = parse_file_timed($grammar, $file);
    ok($r->{success}, 'Boolean.pm parses successfully');

    # Operation counts must be positive (parser did work)
    cmp_ok($r->{scan_stats}{total_matches}, '>', 0, 'scan: total_matches > 0');
    cmp_ok($r->{scan_stats}{clustered_scans}, '>', 0, 'scan: clustered_scans > 0');

    diag '';
    diag "--- Single-file detail: Boolean.pm ---";
    diag sprintf("  File: %d bytes, %d lines", $r->{bytes}, $r->{lines});
    diag sprintf("  Parse time: %.3fs", $r->{elapsed});
    diag sprintf("  Throughput: %.0f bytes/sec", $r->{bytes} / ($r->{elapsed} || 0.001));
    diag '';
    diag "  Scan stats:";
    diag sprintf("    total_matches:   %d", $r->{scan_stats}{total_matches});
    diag sprintf("    cache_hits:      %d", $r->{scan_stats}{cache_hits});
    diag sprintf("    clustered_scans: %d", $r->{scan_stats}{clustered_scans});
    diag '';
    diag "  GC stats:";
    diag sprintf("    positions_freed: %d", $r->{gc_stats}{positions_freed});
    diag sprintf("    safe_sets_found: %d", $r->{gc_stats}{safe_sets_found});
    diag '';
};

# === Mode 2: Multi-file throughput ===

subtest 'Multi-file throughput: Semiring classes' => sub {
    my @files = sort glob('lib/Chalk/Bootstrap/Semiring/*.pm');
    ok(scalar @files > 0, 'found semiring .pm files to benchmark');

    my $total_bytes   = 0;
    my $total_time    = 0;
    my $total_lines   = 0;
    my $parse_ok      = 0;
    my $parse_fail    = 0;
    my @results;

    for my $file (@files) {
        my $r = eval { parse_file_timed($grammar, $file) };
        if ($@ || !defined $r) {
            diag "  SKIP $file: $@";
            $parse_fail++;
            next;
        }
        push @results, $r;
        if ($r->{success}) {
            $total_bytes += $r->{bytes};
            $total_time  += $r->{elapsed};
            $total_lines += $r->{lines};
            $parse_ok++;
        } else {
            $parse_fail++;
        }
    }

    cmp_ok($parse_ok, '>', 0, 'at least one file parsed successfully');

    diag '';
    diag "--- Multi-file throughput: Semiring classes ---";
    diag sprintf("  Files: %d parsed, %d failed, %d total",
        $parse_ok, $parse_fail, scalar @files);
    diag sprintf("  Total: %d bytes, %d lines", $total_bytes, $total_lines);
    diag sprintf("  Total parse time: %.3fs", $total_time);
    diag sprintf("  Throughput: %.0f bytes/sec",
        $total_bytes / ($total_time || 0.001));
    diag '';

    # Per-file breakdown
    diag "  Per-file breakdown:";
    for my $r (sort { $a->{elapsed} <=> $b->{elapsed} } @results) {
        my $short = $r->{file} =~ s{.*/}{}r;
        my $status = $r->{success} ? 'OK' : 'FAIL';
        diag sprintf("    %-35s %5d bytes  %7.3fs  %s",
            $short, $r->{bytes}, $r->{elapsed}, $status);
    }
    diag '';
};

# === XS comparison (if chalk.so built) ===

subtest 'XS comparison (if available)' => sub {
    my $build_dir = '.build/chalk-so-gen';
    unless (-d $build_dir) {
        plan skip_all => "chalk.so not built (run script/build-chalk-so-generated first)";
    }

    # Try to load the XS-compiled modules
    my $xs_available = eval {
        # Add the build dir to @INC for XSLoader to find .so files
        unshift @INC, $build_dir;
        require Chalk::Bootstrap::Semiring::Boolean;
        true;
    };
    unless ($xs_available) {
        plan skip_all => "XS modules not loadable: $@";
    }

    # Re-parse Boolean.pm with XS modules loaded
    my $file = 'lib/Chalk/Bootstrap/Semiring/Boolean.pm';
    my $perl_result = parse_file_timed($grammar, $file);
    ok($perl_result->{success}, 'Perl parse succeeds');

    # The XS modules are now loaded — the parser will use them automatically
    # if FilterComposite dispatches to XS-compiled semirings
    my $xs_result = parse_file_timed($grammar, $file);
    ok($xs_result->{success}, 'XS-loaded parse succeeds');

    # XS should not be slower than Perl
    cmp_ok($xs_result->{elapsed}, '<=', $perl_result->{elapsed} * 1.5,
        'XS parse not significantly slower than Perl (within 1.5x)');

    diag '';
    diag "--- XS comparison: Boolean.pm ---";
    diag sprintf("  Perl parse: %.3fs", $perl_result->{elapsed});
    diag sprintf("  XS parse:   %.3fs", $xs_result->{elapsed});
    if ($perl_result->{elapsed} > 0) {
        my $speedup = $perl_result->{elapsed} / ($xs_result->{elapsed} || 0.001);
        diag sprintf("  Speedup:    %.2fx", $speedup);
    }
    diag '';
};

done_testing;
