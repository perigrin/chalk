# ABOUTME: Behavioral test for Earley.pm compiled to XS via Target::C.
# ABOUTME: Builds XS module, loads it, creates parser instance, and parses a simple grammar.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# Skip guards
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);

# --- Step 1: Parse Earley.pm to IR ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSEarleyBehav') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm') };
ok(defined $ir, 'Earley.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# --- Step 2: Build and load XS module via Target::C ---
my ($result, $err) = eval { build_and_load($ir, $sa, $ctx, 'Test::XSEarley') };
ok(defined $result, 'XS module built and loaded') or BAIL_OUT("Build failed: " . ($err // $@));

# --- Step 3: Verify ADJUST ran by checking readers ---
# Use BNF meta-grammar as test input — it's a real grammar with 10 rules
use Chalk::Grammar::BNF;
use Chalk::Bootstrap::Semiring::Boolean;

my $grammar_rules = Chalk::Grammar::BNF->grammar();
my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();

# Create XS parser instance with the BNF meta-grammar
my $xs_parser = eval { Test::XSEarley->new(
    grammar  => $grammar_rules,
    semiring => $semiring,
) };
is($@, '', 'XS parser instance created') or do {
    diag("Constructor failed: $@");
    done_testing();
    exit 0;
};
ok(defined $xs_parser, 'XS parser object defined');

# Verify ADJUST ran — grammar reader should return the grammar
my $g = eval { $xs_parser->grammar() };
ok(defined $g, 'grammar() reader returns value (ADJUST ran)');

# Verify ADJUST completed — grammar has correct number of rules
my $g_count = eval { scalar($g->@*) };
ok(defined $g_count && $g_count == scalar($grammar_rules->@*),
    'grammar() returns correct number of rules (ADJUST completed)');

# --- Step 4: Parse a simple BNF string ---
my $bnf_input = 'Expr ::= /\\d+/';

# Also parse with pure Perl for comparison
my $perl_parser = Chalk::Bootstrap::Earley->new(
    grammar  => $grammar_rules,
    semiring => $semiring,
);
my $perl_result = $perl_parser->parse($bnf_input);

# --- Step 5: Compare results ---
ok(defined $perl_result, 'Perl parser recognizes simple BNF');

# Run XS parse in a child process to survive potential segfaults.
{
    my $pid = fork();
    if ($pid == 0) {
        # Child: try to parse, exit with status
        my $result = eval { $xs_parser->parse($bnf_input) };
        exit(defined $result ? 0 : 1);
    }
    waitpid($pid, 0);
    my $child_exit = $? >> 8;
    my $child_signal = $? & 127;
    if ($child_signal) {
        fail("XS parser crashed with signal $child_signal");
    } elsif ($child_exit == 0) {
        pass('XS parser recognizes simple BNF');
    } else {
        fail('XS parser failed to parse');
    }
}

done_testing();
