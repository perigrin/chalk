# ABOUTME: Test Program2 rule semantic action (v2 rewrite)
# ABOUTME: Verifies Start2/Return2 wrapper around program statements
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

class MockStore {
    field $id :param :reader = 'store_x';
    field $var :param :reader = 'x';
    field $value :param :reader;
    field $control :param :reader;

    method op() { 'Store' }
}

class MockReturn {
    field $id :param :reader = 'return_main';
    field $value :param :reader;
    field $control :param :reader;

    method op() { 'Return' }
}

class MockConstant {
    field $id :param :reader = 'const_42';
    field $value :param :reader = 42;

    method op() { 'Constant' }
}

class MockContext {
    field $env :param :reader;
    field $children :param;

    method children() { return $children; }

    method child($index) {
        return $children->[$index] if $index < scalar(@$children);
        return undef;
    }
}

class MockStatementListContext {
    field $statements :param;

    method focus() { return $statements; }
    method can($method) { return 1 if $method eq 'focus'; return 0; }
}

# Test 1: Empty program
{
    my $scope = MockScope->new();

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [],  # No statements
    );

    require_ok('Chalk::Grammar::Chalk::Rule::Program2');
    my $rule = Chalk::Grammar::Chalk::Rule::Program2->new();
    my $result = $rule->evaluate($context);

    # Should create Start -> Return(undef)
    isa_ok($result, 'Chalk::IR::Node::Return2', 'Empty program returns Return2 node');
    isa_ok($result->control, 'Chalk::IR::Node::Start2', 'Return control is Start2');
    is($result->control->label, 'main', 'Start2 has "main" label');
    isa_ok($result->value, 'Chalk::IR::Node::Constant2', 'Return value is Constant2');
    is($result->value->type, 'Undef', 'Empty program returns undef constant');
}

# Test 2: Program with single statement (Store)
{
    my $scope = MockScope->new();

    my $const = MockConstant->new(id => 'const_42', value => 42);
    my $store = MockStore->new(
        id => 'store_x',
        var => 'x',
        value => $const,
        control => undef,  # Will be set by Program2
    );

    my $stmt_ctx = MockStatementListContext->new(statements => [$store]);

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [$stmt_ctx],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Program2->new();
    my $result = $rule->evaluate($context);

    # Should create Start -> Store -> Return(stored_value)
    isa_ok($result, 'Chalk::IR::Node::Return2', 'Single statement program returns Return2');
    is($result->control, $store, 'Return control is the Store node');
    is($result->value, $const, 'Return value is the stored value');

    # Check that scope was updated
    isa_ok($scope->current_control, 'Chalk::IR::Node::Start2', 'Start2 was set in scope');
}

# Test 3: Program with multiple statements
{
    my $scope = MockScope->new();

    my $const1 = MockConstant->new(id => 'const_10', value => 10);
    my $const2 = MockConstant->new(id => 'const_20', value => 20);

    my $store1 = MockStore->new(
        id => 'store_x',
        var => 'x',
        value => $const1,
        control => undef,
    );

    my $store2 = MockStore->new(
        id => 'store_y',
        var => 'y',
        value => $const2,
        control => undef,
    );

    my $stmt_ctx = MockStatementListContext->new(statements => [$store1, $store2]);

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [$stmt_ctx],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Program2->new();
    my $result = $rule->evaluate($context);

    # Should create Start -> Store1 -> Store2 -> Return(const2)
    isa_ok($result, 'Chalk::IR::Node::Return2', 'Multi-statement program returns Return2');
    is($result->control, $store2, 'Return control is last Store node');
    is($result->value, $const2, 'Return value is last stored value');
}

# Test 4: Program ending with Return statement
{
    my $scope = MockScope->new();

    my $const = MockConstant->new(id => 'const_42', value => 42);
    my $return_stmt = MockReturn->new(
        id => 'return_explicit',
        value => $const,
        control => undef,
    );

    my $stmt_ctx = MockStatementListContext->new(statements => [$return_stmt]);

    my $context = MockContext->new(
        env => { scope => $scope },
        children => [$stmt_ctx],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Program2->new();
    my $result = $rule->evaluate($context);

    # Should use the existing Return node
    is($result, $return_stmt, 'Program with Return uses that Return node');
}

# Test 5: Program without scope
{
    my $context = MockContext->new(
        env => {},  # No scope
        children => [],
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Program2->new();
    my $result = $rule->evaluate($context);

    is($result, undef, 'Program without scope returns undef');
}

done_testing();
