# ABOUTME: Tests that IfStatement produces If/Proj/Region CFG nodes via parse-time cfg_state.
# ABOUTME: Verifies Sea of Nodes CFG structure from parsed if/else statements.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgIfElseTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::CfgIfElseTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction, 'got SemanticAction from parser');

    # --- Test 1: Simple if/else produces CFG nodes via parse-time cfg_state ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 2 } else { 3 }');
        ok(defined $result, 'if/else parses');

        my $sem_ctx = $result;
        ok(defined $sem_ctx, 'SemanticAction context exists');

        # cfg_state should have been propagated through the parse
        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state returns state');
        ok(defined $state->{control}, 'state has control token');

        # The control should be a Region node (merging true/false paths)
        my $region = $state->{control};
        is($region->operation(), 'Region', 'control after if/else is a Region node');

        # Region's controls should be two Proj nodes
        my $controls = $region->inputs()->[0];
        is(ref($controls), 'ARRAY', 'Region has controls array');
        is(scalar($controls->@*), 2, 'Region has exactly 2 control inputs');

        my $true_proj = $controls->[0];
        my $false_proj = $controls->[1];
        is($true_proj->operation(), 'Proj', 'Region control 0 is a Proj');
        is($false_proj->operation(), 'Proj', 'Region control 1 is a Proj');

        # Both Projs should come from the same If node
        my $if_node = $true_proj->inputs()->[0];
        is($if_node->operation(), 'If', 'Proj source is an If node');
        is($false_proj->inputs()->[0], $if_node, 'both Projs from same If');

        # If node should have a condition input
        my $if_condition = $if_node->inputs()->[1];
        ok(defined $if_condition, 'If node has condition input');

        # If node's control should be Start (initial control)
        is($if_node->inputs()->[0]->operation(), 'Start', 'If controlled by Start');
    }

    # --- Test 2: if without else produces CFG nodes too ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 2 }');
        ok(defined $result, 'if-without-else parses');

        my $sem_ctx = $result;
        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state returns state for if-no-else');

        # Should still have Region (even without else, control merges)
        my $region = $state->{control};
        is($region->operation(), 'Region', 'control after if-no-else is Region');
    }

    # --- Test 3: cfg_state propagates through parse via on_merge ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('if (1) { 2 } else { 3 }');
        ok(defined $result, 'if/else parses for cfg_state check');

        my $sem_ctx = $result;
        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state propagated to outermost context');
        is($state->{control}->operation(), 'Region',
            'cfg_state control is Region (propagated through Earley merges)');
    }
}

done_testing();
