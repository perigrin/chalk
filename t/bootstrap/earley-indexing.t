# ABOUTME: Tests for Earley parser chart indexing optimization.
# ABOUTME: Verifies correctness is preserved after adding waiting/completed indexes.
use 5.42.0;
use utf8;
use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Helper to build simple grammars
my sub sym($type, $value) {
    Chalk::Grammar::Symbol->new(type => $type, value => $value);
}

my sub rule($name, @alts) {
    Chalk::Grammar::Rule->new(
        name        => $name,
        expressions => \@alts,
    );
}

# --- Section 1: Basic correctness after optimization ---

{
    # Simple grammar: S ::= A | 'x'
    #                 A ::= 'a'
    my @grammar = (
        rule('S', [sym('reference', 'A')], [sym('terminal', 'x')]),
        rule('A', [sym('terminal', 'a')]),
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => \@grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );

    ok($parser->parse('a'), 'indexed: accepts via nonterminal reference');
    ok($parser->parse('x'), 'indexed: accepts via direct terminal');
    ok(!$parser->parse('b'), 'indexed: rejects non-matching input');
    ok(!$parser->parse(''), 'indexed: rejects empty input');
}

# --- Section 2: Nullable nonterminals still work ---

{
    # Grammar with nullable: S ::= A B
    #                        A ::= 'a' | epsilon
    #                        B ::= 'b'
    my @grammar = (
        rule('S', [sym('reference', 'A'), sym('reference', 'B')]),
        rule('A', [sym('terminal', 'a')], []),
        rule('B', [sym('terminal', 'b')]),
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => \@grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );

    ok($parser->parse('ab'), 'indexed nullable: accepts A=a B=b');
    ok($parser->parse('b'),  'indexed nullable: accepts A=epsilon B=b');
    ok(!$parser->parse('a'), 'indexed nullable: rejects A=a without B');
}

# --- Section 3: Multiple nullable nonterminals (the _advance_from_completed case) ---

{
    # Grammar: S ::= WS Content WS
    #          WS ::= ' ' WS | epsilon
    #          Content ::= 'x'
    my @grammar = (
        rule('S', [sym('reference', 'WS'), sym('reference', 'Content'), sym('reference', 'WS')]),
        rule('WS', [sym('terminal', '\\s'), sym('reference', 'WS')], []),
        rule('Content', [sym('terminal', 'x')]),
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => \@grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );

    ok($parser->parse('x'),     'indexed multi-nullable: bare content');
    ok($parser->parse(' x'),    'indexed multi-nullable: leading space');
    ok($parser->parse('x '),    'indexed multi-nullable: trailing space');
    ok($parser->parse(' x '),   'indexed multi-nullable: both spaces');
    ok($parser->parse('  x  '), 'indexed multi-nullable: multiple spaces');
}

# --- Section 4: Ambiguous grammar ---

{
    # E ::= E '+' E | 'n'
    my @grammar = (
        rule('E', [sym('reference', 'E'), sym('terminal', '\\+'), sym('reference', 'E')],
                  [sym('terminal', 'n')]),
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => \@grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );

    ok($parser->parse('n'),     'indexed ambiguous: single n');
    ok($parser->parse('n+n'),   'indexed ambiguous: n+n');
    ok($parser->parse('n+n+n'), 'indexed ambiguous: n+n+n');
    ok(!$parser->parse('+'),    'indexed ambiguous: rejects bare +');
}

# --- Section 5: Performance test — real Perl grammar ---
# This is the key test: parsing real .pm files should be meaningfully faster
# with indexing. We measure time for a medium-sized source file.

SKIP: {
    my $ir = perl_pipeline();
    skip 'Perl grammar failed to parse', 4 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::IndexTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 4 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::IndexTest::grammar();
    my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');
    skip 'Recognizer not built', 4 unless defined $recognizer;

    # Test a few synthetic inputs for correctness
    ok($recognizer->parse('my $x = 42;'), 'indexed perl grammar: variable declaration');
    ok($recognizer->parse('if ($x) { $y; }'), 'indexed perl grammar: if statement');
    ok($recognizer->parse("use 5.42.0;\nuse utf8;\nmy \$x = 42;\n"),
        'indexed perl grammar: multi-statement program');

    # Performance: parse a real .pm file and ensure it completes
    my $file = 'lib/Chalk/Bootstrap/Terminal.pm';
    open my $fh, '<:utf8', $file or skip "cannot read $file", 1;
    local $/;
    my $source = <$fh>;
    close $fh;

    my $start = time();
    my $result = $recognizer->parse($source);
    my $elapsed = time() - $start;

    ok($result, "indexed perl grammar: recognizes $file");
    diag(sprintf("Parsed %s (%d chars) in %.3fs", $file, length($source), $elapsed));
}

done_testing();
