# ABOUTME: Tests for the Dead Code Elimination optimizer pass.
# ABOUTME: Covers unit tests with manual IR graphs and integration tests with full pipeline.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Node::Constant;

use_ok('Chalk::Bootstrap::Optimizer::DCE');

# Helper: build a minimal Perl IR graph with a VarDecl root node.
# The VarDecl node references a Constant (variable name) and another Constant (value).
# Returns the root VarDecl node.
sub build_mini_varnode {
    my ($factory, $name, $val) = @_;
    my $name_const = $factory->make('Constant', const_type => 'string', value => $name);
    my $val_const  = $factory->make('Constant', const_type => 'string', value => $val);
    return $factory->make('Constructor',
        class    => 'VarDecl',
        variable => $name_const,
        initializer => $val_const,
    );
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

    my $root = build_mini_varnode($factory, 'x', 'hello');

    # Create an orphan node not reachable from any root
    my $orphan = $factory->make('Constant',
        const_type => 'string', value => 'orphan_value');

    my $count_before = $factory->node_count();
    ok($count_before > 0, "have nodes before DCE (count=$count_before)");

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    my $result = $dce->run([$root]);

    is(ref($result), 'ARRAY', 'run() returns arrayref');
    is(scalar($result->@*), 1, 'run() returns same number of roots');

    my $count_after = $factory->node_count();
    ok($count_after < $count_before,
        "dead nodes removed (before=$count_before, after=$count_after)");

    # Orphan should be gone
    ok(!defined($factory->get_node($orphan->id())),
        'orphan node removed from cache');

    # Reachable nodes should still exist
    ok(defined($factory->get_node($root->id())),
        'root VarDecl node still exists');
}

# Multiple roots sharing nodes: shared subgraph preserved when reachable from both
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Build two VarDecl nodes that share a common Constant (the same initializer value)
    my $shared_const = $factory->make('Constant',
        const_type => 'string', value => 'shared_value');

    my $name1 = $factory->make('Constant', const_type => 'string', value => 'var1');
    my $name2 = $factory->make('Constant', const_type => 'string', value => 'var2');

    my $root1 = $factory->make('Constructor',
        class    => 'VarDecl',
        variable => $name1,
        initializer => $shared_const,
    );
    my $root2 = $factory->make('Constructor',
        class    => 'VarDecl',
        variable => $name2,
        initializer => $shared_const,
    );

    # shared_const is consumed by both roots
    is(scalar($shared_const->consumers()->@*), 2,
        'shared constant has 2 consumers from distinct roots');

    my $count_before = $factory->node_count();
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$root1, $root2]);

    is($factory->node_count(), $count_before,
        'multi-root: all shared nodes preserved');
    is(scalar($shared_const->consumers()->@*), 2,
        'multi-root: shared node consumer count unchanged');
}

# Consumer cleanup: dead node removed from consumer lists of its inputs
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $root = build_mini_varnode($factory, 'ConsumerTest', 'alive');

    # Create a shared constant that the orphan also uses as initializer
    my $shared_const = $factory->make('Constant',
        const_type => 'string', value => 'shared_init');
    my $orphan_name = $factory->make('Constant', const_type => 'string', value => 'dead_var');
    my $orphan = $factory->make('Constructor',
        class    => 'VarDecl',
        variable => $orphan_name,
        initializer => $shared_const,
    );

    # shared_const is consumed by the orphan
    my $consumers_before = scalar($shared_const->consumers()->@*);
    ok($consumers_before >= 1, "shared_const has consumers including orphan");

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    # Only $root is reachable — $orphan is not passed as a root
    $dce->run([$root]);

    my $consumers_after = scalar($shared_const->consumers()->@*);
    ok($consumers_after < $consumers_before,
        "dead consumer removed from shared node (before=$consumers_before, after=$consumers_after)");

    # orphan should be gone
    ok(!defined($factory->get_node($orphan->id())),
        'orphan VarDecl node removed');
}

# No dead nodes: fully-reachable graph is a no-op
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $root = build_mini_varnode($factory, 'FullyReachable', 'value');
    my $count_before = $factory->node_count();

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$root]);

    is($factory->node_count(), $count_before,
        'no-op when all nodes are reachable');
}

# Empty roots: all nodes are dead
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Create some nodes but pass empty roots
    build_mini_varnode($factory, 'DeadVar', 'dead_value');
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

    # Run full pipeline to get grammar data from the real 10-rule BNF
    my $ir = full_pipeline();
    ok(defined($ir), 'full pipeline produces grammar data');
    is(scalar($ir->@*), 10, 'pipeline produces 10 rules');

    # Verify each rule is a Chalk::Grammar::Rule object
    for my $rule ($ir->@*) {
        isa_ok($rule, 'Chalk::Grammar::Rule', "rule '${\$rule->name()}'");
    }

    # Generate Perl code from the grammar data
    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    ok(defined($generated), 'code generation from pipeline produces output');

    # Eval generated code
    eval $generated;
    is($@, '', 'generated code from pipeline evals without error');

    # Compare generated grammar structurally to hand-written grammar
    my $gen_grammar = Chalk::Grammar::BNF::Generated::grammar();
    my $ref_grammar = Chalk::Grammar::BNF::grammar();

    is(scalar($gen_grammar->@*), scalar($ref_grammar->@*),
        'pipeline output has same number of rules as reference');
    ok(grammars_match($gen_grammar, $ref_grammar),
        'generated grammar structurally matches hand-written grammar');
}

done_testing();
