# ABOUTME: Tests for BNF::Target::C — the C static-table emitter for DFA serialization.
# ABOUTME: Verifies grammar reconstruction from IR, DFA construction, and stub result shape.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# === Test 1: Module loads and is the right type ===

use_ok('Chalk::Bootstrap::BNF::Target::C');

my $target = Chalk::Bootstrap::BNF::Target::C->new();
isa_ok($target, 'Chalk::Bootstrap::Target');
isa_ok($target, 'Chalk::Bootstrap::BNF::Target::C');

# === Helpers: build IR nodes for a small 3-rule grammar ===
# S ::= A B
# A ::= /a/
# B ::= /b/

# Helper: build a Constructor:Symbol IR node
my sub make_sym(%args) {
    my $type  = $factory->make('Constant', const_type => 'enum',   value => $args{type});
    my $value = $factory->make('Constant', const_type => 'string', value => $args{value});
    my $quant = defined($args{quantifier})
        ? $factory->make('Constant', const_type => 'string', value => $args{quantifier})
        : undef;
    return $factory->make('Constructor',
        class      => 'Symbol',
        type       => $type,
        value      => $value,
        quantifier => $quant,
    );
}

# Helper: build a Constructor:Expression IR node
my sub make_expr(@symbols) {
    return $factory->make('Constructor',
        class    => 'Expression',
        elements => \@symbols,
    );
}

# Helper: build a Constructor:Rule IR node
my sub make_rule($name, @expressions) {
    my $name_node = $factory->make('Constant', const_type => 'string', value => $name);
    return $factory->make('Constructor',
        class       => 'Rule',
        name        => $name_node,
        expressions => \@expressions,
    );
}

# Build IR for S ::= A B
my $sym_ref_A = make_sym(type => 'reference', value => 'A');
my $sym_ref_B = make_sym(type => 'reference', value => 'B');
my $rule_S    = make_rule('S', make_expr($sym_ref_A, $sym_ref_B));

# Build IR for A ::= /a/
my $sym_term_a = make_sym(type => 'terminal', value => '/a/');
my $rule_A     = make_rule('A', make_expr($sym_term_a));

# Build IR for B ::= /b/
my $sym_term_b = make_sym(type => 'terminal', value => '/b/');
my $rule_B     = make_rule('B', make_expr($sym_term_b));

my $ir = [$rule_S, $rule_A, $rule_B];

# === Test 2: generate() returns a hashref ===

my $result = $target->generate($ir);
ok(ref($result) eq 'HASH', 'generate() returns a hashref');

# === Test 3: Result contains expected keys ===

ok(exists $result->{'dfa_tables.c'}, "result contains 'dfa_tables.c' key");
ok(exists $result->{'dfa_tables.h'}, "result contains 'dfa_tables.h' key");

# === Test 4: generate_distribution() returns same structure ===

my $dist = $target->generate_distribution($ir);
ok(ref($dist) eq 'HASH', 'generate_distribution() returns a hashref');
ok(exists $dist->{'dfa_tables.c'}, "distribution contains 'dfa_tables.c'");
ok(exists $dist->{'dfa_tables.h'}, "distribution contains 'dfa_tables.h'");

# === Test 5: DFA was built (state count > 0 via dfa_state_count accessor) ===

my $state_count = $target->last_dfa_state_count();
ok(defined $state_count, 'last_dfa_state_count() is defined after generate()');
cmp_ok($state_count, '>', 0, 'DFA has at least one state');

# === Test 6: Grammar reconstruction strips /…/ delimiters from terminals ===
# The terminal /a/ should have been stripped to just 'a' when building the grammar.
# We verify this indirectly: if terminals weren't stripped the DFA would be built
# with /a/ as the pattern, but the Earley parser expects the bare pattern 'a'.
# Direct check: inspect via dfa_terminal_patterns().

my @patterns = $target->last_terminal_patterns()->@*;
ok(!grep { m{^/.*/$} } @patterns,
    'no terminal patterns in reconstructed grammar still have /…/ delimiters');

# === Test 7: generate() rejects non-arrayref input ===

eval { $target->generate(undef) };
like($@, qr/requires an arrayref/, 'generate(undef) throws expected error');

eval { $target->generate("not an array") };
like($@, qr/requires an arrayref/, 'generate(string) throws expected error');

# === Test 8: generate() handles empty grammar without crashing ===
# (An empty grammar has no rules, so the DFA cannot be built — that's OK,
#  generate() should just return stub content with state_count 0.)

# NOTE: LR0DFA->build() dies on empty grammar, so Target::C must handle that.
my $empty_result = $target->generate([]);
ok(ref($empty_result) eq 'HASH', 'generate([]) returns a hashref even for empty grammar');
ok(exists $empty_result->{'dfa_tables.c'}, 'empty grammar result has dfa_tables.c');
ok(exists $empty_result->{'dfa_tables.h'}, 'empty grammar result has dfa_tables.h');

# === Tests 9-25: CoreItemIndex static C array emission ===
# Re-run generate() with the 3-rule grammar to get the C output

my $c_result = $target->generate($ir);
my $c_text = $c_result->{'dfa_tables.c'};

# === Test 9: NUM_CORE_ITEMS define is present ===
like($c_text, qr/#define NUM_CORE_ITEMS \d+/,
    'dfa_tables.c contains #define NUM_CORE_ITEMS');

# === Test 10-16: All 7 CoreItemIndex array declarations are present ===
like($c_text, qr/ci_rule_names\[/, 'dfa_tables.c contains ci_rule_names array');
like($c_text, qr/ci_alt_idxs\[/,   'dfa_tables.c contains ci_alt_idxs array');
like($c_text, qr/ci_dots\[/,        'dfa_tables.c contains ci_dots array');
like($c_text, qr/ci_is_complete\[/, 'dfa_tables.c contains ci_is_complete array');
like($c_text, qr/ci_advance\[/,     'dfa_tables.c contains ci_advance array');
like($c_text, qr/ci_to_state\[/,    'dfa_tables.c contains ci_to_state array');
like($c_text, qr/ci_symbol_after_pattern\[/, 'dfa_tables.c contains ci_symbol_after_pattern array');
like($c_text, qr/ci_symbol_after_is_ref\[/,  'dfa_tables.c contains ci_symbol_after_is_ref array');

# === Test 17: Array entry counts match core_index->count() ===
# Count entries in ci_alt_idxs by extracting the initializer list and counting commas+1.
# The grammar S::=AB, A::=/a/, B::=/b/ has:
#   S: 3 items (dot 0,1,2)
#   A: 2 items (dot 0,1)
#   B: 2 items (dot 0,1)
# Total = 7 core items.
my $n = $target->last_dfa_state_count(); # we want core count — use core_index instead
# Extract N from the define
my ($num_core_items) = $c_text =~ /#define NUM_CORE_ITEMS (\d+)/;
ok(defined $num_core_items, 'NUM_CORE_ITEMS is parseable from C text');
cmp_ok($num_core_items, '>', 0, 'NUM_CORE_ITEMS is positive');

# Count entries in ci_alt_idxs initializer to verify it matches NUM_CORE_ITEMS.
# Extract the initializer: static const int ci_alt_idxs[N] = { ... };
my ($ci_alt_idxs_init) = $c_text =~ /ci_alt_idxs\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $ci_alt_idxs_init, 'ci_alt_idxs initializer is parseable');
my @ci_alt_idxs_entries = split /,/, $ci_alt_idxs_init;
# Trim whitespace from each entry and remove empties
@ci_alt_idxs_entries = grep { /\S/ } map { s/^\s+|\s+$//gr } @ci_alt_idxs_entries;
is(scalar @ci_alt_idxs_entries, $num_core_items,
    'ci_alt_idxs entry count matches NUM_CORE_ITEMS');

# === Test 18: core_id 0 rule_name appears at position 0 in ci_rule_names ===
# Extract the ci_rule_names initializer
my ($ci_rule_names_init) = $c_text =~ /ci_rule_names\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $ci_rule_names_init, 'ci_rule_names initializer is parseable');
# First entry should be a quoted string (or NULL)
my ($first_rule_name_entry) = $ci_rule_names_init =~ /^\s*("(?:[^"\\]|\\.)*"|NULL)/;
ok(defined $first_rule_name_entry, 'ci_rule_names[0] entry is parseable');
# It must be a quoted string (core_id 0 always has a rule name)
like($first_rule_name_entry, qr/^"/, 'ci_rule_names[0] is a quoted string, not NULL');

# Extract the unquoted name and verify it is one of our rule names (S, A, or B)
my ($name_at_0) = $first_rule_name_entry =~ /^"(.+)"$/;
ok(defined $name_at_0, 'ci_rule_names[0] value is extractable');
ok($name_at_0 =~ /^(?:S|A|B)$/, "ci_rule_names[0] is 'S', 'A', or 'B' (got '$name_at_0')");

# === Test 19: ci_is_complete contains 0s and 1s only ===
my ($ci_is_complete_init) = $c_text =~ /ci_is_complete\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $ci_is_complete_init, 'ci_is_complete initializer is parseable');
my @complete_vals = split /,/, $ci_is_complete_init;
@complete_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } @complete_vals;
my @invalid_complete = grep { !/^[01]$/ } @complete_vals;
is(scalar @invalid_complete, 0, 'ci_is_complete contains only 0 and 1 values');

# === Test 20: ci_advance contains -1 for completed items, non-negative otherwise ===
my ($ci_advance_init) = $c_text =~ /ci_advance\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $ci_advance_init, 'ci_advance initializer is parseable');
my @advance_vals = split /,/, $ci_advance_init;
@advance_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } @advance_vals;
my @invalid_advance = grep { !/^-?[0-9]+$/ } @advance_vals;
is(scalar @invalid_advance, 0, 'ci_advance contains only integers');
# Completed items (ci_is_complete==1) must have advance==-1
for my ($idx, $complete_val) (indexed @complete_vals) {
    if ($complete_val eq '1') {
        is($advance_vals[$idx], '-1',
            "ci_advance[$idx] is -1 for completed item (ci_is_complete[$idx]==1)");
    }
}

# === Test 21: ci_symbol_after_is_ref contains 0s and 1s only (not NULL entries) ===
my ($ci_sym_is_ref_init) = $c_text =~ /ci_symbol_after_is_ref\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $ci_sym_is_ref_init, 'ci_symbol_after_is_ref initializer is parseable');
my @sym_is_ref_vals = split /,/, $ci_sym_is_ref_init;
@sym_is_ref_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } @sym_is_ref_vals;
my @invalid_is_ref = grep { !/^[01]$/ } @sym_is_ref_vals;
is(scalar @invalid_is_ref, 0, 'ci_symbol_after_is_ref contains only 0 and 1 values');

# === Test 22: ci_symbol_after_pattern NULLs align with ci_is_complete ones ===
my ($ci_sym_pat_init) = $c_text =~ /ci_symbol_after_pattern\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $ci_sym_pat_init, 'ci_symbol_after_pattern initializer is parseable');
# Split on commas that are not inside quotes (simple heuristic: split and rejoin quoted parts)
# We use a regex split that is aware of quoted strings.
my @sym_pat_entries;
{
    my $rest = $ci_sym_pat_init;
    while ($rest =~ s/^\s*("(?:[^"\\]|\\.)*"|NULL)\s*,?//) {
        push @sym_pat_entries, $1;
    }
}
is(scalar @sym_pat_entries, $num_core_items,
    'ci_symbol_after_pattern entry count matches NUM_CORE_ITEMS');
# Every NULL in pattern must correspond to is_complete==1
for my ($idx, $pat) (indexed @sym_pat_entries) {
    if ($pat eq 'NULL') {
        is($complete_vals[$idx], '1',
            "ci_symbol_after_pattern[$idx] is NULL only when ci_is_complete[$idx]==1");
    }
}

done_testing();
