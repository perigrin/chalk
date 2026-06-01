# ABOUTME: Tests lazy Phi creation in postfix loop constructs (EXPR for LIST, EXPR while COND)
# ABOUTME: Verifies PostfixModifier scope forking collects body variable refs into side table
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Phi;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Bindings;
use Chalk::Bootstrap::Semiring::SemanticAction;

my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PostfixLoopPhiTest/g;
    eval $generated;
    skip "Generated code failed: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PostfixLoopPhiTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];

    # --- Test: Postfix for loop with variable read-write creates Phi ---
    # $x is read and written in the loop body expression: $x = $x + 1
    # After the loop, $x should be a Phi node (loop-carried dependency).
    # PostfixModifier must collect body variable refs into %_loop_body_var_refs
    # so Program's Phi insertion loop can find and create the Phi.
    {
        $semiring->reset_cache();

        my $src = 'my $x = 0; $x = $x + 1 for (1, 2, 3);';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'postfix for loop parses');

        my $sem_ctx = $result;
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available after postfix for loop');

        my $x_binding = $state->{scope}->lookup('$x');
        TODO: {
            local $TODO = 'postfix-for loop Phi needs PostfixModifier to build a loop merge (Phase 3)';
            ok($x_binding isa Chalk::IR::Node::Phi,
                '$x is a Phi after postfix for loop (loop-carried dep)')
                or diag('$x binding is: ' . ref($x_binding)
                    . ' / ' . ($x_binding->operation() // 'undef'));
        }
    }

    # --- Test: Postfix while loop with variable read creates degenerate Phi ---
    # $n is read in the while condition (part of body expression).
    # After the loop, $n should be a Phi node.
    {
        $semiring->reset_cache();

        my $src = 'my $n = 10; say $n while ($n > 0);';
        my $result = $parser->parse_value($src);
        ok(defined $result, 'postfix while loop parses');

        my $sem_ctx = $result;
        skip 'no semantic context', 2 unless defined $sem_ctx;

        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available after postfix while loop');

        my $n_binding = $state->{scope}->lookup('$n');
        ok(defined $n_binding, '$n in scope after postfix while loop');
        TODO: {
            local $TODO = 'postfix-while loop Phi needs PostfixModifier to build a loop merge (Phase 3)';
            ok($n_binding isa Chalk::IR::Node::Phi,
                '$n is a Phi after postfix while loop')
                or diag('$n binding is: ' . ref($n_binding));
        }
    }
}

done_testing();
