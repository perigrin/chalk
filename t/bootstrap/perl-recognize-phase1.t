# ABOUTME: Phase 1 test — program skeleton recognition with the Perl grammar.
# ABOUTME: Tests empty programs, comments, identifier statements, and blocks.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;

# Build the Perl grammar recognizer with Program as start symbol
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase1/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::Phase1::grammar();
    my $recognizer = build_perl_recognizer($gen_grammar, start => 'Program');

    skip 'Recognizer not built', 1 unless defined $recognizer;

    # Phase 1 test data from docs/chalk-parse-perl-plan.md
    # Positive cases: program skeleton
    ok($recognizer->parse(''),
        'Phase 1: accepts empty program');
    ok($recognizer->parse(';'),
        'Phase 1: accepts empty statement');
    ok($recognizer->parse(';;'),
        'Phase 1: accepts multiple empty statements');
    ok($recognizer->parse("# a comment\n"),
        'Phase 1: accepts comment-only program');
    ok($recognizer->parse('foo;'),
        'Phase 1: accepts identifier as expression');
    ok($recognizer->parse('foo; bar; baz;'),
        'Phase 1: accepts multiple statements');
    ok($recognizer->parse('{ foo; }'),
        'Phase 1: accepts block as compound statement');

    # Whitespace and comment variations
    ok($recognizer->parse("  \t\n  "),
        'Phase 1: accepts whitespace-only program');
    ok($recognizer->parse("foo;\n# comment\nbar;"),
        'Phase 1: accepts comments between statements');
    ok($recognizer->parse("foo ;"),
        'Phase 1: accepts whitespace before semicolon');

    # Block variations
    ok($recognizer->parse('{}'),
        'Phase 1: accepts empty block');
    ok($recognizer->parse('{ { foo; } }'),
        'Phase 1: accepts nested blocks');
    ok($recognizer->parse('{ foo; bar; }'),
        'Phase 1: accepts block with multiple statements');

    # Negative cases
    ok(!$recognizer->parse('{ foo;'),
        'Phase 1: rejects unclosed brace');
    ok(!$recognizer->parse(':::'),
        'Phase 1: rejects invalid syntax');
    # 'foo' is now accepted — optional semicolons allow bare expressions as statements
    ok($recognizer->parse('foo'),
        'Phase 1: accepts bare identifier (optional semicolon)');
    ok(!$recognizer->parse('{ { foo; }'),
        'Phase 1: rejects unbalanced nested blocks');
    ok(!$recognizer->parse('} foo; {'),
        'Phase 1: rejects reversed braces');
    ok(!$recognizer->parse('"unclosed string'),
        'Phase 1: rejects unclosed string literal');

    # Error handling: invalid start rule
    eval { build_perl_recognizer($gen_grammar, start => 'NonExistentRule') };
    like($@, qr/not found in grammar/,
        'build_perl_recognizer dies on missing start rule');
}

done_testing();
