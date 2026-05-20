# ABOUTME: Tests for TypeInference walker fixes — prune boundary hygiene for all walker callers.
# ABOUTME: Covers Bug 4, Bug 1, Bug 5, and walker-hygiene (Findings 7 + 8) unified prune fixes.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
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
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
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

    # =========================================================================
    # Finding 7: _get_rightmost_type in TypeInferenceActions.pm walks past the
    # inner CallExpression boundary and picks up the array arg's type ('Array'),
    # which leaks as the outer ExpressionList item_types, causing
    # type_satisfies('Array','Scalar') to fail for defined/ref outer calls.
    # Fix: add prune support to _walk_ann and apply _is_completed_sub_expr
    # to all nine unfixed walker callers.
    # =========================================================================

    # Minimal failing case: defined wrapping a call that has an array argument
    {
        my $result = parse_ok('my $x; my @arr; my $r = defined func($x, @arr); return;');
        ok(defined $result,
            'F7: defined func($x, @arr) — outer defined must not see inner @arr type');
    }

    # Single array argument to inner call
    {
        my $result = parse_ok('my @arr; my $r = defined func(@arr); return;');
        ok(defined $result,
            'F7: defined func(@arr) — single Array arg must not pollute outer type');
    }

    # Hash argument to inner call
    {
        my $result = parse_ok('my $x; my %h; my $r = defined func($x, %h); return;');
        ok(defined $result,
            'F7: defined func($x, %h) — Hash arg must not pollute outer defined type');
    }

    # ref as outer head with array in inner args
    {
        my $result = parse_ok('my @arr; my $r = ref func("name", @arr); return;');
        ok(defined $result,
            'F7: ref func("name", @arr) — Array arg must not pollute outer ref type');
    }

    # Control: multi-scalar args — must continue to pass (was already passing)
    {
        my $result = parse_ok('my $x; my $y; my $r = defined func($x, $y); return;');
        ok(defined $result,
            'F7 control: defined func($x, $y) — scalar-only args still pass');
    }

    # Control: no args — must continue to pass
    {
        my $result = parse_ok('my $r = defined func(); return;');
        ok(defined $result,
            'F7 control: defined func() — no args still passes');
    }

    # scalar() as outer — has arg_types=['Any']; must not reject regardless of inner
    {
        my $result = parse_ok('my $x; my @arr; my $r = scalar func($x, @arr); return;');
        ok(defined $result,
            'F7 control: scalar func($x, @arr) — Any arg_type accepts Array');
    }

    # =========================================================================
    # Finding 8: _get_call_symbol in TypeInference.pm and TypeInferenceActions.pm
    # walks past AnonymousSub boundaries, leaking the inner builtin's call_symbol
    # up to the outer (unknown-head) call, which then validates against the wrong
    # (leaked) signature.
    # Fix: apply _is_completed_sub_expr prune to _get_call_symbol in both files.
    # =========================================================================

    # Minimal failing case: anonsub with defined inside as second arg to unknown call
    {
        my $result = parse_ok('my $x; func($x, sub ($n) { return defined $n ? 1 : 0; }); return;');
        ok(defined $result,
            'F8: anonsub with ternary+defined must not leak call_symbol to outer call');
    }

    # No ternary — the actual trigger is any known-builtin call in anonsub body
    {
        my $result = parse_ok('my $x; func($x, sub ($n) { return defined $n; }); return;');
        ok(defined $result,
            'F8: anonsub with bare defined must not leak call_symbol to outer call');
    }

    # defined as statement before return in anonsub body
    {
        my $result = parse_ok('my $x; func($x, sub { defined $_; return 1; }); return;');
        ok(defined $result,
            'F8: anonsub with defined as stmt must not leak call_symbol');
    }

    # ref instead of defined as inner builtin
    {
        my $result = parse_ok('my $x; func($x, sub ($n) { return ref $n ? 1 : 0; }); return;');
        ok(defined $result,
            'F8: anonsub with ref builtin must not leak call_symbol to outer call');
    }

    # Control: known-builtin host (print) — must still pass
    {
        my $result = parse_ok('my $x; print($x, sub { return defined $_[0] ? 1 : 0; }); return;');
        ok(defined $result,
            'F8 control: known-builtin host (print) with anonsub still passes');
    }

    # Control: bare anonsub (no host call) — must still pass
    {
        my $result = parse_ok('my $f = sub ($n) { return defined $n ? 1 : 0; };');
        ok(defined $result,
            'F8 control: bare anonsub with defined still passes (no host call)');
    }

    # Control: simple anonsub body with no inner builtins — must still pass
    {
        my $result = parse_ok('my $x; func($x, sub ($n) { return $n; }); return;');
        ok(defined $result,
            'F8 control: anonsub with no inner builtins still passes');
    }

    # =========================================================================
    # Latent risk probes: cases flagged in the RCA as potential regressions
    # when the unified prune is applied.
    # =========================================================================

    # ParenExpr boundary: outer Atom should find the inner type via ParenExpr wrapper
    # which carries type on itself — walker need not descend past it.
    {
        my $result = parse_ok('my $x; my $r = (1 + 2) * 3; return;');
        ok(defined $result,
            'Latent: ParenExpr boundary — outer expression still finds type');
    }

    # Block boundary: if/else branches — Structural semiring selects; TI should pass
    {
        my $result = parse_ok('my $x; if ($x) { foo() } else { bar() }');
        ok(defined $result,
            'Latent: Block boundary — if/else with function calls still passes');
    }

    # Recursive anonsub-in-call-in-anonsub: compound leak path
    {
        my $result = parse_ok('my $x; func($x, sub ($n) { other($n, sub ($m) { defined $m; }); }); return;');
        ok(defined $result,
            'Latent: nested anonsub in call in anonsub — no compound leak');
    }

    # Anonsub returning anonsub: inner-inner leak through both boundaries
    {
        my $result = parse_ok('my $x; func($x, sub { return sub { defined $_[0]; }; }); return;');
        ok(defined $result,
            'Latent: anonsub returning anonsub with inner defined — no double-boundary leak');
    }
}

done_testing();
