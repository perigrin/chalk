# ABOUTME: Tests for MethodCall semantic action
# ABOUTME: Verifies MethodCall generates Call/CallEnd IR nodes with receiver

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::IR::Graph;
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Token;
use Chalk::Grammar::Chalk::Rule::MethodCall;
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

# Helper to create mock context for MethodCall: $obj->method()
sub mock_methodcall_context {
    my ($receiver_name, $method_name, @args) = @_;

    # Create receiver as identifier (object/class)
    my $receiver = make_identifier($receiver_name);

    # Create method name as identifier
    my $method_id = make_identifier($method_name);

    # Wrap receiver in context
    my $recv_ctx = Chalk::EvalContext->new(
        focus => $receiver,
        children => [],
        start_pos => 0,
        end_pos => length($receiver_name),
        env => {},
        grammar => undef,
        rule => undef
    );

    # Create '->' token context
    my $arrow = Chalk::Grammar::Token->new(value => '->');
    my $arrow_ctx = Chalk::EvalContext->new(
        focus => $arrow,
        children => [],
        start_pos => length($receiver_name),
        end_pos => length($receiver_name) + 2,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Wrap method name in context
    my $method_ctx = Chalk::EvalContext->new(
        focus => $method_id,
        children => [],
        start_pos => length($receiver_name) + 2,
        end_pos => length($receiver_name) + 2 + length($method_name),
        env => {},
        grammar => undef,
        rule => undef
    );

    # Create '(' token context
    my $open_paren = Chalk::Grammar::Token->new(value => '(');
    my $open_ctx = Chalk::EvalContext->new(
        focus => $open_paren,
        children => [],
        start_pos => 100,
        end_pos => 101,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Create ')' token context
    my $close_paren = Chalk::Grammar::Token->new(value => ')');
    my $close_ctx = Chalk::EvalContext->new(
        focus => $close_paren,
        children => [],
        start_pos => 102,
        end_pos => 103,
        env => {},
        grammar => undef,
        rule => undef
    );

    # Build children: receiver '->' method_name '(' ')'
    my @children = ($recv_ctx, $arrow_ctx, $method_ctx, $open_ctx, $close_ctx);

    return Chalk::EvalContext->new(
        children => \@children,
        focus => undef,
        start_pos => 0,
        end_pos => 103,
        env => {},
        grammar => undef,
        rule => undef
    );
}

subtest 'MethodCall generates CallEnd node' => sub {
    my $context = mock_methodcall_context('MyClass', 'new');

    my $rule = Chalk::Grammar::Chalk::Rule::MethodCall->new(
        lhs => 'MethodCall',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    ok($result->isa('Chalk::IR::Node::CallEnd'),
       'Result is CallEnd node') or diag "Got: " . (ref($result) || "'$result'");
};

subtest 'Call node has receiver for method calls' => sub {
    my $context = mock_methodcall_context('obj', 'do_something');

    my $rule = Chalk::Grammar::Chalk::Rule::MethodCall->new(
        lhs => 'MethodCall',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok($result->isa('Chalk::IR::Node::CallEnd'), 'Result is CallEnd');

    my $call = $result->call;
    ok(defined($call), 'CallEnd has call reference');
    ok($call->isa('Chalk::IR::Node::Call'), 'call is Call node');

    # Verify receiver is set
    my $receiver = $call->receiver;
    ok(defined($receiver), 'Call has receiver');
    ok($receiver->can('id'), 'receiver is IR node');
};

done_testing();
