# ABOUTME: Tests lazy Phi creation in loop constructs via ForeachStatement
# ABOUTME: Verifies scope forking, sentinel resolution, and backedge wiring
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Node::Phi;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::LoopPhiTest/g;
    eval $generated;
    skip "Generated code failed: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::LoopPhiTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];

    # --- Test 1: Read-only variable in loop gets degenerate Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $x = 42; for my $i (1, 2, 3) { $x; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'read-only loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 4 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        # $x should still be in scope after the loop
        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x in scope after loop');

        # $x should be a Phi node (created because $x was read inside loop)
        ok($x_binding isa Chalk::Bootstrap::IR::Node::Phi,
            '$x is a Phi (read-only, degenerate)')
            or diag("Got: " . ref($x_binding) . " / "
                . ($x_binding->operation() // 'undef'));
    }

    # --- Test 2: Read-and-written variable gets real loop-carried Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $sum = 0; for my $x (1, 2, 3) { $sum = $sum + $x; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'read-write loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 5 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        my $sum_binding = $state->{scope}->lookup('$sum');
        ok(defined $sum_binding, '$sum in scope after loop');

        # $sum should be a Phi with a wired backedge
        ok($sum_binding isa Chalk::Bootstrap::IR::Node::Phi,
            '$sum is a Phi after read-write loop')
            or diag('$sum binding is: ' . ref($sum_binding));
        if ($sum_binding isa Chalk::Bootstrap::IR::Node::Phi) {
            my $values = $sum_binding->inputs()->[1];
            ok(defined $values->[1],
                'Phi backedge is wired (not undef)')
                or diag("backedge value: " . ($values->[1] // 'undef'));
        }
    }

    # --- Test 3: Variable not read in loop gets no Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $y = 99; for my $i (1, 2) { $i; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'unread variable loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available');

        my $y_binding = $state->{scope}->lookup('$y');
        ok(defined $y_binding, '$y in scope after loop');

        # $y was never read inside the loop — should NOT be a Phi
        ok(!($y_binding isa Chalk::Bootstrap::IR::Node::Phi),
            '$y is not a Phi (never read in loop)')
            or diag("Got Phi for unread variable");
    }
    # --- Test 4: Nested loops produce Phi for outer variable ---
    # The two-phase approach (ForeachStatement collects refs, Program wires Phis)
    # does not yet propagate inner loop variable refs to the outer loop.
    # The inner loop's $x usage is inside the inner ForeachStatement Constructor,
    # so the outer $collect_body_var_refs does not see it.
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $x = 0; for my $i (1, 2) { for my $j (3, 4) { $x = $x + $j; } }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'nested loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available for nested loop');

        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x in scope after nested loops');
        TODO: {
            local $TODO = 'nested loop Phi requires propagating inner body refs to outer loop';
            ok($x_binding isa Chalk::Bootstrap::IR::Node::Phi,
                '$x is a Phi after nested loops')
                or diag('$x binding is: ' . ref($x_binding));
        }
    }

    # --- Test 5: Multiple variables, only referenced ones get Phi ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $src = 'my $a = 0; my $b = 1; for my $i (1, 2, 3) { $a = $a + $i; }';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'multi-var loop parses');

        my $sem_ctx = $result->[4];
        skip 'no semantic context', 4 unless defined $sem_ctx;

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available for multi-var loop');

        my $a_binding = $state->{scope}->lookup('$a');
        ok($a_binding isa Chalk::Bootstrap::IR::Node::Phi,
            '$a is a Phi (referenced in loop)')
            or diag('$a binding is: ' . ref($a_binding));

        my $b_binding = $state->{scope}->lookup('$b');
        ok(defined $b_binding, '$b is still in scope');
        ok(!($b_binding isa Chalk::Bootstrap::IR::Node::Phi),
            '$b is NOT a Phi (never referenced in loop)')
            or diag('$b binding is: ' . ref($b_binding));
    }
}

done_testing();
