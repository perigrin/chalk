# ABOUTME: Tests for the Dead Code Elimination optimizer pass.
# ABOUTME: Covers unit tests with manual graphs and integration tests with full pipeline.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Node::Constant;
use Chalk::Bootstrap::IR::Node::Constructor;

use_ok('Chalk::Bootstrap::Optimizer::DCE');

# Helper: build a minimal rule graph (name_const -> expr -> rule)
# Returns ($factory, $rule_node)
sub build_mini_rule {
    my ($factory, $rule_name) = @_;

    my $name_const = $factory->make('Constant',
        const_type => 'string', value => $rule_name);
    my $type_const = $factory->make('Constant',
        const_type => 'string', value => 'terminal');
    my $val_const = $factory->make('Constant',
        const_type => 'string', value => '/foo/');

    my $symbol = $factory->make('Constructor',
        class => 'Symbol',
        type => $type_const,
        value => $val_const,
        quantifier => undef,
    );

    my $expr = $factory->make('Constructor',
        class => 'Expression',
        elements => [$symbol],
    );

    my $rule = $factory->make('Constructor',
        class => 'Rule',
        name => $name_const,
        expressions => [$expr],
    );

    return $rule;
}

# name() returns 'DCE'
{
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    is($dce->name(), 'DCE', 'name() returns DCE');
}

# Dead node removal: orphan Constant removed, reachable nodes preserved
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $rule = build_mini_rule($factory, 'TestRule');

    # Create an orphan node not reachable from any root
    my $orphan = $factory->make('Constant',
        const_type => 'string', value => 'orphan_value');

    my $count_before = $factory->node_count();
    ok($count_before > 0, "have nodes before DCE (count=$count_before)");

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    my $result = $dce->run([$rule]);

    is(ref($result), 'ARRAY', 'run() returns arrayref');
    is(scalar($result->@*), 1, 'run() returns same number of roots');

    my $count_after = $factory->node_count();
    ok($count_after < $count_before,
        "dead nodes removed (before=$count_before, after=$count_after)");

    # Orphan should be gone
    ok(!defined($factory->get_node($orphan->id())),
        'orphan node removed from cache');

    # Reachable nodes should still exist
    ok(defined($factory->get_node($rule->id())),
        'root rule node still exists');
}

# Multiple roots sharing nodes: shared subgraph preserved when reachable from both
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Build two rules that share the type constant 'terminal' but have different
    # value constants, forcing distinct Symbols that both consume the shared type.
    my $shared_type = $factory->make('Constant',
        const_type => 'string', value => 'terminal');

    my $name1 = $factory->make('Constant',
        const_type => 'string', value => 'Rule1');
    my $val1 = $factory->make('Constant',
        const_type => 'string', value => '/pattern_a/');
    my $sym1 = $factory->make('Constructor',
        class => 'Symbol', type => $shared_type, value => $val1, quantifier => undef);
    my $expr1 = $factory->make('Constructor',
        class => 'Expression', elements => [$sym1]);
    my $rule1 = $factory->make('Constructor',
        class => 'Rule', name => $name1, expressions => [$expr1]);

    my $name2 = $factory->make('Constant',
        const_type => 'string', value => 'Rule2');
    my $val2 = $factory->make('Constant',
        const_type => 'string', value => '/pattern_b/');
    my $sym2 = $factory->make('Constructor',
        class => 'Symbol', type => $shared_type, value => $val2, quantifier => undef);
    my $expr2 = $factory->make('Constructor',
        class => 'Expression', elements => [$sym2]);
    my $rule2 = $factory->make('Constructor',
        class => 'Rule', name => $name2, expressions => [$expr2]);

    # shared_type is consumed by both sym1 and sym2
    is(scalar($shared_type->consumers()->@*), 2,
        'shared type constant has 2 consumers from distinct symbols');

    my $count_before = $factory->node_count();
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$rule1, $rule2]);

    is($factory->node_count(), $count_before,
        'multi-root: all shared nodes preserved');
    is(scalar($shared_type->consumers()->@*), 2,
        'multi-root: shared node consumer count unchanged');
}

# Consumer cleanup: dead node removed from consumer lists of its inputs
# Note: $shared_type retrieves the same 'terminal' Constant created inside
# build_mini_rule() due to hash consing deduplication.
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $rule = build_mini_rule($factory, 'ConsumerTest');

    # Create a shared constant that the orphan constructor also consumes
    my $shared_type = $factory->make('Constant',
        const_type => 'string', value => 'terminal');
    my $shared_val = $factory->make('Constant',
        const_type => 'string', value => '/orphan_pattern/');

    my $orphan_symbol = $factory->make('Constructor',
        class => 'Symbol',
        type => $shared_type,
        value => $shared_val,
        quantifier => undef,
    );

    # shared_type is consumed by both the reachable graph and the orphan
    my $consumers_before = scalar($shared_type->consumers()->@*);

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$rule]);

    my $consumers_after = scalar($shared_type->consumers()->@*);
    ok($consumers_after < $consumers_before,
        "dead consumer removed from shared node (before=$consumers_before, after=$consumers_after)");

    # orphan_symbol should be gone
    ok(!defined($factory->get_node($orphan_symbol->id())),
        'orphan symbol node removed');
}

# No dead nodes: fully-reachable graph is a no-op
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $rule = build_mini_rule($factory, 'FullyReachable');
    my $count_before = $factory->node_count();

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$rule]);

    is($factory->node_count(), $count_before,
        'no-op when all nodes are reachable');
}

# Empty roots: all nodes are dead
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Create some nodes but pass empty roots
    build_mini_rule($factory, 'DeadRule');
    ok($factory->node_count() > 0, 'have nodes before empty-roots DCE');

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([]);

    is($factory->node_count(), 0, 'all nodes removed with empty roots');
}

# Input validation: run(undef) dies
{
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    eval { $dce->run(undef) };
    like($@, qr/requires.*arrayref/i, 'run(undef) dies with useful error');
}

# ===== Integration tests with full BNF pipeline =====

{
    use lib 't/bootstrap/lib';
    use TestPipeline qw(full_pipeline bnf_text grammars_match);
    use Chalk::Bootstrap::BNF::Target::Perl;

    # Run full pipeline to get IR from the real 10-rule BNF
    my $ir = full_pipeline();
    ok(defined($ir), 'full pipeline produces IR');
    is(scalar($ir->@*), 10, 'IR contains 10 rules');

    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $count_before = $factory->node_count();
    ok($count_before > 0, "have nodes before DCE (count=$count_before)");

    # Run DCE
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    my $optimized_ir = $dce->run($ir);

    my $count_after = $factory->node_count();
    ok($count_after <= $count_before,
        "node count did not increase (before=$count_before, after=$count_after)");
    is(scalar($optimized_ir->@*), 10, 'optimized IR still has 10 rules');

    # Generate Perl code from optimized IR
    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($optimized_ir);
    ok(defined($generated), 'code generation from optimized IR produces output');

    # Eval generated code
    eval $generated;
    is($@, '', 'generated code from optimized IR evals without error');

    # Compare generated grammar structurally to hand-written grammar
    my $gen_grammar = Chalk::Grammar::BNF::Generated::grammar();
    my $ref_grammar = Chalk::Grammar::BNF::grammar();

    is(scalar($gen_grammar->@*), scalar($ref_grammar->@*),
        'optimized output has same number of rules as reference');
    ok(grammars_match($gen_grammar, $ref_grammar),
        'optimized generated grammar structurally matches hand-written grammar');
}

done_testing();
