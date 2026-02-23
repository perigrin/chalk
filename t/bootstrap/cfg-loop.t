# ABOUTME: Tests that ForeachLoop produces Loop/Phi CFG nodes via post-parse build_cfg.
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

    # --- Test 1: foreach produces Loop CFG node ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach loop parses');

        my $sem_ctx = $result->[4];
        ok(defined $sem_ctx, 'SemanticAction context exists');

        # Build CFG from the parse tree
        my $state = $sa->build_cfg($sem_ctx);
        ok(defined $state, 'build_cfg returns state');

        # The control should be a Region (loop exit)
        my $control = $state->{control};
        is($control->operation(), 'Region', 'control after foreach is Region (loop exit)');

        # Walk up: Region's controls → Proj → If → Loop
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

    # --- Test 2: Backward compatibility — ForeachLoop Constructor preserved ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'foreach parses for compat check');

        my $sem_ctx = $result->[4];

        # Walk the Context tree to find ForeachLoop Constructor
        my $found_foreach = false;
        my @walk = ($sem_ctx);
        while (@walk) {
            my $node = pop @walk;
            my $f = $node->extract();
            if (defined $f && ref($f) && $f isa Chalk::Bootstrap::IR::Node
                && $f->operation() eq 'Constructor' && $f->class() eq 'ForeachLoop') {
                $found_foreach = true;
                last;
            }
            push @walk, reverse $node->children()->@*;
        }
        ok($found_foreach, 'ForeachLoop Constructor found in tree (backward compat)');
    }

    # --- Test 3: Sequential: vardecl then loop ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $y = 0; for my $x (1, 2, 3) { $x }');
        ok(defined $result, 'vardecl + foreach parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->build_cfg($sem_ctx);

        ok(defined $state->{scope}->lookup('$y'), '$y in scope');
        is($state->{control}->operation(), 'Region', 'control is Region after foreach');
    }
}

done_testing();
