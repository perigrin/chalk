# ABOUTME: Test for Sea of Nodes IR generation - Module support (Issue #98 Phase 5)
# ABOUTME: Validates IR generation for use statement metadata capture

use v5.42;
use Test::More;
use Test::Deep;

# Test that we can load the IR modules
use_ok('Chalk::IR::Node');
use_ok('Chalk::IR::Graph');
use_ok('Chalk::IR::Builder');

# Test manual IR graph construction for use statement metadata
# This tests the IR infrastructure for Phase 5: Module Support
subtest 'Manual IR graph construction for use statements' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create Start node (entry point)
    my $start = Chalk::IR::Node->new(
        id => 'node_0',
        op => 'Start',
        inputs => [],
        attributes => { function => 'main' }
    );
    $graph->add_node($start);

    # Create UseStatement node for: use 5.42.0;
    my $use_version = Chalk::IR::Node->new(
        id => 'node_1',
        op => 'UseStatement',
        inputs => ['node_0'],  # Control dependency
        attributes => {
            type => 'version',
            module => '5.42.0',
            imports => []
        }
    );
    $graph->add_node($use_version);

    # Create UseStatement node for: use experimental qw(class builtin);
    my $use_pragma = Chalk::IR::Node->new(
        id => 'node_2',
        op => 'UseStatement',
        inputs => ['node_0'],
        attributes => {
            type => 'pragma',
            module => 'experimental',
            imports => ['class', 'builtin']
        }
    );
    $graph->add_node($use_pragma);

    # Create UseStatement node for: use utf8;
    my $use_encoding = Chalk::IR::Node->new(
        id => 'node_3',
        op => 'UseStatement',
        inputs => ['node_0'],
        attributes => {
            type => 'pragma',
            module => 'utf8',
            imports => []
        }
    );
    $graph->add_node($use_encoding);

    # Create UseStatement node for: use Chalk::IR::Node;
    my $use_module = Chalk::IR::Node->new(
        id => 'node_4',
        op => 'UseStatement',
        inputs => ['node_0'],
        attributes => {
            type => 'module',
            module => 'Chalk::IR::Node',
            imports => []  # Full import (no import list specified)
        }
    );
    $graph->add_node($use_module);

    # Create UseStatement node for: use builtin qw(blessed reftype);
    my $use_external = Chalk::IR::Node->new(
        id => 'node_5',
        op => 'UseStatement',
        inputs => ['node_0'],
        attributes => {
            type => 'external',
            module => 'builtin',
            imports => ['blessed', 'reftype']
        }
    );
    $graph->add_node($use_external);

    # Create Return node
    my $return = Chalk::IR::Node->new(
        id => 'node_6',
        op => 'Return',
        inputs => ['node_0'],
        attributes => {}
    );
    $graph->add_node($return);

    # Verify graph structure
    is($graph->entry, 'node_0', 'Entry node is Start');
    is($graph->node_count, 7, 'Graph has 7 nodes');

    # Verify version use statement
    my $version_node = $graph->get_node('node_1');
    ok($version_node, 'UseStatement node for version exists');
    is($version_node->op, 'UseStatement', 'Version use has correct op');
    is($version_node->attributes->{type}, 'version', 'Version use has correct type');
    is($version_node->attributes->{module}, '5.42.0', 'Version use has correct module');
    is(scalar(@{$version_node->attributes->{imports}}), 0, 'Version use has no imports');

    # Verify pragma use statement
    my $pragma_node = $graph->get_node('node_2');
    ok($pragma_node, 'UseStatement node for pragma exists');
    is($pragma_node->op, 'UseStatement', 'Pragma use has correct op');
    is($pragma_node->attributes->{type}, 'pragma', 'Pragma use has correct type');
    is($pragma_node->attributes->{module}, 'experimental', 'Pragma use has correct module');
    cmp_deeply($pragma_node->attributes->{imports}, ['class', 'builtin'], 'Pragma use has correct imports');

    # Verify encoding pragma
    my $encoding_node = $graph->get_node('node_3');
    ok($encoding_node, 'UseStatement node for encoding exists');
    is($encoding_node->op, 'UseStatement', 'Encoding use has correct op');
    is($encoding_node->attributes->{type}, 'pragma', 'Encoding use has correct type');
    is($encoding_node->attributes->{module}, 'utf8', 'Encoding use has correct module');

    # Verify module use statement
    my $module_node = $graph->get_node('node_4');
    ok($module_node, 'UseStatement node for module exists');
    is($module_node->op, 'UseStatement', 'Module use has correct op');
    is($module_node->attributes->{type}, 'module', 'Module use has correct type');
    is($module_node->attributes->{module}, 'Chalk::IR::Node', 'Module use has correct module name');
    is(scalar(@{$module_node->attributes->{imports}}), 0, 'Module use has no specific imports (full import)');

    # Verify external module use statement
    my $external_node = $graph->get_node('node_5');
    ok($external_node, 'UseStatement node for external exists');
    is($external_node->op, 'UseStatement', 'External use has correct op');
    is($external_node->attributes->{type}, 'external', 'External use has correct type');
    is($external_node->attributes->{module}, 'builtin', 'External use has correct module');
    cmp_deeply($external_node->attributes->{imports}, ['blessed', 'reftype'], 'External use has correct imports');
};

# Test IR Builder methods for use statements
subtest 'IR Builder methods for module support' => sub {
    use_ok('Chalk::IR::Builder');

    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');
    is($start->op, 'Start', 'Builder creates Start node');

    # Build version use statement
    my $use_version = $builder->build_use_statement_node('version', '5.42.0', []);
    ok($use_version, 'Builder creates UseStatement for version');
    is($use_version->op, 'UseStatement', 'Version use has correct op');
    is($use_version->attributes->{type}, 'version', 'Version use has correct type');
    is($use_version->attributes->{module}, '5.42.0', 'Version use has correct module');

    # Build pragma use statement with imports
    my $use_pragma = $builder->build_use_statement_node('pragma', 'experimental', ['class', 'builtin']);
    ok($use_pragma, 'Builder creates UseStatement for pragma');
    is($use_pragma->op, 'UseStatement', 'Pragma use has correct op');
    is($use_pragma->attributes->{type}, 'pragma', 'Pragma use has correct type');
    cmp_deeply($use_pragma->attributes->{imports}, ['class', 'builtin'], 'Pragma use has correct imports');

    # Build module use statement
    my $use_module = $builder->build_use_statement_node('module', 'Chalk::IR::Node', []);
    ok($use_module, 'Builder creates UseStatement for module');
    is($use_module->op, 'UseStatement', 'Module use has correct op');
    is($use_module->attributes->{type}, 'module', 'Module use has correct type');
    is($use_module->attributes->{module}, 'Chalk::IR::Node', 'Module use has correct module name');

    # Build external module use statement
    my $use_external = $builder->build_use_statement_node('external', 'builtin', ['blessed', 'reftype']);
    ok($use_external, 'Builder creates UseStatement for external');
    is($use_external->op, 'UseStatement', 'External use has correct op');
    is($use_external->attributes->{type}, 'external', 'External use has correct type');
    cmp_deeply($use_external->attributes->{imports}, ['blessed', 'reftype'], 'External use has correct imports');

    # Verify all nodes are in the graph
    ok($graph->get_node($use_version->id), 'Version UseStatement in graph');
    ok($graph->get_node($use_pragma->id), 'Pragma UseStatement in graph');
    ok($graph->get_node($use_module->id), 'Module UseStatement in graph');
    ok($graph->get_node($use_external->id), 'External UseStatement in graph');
};

# Test UseStatement semantic action module loads correctly
subtest 'UseStatement semantic action module' => sub {
    use_ok('Chalk::Grammar::Chalk::Rule::UseStatement');

    # The semantic action will be tested via t/self-hosting.t when Chalk parses itself.
    # Chalk source files contain use statements like:
    #   use 5.42.0;
    #   use experimental 'class';
    #   use builtin qw(blessed);
    #   use Chalk::IR::Node;
    #
    # When the parser encounters these, it will automatically invoke the UseStatement
    # semantic action to categorize them and build UseStatement IR nodes.
};

done_testing();
