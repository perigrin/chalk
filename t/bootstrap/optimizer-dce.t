# ABOUTME: Tests for the Dead Code Elimination optimizer pass.
# ABOUTME: Covers unit tests with manual IR graphs and integration tests with full pipeline.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;

use_ok('Chalk::Bootstrap::Optimizer::DCE');

# Helper: build a minimal Perl IR graph with a VarDecl root node.
# The VarDecl node references a Constant (variable name) and another Constant (value).
# Returns the root VarDecl node.
sub build_mini_varnode {
    my ($factory, $name, $val) = @_;
    my $name_const = $factory->make('Constant', const_type => 'string', value => $name);
    my $val_const  = $factory->make('Constant', const_type => 'string', value => $val);
    return $factory->make('VarDecl',
        inputs       => [undef, $name_const, $val_const],
        compat_class => 'VarDecl',
    );
}

# name() returns 'DCE'
{
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    is($dce->name(), 'DCE', 'name() returns DCE');
}

# Dead node removal: orphan Constant removed, reachable nodes preserved
{
    my $factory = Chalk::IR::NodeFactory->new();

    my $root = build_mini_varnode($factory, 'x', 'hello');

    # Create an orphan node not reachable from any root
    my $orphan = $factory->make('Constant',
        const_type => 'string', value => 'orphan_value');

    my $count_before = $factory->node_count();
    ok($count_before > 0, "have nodes before DCE (count=$count_before)");

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    my $result = $dce->run([$root], $factory);

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
    my $factory = Chalk::IR::NodeFactory->new();

    # Build two VarDecl nodes that share a common Constant (the same initializer value)
    my $shared_const = $factory->make('Constant',
        const_type => 'string', value => 'shared_value');

    my $name1 = $factory->make('Constant', const_type => 'string', value => 'var1');
    my $name2 = $factory->make('Constant', const_type => 'string', value => 'var2');

    my $root1 = $factory->make('VarDecl',
        inputs       => [undef, $name1, $shared_const],
        compat_class => 'VarDecl',
    );
    my $root2 = $factory->make('VarDecl',
        inputs       => [undef, $name2, $shared_const],
        compat_class => 'VarDecl',
    );

    # shared_const is consumed by both roots
    is(scalar($shared_const->consumers()->@*), 2,
        'shared constant has 2 consumers from distinct roots');

    my $count_before = $factory->node_count();
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$root1, $root2], $factory);

    is($factory->node_count(), $count_before,
        'multi-root: all shared nodes preserved');
    is(scalar($shared_const->consumers()->@*), 2,
        'multi-root: shared node consumer count unchanged');
}

# Consumer cleanup: dead node removed from consumer lists of its inputs
{
    my $factory = Chalk::IR::NodeFactory->new();

    my $root = build_mini_varnode($factory, 'ConsumerTest', 'alive');

    # Create a shared constant that the orphan also uses as initializer
    my $shared_const = $factory->make('Constant',
        const_type => 'string', value => 'shared_init');
    my $orphan_name = $factory->make('Constant', const_type => 'string', value => 'dead_var');
    my $orphan = $factory->make('VarDecl',
        inputs       => [undef, $orphan_name, $shared_const],
        compat_class => 'VarDecl',
    );

    # shared_const is consumed by the orphan
    my $consumers_before = scalar($shared_const->consumers()->@*);
    ok($consumers_before >= 1, "shared_const has consumers including orphan");

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    # Only $root is reachable — $orphan is not passed as a root
    $dce->run([$root], $factory);

    my $consumers_after = scalar($shared_const->consumers()->@*);
    ok($consumers_after < $consumers_before,
        "dead consumer removed from shared node (before=$consumers_before, after=$consumers_after)");

    # orphan should be gone
    ok(!defined($factory->get_node($orphan->id())),
        'orphan VarDecl node removed');
}

# No dead nodes: fully-reachable graph is a no-op
{
    my $factory = Chalk::IR::NodeFactory->new();

    my $root = build_mini_varnode($factory, 'FullyReachable', 'value');
    my $count_before = $factory->node_count();

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([$root], $factory);

    is($factory->node_count(), $count_before,
        'no-op when all nodes are reachable');
}

# Empty roots: all nodes are dead
{
    my $factory = Chalk::IR::NodeFactory->new();

    # Create some nodes but pass empty roots
    build_mini_varnode($factory, 'DeadVar', 'dead_value');
    ok($factory->node_count() > 0, 'have nodes before empty-roots DCE');

    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    $dce->run([], $factory);

    is($factory->node_count(), 0, 'all nodes removed with empty roots');
}

# Input validation: run(undef) dies
{
    my $dce = Chalk::Bootstrap::Optimizer::DCE->new();
    eval { $dce->run(undef) };
    like($@, qr/requires/i, 'run(undef) dies with useful error');
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
