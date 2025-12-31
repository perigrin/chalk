# ABOUTME: Tests for DoubleQuotedString rule - escape sequences and interpolation
# ABOUTME: Verifies double-quoted strings process escapes and detect variable interpolation

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk::Rule::DoubleQuotedString;
use Chalk::Grammar::Chalk::Rule::String;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::InterpolatedString;
use Chalk::IR::Node::Load;
use Chalk::IR::Node::UnboundVariable;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::EvalContext;
use Chalk::IR::Node::Scope;
use Scalar::Util 'blessed';

# Helper to create a mock token context
sub make_token_context {
    my ($token_value) = @_;
    return Chalk::EvalContext->new(
        focus => $token_value,
        children => [],
        start_pos => 0,
        end_pos => length($token_value),
        env => { scope => Chalk::IR::Node::Scope->new() },
        grammar => undef,
        rule => undef
    );
}

# Helper to create context with children
sub make_context {
    my ($children, $env) = @_;
    $env //= { scope => Chalk::IR::Node::Scope->new() };
    return Chalk::EvalContext->new(
        children => $children,
        focus => undef,
        start_pos => 0,
        end_pos => 10,
        env => $env,
        grammar => undef,
        rule => undef
    );
}

subtest 'Escape sequences in double-quoted strings' => sub {
    my $rule = Chalk::Grammar::Chalk::Rule::DoubleQuotedString->new(
        lhs => 'DoubleQuotedString',
        rhs => []
    );

    # Test newline escape
    my $ctx = make_context([make_token_context('"hello\nworld"')]);
    my $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node for escaped string');
    is($node->value, "hello\nworld", 'Newline escape processed correctly');

    # Test tab escape
    $ctx = make_context([make_token_context('"tab\there"')]);
    $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node');
    is($node->value, "tab\there", 'Tab escape processed correctly');

    # Test backslash escape
    $ctx = make_context([make_token_context('"back\\\\slash"')]);
    $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node');
    is($node->value, 'back\\slash', 'Backslash escape processed correctly');

    # Test quote escape
    $ctx = make_context([make_token_context('"say \\"hi\\""')]);
    $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node');
    is($node->value, 'say "hi"', 'Quote escape processed correctly');

    # Test dollar sign escape
    $ctx = make_context([make_token_context('"costs \\$5"')]);
    $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node');
    is($node->value, 'costs $5', 'Dollar escape processed correctly');

    # Test @ escape
    $ctx = make_context([make_token_context('"email\\@test"')]);
    $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node');
    is($node->value, 'email@test', '@ escape processed correctly');
};

subtest 'Simple strings without interpolation' => sub {
    my $rule = Chalk::Grammar::Chalk::Rule::DoubleQuotedString->new(
        lhs => 'DoubleQuotedString',
        rhs => []
    );
    my $ctx = make_context([make_token_context('"hello"')]);
    my $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node for plain string');
    is($node->value, 'hello', 'String value correct');
};

subtest 'String with variable interpolation' => sub {
    my $rule = Chalk::Grammar::Chalk::Rule::DoubleQuotedString->new(
        lhs => 'DoubleQuotedString',
        rhs => []
    );
    my $ctx = make_context([make_token_context('"hello $name"')]);
    my $node = $rule->evaluate($ctx);
    is($node->op, 'InterpolatedString', 'Returns InterpolatedString node');
    ok(defined($node->parts), 'Has parts array');
    is(scalar(@{$node->parts}), 2, 'Has 2 parts');

    # First part should be constant "hello "
    is($node->parts->[0]->op, 'Constant', 'First part is Constant');
    is($node->parts->[0]->value, 'hello ', 'First part value correct');

    # Second part should be variable reference (Load or UnboundVariable)
    ok($node->parts->[1]->op =~ /^(Load|UnboundVariable)$/,
       'Second part is variable reference');
};

subtest 'String with multiple interpolations' => sub {
    my $rule = Chalk::Grammar::Chalk::Rule::DoubleQuotedString->new(
        lhs => 'DoubleQuotedString',
        rhs => []
    );
    my $ctx = make_context([make_token_context('"$a and $b"')]);
    my $node = $rule->evaluate($ctx);
    is($node->op, 'InterpolatedString', 'Returns InterpolatedString node');
    is(scalar(@{$node->parts}), 3, 'Has 3 parts');

    # First part: variable $a
    ok($node->parts->[0]->op =~ /^(Load|UnboundVariable)$/,
       'First part is variable reference');

    # Second part: " and "
    is($node->parts->[1]->op, 'Constant', 'Second part is Constant');
    is($node->parts->[1]->value, ' and ', 'Second part value correct');

    # Third part: variable $b
    ok($node->parts->[2]->op =~ /^(Load|UnboundVariable)$/,
       'Third part is variable reference');
};

subtest 'Escaped dollar does not trigger interpolation' => sub {
    my $rule = Chalk::Grammar::Chalk::Rule::DoubleQuotedString->new(
        lhs => 'DoubleQuotedString',
        rhs => []
    );
    my $ctx = make_context([make_token_context('"price is \\$100"')]);
    my $node = $rule->evaluate($ctx);
    is($node->op, 'Constant', 'Returns Constant node (no interpolation)');
    is($node->value, 'price is $100', 'Escaped dollar preserved');
};

subtest 'Mixed escapes and interpolation' => sub {
    my $rule = Chalk::Grammar::Chalk::Rule::DoubleQuotedString->new(
        lhs => 'DoubleQuotedString',
        rhs => []
    );
    my $ctx = make_context([make_token_context('"line1\\nvalue: $x"')]);
    my $node = $rule->evaluate($ctx);
    is($node->op, 'InterpolatedString', 'Returns InterpolatedString node');
    is(scalar(@{$node->parts}), 2, 'Has 2 parts');

    # First part: "line1\nvalue: "
    is($node->parts->[0]->op, 'Constant', 'First part is Constant');
    is($node->parts->[0]->value, "line1\nvalue: ", 'Escape processed in constant part');

    # Second part: variable $x
    ok($node->parts->[1]->op =~ /^(Load|UnboundVariable)$/,
       'Second part is variable reference');
};

done_testing();
