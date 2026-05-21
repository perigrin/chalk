# ABOUTME: Integration tests for lazy Phi mechanism on real and synthetic multi-statement programs.
# ABOUTME: Verifies Phi nodes appear for loop-carried variables using the full pipeline.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Phi;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Build the Perl grammar recognizer pipeline once for all tests.
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PhiIntegrationTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PhiIntegrationTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    # FilterComposite: [Boolean, Prec, TypeInf, Structural, SemanticAction]
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction,
        'got SemanticAction from parser');

    # --- Test 1: Synthetic accumulator loop produces Phi for outer variable ---
    # my $x = 0; for my $i (1, 2, 3) { $x = $x + $i; }
    # $x is read and written inside the loop, so it should get a loop-carried Phi.
    # Note: no trailing statement after the loop — the trailing-statement case
    # exposes a known scope-propagation limitation with multiply() right-wins merge.
    {
        $semiring->reset_cache();

        my $src = 'my $x = 0; for my $i (1, 2, 3, 4, 5) { $x = $x + $i; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'integer accumulator loop parses');

        my $sem_ctx = $result;
        skip 'no semantic context for Test 1', 3 unless defined $sem_ctx;

        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available for accumulator loop');

        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x in scope after accumulator loop');

        ok($x_binding isa Chalk::IR::Node::Phi,
            '$x is a Phi node (loop-carried accumulator)')
            or diag('$x binding: ' . ref($x_binding)
                . ' / ' . ($x_binding->operation() // 'undef'));
    }

    # --- Test 2: Synthetic string concatenation loop produces Phi ---
    # my $s = ""; for my $c ("a", "b", "c") { $s = $s . $c; }
    # $s is read and written in the loop, should be a Phi.
    {
        $semiring->reset_cache();

        my $src = 'my $s = ""; for my $c ("a", "b", "c") { $s = $s . $c; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'string concatenation loop parses');

        my $sem_ctx = $result;
        skip 'no semantic context for Test 2', 3 unless defined $sem_ctx;

        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available for string loop');

        my $s_binding = $state->{scope}->lookup('$s');
        ok(defined $s_binding, '$s in scope after string concatenation loop');

        ok($s_binding isa Chalk::IR::Node::Phi,
            '$s is a Phi node (loop-carried string accumulator)')
            or diag('$s binding: ' . ref($s_binding)
                . ' / ' . ($s_binding->operation() // 'undef'));
    }

    # --- Test 3: Phi backedges are wired in a read-write loop ---
    # The Phi for $sum must have its backedge (values->[1]) wired to the
    # post-body assignment, not left as undef.
    {
        $semiring->reset_cache();

        my $src = 'my $sum = 0; for my $n (1, 2, 3) { $sum = $sum + $n; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'backedge wiring loop parses');

        my $sem_ctx = $result;
        skip 'no semantic context for Test 3', 4 unless defined $sem_ctx;

        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available for backedge check');

        my $sum_binding = $state->{scope}->lookup('$sum');
        ok($sum_binding isa Chalk::IR::Node::Phi,
            '$sum is a Phi in backedge test')
            or diag('$sum binding: ' . ref($sum_binding));

        if ($sum_binding isa Chalk::IR::Node::Phi) {
            my $values = $sum_binding->inputs()->[1];
            ok(defined $values->[1],
                'Phi backedge is wired (not undef) for $sum')
                or diag('backedge: ' . ($values->[1] // 'undef'));
        }
        else {
            TODO: {
                local $TODO = 'sum is not a Phi — skipping backedge check';
                ok(false, 'Phi backedge wired');
            }
        }
    }

    # --- Test 4: Real file integration — Scope.pm has a for my $name loop ---
    # Scope.pm contains: for my $name (keys $bindings->%*) { ... }
    # This is a smoke test to verify lazy Phi doesn't crash on real code.
    {
        $semiring->reset_cache();

        open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/Scope.pm'
            or skip 'Cannot read Scope.pm', 2;
        local $/;
        my $source = <$fh>;
        close $fh;

        my $result = $parser->parse_value($source);
        ok(defined $result, 'Scope.pm parses with lazy Phi enabled');

        my $sem_ctx = $result;
        ok(defined $sem_ctx, 'Scope.pm produces a semantic context');
    }

    # --- Test 5: Real file integration — smoke test with for loops ---
    # Pick a small lib/ file that exercises for-loops to verify lazy Phi
    # doesn't crash on real production code. Symbol.pm is tiny but lacks
    # loops; Context.pm has the right shape (extend uses a for-like walk
    # internally via duplicate/extend on children).
    {
        $semiring->reset_cache();

        open my $fh, '<:utf8', 'lib/Chalk/Bootstrap/Context.pm'
            or skip 'Cannot read Context.pm', 2;
        local $/;
        my $source = <$fh>;
        close $fh;

        my $result = $parser->parse_value($source);
        ok(defined $result, 'Context.pm parses with lazy Phi enabled');

        my $sem_ctx = $result;
        ok(defined $sem_ctx, 'Context.pm produces a semantic context');
    }

    # --- Test 6: Trailing-statement scope limitation (documented known issue) ---
    # When a statement follows a loop (e.g., $x; after for...{}), the multiply()
    # right-wins scope merge overwrites the Program-level Phi with the stale
    # pre-loop value that ScalarVariable resolved before ForeachStatement fired.
    # This is a known limitation of bottom-up Earley parsing with mutable scope.
    # The loop-only form (Test 1/2 above) works correctly.
    {
        $semiring->reset_cache();

        my $src = 'my $x = 0; for my $i (1, 2, 3) { $x = $x + $i; } $x;';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'loop with trailing statement parses');

        my $sem_ctx = $result;
        skip 'no semantic context for Test 6', 1 unless defined $sem_ctx;

        my $state = $sem_ctx->cfg_state();
        TODO: {
            local $TODO = 'trailing statement overwrites loop Phi via multiply() right-wins merge';
            my $x_binding = $state->{scope}->lookup('$x');
            ok($x_binding isa Chalk::IR::Node::Phi,
                '$x is a Phi even with trailing statement');
        }
    }
}

done_testing();
