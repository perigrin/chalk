# ABOUTME: Tests for Variable semantic action
# ABOUTME: Verifies Variable handles ScalarVar, ArrayVar, HashVar correctly

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::Variable;
use Chalk::Grammar::Chalk::Rule::ScalarVar;
use Chalk::Grammar::Chalk::Rule::ArrayVar;
use Chalk::Grammar::Chalk::Rule::HashVar;
use Chalk::IR::Node::Scope;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# ===== ScalarVar metadata tests =====

subtest 'ScalarVar returns metadata hash' => sub {
    # Mock context for '$foo'
    my $context = Chalk::EvalContext->new(
        children => [
            # Child 0: '$' sigil
            Chalk::EvalContext->new(
                focus => '$',
                children => [],
                start_pos => 0,
                end_pos => 1,
                env => {},
                grammar => undef,
                rule => undef
            ),
            # Child 1: identifier 'foo'
            Chalk::EvalContext->new(
                focus => 'foo',
                children => [],
                start_pos => 1,
                end_pos => 4,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ScalarVar->new(
        lhs => 'ScalarVar',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    is(ref($result), 'HASH', 'ScalarVar returns hashref');
    is($result->{type}, 'scalar_var', 'type is scalar_var');
    is($result->{name}, 'foo', 'name is correct');
    is($result->{sigil}, '$', 'sigil is $');
};

# ===== ArrayVar metadata tests =====

subtest 'ArrayVar returns metadata hash' => sub {
    # Mock context for '@arr'
    my $context = Chalk::EvalContext->new(
        children => [
            # Child 0: '@' sigil
            Chalk::EvalContext->new(
                focus => '@',
                children => [],
                start_pos => 0,
                end_pos => 1,
                env => {},
                grammar => undef,
                rule => undef
            ),
            # Child 1: identifier 'arr'
            Chalk::EvalContext->new(
                focus => 'arr',
                children => [],
                start_pos => 1,
                end_pos => 4,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 4,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ArrayVar->new(
        lhs => 'ArrayVar',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    is(ref($result), 'HASH', 'ArrayVar returns hashref');
    is($result->{type}, 'array_var', 'type is array_var');
    is($result->{name}, 'arr', 'name is correct');
    is($result->{sigil}, '@', 'sigil is @');
};

# ===== HashVar metadata tests =====

subtest 'HashVar returns metadata hash' => sub {
    # Mock context for '%hash'
    my $context = Chalk::EvalContext->new(
        children => [
            # Child 0: '%' sigil
            Chalk::EvalContext->new(
                focus => '%',
                children => [],
                start_pos => 0,
                end_pos => 1,
                env => {},
                grammar => undef,
                rule => undef
            ),
            # Child 1: identifier 'hash'
            Chalk::EvalContext->new(
                focus => 'hash',
                children => [],
                start_pos => 1,
                end_pos => 5,
                env => {},
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 5,
        env => {},
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::HashVar->new(
        lhs => 'HashVar',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    is(ref($result), 'HASH', 'HashVar returns hashref');
    is($result->{type}, 'hash_var', 'type is hash_var');
    is($result->{name}, 'hash', 'name is correct');
    is($result->{sigil}, '%', 'sigil is %');
};

# ===== Variable rule tests =====

subtest 'Variable handles array_var metadata' => sub {
    # Create a scope with an array variable
    my $scope = Chalk::IR::Node::Scope->new();
    my $array_node = Chalk::IR::Node::Constant->new(
        value => 'mock_array_ref',
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    $scope = $scope->with_binding('@arr', $array_node);

    # Create metadata that ArrayVar would return
    my $array_metadata = {
        type => 'array_var',
        name => 'arr',
        sigil => '@'
    };

    # Mock context with scope and array metadata
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => $array_metadata,
                children => [],
                start_pos => 0,
                end_pos => 4,
                env => { scope => $scope },
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 4,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Variable->new(
        lhs => 'Variable',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Variable returns IR node for array');
    is($result->id, $array_node->id, 'Returns the correct array node');
};

subtest 'Variable handles hash_var metadata' => sub {
    # Create a scope with a hash variable
    my $scope = Chalk::IR::Node::Scope->new();
    my $hash_node = Chalk::IR::Node::Constant->new(
        value => 'mock_hash_ref',
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );
    $scope = $scope->with_binding('%myhash', $hash_node);

    # Create metadata that HashVar would return
    my $hash_metadata = {
        type => 'hash_var',
        name => 'myhash',
        sigil => '%'
    };

    # Mock context with scope and hash metadata
    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => $hash_metadata,
                children => [],
                start_pos => 0,
                end_pos => 7,
                env => { scope => $scope },
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 7,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Variable->new(
        lhs => 'Variable',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Variable returns IR node for hash');
    is($result->id, $hash_node->id, 'Returns the correct hash node');
};

subtest 'Variable passes through metadata for undeclared array' => sub {
    # Create an empty scope (no @arr defined)
    my $scope = Chalk::IR::Node::Scope->new();

    # Create metadata that ArrayVar would return
    my $array_metadata = {
        type => 'array_var',
        name => 'undefined_arr',
        sigil => '@'
    };

    my $context = Chalk::EvalContext->new(
        children => [
            Chalk::EvalContext->new(
                focus => $array_metadata,
                children => [],
                start_pos => 0,
                end_pos => 14,
                env => { scope => $scope },
                grammar => undef,
                rule => undef
            ),
        ],
        focus => undef,
        start_pos => 0,
        end_pos => 14,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Variable->new(
        lhs => 'Variable',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    # Variable now returns UnboundVariable for undeclared variables
    # This allows duck-typed access via name() method
    isa_ok($result, 'Chalk::IR::Node::UnboundVariable', 'Returns UnboundVariable for undeclared variable');
    is($result->name, '@undefined_arr', 'UnboundVariable has correct full name with sigil');
};

done_testing();
