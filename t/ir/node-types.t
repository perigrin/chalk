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
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::NE;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::LE;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::GE;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Bool;

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

subtest 'EQ node yields Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );

    my $eq = Chalk::IR::Node::EQ->new(left => $left, right => $right);
    ok($eq->can('compute_type'), 'EQ has compute_type method');
    isa_ok($eq->compute_type(), 'Chalk::IR::Type::Bool', 'EQ yields Bool');
};

subtest 'NE node yields Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $ne = Chalk::IR::Node::NE->new(left => $left, right => $right);
    ok($ne->can('compute_type'), 'NE has compute_type method');
    isa_ok($ne->compute_type(), 'Chalk::IR::Type::Bool', 'NE yields Bool');
};

subtest 'LT node yields Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );

    my $lt = Chalk::IR::Node::LT->new(left => $left, right => $right);
    ok($lt->can('compute_type'), 'LT has compute_type method');
    isa_ok($lt->compute_type(), 'Chalk::IR::Type::Bool', 'LT yields Bool');
};

subtest 'LE node yields Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );

    my $le = Chalk::IR::Node::LE->new(left => $left, right => $right);
    ok($le->can('compute_type'), 'LE has compute_type method');
    isa_ok($le->compute_type(), 'Chalk::IR::Type::Bool', 'LE yields Bool');
};

subtest 'GT node yields Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 2,
        type  => Chalk::IR::Type::Integer->constant(2),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );

    my $gt = Chalk::IR::Node::GT->new(left => $left, right => $right);
    ok($gt->can('compute_type'), 'GT has compute_type method');
    isa_ok($gt->compute_type(), 'Chalk::IR::Type::Bool', 'GT yields Bool');
};

subtest 'GE node yields Bool' => sub {
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );

    my $ge = Chalk::IR::Node::GE->new(left => $left, right => $right);
    ok($ge->can('compute_type'), 'GE has compute_type method');
    isa_ok($ge->compute_type(), 'Chalk::IR::Type::Bool', 'GE yields Bool');
};

done_testing();
