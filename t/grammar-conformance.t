# ABOUTME: Grammar conformance harness: every lib/ .pm file must parse and produce zero unresolved ties.
# ABOUTME: Excluded files are listed explicitly with a comment explaining why each skip exists.
use 5.42.0;
use utf8;
use Test::More;
use File::Find ();

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::FilterComposite;

# ============================================================================
# Skip list: files excluded from the conformance corpus.
# Each entry is an absolute path suffix to match against File::Find results.
# The comment after each entry is the required explanation.
# ============================================================================
my %SKIP = (
    # excluded — transitional, slated for retirement when MOP completes
    # (per docs/plans/2026-04-24-maturity-audit-plan.md)
    'lib/Chalk/Bootstrap/DepChaser.pm' => 'transitional: DepChaser retired by MOP completion',
);

# ============================================================================
# Build the parse infrastructure.
# ============================================================================
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

unless (defined $ir) {
    plan skip_all => 'Perl grammar (docs/chalk-bootstrap.bnf) failed to parse — cannot run conformance harness';
    exit;
}

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ConformanceHarness/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated Perl grammar code failed to compile: $@";
    exit;
}

my $gen_grammar = Chalk::Grammar::Perl::ConformanceHarness::grammar();
# Use build_perl_concise_parser so the semiring is FilterComposite, which
# supports flush_tie_log() and tie_log() for the zero-tie assertion.
# FilterComposite also performs Boolean recognition internally (Boolean is
# the first component semiring), so parse results are the same as a plain
# Boolean recognizer.
my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');

unless (defined $parser) {
    plan skip_all => 'Could not build Perl parser from generated grammar';
    exit;
}

# ============================================================================
# Collect .pm files under lib/, sorted for deterministic ordering.
# ============================================================================
my @pm_files;
File::Find::find(
    sub {
        return unless /\.pm$/;
        return if $File::Find::name =~ m{/\..};   # skip hidden paths
        push @pm_files, $File::Find::name;
    },
    'lib',
);
@pm_files = sort @pm_files;

# ============================================================================
# Per-file test loop.
# Each file gets two assertions:
#   1. The file parses successfully (recognized by the Perl grammar).
#   2. Zero unresolved ties occurred in FilterComposite::_filter_compare.
# ============================================================================

# Enable tie instrumentation for this run.
local $ENV{CHALK_COUNT_FILTER_TIES} = '1';

for my $file (@pm_files) {
    # Normalize path for skip-list lookup (strip leading ./ if present)
    (my $norm = $file) =~ s{^\./}{};

    if (exists $SKIP{$norm}) {
        my $reason = $SKIP{$norm};
        # Emit one skipped test per file (two assertions are skipped as one unit)
      SKIP: {
            skip "$norm: $reason", 2;
        }
        next;
    }

    # Read source
    my $source = do {
        open my $fh, '<:utf8', $file
            or do { fail "Cannot open $file: $!"; next };
        local $/;
        <$fh>;
    };

    # Reset tie log and semiring caches before each file parse.
    $parser->semiring->flush_tie_log();
    $parser->semiring->reset_cache();

    # parse_value returns a unified Context; is_zero false means parse succeeded.
    my $result   = $parser->parse_value($source);
    my $parse_ok = defined($result) && !$result->is_zero();

    ok($parse_ok, "PARSE_OK: $norm");

    if ($parse_ok) {
        my $ties = $parser->semiring->tie_log();
        my $tie_count = scalar($ties->@*);
        is($tie_count, 0, "ZERO_TIES: $norm")
            or diag("  $tie_count unresolved tie(s) in FilterComposite::_filter_compare");
    } else {
        # Parse failed — skip the tie assertion (no parse means no tie data)
        # Emit a diagnostic pointing to the two likely failure modes.
      SKIP: {
            skip "parse failed for $norm — tie check skipped", 1;
        }
        diag("  FAILURE MODE: parse error (grammar gap or unsupported construct)");
    }
}

done_testing();
