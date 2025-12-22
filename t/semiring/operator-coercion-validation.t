# ABOUTME: Test operator coercion validation in ArithmeticOp and ConcatenationOp
# ABOUTME: Validates Phase 3 of #433 - operators validate coercion capabilities

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Defines Chalk::GrammarRule base class
use Chalk::Grammar::Chalk::TypeLattice;
use Chalk::Semiring::TypeInference;
use Chalk::Grammar::Chalk::Rule::ArithmeticOp;
use Chalk::Grammar::Chalk::Rule::ConcatenationOp;

my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

subtest 'ArithmeticOp: Int + Int succeeds' => sub {
    my $left = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Int'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 1,
        container_context => 'scalar',
        value_context => undef
    );

    my $right = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Int'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 4,
        end_pos => 5,
        container_context => 'scalar',
        value_context => undef
    );

    my $arith_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [$left, $right],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 5,
        container_context => 'scalar',
        value_context => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ArithmeticOp->new(
        lhs => 'ArithmeticOp',
        rhs => []
    );

    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $result = $rule->infer_type($type_sr, $arith_elem);

    ok($result, "ArithmeticOp infer_type returns result");
    is($result->type_obj->name, 'Int', "Result type is Int");
    ok(!$result->has_errors, "No coercion errors for Int + Int");
};

subtest 'ArithmeticOp: Str + Str succeeds with coercion' => sub {
    my $left = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Str'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 3,
        container_context => 'scalar',
        value_context => undef
    );

    my $right = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Str'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 6,
        end_pos => 9,
        container_context => 'scalar',
        value_context => undef
    );

    my $arith_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [$left, $right],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 9,
        container_context => 'scalar',
        value_context => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ArithmeticOp->new(
        lhs => 'ArithmeticOp',
        rhs => []
    );

    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $result = $rule->infer_type($type_sr, $arith_elem);

    ok($result, "ArithmeticOp infer_type returns result");
    # Str can coerce to Num, so result should be Num (not bottom)
    is($result->type_obj->name, 'Num', "Result type is Num (after coercion)");
    ok(!$result->has_errors, "No coercion errors for Str + Str (strings can coerce to numbers)");
};

subtest 'ConcatenationOp: Int . Int succeeds with coercion' => sub {
    my $left = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Int'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 1,
        container_context => 'scalar',
        value_context => undef
    );

    use Chalk::Grammar::Token;
    my $dot_token = Chalk::Grammar::Token->new(value => '.');

    my $operator_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [],
        token => $dot_token,
        errors => [],
        start_pos => 2,
        end_pos => 3,
        container_context => undef,
        value_context => undef
    );

    my $right = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Int'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 4,
        end_pos => 5,
        container_context => 'scalar',
        value_context => undef
    );

    my $concat_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [$left, $operator_elem, $right],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 5,
        container_context => 'scalar',
        value_context => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ConcatenationOp->new(
        lhs => 'ConcatenationOp',
        rhs => []
    );

    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $result = $rule->infer_type($type_sr, $concat_elem);

    ok($result, "ConcatenationOp infer_type returns result");
    is($result->type_obj->name, 'Str', "Result type is Str");
    ok(!$result->has_errors, "No coercion errors for Int . Int");
};

subtest 'ConcatenationOp: Str . Str succeeds' => sub {
    my $left = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Str'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 5,
        container_context => 'scalar',
        value_context => undef
    );

    use Chalk::Grammar::Token;
    my $dot_token = Chalk::Grammar::Token->new(value => '.');

    my $operator_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [],
        token => $dot_token,
        errors => [],
        start_pos => 6,
        end_pos => 7,
        container_context => undef,
        value_context => undef
    );

    my $right = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Str'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 8,
        end_pos => 13,
        container_context => 'scalar',
        value_context => undef
    );

    my $concat_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [$left, $operator_elem, $right],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 13,
        container_context => 'scalar',
        value_context => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::ConcatenationOp->new(
        lhs => 'ConcatenationOp',
        rhs => []
    );

    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $result = $rule->infer_type($type_sr, $concat_elem);

    ok($result, "ConcatenationOp infer_type returns result");
    is($result->type_obj->name, 'Str', "Result type is Str");
    ok(!$result->has_errors, "No coercion errors for Str . Str");
};

# done_testing handled by defer at top
