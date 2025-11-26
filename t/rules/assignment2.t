# ABOUTME: Test Assignment2 rule semantic action (v2 rewrite)
# ABOUTME: Verifies direct IR node creation without Builder
use 5.42.0;
use Test::More;
use experimental qw(class);

# Create mock classes for testing
class MockScope {
    field $current_control :reader;
    field $bindings = {};

    method set_current_control($ctrl) {
        $current_control = $ctrl;
    }

    method define($name, $node) {
        $bindings->{$name} = $node;
    }

    method get($name) {
        return $bindings->{$name};
    }
}

class MockControl {
    field $id :param :reader = 'start';
    method op() { 'Start' }
}

class MockValue {
    field $id :param :reader = 'const_42';
    method op() { 'Constant' }
}

class MockContext {
    field $env :param :reader;
    field $children :param;
    field $child_index :param = 0;

    method children() { return $children; }

    method child($index) {
        return $children->[$index] if $index < scalar(@$children);
        return undef;
    }
}

class MockVarContext {
    field $var_name :param;

    method extract() {
        return { type => 'scalar_var', name => $var_name };
    }

    method can($method) { return 1 if $method eq 'extract'; return 0; }
    method children() { return []; }
}

# Test 1: Pass-through case (no assignment operator)
{
    my $scope = MockScope->new();
    my $value = MockValue->new(id => 'ternary_result');

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [$value],  # Just Ternary, no '='
    );

    require_ok('Chalk::Grammar::Chalk::Rule::Assignment2');
    my $rule = Chalk::Grammar::Chalk::Rule::Assignment2->new();
    my $result = $rule->evaluate($context);

    is($result, $value, 'Pass-through: returns Ternary value when no assignment');
}

# Test 2: Simple assignment case
{
    my $scope = MockScope->new();
    my $control = MockControl->new(id => 'start');
    $scope->set_current_control($control);

    my $var_ctx = MockVarContext->new(var_name => 'x');
    my $value = MockValue->new(id => 'const_42');

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [
            $var_ctx,    # Ternary (contains variable)
            '=',         # assignment operator
            $value,      # Assignment (RHS)
        ],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Assignment2->new();
    my $result = $rule->evaluate($context);

    # Verify Store2 was created
    isa_ok($result, 'Chalk::IR::Node::Store2', 'Assignment creates Store2 node');
    is($result->var, 'x', 'Store2 has correct variable name');
    is($result->value, $value, 'Store2 has correct value reference');
    is($result->control, $control, 'Store2 has correct control reference');

    # Verify scope was updated
    is($scope->get('x'), $value, 'Scope defines variable with value');
    is($scope->current_control, $result, 'Scope current_control updated to Store2');
}

# Test 3: Assignment extracts variable name from parse tree
{
    my $scope = MockScope->new();
    my $control = MockControl->new(id => 'start');
    $scope->set_current_control($control);

    # Create nested structure to test breadth-first search
    class MockNestedContext {
        field $children :param;
        method can($m) { return 1 if $m eq 'children'; return 0; }
        method children() { return $children; }
    }

    my $var_ctx = MockVarContext->new(var_name => 'result');
    my $nested = MockNestedContext->new(children => [$var_ctx]);
    my $value = MockValue->new(id => 'const_100');

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [
            $nested,     # Ternary (nested, contains variable)
            '=',         # assignment operator
            $value,      # Assignment (RHS)
        ],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Assignment2->new();
    my $result = $rule->evaluate($context);

    isa_ok($result, 'Chalk::IR::Node::Store2', 'Nested var: creates Store2 node');
    is($result->var, 'result', 'Nested var: extracts variable from nested context');
}

# Test 4: Assignment without scope returns pass-through
{
    my $var_ctx = MockVarContext->new(var_name => 'x');
    my $value = MockValue->new(id => 'const_42');

    my $context = MockContext->new(
        env => {},  # No scope
        children => [$var_ctx, '=', $value],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Assignment2->new();
    my $result = $rule->evaluate($context);

    is($result, $var_ctx, 'Without scope: returns LHS (pass-through)');
}

done_testing();
