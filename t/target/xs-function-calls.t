# ABOUTME: Test XS target function call visitor methods for Call, CallEnd
# ABOUTME: Verifies FunctionCall AST node generation for function invocations
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
use Chalk::Target::XS::AST::FunctionCall;
use Chalk::Target::XS::AST::VarDecl;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::CallEnd;
use Chalk::IR::Node::Constant;
use Chalk::IR::Type::Integer;

# Test 1: FunctionCall AST node basic structure
subtest 'FunctionCall AST node structure' => sub {
    my $call = Chalk::Target::XS::AST::FunctionCall->new(
        name => 'add',
        args => ['x', 'y'],
    );

    is($call->name, 'add', 'FunctionCall has name');
    is_deeply($call->args, ['x', 'y'], 'FunctionCall has args');
};

# Test 2: FunctionCall emit() with no arguments
subtest 'FunctionCall emit with no args' => sub {
    my $call = Chalk::Target::XS::AST::FunctionCall->new(
        name => 'get_value',
        args => [],
    );

    is($call->emit(), 'get_value()', 'Emits function call with no args');
};

# Test 3: FunctionCall emit() with arguments
subtest 'FunctionCall emit with args' => sub {
    my $call = Chalk::Target::XS::AST::FunctionCall->new(
        name => 'compute',
        args => ['tmp_0', 'tmp_1', 'tmp_2'],
    );

    is($call->emit(), 'compute(tmp_0, tmp_1, tmp_2)', 'Emits function call with args');
};

# Test 4: VarDecl with FunctionCall init
subtest 'VarDecl with FunctionCall init' => sub {
    my $call = Chalk::Target::XS::AST::FunctionCall->new(
        name => 'fib',
        args => ['n'],
    );

    my $vardecl = Chalk::Target::XS::AST::VarDecl->new(
        type => 'IV',
        name => 'result',
        init => $call,
    );

    is($vardecl->emit(), 'IV result = fib(n);', 'VarDecl with function call emits correctly');
};

# Test 5: visit_Call creates VarDecl with FunctionCall
subtest 'visit_Call creates VarDecl with FunctionCall' => sub {
    # Create a callee constant (function name)
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'add',
        type => Chalk::IR::Type::Integer->TOP(),
    );

    # Create argument constants
    my $arg1 = Chalk::IR::Node::Constant->new(
        value => 1,
        type => Chalk::IR::Type::Integer->constant(1),
    );
    my $arg2 = Chalk::IR::Node::Constant->new(
        value => 2,
        type => Chalk::IR::Type::Integer->constant(2),
    );

    my $call_node = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [$arg1, $arg2],
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    # Bind the argument variables
    $target->bind_var($arg1->id, 'tmp_0');
    $target->bind_var($arg2->id, 'tmp_1');

    my $result = $target->visit_Call($call_node);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl', 'visit_Call returns VarDecl');
    like($result->name, qr/^tmp_\d+$/, 'visit_Call allocates temp variable');

    my $init = $result->init;
    isa_ok($init, 'Chalk::Target::XS::AST::FunctionCall', 'visit_Call init is FunctionCall');
    is($init->name, 'add', 'FunctionCall has correct name');
    is_deeply($init->args, ['tmp_0', 'tmp_1'], 'FunctionCall has correct args');
};

# Test 6: visit_CallEnd returns undef (projection node)
subtest 'visit_CallEnd returns undef' => sub {
    my $callee = Chalk::IR::Node::Constant->new(
        value => 'foo',
        type => Chalk::IR::Type::Integer->TOP(),
    );

    my $call_node = Chalk::IR::Node::Call->new(
        callee => $callee,
        args => [],
    );

    my $call_end = Chalk::IR::Node::CallEnd->new(
        call => $call_node,
    );

    my $target = Chalk::Target::XS->new(
        graph => undef,
        module_name => 'TestModule',
    );

    my $result = $target->visit_CallEnd($call_end);

    # CallEnd is a projection node - the actual call is handled by visit_Call
    ok(!defined($result), 'visit_CallEnd returns undef');
};

done_testing();
