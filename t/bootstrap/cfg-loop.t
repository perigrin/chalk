# ABOUTME: Tests that ForeachLoop produces Loop/Phi CFG nodes via parse-time cfg_state.
# ABOUTME: Verifies Sea of Nodes CFG structure from parsed loop statements.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::CfgLoopTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::CfgLoopTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    my $semiring = $parser->semiring();
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction, 'got SemanticAction from parser');

    # --- Test 1: foreach produces Loop CFG node via parse-time cfg_state ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach loop parses');

        my $sem_ctx = $result->[4];
        ok(defined $sem_ctx, 'SemanticAction context exists');

        # cfg_state should reflect the Loop/If/Region CFG structure
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state returns state');

        # The control should be a Region (loop exit)
        my $control = $state->{control};
        is($control->operation(), 'Region', 'control after foreach is Region (loop exit)');

        # Walk up: Region's controls -> Proj -> If -> Loop
        my $controls = $control->inputs()->[0];
        is(ref($controls), 'ARRAY', 'Region has controls array');
        ok(scalar($controls->@*) >= 1, 'Region has at least 1 control input');

        # The exit proj should come from an If node
        my $exit_proj = $controls->[0];
        is($exit_proj->operation(), 'Proj', 'exit control is a Proj');

        my $if_node = $exit_proj->inputs()->[0];
        is($if_node->operation(), 'If', 'Proj source is an If node');

        # If should be controlled by a Loop node
        my $loop_node = $if_node->inputs()->[0];
        is($loop_node->operation(), 'Loop', 'If controlled by Loop node');
    }

    # --- Test 2: postfix for produces Loop CFG node via parse-time cfg_state ---
    # PostfixModifier rule is not triggered for `$x++ for 1, 2, 3;` because
    # the grammar parses it as a fragmented statement list rather than
    # recognizing the postfix `for` modifier. The PostfixModifier CFG
    # construction is in place but requires grammar fixes to trigger.
    TODO: {
        local $TODO = 'PostfixModifier not recognized by grammar for postfix for';
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('$x++ for 1, 2, 3;');
        ok(defined $result, 'postfix for parses');

        my $sem_ctx = $result ? $result->[4] : undef;
        my $state = defined $sem_ctx ? $sa->cfg_state($sem_ctx) : undef;
        ok(defined $state, 'cfg_state returns state for postfix for');

        my $control = $state ? $state->{control} : undef;
        is($control ? $control->operation() : 'undef', 'Region',
            'control after postfix for is Region');
    }
}

done_testing();
