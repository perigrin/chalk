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
# Re-run generate() with the 3-rule grammar to get the C output.
# $h_text_ci is the header for this generate() call; #define constants and
# typedefs now live in the header rather than the .c file.

my $c_result = $target->generate($ir);
my $c_text = $c_result->{'dfa_tables.c'};
my $h_text_ci = $c_result->{'dfa_tables.h'};

# === Test 9: NUM_CORE_ITEMS define is present in the header ===
like($h_text_ci, qr/#define NUM_CORE_ITEMS \d+/,
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
# Extract N from the header (defines now live in dfa_tables.h, not dfa_tables.c)
my ($num_core_items) = $h_text_ci =~ /#define NUM_CORE_ITEMS (\d+)/;
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

# ============================================================
# === Tests 23+: DFA state table emission (Component 3)  ===
# ============================================================
# Re-use $c_text from the generate() call above (the 3-rule grammar S::=AB A::=/a/ B::=/b/).
# The grammar has terminals /a/ and /b/, nonterminals S/A/B, and several DFA states with
# goto entries.

# Extract the number of DFA states for later cross-checks.
# Defines now live in dfa_tables.h, not dfa_tables.c.
my ($num_dfa_states) = $h_text_ci =~ /#define NUM_DFA_STATES (\d+)/;

# === Test: NUM_DFA_STATES define is present in header ===
like($h_text_ci, qr/#define NUM_DFA_STATES \d+/,
    'dfa_tables.c contains #define NUM_DFA_STATES');
ok(defined $num_dfa_states && $num_dfa_states > 0,
    'NUM_DFA_STATES is a positive integer');

# ============================================================
# === Terminal map arrays ===
# ============================================================

# === Test: TOTAL_TMAP_ENTRIES define ===
like($h_text_ci, qr/#define TOTAL_TMAP_ENTRIES \d+/,
    'dfa_tables.c contains #define TOTAL_TMAP_ENTRIES');
my ($total_tmap_entries) = $h_text_ci =~ /#define TOTAL_TMAP_ENTRIES (\d+)/;
ok(defined $total_tmap_entries && $total_tmap_entries > 0,
    'TOTAL_TMAP_ENTRIES is positive (the test grammar has terminals)');

# === Test: TOTAL_TMAP_SLICES define ===
like($h_text_ci, qr/#define TOTAL_TMAP_SLICES \d+/,
    'dfa_tables.c contains #define TOTAL_TMAP_SLICES');
my ($total_tmap_slices) = $h_text_ci =~ /#define TOTAL_TMAP_SLICES (\d+)/;
ok(defined $total_tmap_slices && $total_tmap_slices > 0,
    'TOTAL_TMAP_SLICES is positive');

# === Test: NUM_UNIQUE_TMAP_PATTERNS define ===
like($h_text_ci, qr/#define NUM_UNIQUE_TMAP_PATTERNS \d+/,
    'dfa_tables.c contains #define NUM_UNIQUE_TMAP_PATTERNS');
my ($num_unique_tmap) = $h_text_ci =~ /#define NUM_UNIQUE_TMAP_PATTERNS (\d+)/;
ok(defined $num_unique_tmap && $num_unique_tmap > 0,
    'NUM_UNIQUE_TMAP_PATTERNS is positive');

# === Test: tmap_core_ids array present ===
like($c_text, qr/tmap_core_ids\[/, 'dfa_tables.c contains tmap_core_ids array');

# === Test: tmap_patterns array present ===
like($c_text, qr/tmap_patterns\[/, 'dfa_tables.c contains tmap_patterns array');

# === Test: TMapSlice typedef present in header ===
like($h_text_ci, qr/typedef struct \{[^}]*pattern_idx[^}]*\}\s*TMapSlice/s,
    'dfa_tables.c contains TMapSlice typedef');

# === Test: tmap_slices array present ===
like($c_text, qr/tmap_slices\[/, 'dfa_tables.c contains tmap_slices array');

# === Test: tmap_state_offset array present ===
like($c_text, qr/tmap_state_offset\[/, 'dfa_tables.c contains tmap_state_offset array');

# === Test: tmap_state_count array present ===
like($c_text, qr/tmap_state_count\[/, 'dfa_tables.c contains tmap_state_count array');

# === Test: tmap_state_offset has NUM_DFA_STATES entries ===
my ($tmap_so_init) = $c_text =~ /tmap_state_offset\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $tmap_so_init, 'tmap_state_offset initializer is parseable');
my @tmap_so_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $tmap_so_init);
is(scalar @tmap_so_vals, $num_dfa_states,
    'tmap_state_offset has NUM_DFA_STATES entries');

# === Test: tmap_state_count has NUM_DFA_STATES entries ===
my ($tmap_sc_init) = $c_text =~ /tmap_state_count\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $tmap_sc_init, 'tmap_state_count initializer is parseable');
my @tmap_sc_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $tmap_sc_init);
is(scalar @tmap_sc_vals, $num_dfa_states,
    'tmap_state_count has NUM_DFA_STATES entries');

# === Test: tmap_core_ids has TOTAL_TMAP_ENTRIES entries ===
my ($tmap_ci_init) = $c_text =~ /tmap_core_ids\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $tmap_ci_init, 'tmap_core_ids initializer is parseable');
my @tmap_ci_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $tmap_ci_init);
is(scalar @tmap_ci_vals, $total_tmap_entries,
    'tmap_core_ids entry count matches TOTAL_TMAP_ENTRIES');

# ============================================================
# === Completion map arrays ===
# ============================================================

# === Test: TOTAL_CMAP_ENTRIES define ===
like($h_text_ci, qr/#define TOTAL_CMAP_ENTRIES \d+/,
    'dfa_tables.c contains #define TOTAL_CMAP_ENTRIES');

# === Test: TOTAL_CMAP_SLICES define ===
like($h_text_ci, qr/#define TOTAL_CMAP_SLICES \d+/,
    'dfa_tables.c contains #define TOTAL_CMAP_SLICES');

# === Test: NUM_UNIQUE_CMAP_NONTERMS define ===
like($h_text_ci, qr/#define NUM_UNIQUE_CMAP_NONTERMS \d+/,
    'dfa_tables.c contains #define NUM_UNIQUE_CMAP_NONTERMS');

# === Test: cmap_core_ids array present ===
like($c_text, qr/cmap_core_ids\[/, 'dfa_tables.c contains cmap_core_ids array');

# === Test: cmap_nonterminals array present ===
like($c_text, qr/cmap_nonterminals\[/, 'dfa_tables.c contains cmap_nonterminals array');

# === Test: CMapSlice typedef present in header ===
like($h_text_ci, qr/typedef struct \{[^}]*nonterm_idx[^}]*\}\s*CMapSlice/s,
    'dfa_tables.c contains CMapSlice typedef');

# === Test: cmap_slices array present ===
like($c_text, qr/cmap_slices\[/, 'dfa_tables.c contains cmap_slices array');

# === Test: cmap_state_offset has NUM_DFA_STATES entries ===
my ($cmap_so_init) = $c_text =~ /cmap_state_offset\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $cmap_so_init, 'cmap_state_offset initializer is parseable');
my @cmap_so_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $cmap_so_init);
is(scalar @cmap_so_vals, $num_dfa_states,
    'cmap_state_offset has NUM_DFA_STATES entries');

# === Test: cmap_state_count has NUM_DFA_STATES entries ===
my ($cmap_sc_init) = $c_text =~ /cmap_state_count\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $cmap_sc_init, 'cmap_state_count initializer is parseable');
my @cmap_sc_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $cmap_sc_init);
is(scalar @cmap_sc_vals, $num_dfa_states,
    'cmap_state_count has NUM_DFA_STATES entries');

# ============================================================
# === Goto table arrays ===
# ============================================================

# === Test: TOTAL_GOTO_ENTRIES define ===
like($h_text_ci, qr/#define TOTAL_GOTO_ENTRIES \d+/,
    'dfa_tables.c contains #define TOTAL_GOTO_ENTRIES');
my ($total_goto_entries) = $h_text_ci =~ /#define TOTAL_GOTO_ENTRIES (\d+)/;
ok(defined $total_goto_entries && $total_goto_entries > 0,
    'TOTAL_GOTO_ENTRIES is positive (the test grammar has goto transitions)');

# === Test: GotoEntry typedef present in header ===
like($h_text_ci, qr/typedef struct \{[^}]*symbol_key[^}]*target_state[^}]*\}\s*GotoEntry/s,
    'dfa_tables.c contains GotoEntry typedef');

# === Test: goto_entries array present ===
like($c_text, qr/goto_entries\[/, 'dfa_tables.c contains goto_entries array');

# === Test: goto_state_offset present ===
like($c_text, qr/goto_state_offset\[/, 'dfa_tables.c contains goto_state_offset array');

# === Test: goto_state_count present ===
like($c_text, qr/goto_state_count\[/, 'dfa_tables.c contains goto_state_count array');

# === Test: goto_entries contains at least one entry ===
my ($goto_entries_init) = $c_text =~ /goto_entries\[\d+\]\s*=\s*\{(.*?)\}\s*;/s;
ok(defined $goto_entries_init, 'goto_entries initializer is parseable');
like($goto_entries_init, qr/\{[^}]+\}/,
    'goto_entries contains at least one entry (braced struct literal)');

# === Test: goto_state_offset has NUM_DFA_STATES entries ===
my ($goto_so_init) = $c_text =~ /goto_state_offset\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $goto_so_init, 'goto_state_offset initializer is parseable');
my @goto_so_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $goto_so_init);
is(scalar @goto_so_vals, $num_dfa_states,
    'goto_state_offset has NUM_DFA_STATES entries');

# === Test: goto_state_count has NUM_DFA_STATES entries ===
my ($goto_sc_init) = $c_text =~ /goto_state_count\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $goto_sc_init, 'goto_state_count initializer is parseable');
my @goto_sc_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $goto_sc_init);
is(scalar @goto_sc_vals, $num_dfa_states,
    'goto_state_count has NUM_DFA_STATES entries');

# === Test: goto_entries has TOTAL_GOTO_ENTRIES entries ===
# Count braced struct literals: { "...", N }
my @goto_entry_structs = ($goto_entries_init =~ /\{[^}]+\}/g);
is(scalar @goto_entry_structs, $total_goto_entries,
    'goto_entries struct count matches TOTAL_GOTO_ENTRIES');

# ============================================================
# === Determinism: emit twice, outputs must be byte-identical ===
# ============================================================

# Reset the factory so nodes aren't shared across calls (tests independence)
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory2 = Chalk::Bootstrap::IR::NodeFactory->instance();

my sub make_sym2(%args) {
    my $type  = $factory2->make('Constant', const_type => 'enum',   value => $args{type});
    my $value = $factory2->make('Constant', const_type => 'string', value => $args{value});
    my $quant = defined($args{quantifier})
        ? $factory2->make('Constant', const_type => 'string', value => $args{quantifier})
        : undef;
    return $factory2->make('Constructor',
        class      => 'Symbol',
        type       => $type,
        value      => $value,
        quantifier => $quant,
    );
}

my sub make_expr2(@symbols) {
    return $factory2->make('Constructor', class => 'Expression', elements => \@symbols);
}

my sub make_rule2($name, @expressions) {
    my $name_node = $factory2->make('Constant', const_type => 'string', value => $name);
    return $factory2->make('Constructor',
        class       => 'Rule',
        name        => $name_node,
        expressions => \@expressions,
    );
}

my $ir2 = [
    make_rule2('S', make_expr2(make_sym2(type => 'reference', value => 'A'),
                               make_sym2(type => 'reference', value => 'B'))),
    make_rule2('A', make_expr2(make_sym2(type => 'terminal',  value => '/a/'))),
    make_rule2('B', make_expr2(make_sym2(type => 'terminal',  value => '/b/'))),
];

my $target2 = Chalk::Bootstrap::BNF::Target::C->new();
my $result2  = $target2->generate($ir2);
my $c_text2  = $result2->{'dfa_tables.c'};

is($c_text2, $c_text, 'generate() is deterministic: two runs on equivalent IR are byte-identical');

# ============================================================
# === Tests: Prediction tables (Component 4)              ===
# ============================================================
# Re-use $c_text from the 3-rule grammar S::=AB A::=/a/ B::=/b/ above.
# That grammar has no nullable nonterminals but does have prediction closures
# for S, A, and B.

# === Test: TOTAL_PRED_ENTRIES define is present in header ===
like($h_text_ci, qr/#define TOTAL_PRED_ENTRIES \d+/,
    'dfa_tables.c contains #define TOTAL_PRED_ENTRIES');
my ($total_pred_entries) = $h_text_ci =~ /#define TOTAL_PRED_ENTRIES (\d+)/;
ok(defined $total_pred_entries && $total_pred_entries > 0,
    'TOTAL_PRED_ENTRIES is positive (test grammar has prediction items)');

# === Test: NUM_PRED_NONTERMS define is present in header ===
like($h_text_ci, qr/#define NUM_PRED_NONTERMS \d+/,
    'dfa_tables.c contains #define NUM_PRED_NONTERMS');
my ($num_pred_nonterms) = $h_text_ci =~ /#define NUM_PRED_NONTERMS (\d+)/;
ok(defined $num_pred_nonterms && $num_pred_nonterms > 0,
    'NUM_PRED_NONTERMS is positive (test grammar has nonterminals)');

# === Test: PredictionEntry typedef present in header ===
like($h_text_ci, qr/typedef struct \{[^}]*core_id[^}]*skip_count[^}]*\}\s*PredictionEntry/s,
    'dfa_tables.c contains PredictionEntry typedef');

# === Test: prediction_entries array present ===
like($c_text, qr/prediction_entries\[/,
    'dfa_tables.c contains prediction_entries array');

# === Test: prediction_nonterminals array present ===
like($c_text, qr/prediction_nonterminals\[/,
    'dfa_tables.c contains prediction_nonterminals array');

# === Test: prediction_offset array present ===
like($c_text, qr/prediction_offset\[/,
    'dfa_tables.c contains prediction_offset array');

# === Test: prediction_count array present ===
like($c_text, qr/prediction_count\[/,
    'dfa_tables.c contains prediction_count array');

# === Test: prediction_offset has NUM_PRED_NONTERMS entries ===
my ($pred_off_init) = $c_text =~ /prediction_offset\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $pred_off_init, 'prediction_offset initializer is parseable');
my @pred_off_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $pred_off_init);
is(scalar @pred_off_vals, $num_pred_nonterms,
    'prediction_offset has NUM_PRED_NONTERMS entries');

# === Test: prediction_count has NUM_PRED_NONTERMS entries ===
my ($pred_cnt_init) = $c_text =~ /prediction_count\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $pred_cnt_init, 'prediction_count initializer is parseable');
my @pred_cnt_vals = grep { /\S/ } map { s/^\s+|\s+$//gr } split(/,/, $pred_cnt_init);
is(scalar @pred_cnt_vals, $num_pred_nonterms,
    'prediction_count has NUM_PRED_NONTERMS entries');

# === Test: prediction_entries has TOTAL_PRED_ENTRIES entries ===
# Each entry is a braced struct {core_id, skip_count}
my ($pred_entries_init) = $c_text =~ /prediction_entries\[\d+\]\s*=\s*\{(.*?)\}\s*;/s;
ok(defined $pred_entries_init, 'prediction_entries initializer is parseable');
my @pred_entry_structs = ($pred_entries_init =~ /\{[^}]+\}/g);
is(scalar @pred_entry_structs, $total_pred_entries,
    'prediction_entries struct count matches TOTAL_PRED_ENTRIES');

# === Test: prediction_nonterminals has NUM_PRED_NONTERMS entries ===
my ($pred_nt_init) = $c_text =~ /prediction_nonterminals\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $pred_nt_init, 'prediction_nonterminals initializer is parseable');
my @pred_nt_entries;
{
    my $rest = $pred_nt_init;
    while ($rest =~ s/^\s*("(?:[^"\\]|\\.)*"|NULL)\s*,?//) {
        push @pred_nt_entries, $1;
    }
}
is(scalar @pred_nt_entries, $num_pred_nonterms,
    'prediction_nonterminals entry count matches NUM_PRED_NONTERMS');

# === Test: prediction_offset[0] is always 0 ===
is($pred_off_vals[0], '0', 'prediction_offset[0] is 0 (first nonterminal starts at slot 0)');

# === Test: prediction_count entries sum to TOTAL_PRED_ENTRIES ===
my $count_sum = 0;
$count_sum += $_ for @pred_cnt_vals;
is($count_sum, $total_pred_entries,
    'sum of prediction_count entries equals TOTAL_PRED_ENTRIES');

# === Test: prediction_offset is non-decreasing (monotone) ===
my $monotone = true;
for my $i (1 .. $#pred_off_vals) {
    if ($pred_off_vals[$i] < $pred_off_vals[$i - 1]) {
        $monotone = false;
        last;
    }
}
ok($monotone, 'prediction_offset values are non-decreasing');

# === Test: skip_count in prediction_entries is non-negative ===
# Extract (core_id, skip_count) pairs from prediction_entries structs
my @skip_counts;
for my $struct (@pred_entry_structs) {
    my ($core_id, $skip) = $struct =~ /\{(\d+),\s*(\d+)\}/;
    push @skip_counts, $skip if defined $skip;
}
is(scalar @skip_counts, $total_pred_entries,
    'all prediction_entries structs have parseable (core_id, skip_count)');
my @negative_skips = grep { $_ < 0 } @skip_counts;
is(scalar @negative_skips, 0, 'all skip_count values are non-negative');

# ============================================================
# === Tests: Nullable set (Component 4)                   ===
# ============================================================
# The test grammar S::=AB A::=/a/ B::=/b/ has no nullable nonterminals.
# We test that the define and array are present; NUM_NULLABLE may be 0.

# === Test: NUM_NULLABLE define is present in header ===
like($h_text_ci, qr/#define NUM_NULLABLE \d+/,
    'dfa_tables.c contains #define NUM_NULLABLE');
my ($num_nullable) = $h_text_ci =~ /#define NUM_NULLABLE (\d+)/;
ok(defined $num_nullable, 'NUM_NULLABLE is parseable from C text');
# For this grammar there are no nullable nonterminals
is($num_nullable, 0, 'NUM_NULLABLE is 0 for the non-nullable test grammar');

# === Test: nullable_nonterminals array is present ===
like($c_text, qr/nullable_nonterminals\[/,
    'dfa_tables.c contains nullable_nonterminals array');

# ============================================================
# === Tests: Nullable grammar (grammar with nullable nonterminal) ===
# ============================================================
# Build a grammar where one nonterminal IS nullable:
#   Top ::= A B
#   A   ::= /x/ | (empty — epsilon production)
#   B   ::= /y/
# Here A is nullable because it has an empty alternative.
# This validates that nullable_nonterminals and NUM_NULLABLE > 0
# when the grammar actually has nullable nonterminals.

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory3 = Chalk::Bootstrap::IR::NodeFactory->instance();

my sub make_sym3(%args) {
    my $type  = $factory3->make('Constant', const_type => 'enum',   value => $args{type});
    my $value = $factory3->make('Constant', const_type => 'string', value => $args{value});
    my $quant = defined($args{quantifier})
        ? $factory3->make('Constant', const_type => 'string', value => $args{quantifier})
        : undef;
    return $factory3->make('Constructor',
        class      => 'Symbol',
        type       => $type,
        value      => $value,
        quantifier => $quant,
    );
}

my sub make_expr3(@symbols) {
    return $factory3->make('Constructor', class => 'Expression', elements => \@symbols);
}

my sub make_rule3($name, @expressions) {
    my $name_node = $factory3->make('Constant', const_type => 'string', value => $name);
    return $factory3->make('Constructor',
        class       => 'Rule',
        name        => $name_node,
        expressions => \@expressions,
    );
}

# A ::= /x/ | (epsilon)  — two alternatives, second is empty
my $ir3 = [
    make_rule3('Top', make_expr3(
        make_sym3(type => 'reference', value => 'A'),
        make_sym3(type => 'reference', value => 'B'),
    )),
    make_rule3('A',
        make_expr3(make_sym3(type => 'terminal', value => '/x/')),
        make_expr3(),   # epsilon alternative
    ),
    make_rule3('B', make_expr3(make_sym3(type => 'terminal', value => '/y/'))),
];

my $target3 = Chalk::Bootstrap::BNF::Target::C->new();
my $result3  = $target3->generate($ir3);
my $c_text3  = $result3->{'dfa_tables.c'};
my $h_text3  = $result3->{'dfa_tables.h'};

# === Test: nullable grammar has NUM_NULLABLE > 0 (define is in header) ===
my ($num_nullable3) = $h_text3 =~ /#define NUM_NULLABLE (\d+)/;
ok(defined $num_nullable3 && $num_nullable3 > 0,
    'NUM_NULLABLE > 0 for grammar with nullable nonterminal A');

# === Test: nullable_nonterminals contains "A" ===
my ($null_nt_init3) = $c_text3 =~ /nullable_nonterminals\[\d+\]\s*=\s*\{([^}]*)\}/s;
ok(defined $null_nt_init3, 'nullable_nonterminals initializer parseable for nullable grammar');
like($null_nt_init3, qr/"A"/, 'nullable_nonterminals contains "A" for nullable grammar');

# ============================================================
# === Component 5: dfa_tables.h header emission           ===
# ============================================================
# Re-use $c_text and $result from the 3-rule S::=AB A::=/a/ B::=/b/ grammar.
# $result was the last call to $target->generate($ir).
# We re-generate to get a fresh result with the current target.

my $h_result = $target->generate($ir);
my $h_text   = $h_result->{'dfa_tables.h'};
my $c_text_h = $h_result->{'dfa_tables.c'};

# === Test: dfa_tables.h starts with #pragma once ===
like($h_text, qr/\A\s*#pragma once/,
    'dfa_tables.h begins with #pragma once');

# === Test: dfa_tables.c includes chalk.h before dfa_tables.h ===
# chalk.h sets up the Perl environment (EXTERN.h + perl.h + XSUB.h) which
# dfa_tables.h depends on at the usage site.
like($c_text_h, qr/#include\s+"chalk\.h"/,
    'dfa_tables.c includes chalk.h (Perl environment setup)');

# === Test: dfa_tables.h contains all #define constants ===
like($h_text, qr/#define NUM_CORE_ITEMS \d+/,
    'dfa_tables.h contains #define NUM_CORE_ITEMS');
like($h_text, qr/#define NUM_DFA_STATES \d+/,
    'dfa_tables.h contains #define NUM_DFA_STATES');
like($h_text, qr/#define TOTAL_TMAP_ENTRIES \d+/,
    'dfa_tables.h contains #define TOTAL_TMAP_ENTRIES');
like($h_text, qr/#define TOTAL_TMAP_SLICES \d+/,
    'dfa_tables.h contains #define TOTAL_TMAP_SLICES');
like($h_text, qr/#define NUM_UNIQUE_TMAP_PATTERNS \d+/,
    'dfa_tables.h contains #define NUM_UNIQUE_TMAP_PATTERNS');
like($h_text, qr/#define TOTAL_CMAP_ENTRIES \d+/,
    'dfa_tables.h contains #define TOTAL_CMAP_ENTRIES');
like($h_text, qr/#define TOTAL_CMAP_SLICES \d+/,
    'dfa_tables.h contains #define TOTAL_CMAP_SLICES');
like($h_text, qr/#define NUM_UNIQUE_CMAP_NONTERMS \d+/,
    'dfa_tables.h contains #define NUM_UNIQUE_CMAP_NONTERMS');
like($h_text, qr/#define TOTAL_GOTO_ENTRIES \d+/,
    'dfa_tables.h contains #define TOTAL_GOTO_ENTRIES');
like($h_text, qr/#define TOTAL_PRED_ENTRIES \d+/,
    'dfa_tables.h contains #define TOTAL_PRED_ENTRIES');
like($h_text, qr/#define NUM_PRED_NONTERMS \d+/,
    'dfa_tables.h contains #define NUM_PRED_NONTERMS');
like($h_text, qr/#define NUM_NULLABLE \d+/,
    'dfa_tables.h contains #define NUM_NULLABLE');

# === Test: dfa_tables.h contains all four typedefs ===
like($h_text, qr/typedef struct \{[^}]*pattern_idx[^}]*\}\s*TMapSlice/s,
    'dfa_tables.h contains TMapSlice typedef');
like($h_text, qr/typedef struct \{[^}]*nonterm_idx[^}]*\}\s*CMapSlice/s,
    'dfa_tables.h contains CMapSlice typedef');
like($h_text, qr/typedef struct \{[^}]*symbol_key[^}]*target_state[^}]*\}\s*GotoEntry/s,
    'dfa_tables.h contains GotoEntry typedef');
like($h_text, qr/typedef struct \{[^}]*core_id[^}]*skip_count[^}]*\}\s*PredictionEntry/s,
    'dfa_tables.h contains PredictionEntry typedef');

# === Test: dfa_tables.h contains extern declarations for all CoreItemIndex arrays ===
like($h_text, qr/extern\s+const\s+char\s*\*\s*ci_rule_names\b/,
    'dfa_tables.h contains extern decl for ci_rule_names');
like($h_text, qr/extern\s+const\s+int\s+ci_alt_idxs\b/,
    'dfa_tables.h contains extern decl for ci_alt_idxs');
like($h_text, qr/extern\s+const\s+int\s+ci_dots\b/,
    'dfa_tables.h contains extern decl for ci_dots');
like($h_text, qr/extern\s+const\s+int\s+ci_is_complete\b/,
    'dfa_tables.h contains extern decl for ci_is_complete');
like($h_text, qr/extern\s+const\s+int\s+ci_advance\b/,
    'dfa_tables.h contains extern decl for ci_advance');
like($h_text, qr/extern\s+const\s+int\s+ci_to_state\b/,
    'dfa_tables.h contains extern decl for ci_to_state');
like($h_text, qr/extern\s+const\s+char\s*\*\s*ci_symbol_after_pattern\b/,
    'dfa_tables.h contains extern decl for ci_symbol_after_pattern');
like($h_text, qr/extern\s+const\s+int\s+ci_symbol_after_is_ref\b/,
    'dfa_tables.h contains extern decl for ci_symbol_after_is_ref');

# === Test: dfa_tables.h contains extern declarations for all terminal map arrays ===
like($h_text, qr/extern\s+const\s+int\s+tmap_core_ids\b/,
    'dfa_tables.h contains extern decl for tmap_core_ids');
like($h_text, qr/extern\s+const\s+char\s*\*\s*tmap_patterns\b/,
    'dfa_tables.h contains extern decl for tmap_patterns');
like($h_text, qr/extern\s+const\s+TMapSlice\s+tmap_slices\b/,
    'dfa_tables.h contains extern decl for tmap_slices');
like($h_text, qr/extern\s+const\s+int\s+tmap_state_offset\b/,
    'dfa_tables.h contains extern decl for tmap_state_offset');
like($h_text, qr/extern\s+const\s+int\s+tmap_state_count\b/,
    'dfa_tables.h contains extern decl for tmap_state_count');

# === Test: dfa_tables.h contains extern declarations for all completion map arrays ===
like($h_text, qr/extern\s+const\s+int\s+cmap_core_ids\b/,
    'dfa_tables.h contains extern decl for cmap_core_ids');
like($h_text, qr/extern\s+const\s+char\s*\*\s*cmap_nonterminals\b/,
    'dfa_tables.h contains extern decl for cmap_nonterminals');
like($h_text, qr/extern\s+const\s+CMapSlice\s+cmap_slices\b/,
    'dfa_tables.h contains extern decl for cmap_slices');
like($h_text, qr/extern\s+const\s+int\s+cmap_state_offset\b/,
    'dfa_tables.h contains extern decl for cmap_state_offset');
like($h_text, qr/extern\s+const\s+int\s+cmap_state_count\b/,
    'dfa_tables.h contains extern decl for cmap_state_count');

# === Test: dfa_tables.h contains extern declarations for goto table arrays ===
like($h_text, qr/extern\s+const\s+GotoEntry\s+goto_entries\b/,
    'dfa_tables.h contains extern decl for goto_entries');
like($h_text, qr/extern\s+const\s+int\s+goto_state_offset\b/,
    'dfa_tables.h contains extern decl for goto_state_offset');
like($h_text, qr/extern\s+const\s+int\s+goto_state_count\b/,
    'dfa_tables.h contains extern decl for goto_state_count');

# === Test: dfa_tables.h contains extern declarations for prediction table arrays ===
like($h_text, qr/extern\s+const\s+PredictionEntry\s+prediction_entries\b/,
    'dfa_tables.h contains extern decl for prediction_entries');
like($h_text, qr/extern\s+const\s+char\s*\*\s*prediction_nonterminals\b/,
    'dfa_tables.h contains extern decl for prediction_nonterminals');
like($h_text, qr/extern\s+const\s+int\s+prediction_offset\b/,
    'dfa_tables.h contains extern decl for prediction_offset');
like($h_text, qr/extern\s+const\s+int\s+prediction_count\b/,
    'dfa_tables.h contains extern decl for prediction_count');

# === Test: dfa_tables.h contains extern declaration for nullable_nonterminals ===
like($h_text, qr/extern\s+const\s+char\s*\*\s*nullable_nonterminals\b/,
    'dfa_tables.h contains extern decl for nullable_nonterminals');

# === Test: dfa_tables.c includes dfa_tables.h (not stub) ===
like($c_text_h, qr/#include\s+"dfa_tables\.h"/,
    'dfa_tables.c includes "dfa_tables.h"');

# === Test: dfa_tables.c does NOT contain duplicate #define constants ===
# After moving defines to header, the .c file should not duplicate them
unlike($c_text_h, qr/#define NUM_CORE_ITEMS/,
    'dfa_tables.c does not duplicate #define NUM_CORE_ITEMS (now in header)');
unlike($c_text_h, qr/#define NUM_DFA_STATES/,
    'dfa_tables.c does not duplicate #define NUM_DFA_STATES (now in header)');

# === Test: dfa_tables.c does NOT contain duplicate typedef definitions ===
unlike($c_text_h, qr/typedef struct \{[^}]*pattern_idx[^}]*\}\s*TMapSlice/s,
    'dfa_tables.c does not duplicate TMapSlice typedef (now in header)');
unlike($c_text_h, qr/typedef struct \{[^}]*nonterm_idx[^}]*\}\s*CMapSlice/s,
    'dfa_tables.c does not duplicate CMapSlice typedef (now in header)');
unlike($c_text_h, qr/typedef struct \{[^}]*symbol_key[^}]*target_state[^}]*\}\s*GotoEntry/s,
    'dfa_tables.c does not duplicate GotoEntry typedef (now in header)');
unlike($c_text_h, qr/typedef struct \{[^}]*core_id[^}]*skip_count[^}]*\}\s*PredictionEntry/s,
    'dfa_tables.c does not duplicate PredictionEntry typedef (now in header)');

# === Test: dfa_tables.c still contains the array definitions ===
like($c_text_h, qr/const.*ci_rule_names\[/,
    'dfa_tables.c still has ci_rule_names definition');
like($c_text_h, qr/const.*tmap_core_ids\[/,
    'dfa_tables.c still has tmap_core_ids definition');

# ============================================================
# === Compilation test: cc -c dfa_tables.c must succeed   ===
# ============================================================

use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Config;
use ExtUtils::CBuilder;

SKIP: {
    skip 'No C compiler available', 1
        unless ExtUtils::CBuilder->new(quiet => 1)->have_compiler;

    my $tmpdir = tempdir(CLEANUP => 1);

    # Write .c and .h to tempdir
    open(my $cfh, '>', "$tmpdir/dfa_tables.c")
        or die "Cannot write dfa_tables.c: $!";
    print $cfh $c_text_h;
    close $cfh;

    open(my $hfh, '>', "$tmpdir/dfa_tables.h")
        or die "Cannot write dfa_tables.h: $!";
    print $hfh $h_text;
    close $hfh;

    # Copy chalk.h into tempdir so the include resolves
    my $chalk_h_src = 'c_src/chalk.h';
    copy($chalk_h_src, "$tmpdir/chalk.h")
        or die "Cannot copy chalk.h: $!";

    # Also copy EXTERN.h and XSUB.h stubs if needed, but the perl archlib path
    # is on the include line so Perl's headers resolve from there.
    # The -I$Config{archlib}/CORE flag covers perl.h / EXTERN.h / XSUB.h.
    my $perl_core = "$Config{archlib}/CORE";
    my $cmd = "$Config{cc} -c -fPIC $Config{ccflags} -I$perl_core -I$tmpdir"
            . " $tmpdir/dfa_tables.c -o $tmpdir/dfa_tables.o 2>&1";
    my $output = `$cmd`;
    my $exit = $?;

    is($exit, 0, 'dfa_tables.c compiles without errors (cc -c)')
        or diag("Compiler output:\n$output");
}

# ============================================================
# === Determinism: .h output must be byte-identical       ===
# ============================================================

my $target_det = Chalk::Bootstrap::BNF::Target::C->new();
my $result_det = $target_det->generate($ir);
my $h_text_det = $result_det->{'dfa_tables.h'};

is($h_text_det, $h_text,
    'dfa_tables.h is deterministic: two runs on equivalent IR are byte-identical');

done_testing();
