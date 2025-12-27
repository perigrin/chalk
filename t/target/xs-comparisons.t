# ABOUTME: Test XS target comparison visitor methods for LT, LE, GT, GE, EQ, NE
# ABOUTME: Verifies BinaryOp AST node generation for comparison operations
use 5.42.0;
use Test::More;

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Target::XS;
use Chalk::Target::XS::AST::BinaryOp;
use Chalk::Target::XS::AST::VarDecl;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::LE;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::GE;
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::NE;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

# Test 1: visit_LT creates VarDecl with BinaryOp using '<' operator
subtest 'visit_LT creates comparison BinaryOp' => sub {
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10),
    );

    my $lt = Chalk::IR::Node::LT->new(
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

    my $result = $target->visit_LT($lt);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_LT returns VarDecl');
    like($result->name, qr/^tmp_\d+$/, 'visit_LT allocates temp variable');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_LT init is BinaryOp');
    is($init->operator, '<', 'visit_LT BinaryOp has < operator');
    is($init->left, 'tmp_0', 'visit_LT BinaryOp left is tmp_0');
    is($init->right, 'tmp_1', 'visit_LT BinaryOp right is tmp_1');
};

# Test 2: visit_LE creates VarDecl with BinaryOp using '<=' operator
subtest 'visit_LE creates comparison BinaryOp' => sub {
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );

    my $le = Chalk::IR::Node::LE->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_LE($le);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_LE returns VarDecl');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_LE init is BinaryOp');
    is($init->operator, '<=', 'visit_LE BinaryOp has <= operator');
};

# Test 3: visit_GT creates VarDecl with BinaryOp using '>' operator
subtest 'visit_GT creates comparison BinaryOp' => sub {
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );

    my $gt = Chalk::IR::Node::GT->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_GT($gt);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_GT returns VarDecl');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_GT init is BinaryOp');
    is($init->operator, '>', 'visit_GT BinaryOp has > operator');
};

# Test 4: visit_GE creates VarDecl with BinaryOp using '>=' operator
subtest 'visit_GE creates comparison BinaryOp' => sub {
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 10,
        type => Chalk::IR::Type::Integer->constant(10),
    );

    my $ge = Chalk::IR::Node::GE->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_GE($ge);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_GE returns VarDecl');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_GE init is BinaryOp');
    is($init->operator, '>=', 'visit_GE BinaryOp has >= operator');
};

# Test 5: visit_EQ creates VarDecl with BinaryOp using '==' operator
subtest 'visit_EQ creates comparison BinaryOp' => sub {
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    my $eq = Chalk::IR::Node::EQ->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_EQ($eq);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_EQ returns VarDecl');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_EQ init is BinaryOp');
    is($init->operator, '==', 'visit_EQ BinaryOp has == operator');
};

# Test 6: visit_NE creates VarDecl with BinaryOp using '!=' operator
subtest 'visit_NE creates comparison BinaryOp' => sub {
    my $const_a = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );
    my $const_b = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2),
    );

    my $ne = Chalk::IR::Node::NE->new(
        left => $const_a,
        right => $const_b,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($const_a->id, 'tmp_0');
    $target->bind_var($const_b->id, 'tmp_1');

    my $result = $target->visit_NE($ne);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_NE returns VarDecl');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::BinaryOp', 'visit_NE init is BinaryOp');
    is($init->operator, '!=', 'visit_NE BinaryOp has != operator');
};

# Test 7: Comparison VarDecl emits valid C code
subtest 'Comparison VarDecl emits valid C code' => sub {
    my $binop = Chalk::Target::XS::AST::BinaryOp->new(
        left => 'tmp_0',
        operator => '<',
        right => 'tmp_1',
    );

    my $vardecl = Chalk::Target::XS::AST::VarDecl->new(
        type => 'IV',
        name => 'tmp_2',
        init => $binop,
    );

    is($vardecl->emit(), 'IV tmp_2 = tmp_0 < tmp_1;', 'Comparison VarDecl emits valid C');
};

done_testing();
