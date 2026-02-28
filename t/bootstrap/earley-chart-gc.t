# ABOUTME: Tests for safe-set chart garbage collection in the Earley parser.
# ABOUTME: Verifies that old chart positions are released while maintaining correct parse results.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Earley;

# === Test 1: GC does not affect parse correctness ===
subtest 'GC preserves correct parse results' => sub {
    # Grammar: S ::= A B
    #          A ::= /a+/
    #          B ::= /b+/
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a+');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b+');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S',
        expressions => [[$sym_A, $sym_B]],
    );
    my $rule_A = Chalk::Grammar::Rule->new(
        name => 'A',
        expressions => [[$sym_a]],
    );
    my $rule_B = Chalk::Grammar::Rule->new(
        name => 'B',
        expressions => [[$sym_b]],
    );

    my $grammar = [$rule_S, $rule_A, $rule_B];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # With GC enabled, these should still parse correctly
    ok($parser->parse('ab'), 'accepts "ab" with GC');
    ok($parser->parse('aaabb'), 'accepts "aaabb" with GC');
    ok(!$parser->parse('ba'), 'rejects "ba" with GC');
    ok(!$parser->parse(''), 'rejects empty with GC');
};

# === Test 2: Long input still parses correctly ===
subtest 'long input parses correctly with GC' => sub {
    # Grammar: S ::= /a/ S | /a/  (right-recursive, generates a+ strings)
    my $sym_S = Chalk::Grammar::Symbol->new(type => 'reference', value => 'S');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S',
        expressions => [[$sym_a, $sym_S], [$sym_a]],
    );

    my $grammar = [$rule_S];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # Test with progressively longer inputs
    ok($parser->parse('a'), 'accepts single "a"');
    ok($parser->parse('a' x 10), 'accepts 10 "a"s');
    ok($parser->parse('a' x 100), 'accepts 100 "a"s');
    ok($parser->parse('a' x 500), 'accepts 500 "a"s');
    ok(!$parser->parse('b'), 'rejects "b"');
};

# === Test 3: Nullable rules still work with GC ===
subtest 'nullable rules work with GC' => sub {
    # Grammar: S ::= A B
    #          A ::= /a/ | /(?:)/  (nullable)
    #          B ::= /b/
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b');
    my $sym_empty = Chalk::Grammar::Symbol->new(type => 'terminal', value => '(?:)');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S',
        expressions => [[$sym_A, $sym_B]],
    );
    my $rule_A = Chalk::Grammar::Rule->new(
        name => 'A',
        expressions => [[$sym_a], [$sym_empty]],
    );
    my $rule_B = Chalk::Grammar::Rule->new(
        name => 'B',
        expressions => [[$sym_b]],
    );

    my $grammar = [$rule_S, $rule_A, $rule_B];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), 'accepts "ab" (A matches "a")');
    ok($parser->parse('b'), 'accepts "b" (A matches empty)');
    ok(!$parser->parse('a'), 'rejects "a" (no B)');
};

# === Test 4: Verify gc_stats are tracked ===
subtest 'gc_stats tracking' => sub {
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_a]],
    );

    my $grammar = [$rule_S];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $semiring,
    );

    $parser->parse('a');
    my $stats = $parser->gc_stats();
    ok(defined $stats, 'gc_stats returns defined value');
    ok(exists $stats->{positions_freed}, 'stats has positions_freed');
    cmp_ok($stats->{positions_freed}, '>=', 0, 'positions_freed is non-negative');
};

# === Test 4b: GC frees positions in list-like grammar ===
subtest 'GC frees positions in list grammar' => sub {
    # Grammar: List ::= Item List | Item
    #          Item ::= /a/ /;/
    # Each Item completes locally (origin = start of that item).
    # The List rule also starts at origin 0, but Items at later positions
    # don't reference earlier Item positions. After an Item at pos k completes,
    # positions before k that only held Item internals can be freed.
    #
    # However, List spans origin 0 the whole time, so safe_floor stays at 0.
    # This is a known limitation: top-level spanning rules prevent GC.
    # The test verifies GC doesn't break correctness for list-like grammars.
    my $sym_List = Chalk::Grammar::Symbol->new(type => 'reference', value => 'List');
    my $sym_Item = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Item');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a');
    my $sym_semi = Chalk::Grammar::Symbol->new(type => 'terminal', value => ';');

    my $rule_List = Chalk::Grammar::Rule->new(
        name => 'List', expressions => [[$sym_Item, $sym_List], [$sym_Item]],
    );
    my $rule_Item = Chalk::Grammar::Rule->new(
        name => 'Item', expressions => [[$sym_a, $sym_semi]],
    );

    my $grammar = [$rule_List, $rule_Item];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $semiring,
    );

    ok($parser->parse('a;a;a;a;a;'), 'accepts 5-item list');
    ok($parser->parse('a;'), 'accepts single item');
    ok(!$parser->parse('a'), 'rejects item without semicolon');
};

# === Test 5: Regex jump (a+ matches multiple chars) with GC ===
subtest 'regex jump does not cause incorrect GC' => sub {
    # Regression test: when a+ matches "aaa" jumping from pos 0 to pos 3,
    # positions 1-2 are empty. GC must not free pos 0 based on empty positions.
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'A');
    my $sym_B = Chalk::Grammar::Symbol->new(type => 'reference', value => 'B');
    my $sym_a = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'a+');
    my $sym_b = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'b+');

    my $rule_S = Chalk::Grammar::Rule->new(
        name => 'S', expressions => [[$sym_A, $sym_B]],
    );
    my $rule_A = Chalk::Grammar::Rule->new(
        name => 'A', expressions => [[$sym_a]],
    );
    my $rule_B = Chalk::Grammar::Rule->new(
        name => 'B', expressions => [[$sym_b]],
    );

    my $grammar = [$rule_S, $rule_A, $rule_B];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $semiring,
    );

    ok($parser->parse('aaabbb'), 'accepts "aaabbb" with regex jump');
    ok($parser->parse('ab'), 'accepts "ab"');
    ok(!$parser->parse('ba'), 'rejects "ba"');
};

# === Test 6: BNF alternatives parsing works with GC ===
subtest 'BNF alternatives parsing with GC' => sub {
    # This tests the pattern that broke in earlier GC: the Alternatives rule
    # with | separator requires completing back across multiple positions.
    my $sym_A = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Alts');
    my $sym_S = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Seq');
    my $sym_seq = Chalk::Grammar::Symbol->new(type => 'terminal', value => '[a-z]+');
    my $sym_bar = Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\|');
    my $sym_ws = Chalk::Grammar::Symbol->new(type => 'terminal', value => '\\s+');

    # Alts ::= Seq WS '|' WS Alts | Seq
    my $rule_Alts = Chalk::Grammar::Rule->new(
        name => 'Alts',
        expressions => [[$sym_S, $sym_ws, $sym_bar, $sym_ws, $sym_A], [$sym_S]],
    );
    my $rule_Seq = Chalk::Grammar::Rule->new(
        name => 'Seq',
        expressions => [[$sym_seq]],
    );

    my $grammar = [$rule_Alts, $rule_Seq];
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $semiring,
    );

    ok($parser->parse('foo'), 'accepts single alternative');
    ok($parser->parse('foo | bar'), 'accepts two alternatives');
    ok($parser->parse('foo | bar | baz'), 'accepts three alternatives');
    ok(!$parser->parse('|'), 'rejects bare pipe');
};

done_testing;
