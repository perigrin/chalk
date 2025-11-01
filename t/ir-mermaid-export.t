#!/usr/bin/env perl
# ABOUTME: Test IR graph export to Mermaid diagram format
# ABOUTME: Verify MermaidExporter produces valid Mermaid syntax for visualization
use 5.42.0;
use utf8;
use lib 'lib';
use lib 'tools';
use Test::More tests => 8;
use Chalk::IR::Graph;
use Chalk::IR::Node;
use MermaidExporter;

# Test 1: Simple constant graph
{
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id         => 'node_1',
        op         => 'Start',
        inputs     => [],
        attributes => { function_name => 'main', params => [] },
    );

    my $const = Chalk::IR::Node->new(
        id         => 'node_2',
        op         => 'Constant',
        inputs     => ['node_1'],
        attributes => { value => 42, type => 'int' },
    );

    my $return = Chalk::IR::Node->new(
        id         => 'node_3',
        op         => 'Return',
        inputs     => ['node_1', 'node_2'],
        attributes => { value_id => 'node_2', control_id => 'node_1' },
    );

    $graph->add_node($start);
    $graph->add_node($const);
    $graph->add_node($return);

    my $mermaid = MermaidExporter->export($graph);

    ok(defined($mermaid), 'MermaidExporter->export() returns a value');
    like($mermaid, qr/graph/, 'output contains graph declaration');
    like($mermaid, qr/node_1.*Start/, 'output contains Start node');
    like($mermaid, qr/node_2.*Constant.*42/, 'output contains Constant with value');
    like($mermaid, qr/node_3.*Return/, 'output contains Return node');
}

# Test 2: Graph with edges
{
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id         => 'node_10',
        op         => 'Start',
        inputs     => [],
        attributes => {},
    );

    my $c1 = Chalk::IR::Node->new(
        id         => 'node_11',
        op         => 'Constant',
        inputs     => ['node_10'],
        attributes => { value => 1 },
    );

    my $c2 = Chalk::IR::Node->new(
        id         => 'node_12',
        op         => 'Constant',
        inputs     => ['node_10'],
        attributes => { value => 2 },
    );

    my $add = Chalk::IR::Node->new(
        id         => 'node_13',
        op         => 'Add',
        inputs     => ['node_10', 'node_11', 'node_12'],
        attributes => { left_id => 'node_11', right_id => 'node_12' },
    );

    $graph->add_node($start);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add);

    my $mermaid = MermaidExporter->export($graph);

    like($mermaid, qr/node_11.*-->.*node_13/, 'output shows edge from constant to add');
    like($mermaid, qr/node_12.*-->.*node_13/, 'output shows edge from constant to add');
}

# Test 3: Empty graph
{
    my $graph = Chalk::IR::Graph->new();
    my $mermaid = MermaidExporter->export($graph);

    ok(defined($mermaid), 'empty graph returns valid Mermaid output');
}
