# ABOUTME: Tests for the TypeInference walker fix — ensures _get_item_types stops descent
# ABOUTME: at completed sub-CallExpression boundaries, not descending into nested ExpressionLists.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build the full 5-ary FilterComposite parser with Perl grammar.
# This reproduces the exact conditions of Bug 4: TI in filter position
# (not _sa()) so its annotations->{type} slots are populated and the
# CallExpression walker fires the signature-validation path.

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::WalkerFixTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::WalkerFixTest::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    # Helper: parse and return defined result, or undef on failure.
    my sub parse_ok($source) {
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        return undef if $result->is_zero();
        return $result;
    }

    # =========================================================================
    # Control case: constructs that should already pass (confirm infrastructure)
    # =========================================================================

    # pop @x: parsed via a dedicated grammar rule, not CallExpression alt=1.
    # Bug 4 does not trigger for pop. This is a control test.
    {
        my $result = parse_ok('my @x = (1, 2, 3); pop @x;');
        ok(defined $result,
            'control: pop @x parses without semiring rejection');
    }

    # =========================================================================
    # Bug 4 trigger cases: BLOCK contains a CallExpression alt=1
    # (Identifier WS ExpressionList) — _get_item_types finds the inner
    # ExpressionList's item_types ([Scalar] for $_) instead of the outer one
    # ([Array] for @arr), causing type_satisfies('Scalar','List') to fail.
    # =========================================================================

    # Seed case from Bug 4 RCA: `defined $_` inside map BLOCK
    {
        my $result = parse_ok('my @x = map { defined $_ } @arr;');
        ok(defined $result,
            'Bug4 seed: map { defined $_ } @arr parses with full semiring stack');
    }

    # `ref $_` — same pattern, named-unary builtin
    {
        my $result = parse_ok('my @x = map { ref $_ } @arr;');
        ok(defined $result,
            'Bug4: map { ref $_ } @arr parses with full semiring stack');
    }

    # `length $_` — same pattern, named-unary builtin
    {
        my $result = parse_ok('my @x = map { length $_ } @arr;');
        ok(defined $result,
            'Bug4: map { length $_ } @arr parses with full semiring stack');
    }

    # Multi-arg list-op builtin: `join(",", $_)` — would test an ExpressionList
    # with two items, but join(",", ...) fails to parse at the grammar level
    # due to a pre-existing unrelated grammar issue (the comma inside the arg
    # list stops the parse before TypeInference applies). This is not a Bug 4
    # issue. Marked TODO pending separate grammar fix for multi-arg builtins.
    TODO: {
        local $TODO = 'join(",", ...) grammar parse fails before TypeInference applies — pre-existing unrelated issue';
        my $result = parse_ok('my @x = map { join(",", $_) } @arr;');
        ok(defined $result,
            'Bug4: map { join(",", $_) } @arr parses with full semiring stack');
    }

    # grep with trigger builtin
    {
        my $result = parse_ok('my @x = grep { defined $_ } @arr;');
        ok(defined $result,
            'Bug4: grep { defined $_ } @arr parses with full semiring stack');
    }
}

done_testing();
