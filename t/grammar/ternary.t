# ABOUTME: Test ternary operator (? :) generates If/Region/Phi IR nodes
# ABOUTME: Part of control flow expression support (#399)

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use Scalar::Util 'blessed';

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::Ternary;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::GT;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Bool;
use Chalk::EvalContext;

# Helper to create a mock token
package MockToken {
    use overload '""' => sub { $_[0]->{value} };
    sub new { bless { value => $_[1] }, $_[0] }
    sub extract { $_[0] }
}

# Helper to create a mock child context
package MockChildContext {
    sub new {
        my ($class, $value) = @_;
        bless { value => $value }, $class;
    }
    sub extract { $_[0]->{value} }
    sub children { [] }
    sub rule { undef }
}

# Helper to create a mock context for Ternary
sub mock_ternary_context {
    my ($condition, $true_expr, $false_expr) = @_;

    # Children: condition, ws, '?', ws, true_expr, ws, ':', ws, false_expr
    my @children = (
        MockChildContext->new($condition),
        MockChildContext->new(undef),  # ws
        MockChildContext->new(MockToken->new('?')),
        MockChildContext->new(undef),  # ws
        MockChildContext->new($true_expr),
        MockChildContext->new(undef),  # ws
        MockChildContext->new(MockToken->new(':')),
        MockChildContext->new(undef),  # ws
        MockChildContext->new($false_expr),
    );

    my $idx = 0;
    return bless {
        children => \@children,
        child_fn => sub {
            my $i = shift;
            my $child = $children[$i];
            return $child->{value} if blessed($child->{value}) && $child->{value}->can('id');
            return $child->extract;
        },
    }, 'MockContext';
}

package MockContext {
    sub children { $_[0]->{children} }
    sub child {
        my ($self, $i) = @_;
        return $self->{child_fn}->($i);
    }
}

package main;

# Test 1: Pass-through case (single child, no ternary)
subtest 'pass-through without ternary operators' => sub {
    my $const = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );

    # Single child = pass-through
    my $ctx = bless {
        children => [MockChildContext->new($const)],
        child_fn => sub { $const },
    }, 'MockContext';

    my $rule = Chalk::Grammar::Chalk::Rule::Ternary->new(lhs => 'Ternary', rhs => []);
    my $result = $rule->evaluate($ctx);

    ok(defined($result), 'Result is defined');
    is($result->op, 'Constant', 'Pass-through returns Constant');
    is($result->value, 42, 'Value preserved');
};

# Test 2: Full ternary generates Phi
subtest 'ternary generates Phi node' => sub {
    my $condition = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $true_expr = Chalk::IR::Node::Constant->new(
        value => 10,
        type  => Chalk::IR::Type::Integer->constant(10),
    );
    my $false_expr = Chalk::IR::Node::Constant->new(
        value => 20,
        type  => Chalk::IR::Type::Integer->constant(20),
    );

    my $ctx = mock_ternary_context($condition, $true_expr, $false_expr);

    my $rule = Chalk::Grammar::Chalk::Rule::Ternary->new(lhs => 'Ternary', rhs => []);
    my $result = $rule->evaluate($ctx);

    ok(defined($result), 'Result is defined');
    ok(blessed($result), 'Result is blessed');
    is($result->op, 'Phi', 'Result is Phi node');
};

# Test 3: Phi has correct structure
subtest 'Phi references Region correctly' => sub {
    my $condition = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    my $true_expr = Chalk::IR::Node::Constant->new(
        value => 100,
        type  => Chalk::IR::Type::Integer->constant(100),
    );
    my $false_expr = Chalk::IR::Node::Constant->new(
        value => 200,
        type  => Chalk::IR::Type::Integer->constant(200),
    );

    my $ctx = mock_ternary_context($condition, $true_expr, $false_expr);

    my $rule = Chalk::Grammar::Chalk::Rule::Ternary->new(lhs => 'Ternary', rhs => []);
    my $result = $rule->evaluate($ctx);

    ok($result->can('region_id'), 'Phi has region_id accessor');
    ok(defined($result->region_id), 'region_id is defined');

    # Phi inputs should be: [region_id, true_val_id, false_val_id]
    my @inputs = $result->inputs->@*;
    is(scalar(@inputs), 3, 'Phi has 3 inputs (region + 2 values)');
};

done_testing();
