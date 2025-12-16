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

subtest 'Add with Float operand yields Float' => sub {
    use Chalk::IR::Type::Float;

    my $int_const = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $float_const = Chalk::IR::Node::Constant->new(
        value => 2.5,
        type  => Chalk::IR::Type::Float->constant(2.5),
    );

    my $add = Chalk::IR::Node::Add->new(
        left  => $int_const,
        right => $float_const,
    );

    my $result_type = $add->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Int + Float yields Float');
};

subtest 'Add with two Float operands yields Float' => sub {
    use Chalk::IR::Type::Float;

    my $float1 = Chalk::IR::Node::Constant->new(
        value => 1.5,
        type  => Chalk::IR::Type::Float->constant(1.5),
    );
    my $float2 = Chalk::IR::Node::Constant->new(
        value => 2.5,
        type  => Chalk::IR::Type::Float->constant(2.5),
    );

    my $add = Chalk::IR::Node::Add->new(
        left  => $float1,
        right => $float2,
    );

    my $result_type = $add->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Float + Float yields Float');
};

done_testing();
