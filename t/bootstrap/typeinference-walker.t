# ABOUTME: Tests for TypeInference walker fixes — Bug 4 prune boundary, Bug 1 List-flattening,
# ABOUTME: and Bug 5 root-prune protection for call-form builtins with parens.
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

    # Multi-arg list-op builtin inside map BLOCK: `join(",", $_)` now passes
    # after the Bug 5 walker fix (root-prune protection enables parens-form builtins).
    {
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

    # =========================================================================
    # Bug 1 cases: literal list as LIST argument to block-form builtin.
    # type_satisfies('Int','List') must return true — Perl flattens scalars
    # into list context at runtime, so any concrete type satisfies List.
    # =========================================================================

    # Parenthesized literal list with identity block
    {
        my $result = parse_ok('my @x = map { $_ } (1, 2, 3);');
        ok(defined $result,
            'Bug1: map { $_ } (1, 2, 3) parses — Int satisfies List');
    }

    # Parenthesized literal list with arithmetic block
    {
        my $result = parse_ok('my @x = map { $_ + 1 } (1, 2, 3);');
        ok(defined $result,
            'Bug1: map { $_ + 1 } (1, 2, 3) parses — Int satisfies List');
    }

    # Bare (unparenthesized) literal list
    {
        my $result = parse_ok('my @x = map { $_ } 1, 2, 3;');
        ok(defined $result,
            'Bug1: map { $_ } 1, 2, 3 parses — bare Int satisfies List');
    }

    # grep with literal list
    {
        my $result = parse_ok('my @y = grep { $_ > 0 } (1, -1, 2);');
        ok(defined $result,
            'Bug1: grep { $_ > 0 } (1, -1, 2) parses — Int satisfies List');
    }

    # =========================================================================
    # Bug 1 regression guards: working cases must continue to pass.
    # =========================================================================

    # Array variable (already passes via Array is_subtype List)
    {
        my $result = parse_ok('my @arr; my @x = map { $_ } @arr;');
        ok(defined $result,
            'Bug1 guard: map { $_ } @arr still passes after fix');
    }

    # Bug 4 retired case — must still pass (Bug 4 fix + Bug 1 fix together)
    {
        my $result = parse_ok('my @x = map { defined $_ } @arr;');
        ok(defined $result,
            'Bug1 guard: map { defined $_ } @arr still passes after Bug1 fix');
    }

    # =========================================================================
    # Bug 5 cases: call-form builtin with parens rejected due to root-prune.
    # _walk_annotations must not prune the walker root (depth 0).
    # Failing builtins have min_arity >= 2; arity defaults to 1 when walker
    # prunes itself at root, triggering arity < min_arity rejection.
    # =========================================================================

    # push with parens form
    {
        my $result = parse_ok('my @a; push(@a, 1);');
        ok(defined $result,
            'Bug5: push(@a, 1) parses — walker must not prune root');
    }

    # unshift with parens form
    {
        my $result = parse_ok('my @a; unshift(@a, 1);');
        ok(defined $result,
            'Bug5: unshift(@a, 1) parses — walker must not prune root');
    }

    # join with parens form
    {
        my $result = parse_ok('my @a; my $s = join(",", @a);');
        ok(defined $result,
            'Bug5: join(",", @a) parses — walker must not prune root');
    }

    # substr with parens form
    {
        my $result = parse_ok('my $s; my $t = substr($s, 0, 3);');
        ok(defined $result,
            'Bug5: substr($s, 0, 3) parses — walker must not prune root');
    }

    # =========================================================================
    # Bug 5 regression guards: bare form must continue to pass.
    # =========================================================================

    {
        my $result = parse_ok('my @a; push @a, 1;');
        ok(defined $result,
            'Bug5 guard: push @a, 1 (bare form) still passes after fix');
    }

    {
        my $result = parse_ok('my @a; my $s = join ",", @a;');
        ok(defined $result,
            'Bug5 guard: join ",", @a (bare form) still passes after fix');
    }
}

done_testing();
