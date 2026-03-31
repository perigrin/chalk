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

done_testing();
