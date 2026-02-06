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

# Consumer cleanup: dead node removed from consumer lists of its inputs
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
    use TestPipeline qw(full_pipeline bnf_text);
    use Chalk::Bootstrap::Target::Perl;

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
    my $target = Chalk::Bootstrap::Target::Perl->new();
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

    my $all_match = true;
    for my $i (0 .. $#{$ref_grammar}) {
        my $gen = $gen_grammar->[$i];
        my $ref = $ref_grammar->[$i];
        if ($gen->name() ne $ref->name()) {
            $all_match = false;
            diag("Rule name mismatch at index $i: got " . $gen->name() . ", expected " . $ref->name());
            last;
        }
        if ($gen->alternative_count() != $ref->alternative_count()) {
            $all_match = false;
            diag("Alt count mismatch at rule " . $ref->name());
            last;
        }
        for my $j (0 .. $#{$ref->expressions()}) {
            my $gen_alt = $gen->expressions()->[$j];
            my $ref_alt = $ref->expressions()->[$j];
            if (scalar($gen_alt->@*) != scalar($ref_alt->@*)) {
                $all_match = false;
                diag("Element count mismatch at rule " . $ref->name() . " alt $j");
                last;
            }
            for my $k (0 .. $#{$ref_alt}) {
                my $gs = $gen_alt->[$k];
                my $rs = $ref_alt->[$k];
                if ($gs->type() ne $rs->type()
                    || $gs->value() ne $rs->value()
                    || ($gs->quantifier() // '') ne ($rs->quantifier() // '')) {
                    $all_match = false;
                    diag("Symbol mismatch at rule " . $ref->name() . " alt $j elem $k");
                    last;
                }
            }
        }
    }
    ok($all_match, 'optimized generated grammar structurally matches hand-written grammar');
}

done_testing();
