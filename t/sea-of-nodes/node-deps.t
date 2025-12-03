# ABOUTME: Tests for dependency tracking on IR nodes (_deps field)
# ABOUTME: Used by peepholes to register for re-optimization when remote nodes change

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Graph;

subtest 'Node starts with empty deps' => sub {
    my $node = Chalk::IR::Node->new(
        id => 'n1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );

    my @deps = $node->get_deps();
    is scalar(@deps), 0, 'new node has no dependencies';
};

subtest 'add_dep adds dependency' => sub {
    my $node = Chalk::IR::Node->new(
        id => 'n1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );

    $node->add_dep('n2');
    my @deps = $node->get_deps();
    is scalar(@deps), 1, 'has one dependency';
    is $deps[0], 'n2', 'dependency is n2';
};

subtest 'add_dep accumulates dependencies' => sub {
    my $node = Chalk::IR::Node->new(
        id => 'n1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );

    $node->add_dep('n2');
    $node->add_dep('n3');
    $node->add_dep('n4');

    my @deps = $node->get_deps();
    is scalar(@deps), 3, 'has three dependencies';
    is [sort @deps], ['n2', 'n3', 'n4'], 'all dependencies present';
};

subtest 'get_deps returns copy (modification safe)' => sub {
    my $node = Chalk::IR::Node->new(
        id => 'n1',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );

    $node->add_dep('n2');
    my @deps1 = $node->get_deps();
    push @deps1, 'n99';  # modify returned array

    my @deps2 = $node->get_deps();
    is scalar(@deps2), 1, 'original deps unchanged';
};
