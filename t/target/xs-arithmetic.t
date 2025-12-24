# ABOUTME: Test XS target arithmetic visitor methods for Add, Subtract, Multiply, Divide
# ABOUTME: Verifies BinaryOp AST node generation and emission for binary arithmetic operations
use 5.42.0;
use Test::More;
use Chalk::Target::XS;
use Chalk::Target::XS::AST::BinaryOp;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

# Test 1: BinaryOp AST node basic structure
{
    my $binop = Chalk::Target::XS::AST::BinaryOp->new(
        left => 'x',
        operator => '+',
        right => 'y',
    );

    is($binop->left, 'x', 'BinaryOp left field');
    is($binop->operator, '+', 'BinaryOp operator field');
    is($binop->right, 'y', 'BinaryOp right field');
}

# Test 2: BinaryOp emit() produces "left operator right"
{
    my $binop = Chalk::Target::XS::AST::BinaryOp->new(
        left => 'a',
        operator => '+',
        right => 'b',
    );

    is($binop->emit(), 'a + b', 'BinaryOp emits "a + b"');
}

# Test 3: BinaryOp emit() with different operators
{
    my @tests = (
        { left => 'x', op => '+', right => 'y', expected => 'x + y' },
        { left => 'a', op => '-', right => 'b', expected => 'a - b' },
        { left => 'p', op => '*', right => 'q', expected => 'p * q' },
        { left => 'm', op => '/', right => 'n', expected => 'm / n' },
    );

    for my $test (@tests) {
        my $binop = Chalk::Target::XS::AST::BinaryOp->new(
            left => $test->{left},
            operator => $test->{op},
            right => $test->{right},
        );
        is($binop->emit(), $test->{expected}, "BinaryOp emits '$test->{expected}'");
    }
}

# Test 4: visit_Add creates VarDecl with BinaryOp init
{
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10),
    );

    my $add = Chalk::IR::Node::Add->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Pre-bind variables for the constants
    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_Add($add);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Add returns VarDecl');
    is($result->type, 'IV', 'visit_Add result type is IV');
    like($result->name, qr/^tmp_\d+$/, 'visit_Add allocates temp variable');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_Add init is BinaryOp');
    is($init->operator, '+', 'visit_Add BinaryOp has + operator');
    is($init->left, 'tmp_0', 'visit_Add BinaryOp left is tmp_0');
    is($init->right, 'tmp_1', 'visit_Add BinaryOp right is tmp_1');
}

# Test 5: visit_Subtract creates VarDecl with BinaryOp init
{
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 15,
        type => Chalk::IR::Type::Integer->constant(15),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 7,
        type => Chalk::IR::Type::Integer->constant(7),
    );

    my $sub = Chalk::IR::Node::Subtract->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_Subtract($sub);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Subtract returns VarDecl');
    is($result->init->operator, '-', 'visit_Subtract BinaryOp has - operator');
}

# Test 6: visit_Multiply creates VarDecl with BinaryOp init
{
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 3,
        type => Chalk::IR::Type::Integer->constant(3),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 4,
        type => Chalk::IR::Type::Integer->constant(4),
    );

    my $mul = Chalk::IR::Node::Multiply->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_Multiply($mul);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Multiply returns VarDecl');
    is($result->init->operator, '*', 'visit_Multiply BinaryOp has * operator');
}

# Test 7: visit_Divide creates VarDecl with BinaryOp init
{
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 20,
        type => Chalk::IR::Type::Integer->constant(20),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );

    my $div = Chalk::IR::Node::Divide->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_Divide($div);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Divide returns VarDecl');
    is($result->init->operator, '/', 'visit_Divide BinaryOp has / operator');
}

# Test 8: VarDecl with BinaryOp emits complete C declaration
{
    my $binop = Chalk::Target::XS::AST::BinaryOp->new(
        left => 'tmp_0',
        operator => '+',
        right => 'tmp_1',
    );

    my $vardecl = Chalk::Target::XS::AST::VarDecl->new(
        type => 'IV',
        name => 'tmp_2',
        init => $binop,
    );

    is($vardecl->emit(), 'IV tmp_2 = tmp_0 + tmp_1;', 'VarDecl emits complete C declaration with BinaryOp');
}

done_testing();
