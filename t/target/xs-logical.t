# ABOUTME: Test XS target visitors for logical operators (And, Or, Not, DefinedOr)
# ABOUTME: Verifies XS code generation for &&, ||, !, // expressions
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
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::DefinedOr;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;

# Test 1: visit_And creates VarDecl with ternary
{
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2),
    );

    my $and = Chalk::IR::Node::And->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'a');
    $target->bind_var($right->id, 'b');

    my $result = $target->visit_And($and);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_And returns VarDecl');
    like($result->emit(), qr/SvTRUE.*\?.*:/, 'visit_And emits ternary with SvTRUE');
}

# Test 2: visit_Or creates VarDecl with ternary
{
    my $left = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 5,
        type => Chalk::IR::Type::Integer->constant(5),
    );

    my $or = Chalk::IR::Node::Or->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'x');
    $target->bind_var($right->id, 'y');

    my $result = $target->visit_Or($or);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Or returns VarDecl');
    like($result->emit(), qr/SvTRUE.*\?.*:/, 'visit_Or emits ternary with SvTRUE');
}

# Test 3: visit_Not creates VarDecl with negation
{
    my $operand = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Bool->constant(1),
    );

    my $not = Chalk::IR::Node::Not->new(
        operand => $operand,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($operand->id, 'flag');

    my $result = $target->visit_Not($not);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Not returns VarDecl');
    like($result->emit(), qr/SvTRUE.*\?.*PL_sv_no.*:.*PL_sv_yes|!SvTRUE/, 'visit_Not emits negation');
}

# Test 4: visit_DefinedOr creates VarDecl with SvOK check
{
    my $left = Chalk::IR::Node::Constant->new(
        value => undef,
        type => Chalk::IR::Type::Integer->TOP(),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::IR::Type::Integer->constant(42),
    );

    my $defined_or = Chalk::IR::Node::DefinedOr->new(
        left => $left,
        right => $right,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'maybe');
    $target->bind_var($right->id, 'default');

    my $result = $target->visit_DefinedOr($defined_or);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_DefinedOr returns VarDecl');
    like($result->emit(), qr/SvOK.*\?.*:/, 'visit_DefinedOr emits ternary with SvOK');
}

# Test 5: visit dispatch includes all logical operators
{
    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    my $const1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );
    my $const2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2),
    );
    $target->bind_var($const1->id, 'a');
    $target->bind_var($const2->id, 'b');

    my $and = Chalk::IR::Node::And->new(left => $const1, right => $const2);
    my $or = Chalk::IR::Node::Or->new(left => $const1, right => $const2);
    my $not = Chalk::IR::Node::Not->new(operand => $const1);
    my $defined_or = Chalk::IR::Node::DefinedOr->new(left => $const1, right => $const2);

    isa_ok($target->visit($and), 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches And');
    isa_ok($target->visit($or), 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches Or');
    isa_ok($target->visit($not), 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches Not');
    isa_ok($target->visit($defined_or), 'Chalk::Target::XS::AST::VarDecl', 'visit() dispatches DefinedOr');
}

# Test 6: And short-circuit pattern - returns left if false, right if true
{
    my $left = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2),
    );

    my $and = Chalk::IR::Node::And->new(left => $left, right => $right);

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'left_val');
    $target->bind_var($right->id, 'right_val');

    my $result = $target->visit_And($and);
    my $emitted = $result->emit();

    # And: SvTRUE(left) ? right : left
    like($emitted, qr/left_val/, 'And references left operand');
    like($emitted, qr/right_val/, 'And references right operand');
}

# Test 7: Or short-circuit pattern - returns left if true, right if false
{
    my $left = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::IR::Type::Integer->constant(0),
    );
    my $right = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );

    my $or = Chalk::IR::Node::Or->new(left => $left, right => $right);

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($left->id, 'first');
    $target->bind_var($right->id, 'second');

    my $result = $target->visit_Or($or);
    my $emitted = $result->emit();

    # Or: SvTRUE(left) ? left : right
    like($emitted, qr/first/, 'Or references left operand');
    like($emitted, qr/second/, 'Or references right operand');
}

done_testing();
