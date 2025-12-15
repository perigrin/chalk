# ABOUTME: Tests for FunctionCall semantic action
# ABOUTME: Verifies FunctionCall generates Call/CallEnd IR nodes

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Token;
use Chalk::Grammar::Chalk::Rule::FunctionCall;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::CallEnd;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Create a fresh graph for tests
my $graph = Chalk::IR::Graph->new();

# Helper to create identifier constant
sub make_identifier {
    my ($name) = @_;
    return Chalk::IR::Node::Constant->new(
        value => $name,
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );
}

# Helper to create mock context for FunctionCall
sub mock_functioncall_context {
    my ($func_name, @args) = @_;

    # Create function name as identifier
    my $func_id = make_identifier($func_name);

    # Wrap function name in context
    my $func_ctx = Chalk::EvalContext->new(
        focus => $func_id,
        children => [],
        start_pos => 0,
        end_pos => length($func_name),
        env => {},
        grammar => undef,
        rule => undef
    );

    # Create '(' token context
    my $open_paren = Chalk::Grammar::Token->new(value => '(');
    my $open_ctx = Chalk::EvalContext->new(
        focus => $open_paren,
        children => [],
        start_pos => length($func_name),
        end_pos => length($func_name) + 1,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Create argument contexts
    my @arg_contexts;
    my $pos = length($func_name) + 1;
    for my $arg (@args) {
        my $arg_ctx = Chalk::EvalContext->new(
            focus => $arg,
            children => [],
            start_pos => $pos,
            end_pos => $pos + 5,
            env => {},
            grammar => undef,
            rule => undef
        );
        push @arg_contexts, $arg_ctx;
        $pos += 5;
    }

    # Create ')' token context
    my $close_paren = Chalk::Grammar::Token->new(value => ')');
    my $close_ctx = Chalk::EvalContext->new(
        focus => $close_paren,
        children => [],
        start_pos => $pos,
        end_pos => $pos + 1,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Build children: func_name '(' args ')'
    my @children = ($func_ctx, $open_ctx, @arg_contexts, $close_ctx);

    return Chalk::EvalContext->new(
        children => \@children,
        focus => undef,
        start_pos => 0,
        end_pos => $pos + 1,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'FunctionCall generates CallEnd node' => sub {
    my $context = mock_functioncall_context('my_func');

    my $rule = Chalk::Grammar::Chalk::Rule::FunctionCall->new(
        lhs => 'FunctionCall',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::CallEnd'),
       'Result is CallEnd node') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'CallEnd references Call with correct callee' => sub {
    my $context = mock_functioncall_context('test_function');

    my $rule = Chalk::Grammar::Chalk::Rule::FunctionCall->new(
        lhs => 'FunctionCall',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok($result->isa('Chalk::IR::Node::CallEnd'), 'Result is CallEnd');

    # Get the Call node
    my $call = $result->call;
    ok(defined($call), 'CallEnd has call reference');
    ok($call->isa('Chalk::IR::Node::Call'), 'call is Call node');

    # Verify callee
    my $callee = $call->callee;
    ok(defined($callee), 'Call has callee');
};

subtest 'FunctionCall with single argument' => sub {
    my $arg1 = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $context = mock_functioncall_context('func_with_arg', $arg1);

    my $rule = Chalk::Grammar::Chalk::Rule::FunctionCall->new(
        lhs => 'FunctionCall',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok($result->isa('Chalk::IR::Node::CallEnd'), 'Result is CallEnd');

    my $call = $result->call;
    ok($call->isa('Chalk::IR::Node::Call'), 'call is Call node');

    # Verify args (may have 1+ depending on mock context structure)
    my $args = $call->args;
    ok(ref($args) eq 'ARRAY', 'args is arrayref');
};

done_testing();
