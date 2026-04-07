# ABOUTME: Tests that IfStatement merges branch scopes with Phi nodes at the merge point.
# ABOUTME: Verifies that variables assigned in if/else branches produce Phis in post-if scope.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::IR::Node::Phi;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScopeIfMergeTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ScopeIfMergeTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction, 'got SemanticAction from parser');

    # --- Test 1: if/else with different values for $x creates a Phi ---
    # Input: my $x = 1; if (1) { $x = 2; } else { $x = 3; }
    # Expected: after the if/else, $x is a Phi(2, 3)
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 1; if (1) { $x = 2; } else { $x = 3; }');
        ok(defined $result, 'if/else with branch assignments parses');

        my $sem_ctx = $result->[4];
        ok(defined $sem_ctx, 'SemanticAction context exists');

        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state is set after if/else');

        SKIP: {
            skip 'no cfg_state to check scope', 3 unless defined $state;
            my $scope = $state->{scope};
            ok(defined $scope, 'cfg_state has scope');

            SKIP: {
                skip 'no scope to check', 2 unless defined $scope;
                my $x_val = $scope->lookup('$x');
                ok(defined $x_val, '$x is bound in scope after if/else');
                ok($x_val isa Chalk::IR::Node::Phi,
                    '$x is a Phi node after if/else with different branch values');
            }
        }
    }

    # --- Test 2: if without else — $x assigned in then-branch becomes Phi ---
    # Input: my $x = 1; if (1) { $x = 2; }
    # Expected: after the if, $x is a Phi(then=2, else=1) or Phi(2, pre-value)
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 1; if (1) { $x = 2; }');
        ok(defined $result, 'if-without-else with branch assignment parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state is set after if-without-else');

        SKIP: {
            skip 'no cfg_state to check scope', 3 unless defined $state;
            my $scope = $state->{scope};
            ok(defined $scope, 'cfg_state has scope for if-without-else');

            SKIP: {
                skip 'no scope to check', 2 unless defined $scope;
                my $x_val = $scope->lookup('$x');
                ok(defined $x_val, '$x is bound in scope after if-without-else');
                ok($x_val isa Chalk::IR::Node::Phi,
                    '$x is a Phi after if-without-else (then assigns, else uses pre-value)');
            }
        }
    }

    # --- Test 3: if/else where $x is the same in both branches — no Phi ---
    # Input: my $x = 1; if (1) { my $y = 2; } else { my $y = 3; }
    # Expected: $x is NOT a Phi (unchanged in both branches)
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 1; if (1) { my $y = 2; } else { my $y = 3; }');
        ok(defined $result, 'if/else without $x assignment parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state is set');

        SKIP: {
            skip 'no cfg_state to check scope', 2 unless defined $state;
            my $scope = $state->{scope};
            ok(defined $scope, 'cfg_state has scope');

            SKIP: {
                skip 'no scope to check', 1 unless defined $scope;
                my $x_val = $scope->lookup('$x');
                ok(!defined($x_val) || !($x_val isa Chalk::IR::Node::Phi),
                    '$x is NOT a Phi when not assigned in either branch');
            }
        }
    }
}

done_testing();
