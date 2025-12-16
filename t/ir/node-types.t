# ABOUTME: Tests for IR node type computation
# ABOUTME: Validates that operation nodes can compute their result types

use 5.042;
use Test::More;
use lib 'lib';

use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;

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

subtest 'Subtract node computes type from operands' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 5,
        type  => Chalk::IR::Type::Integer->constant(5),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 3,
        type  => Chalk::IR::Type::Integer->constant(3),
    );

    my $subtract = Chalk::IR::Node::Subtract->new(
        left  => $left,
        right => $right,
    );

    ok($subtract->can('compute_type'), 'Subtract has compute_type method');
    my $result_type = $subtract->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Integer', 'Subtract of integers yields Integer');
};

subtest 'Subtract with Float operand yields Float' => sub {
    my $float_const = Chalk::IR::Node::Constant->new(
        value => 5.5,
        type  => Chalk::IR::Type::Float->constant(5.5),
    );
    my $int_const = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $subtract = Chalk::IR::Node::Subtract->new(
        left  => $float_const,
        right => $int_const,
    );

    my $result_type = $subtract->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Float - Int yields Float');
};

subtest 'Multiply node computes type from operands' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 3,
        type  => Chalk::IR::Type::Integer->constant(3),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 4,
        type  => Chalk::IR::Type::Integer->constant(4),
    );

    my $multiply = Chalk::IR::Node::Multiply->new(
        left  => $left,
        right => $right,
    );

    ok($multiply->can('compute_type'), 'Multiply has compute_type method');
    my $result_type = $multiply->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Integer', 'Multiply of integers yields Integer');
};

subtest 'Multiply with Float operand yields Float' => sub {
    my $int_const = Chalk::IR::Node::Constant->new(
        value => 3,
        type  => Chalk::IR::Type::Integer->constant(3),
    );
    my $float_const = Chalk::IR::Node::Constant->new(
        value => 2.5,
        type  => Chalk::IR::Type::Float->constant(2.5),
    );

    my $multiply = Chalk::IR::Node::Multiply->new(
        left  => $int_const,
        right => $float_const,
    );

    my $result_type = $multiply->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Int * Float yields Float');
};

subtest 'Divide node always yields Float' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 10,
        type  => Chalk::IR::Type::Integer->constant(10),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $divide = Chalk::IR::Node::Divide->new(
        left  => $left,
        right => $right,
    );

    ok($divide->can('compute_type'), 'Divide has compute_type method');
    my $result_type = $divide->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Divide of integers yields Float (division can produce decimals)');
};

subtest 'Divide with Float operand yields Float' => sub {
    my $float_const = Chalk::IR::Node::Constant->new(
        value => 7.5,
        type  => Chalk::IR::Type::Float->constant(7.5),
    );
    my $int_const = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $divide = Chalk::IR::Node::Divide->new(
        left  => $float_const,
        right => $int_const,
    );

    my $result_type = $divide->compute_type();
    isa_ok($result_type, 'Chalk::IR::Type::Float', 'Float / Int yields Float');
};

done_testing();
