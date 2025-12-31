# ABOUTME: Tests for Match/NotMatch XS visitor stubs
# ABOUTME: Verifies Match/NotMatch nodes don't cause unknown node type errors
use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::IR::Node::Match;
use Chalk::IR::Node::NotMatch;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::String;
use Chalk::Target::XS;
use Scalar::Util 'blessed';

# Create test IR nodes
my $left = Chalk::IR::Node::Constant->new(
    value => 'test_string',
    type => Chalk::IR::Type::String->new()
);

my $right = Chalk::IR::Node::Constant->new(
    value => '/pattern/',
    type => Chalk::IR::Type::String->new()
);

subtest 'Match visitor exists and returns undef (stub)' => sub {
    my $match_node = Chalk::IR::Node::Match->new(
        left => $left,
        right => $right
    );

    my $graph = Chalk::IR::Graph->new();
    my $visitor = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'TestModule'
    );

    # visit_Match should exist and not die
    ok($visitor->can('visit_Match'), 'visit_Match method exists');

    my $result = $visitor->visit_Match($match_node);

    # Stub implementation should return undef
    ok(!defined($result), 'visit_Match returns undef (stub)');
};

subtest 'NotMatch visitor exists and returns undef (stub)' => sub {
    my $notmatch_node = Chalk::IR::Node::NotMatch->new(
        left => $left,
        right => $right
    );

    my $graph = Chalk::IR::Graph->new();
    my $visitor = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'TestModule'
    );

    # visit_NotMatch should exist and not die
    ok($visitor->can('visit_NotMatch'), 'visit_NotMatch method exists');

    my $result = $visitor->visit_NotMatch($notmatch_node);

    # Stub implementation should return undef
    ok(!defined($result), 'visit_NotMatch returns undef (stub)');
};

subtest 'Match node dispatches to visit_Match' => sub {
    my $match_node = Chalk::IR::Node::Match->new(
        left => $left,
        right => $right
    );

    my $graph = Chalk::IR::Graph->new();
    my $visitor = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'TestModule'
    );

    # visit() should dispatch to visit_Match for Match nodes
    my $result = $visitor->visit($match_node);

    # Should not die and should return undef (stub)
    ok(!defined($result), 'visit() dispatches Match to visit_Match stub');
};

subtest 'NotMatch node dispatches to visit_NotMatch' => sub {
    my $notmatch_node = Chalk::IR::Node::NotMatch->new(
        left => $left,
        right => $right
    );

    my $graph = Chalk::IR::Graph->new();
    my $visitor = Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'TestModule'
    );

    # visit() should dispatch to visit_NotMatch for NotMatch nodes
    my $result = $visitor->visit($notmatch_node);

    # Should not die and should return undef (stub)
    ok(!defined($result), 'visit() dispatches NotMatch to visit_NotMatch stub');
};

done_testing();
