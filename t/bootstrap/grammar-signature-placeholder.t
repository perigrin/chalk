# ABOUTME: Tests for anonymous-placeholder $ signature parameter in Perl grammar.
# ABOUTME: Covers the bare $ skip-parameter form admitted by Perl 5.20+ signatures.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build the Perl grammar pipeline once for all tests.
my $ir = perl_pipeline();

unless (defined $ir) {
    plan skip_all => 'Perl grammar failed to parse — cannot run placeholder tests';
    exit;
}

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PlaceholderTests/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated grammar code failed: $@";
    exit;
}

my $gen_grammar = Chalk::Grammar::Perl::PlaceholderTests::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');

unless (defined $parser) {
    plan skip_all => 'Could not build parser';
    exit;
}

# Helper: parse a full program fragment and assert it succeeds.
my sub parses($src, $label) {
    $parser->semiring->reset_cache();
    my $result = $parser->parse_value($src);
    my $ok = defined($result) && !$result->is_zero();
    ok($ok, $label);
    unless ($ok) {
        diag("  Failed to parse: $src");
    }
    return $ok;
}

# Helper: parse and assert it fails.
my sub rejects($src, $label) {
    $parser->semiring->reset_cache();
    my $result = $parser->parse_value($src);
    my $ok = !defined($result) || $result->is_zero();
    ok($ok, $label);
    unless ($ok) {
        diag("  Unexpectedly parsed: $src");
    }
    return $ok;
}

# ============================================================================
# Section 1: Anonymous-placeholder $ signature parameter
#
# Grammar gap: ScalarSignatureParam only admitted ScalarVariable (which requires
# a name: /\$[a-zA-Z_]\w*/). Bare $ (anonymous skip) was not admitted.
# Fix: add /\$(?![\w{])/ as a third alternative in ScalarSignatureParam.
# Site: lib/Chalk/Bootstrap/IR/Optimizer.pm:10 (sub collapse_phi($, $phi))
# ============================================================================

{
    # Placeholder as first positional parameter
    parses(q(sub foo($, $b) { $b }),
        'placeholder: first arg skip, named second — sub foo($, $b)');

    # Placeholder as last positional parameter
    parses(q(sub foo($a, $) { $a }),
        'placeholder: named first, skip last — sub foo($a, $)');

    # Multiple consecutive placeholders
    parses(q(sub foo($, $, $c) { $c }),
        'placeholder: two skips then named — sub foo($, $, $c)');

    # my sub with placeholder
    parses(q(my sub foo($, $b) { $b }),
        'placeholder: my sub with skip first — my sub foo($, $b)');

    # method with placeholder
    parses(q(method foo($, $b) { $b }),
        'placeholder: method with skip first — method foo($, $b)');
}

# ============================================================================
# Section 2: Regression guards — existing signature forms still work
# ============================================================================

{
    # Normal named parameters (pre-existing)
    parses(q(sub foo($a, $b) { $b }),
        'regression: normal two-param sub still works');

    # Empty signature (pre-existing)
    parses(q(sub foo() { 1 }),
        'regression: empty signature still works');

    # Parameter with default (pre-existing)
    parses(q(sub foo($a = 0) { $a }),
        'regression: default parameter still works');

    # Slurpy array parameter (pre-existing)
    parses(q(sub foo(@rest) { @rest }),
        'regression: slurpy array parameter still works');

    # Slurpy hash parameter (pre-existing)
    parses(q(sub foo(%opts) { %opts }),
        'regression: slurpy hash parameter still works');

    # Single named parameter (pre-existing)
    parses(q(sub foo($x) { $x }),
        'regression: single named parameter still works');

    # $_ should parse as ScalarVariable, not placeholder
    parses(q(my $x = $_;),
        'regression: $_ parses as ScalarVariable, not placeholder');

    # $a, $b should parse as ScalarVariable (not swallowed by placeholder)
    parses(q(my $x = $a + $b;),
        'regression: $a and $b parse as ScalarVariable, not placeholder');
}

done_testing();
