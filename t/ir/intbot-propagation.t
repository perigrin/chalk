# ABOUTME: Test IntBot (error state) propagation through arithmetic operations
# ABOUTME: Verify whether IntBot + x = IntBot (error propagation) or IntTop (unknown)

use lib 'lib';
use v5.42;
use Test::More;
use Chalk::IR::Type::Integer;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;

# Test division by zero creates IntBot
subtest 'Division by zero returns IntBot' => sub {
    my $numerator = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0)
    );

    my $div = Chalk::IR::Node::Divide->new(left => $numerator, right => $zero);
    my $type = $div->compute();

    ok($type isa Chalk::IR::Type::Integer, 'Division by zero returns TypeInteger');
    ok($type->is_bottom, 'Division by zero returns IntBot (error state)');
};

# Test IntBot lattice behavior
subtest 'IntBot meet() absorbs other integers' => sub {
    my $bot = Chalk::IR::Type::Integer->BOTTOM();
    my $const5 = Chalk::IR::Type::Integer->constant(5);
    my $top = Chalk::IR::Type::Integer->TOP();

    my $result1 = $bot->meet($const5);
    ok($result1->is_bottom, 'IntBot meet constant = IntBot');

    my $result2 = $bot->meet($top);
    ok($result2->is_bottom, 'IntBot meet IntTop = IntBot');

    my $result3 = $const5->meet($bot);
    ok($result3->is_bottom, 'constant meet IntBot = IntBot');
};

# Test IntBot propagation through Add
subtest 'Add propagates IntBot (error state)' => sub {
    # Create a divide-by-zero to get IntBot
    my $numerator = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0)
    );
    my $div_by_zero = Chalk::IR::Node::Divide->new(left => $numerator, right => $zero);

    # Add IntBot + 5
    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    my $add = Chalk::IR::Node::Add->new(left => $div_by_zero, right => $const5);

    my $result_type = $add->compute();

    ok($result_type isa Chalk::IR::Type::Integer, 'Add returns TypeInteger');
    ok($result_type->is_bottom, 'Add propagates IntBot (error state absorbs)');
    ok(!$result_type->is_top, 'Result is not IntTop');
    ok(!$result_type->is_constant, 'Result is not constant');
};

subtest 'Subtract propagates IntBot (error state)' => sub {
    my $numerator = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0)
    );
    my $div_by_zero = Chalk::IR::Node::Divide->new(left => $numerator, right => $zero);

    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    my $sub = Chalk::IR::Node::Subtract->new(left => $const5, right => $div_by_zero);

    my $result_type = $sub->compute();
    ok($result_type isa Chalk::IR::Type::Integer, 'Subtract returns TypeInteger');
    ok($result_type->is_bottom, 'Subtract propagates IntBot (error state absorbs)');
};

subtest 'Multiply propagates IntBot (error state)' => sub {
    my $numerator = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0)
    );
    my $div_by_zero = Chalk::IR::Node::Divide->new(left => $numerator, right => $zero);

    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    my $mul = Chalk::IR::Node::Multiply->new(left => $div_by_zero, right => $const5);

    my $result_type = $mul->compute();
    ok($result_type isa Chalk::IR::Type::Integer, 'Multiply returns TypeInteger');
    ok($result_type->is_bottom, 'Multiply propagates IntBot (error state absorbs)');
};

subtest 'Divide propagates IntBot from left operand' => sub {
    my $numerator = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10)
    );
    my $zero = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0)
    );
    my $div_by_zero = Chalk::IR::Node::Divide->new(left => $numerator, right => $zero);

    my $const5 = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5)
    );
    my $div = Chalk::IR::Node::Divide->new(left => $div_by_zero, right => $const5);

    my $result_type = $div->compute();
    ok($result_type isa Chalk::IR::Type::Integer, 'Divide returns TypeInteger');
    ok($result_type->is_bottom, 'Divide propagates IntBot from left operand');
};

done_testing();
