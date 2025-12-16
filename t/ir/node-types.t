# ABOUTME: Tests for IR node type computation
# ABOUTME: Validates that operation nodes can compute their result types

use 5.042;
use Test::More;
use lib 'lib';

use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Type::Integer;

subtest 'Add node computes type from operands' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $add = Chalk::IR::Node::Add->new(
        left  => $left,
        right => $right,
    );

    ok($add->can('compute_type'), 'Add has compute_type method');
    my $result_type = $add->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Integer', 'Add of integers yields Integer');
};

done_testing();
