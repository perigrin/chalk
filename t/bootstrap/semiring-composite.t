# ABOUTME: Tests Composite semiring that runs Boolean and SemanticAction together
# ABOUTME: Verifies that both semirings are evaluated and results combined as tuple
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: Composite creation
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    isa_ok($comp, 'Chalk::Bootstrap::Semiring::Composite', 'creates composite semiring');
}

# Test 2: zero returns (bool_zero, sem_zero)
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $zero = $comp->zero();

    isa_ok($zero, 'ARRAY', 'zero returns array ref');
    is(scalar($zero->@*), 2, 'zero returns 2-tuple');
    ok($bool_sr->is_zero($zero->[0]), 'first element is bool zero');
    ok($sem_sr->is_zero($zero->[1]), 'second element is sem zero');
}

# Test 3: one returns (bool_one, sem_one)
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $one = $comp->one();

    isa_ok($one, 'ARRAY', 'one returns array ref');
    is(scalar($one->@*), 2, 'one returns 2-tuple');
    ok(!$bool_sr->is_zero($one->[0]), 'first element is bool one');
    ok(!$sem_sr->is_zero($one->[1]), 'second element is sem one');
}

# Test 4: is_zero checks boolean component
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $zero = $comp->zero();
    my $one = $comp->one();

    ok($comp->is_zero($zero), 'is_zero recognizes zero tuple');
    ok(!$comp->is_zero($one), 'is_zero recognizes non-zero tuple');
}

# Test 5: multiply delegates to both semirings
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Left',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 5,
        rule     => 'Right',
    );

    my $val1 = [$bool_sr->one(), $ctx1];
    my $val2 = [$bool_sr->one(), $ctx2];

    my $result = $comp->multiply($val1, $val2);

    isa_ok($result, 'ARRAY', 'multiply returns array ref');
    is(scalar($result->@*), 2, 'multiply returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component is true');
    isa_ok($result->[1], 'Chalk::Bootstrap::Context', 'sem component is Context');
    is(scalar($result->[1]->children()->@*), 2, 'sem component has 2 children');
}

# Test 6: add delegates to both semirings
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'alt1');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Alt1',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'alt2');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Alt2',
    );

    my $val1 = [$bool_sr->one(), $ctx1];
    my $val2 = [$bool_sr->one(), $ctx2];

    my $result = $comp->add($val1, $val2);

    isa_ok($result, 'ARRAY', 'add returns array ref');
    is(scalar($result->@*), 2, 'add returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component is true');
    is($result->[1]->extract()->value(), 'alt1', 'sem component returns first alt');
}

# Test 7: multiply with zero propagates zero
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $zero = $comp->zero();
    my $one = $comp->one();

    my $result = $comp->multiply($zero, $one);

    ok($comp->is_zero($result), 'multiply(zero, one) is zero');
}

# Test 8: scan_value delegates to both semirings
{
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $result = $comp->scan_value('hello');

    isa_ok($result, 'ARRAY', 'scan_value returns array ref');
    is(scalar($result->@*), 2, 'scan_value returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component is non-zero (one)');
    isa_ok($result->[1], 'Chalk::Bootstrap::Context', 'sem component is Context');
    is($result->[1]->extract(), 'hello', 'sem component has matched text as focus');
}

# Test 9: complete_value delegates to both semirings
{
    # Create a test package with an action
    package CompositeTestActions {
        sub TestRule ($ctx) { return uc($ctx->extract() // ''); }
    }

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        action_package => 'CompositeTestActions',
    );
    my $comp = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'hello',
        children => [],
        position => 0,
        rule     => undef,
    );
    my $val = [$bool_sr->one(), $ctx];

    my $result = $comp->complete_value($val, 'TestRule');

    isa_ok($result, 'ARRAY', 'complete_value returns array ref');
    is(scalar($result->@*), 2, 'complete_value returns 2-tuple');
    ok(!$bool_sr->is_zero($result->[0]), 'bool component unchanged');
    isa_ok($result->[1], 'Chalk::Bootstrap::Context', 'sem component is Context');
    is($result->[1]->extract(), 'HELLO', 'sem component has action applied');
    is($result->[1]->rule(), 'TestRule', 'sem component has rule name set');
}

done_testing();
