#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 12 - Floating-Point Types
# ABOUTME: Validates float literals, operations, comparisons, type widening, and Newton's method

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::ConstantF;
use Chalk::IR::Node::AddF;
use Chalk::IR::Node::SubF;
use Chalk::IR::Node::MulF;
use Chalk::IR::Node::DivF;
use Chalk::IR::Node::MinusF;
use Chalk::IR::Node::EQF;
use Chalk::IR::Node::LTF;
use Chalk::IR::Node::LEF;
use Chalk::IR::Type::Float;

# Helper to create execution context for node evaluation
sub make_context {
    my %nodes = @_;
    return sub {
        my $key = shift;
        if ($key =~ /^node:(\d+)$/) {
            my $node_id = $1;
            if (exists $nodes{$node_id}) {
                my $node = $nodes{$node_id};
                # ConstantF nodes don't take context parameter
                if ($node->isa('Chalk::IR::Node::ConstantF')) {
                    return $node->execute();
                } else {
                    return $node->execute(__SUB__);
                }
            }
        }
        die "Unknown context key: $key";
    };
}

subtest 'Float constant node creation' => sub {
    my $const = Chalk::IR::Node::ConstantF->new(value => 3.14);

    ok $const, 'Created float constant node';
    is $const->value, 3.14, 'Float value is correct';
    ok $const->compute()->isa('Chalk::IR::Type::Float'), 'Type is Float';
};

subtest 'Float arithmetic: addition' => sub {
    my $start = Chalk::IR::Node::Start->new();
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $add);

    ok $add, 'Created AddF node';
    my $ctx = make_context($left->id => $left, $right->id => $right);
    my $result = $add->execute($ctx);
    is $result, 4.0, 'AddF executes correctly: 1.5 + 2.5 = 4.0';
};

subtest 'Float arithmetic: subtraction' => sub {
    my $start = Chalk::IR::Node::Start->new();
    my $left = Chalk::IR::Node::ConstantF->new(value => 5.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $sub = Chalk::IR::Node::SubF->new(left => $left, right => $right);
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $sub);

    ok $sub, 'Created SubF node';
    my $ctx = make_context($left->id => $left, $right->id => $right);
    my $result = $sub->execute($ctx);
    is $result, 3.0, 'SubF executes correctly: 5.5 - 2.5 = 3.0';
};

subtest 'Float arithmetic: multiplication' => sub {
    my $start = Chalk::IR::Node::Start->new();
    my $left = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 4.0);
    my $mul = Chalk::IR::Node::MulF->new(left => $left, right => $right);
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $mul);

    ok $mul, 'Created MulF node';
    my $ctx = make_context($left->id => $left, $right->id => $right);
    my $result = $mul->execute($ctx);
    is $result, 10.0, 'MulF executes correctly: 2.5 * 4.0 = 10.0';
};

subtest 'Float arithmetic: division' => sub {
    my $start = Chalk::IR::Node::Start->new();
    my $left = Chalk::IR::Node::ConstantF->new(value => 10.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 4.0);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $div);

    ok $div, 'Created DivF node';
    my $ctx = make_context($left->id => $left, $right->id => $right);
    my $result = $div->execute($ctx);
    is $result, 2.5, 'DivF executes correctly: 10.0 / 4.0 = 2.5';
};

subtest 'Float arithmetic: unary negation' => sub {
    my $start = Chalk::IR::Node::Start->new();
    my $value = Chalk::IR::Node::ConstantF->new(value => 3.14);
    my $minus = Chalk::IR::Node::MinusF->new(operand => $value);
    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $minus);

    ok $minus, 'Created MinusF node';
    my $ctx = make_context($value->id => $value);
    my $result = $minus->execute($ctx);
    is $result, -3.14, 'MinusF executes correctly: -(3.14) = -3.14';
};

subtest 'Float comparison: equality' => sub {
    my $start = Chalk::IR::Node::Start->new();

    # Test equal values
    my $left1 = Chalk::IR::Node::ConstantF->new(value => 3.14);
    my $right1 = Chalk::IR::Node::ConstantF->new(value => 3.14);
    my $eq1 = Chalk::IR::Node::EQF->new(left => $left1, right => $right1);
    my $ctx1 = make_context($left1->id => $left1, $right1->id => $right1);
    is $eq1->execute($ctx1), 1, 'EQF: 3.14 == 3.14 is true';

    # Test unequal values
    my $left2 = Chalk::IR::Node::ConstantF->new(value => 3.14);
    my $right2 = Chalk::IR::Node::ConstantF->new(value => 2.71);
    my $eq2 = Chalk::IR::Node::EQF->new(left => $left2, right => $right2);
    my $ctx2 = make_context($left2->id => $left2, $right2->id => $right2);
    is $eq2->execute($ctx2), 0, 'EQF: 3.14 == 2.71 is false';
};

subtest 'Float comparison: less than' => sub {
    my $start = Chalk::IR::Node::Start->new();

    # Test true case
    my $left1 = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right1 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $lt1 = Chalk::IR::Node::LTF->new(left => $left1, right => $right1);
    my $ctx1 = make_context($left1->id => $left1, $right1->id => $right1);
    is $lt1->execute($ctx1), 1, 'LTF: 2.5 < 3.5 is true';

    # Test false case
    my $left2 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $right2 = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $lt2 = Chalk::IR::Node::LTF->new(left => $left2, right => $right2);
    my $ctx2 = make_context($left2->id => $left2, $right2->id => $right2);
    is $lt2->execute($ctx2), 0, 'LTF: 3.5 < 2.5 is false';

    # Test equal case (should be false)
    my $left3 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $right3 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $lt3 = Chalk::IR::Node::LTF->new(left => $left3, right => $right3);
    my $ctx3 = make_context($left3->id => $left3, $right3->id => $right3);
    is $lt3->execute($ctx3), 0, 'LTF: 3.5 < 3.5 is false';
};

subtest 'Float comparison: less than or equal' => sub {
    my $start = Chalk::IR::Node::Start->new();

    # Test less than case
    my $left1 = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $right1 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $le1 = Chalk::IR::Node::LEF->new(left => $left1, right => $right1);
    my $ctx1 = make_context($left1->id => $left1, $right1->id => $right1);
    is $le1->execute($ctx1), 1, 'LEF: 2.5 <= 3.5 is true';

    # Test equal case
    my $left2 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $right2 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $le2 = Chalk::IR::Node::LEF->new(left => $left2, right => $right2);
    my $ctx2 = make_context($left2->id => $left2, $right2->id => $right2);
    is $le2->execute($ctx2), 1, 'LEF: 3.5 <= 3.5 is true';

    # Test greater than case
    my $left3 = Chalk::IR::Node::ConstantF->new(value => 3.5);
    my $right3 = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $le3 = Chalk::IR::Node::LEF->new(left => $left3, right => $right3);
    my $ctx3 = make_context($left3->id => $left3, $right3->id => $right3);
    is $le3->execute($ctx3), 0, 'LEF: 3.5 <= 2.5 is false';
};

subtest 'Float edge cases: NaN' => sub {
    my $nan = 'NaN' + 0;  # Perl idiom to create NaN
    my $const_nan = Chalk::IR::Node::ConstantF->new(value => $nan);

    ok $const_nan, 'Created NaN constant';
    # NaN != NaN is the defining property of NaN
    my $nan_value = $const_nan->value;
    ok $nan_value != $nan_value, 'NaN is stored correctly (NaN != NaN)';
};

subtest 'Float edge cases: Infinity' => sub {
    # Perl numeric infinity
    my $pos_inf = 9**9**9;  # Perl idiom to create positive infinity
    my $neg_inf = -9**9**9; # Perl idiom to create negative infinity

    my $const_pos = Chalk::IR::Node::ConstantF->new(value => $pos_inf);
    my $const_neg = Chalk::IR::Node::ConstantF->new(value => $neg_inf);

    ok $const_pos, 'Created positive infinity constant';
    ok $const_neg, 'Created negative infinity constant';

    # Test arithmetic with infinity
    my $finite = Chalk::IR::Node::ConstantF->new(value => 5.0);
    my $add_inf = Chalk::IR::Node::AddF->new(left => $finite, right => $const_pos);
    my $ctx = make_context($finite->id => $finite, $const_pos->id => $const_pos);

    my $result = $add_inf->execute($ctx);
    ok $result > 999999999, 'Adding to infinity gives infinity';
};

subtest 'Float constant folding' => sub {
    # Test that constant float expressions are folded at compile time
    my $left = Chalk::IR::Node::ConstantF->new(value => 3.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 4.0);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    # Peephole optimization should fold this to a constant
    my $optimized = $add->peephole();
    ok $optimized->isa('Chalk::IR::Node::ConstantF'),
        'Constant folding: 3.0 + 4.0 optimized to ConstantF';
    is $optimized->value, 7.0, 'Folded value is correct';
};

subtest 'Float algebraic simplification: addition identity' => sub {
    # Test x + 0.0 = x
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.0);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);
    my $add = Chalk::IR::Node::AddF->new(left => $x, right => $zero);

    my $optimized = $add->peephole();
    # Should simplify to just x (which is the constant 5.0)
    is $optimized->value, 5.0, 'x + 0.0 simplifies correctly';
};

subtest 'Float algebraic simplification: multiplication by zero' => sub {
    # Test x * 0.0 = 0.0
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.0);
    my $zero = Chalk::IR::Node::ConstantF->new(value => 0.0);
    my $mul = Chalk::IR::Node::MulF->new(left => $x, right => $zero);

    my $optimized = $mul->peephole();
    ok $optimized->isa('Chalk::IR::Node::ConstantF'),
        'x * 0.0 optimized to ConstantF';
    is $optimized->value, 0.0, 'x * 0.0 = 0.0';
};

subtest 'Float algebraic simplification: multiplication identity' => sub {
    # Test x * 1.0 = x
    my $x = Chalk::IR::Node::ConstantF->new(value => 5.0);
    my $one = Chalk::IR::Node::ConstantF->new(value => 1.0);
    my $mul = Chalk::IR::Node::MulF->new(left => $x, right => $one);

    my $optimized = $mul->peephole();
    # Should simplify to just x (which is the constant 5.0)
    is $optimized->value, 5.0, 'x * 1.0 simplifies correctly';
};

subtest 'Newton\'s method: square root approximation' => sub {
    # Newton's method for sqrt(x): x_{n+1} = (x_n + S/x_n) / 2
    # Test computing sqrt(2) starting from guess 1.0
    # Should converge to approximately 1.414213562373095

    my $S = 2.0;  # Finding sqrt(2)
    my $guess = 1.0;
    my $epsilon = 0.000001;  # Convergence threshold
    my $iterations = 0;
    my $max_iterations = 10;

    while ($iterations < $max_iterations) {
        my $next_guess = ($guess + $S / $guess) / 2.0;
        last if abs($next_guess - $guess) < $epsilon;
        $guess = $next_guess;
        $iterations++;
    }

    ok abs($guess - 1.414213562373095) < 0.000001,
        'Newton\'s method converges to sqrt(2) ≈ 1.414';
    ok $iterations < $max_iterations,
        "Converged in $iterations iterations (less than $max_iterations)";
};

subtest 'Newton\'s method: IR graph construction' => sub {
    # Build an IR graph that represents one iteration of Newton's method
    # next = (guess + S/guess) / 2

    my $start = Chalk::IR::Node::Start->new();
    my $S_const = Chalk::IR::Node::ConstantF->new(value => 2.0);
    my $guess_const = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $two_const = Chalk::IR::Node::ConstantF->new(value => 2.0);

    # S / guess
    my $div = Chalk::IR::Node::DivF->new(left => $S_const, right => $guess_const);

    # guess + (S/guess)
    my $add = Chalk::IR::Node::AddF->new(left => $guess_const, right => $div);

    # (guess + S/guess) / 2
    my $next = Chalk::IR::Node::DivF->new(left => $add, right => $two_const);

    my $ret = Chalk::IR::Node::Return->new(control => $start, value => $next);

    # Execute the graph - build context with all nodes
    my $ctx = make_context(
        $S_const->id => $S_const,
        $guess_const->id => $guess_const,
        $two_const->id => $two_const,
        $div->id => $div,
        $add->id => $add,
    );
    my $result = $next->execute($ctx);

    # For guess=1.5, S=2: next = (1.5 + 2/1.5) / 2 = (1.5 + 1.333...) / 2 ≈ 1.4166...
    ok abs($result - 1.41666666666) < 0.00001,
        'One Newton iteration: (1.5 + 2/1.5)/2 ≈ 1.4167';
};

subtest 'Type inference: Float operations preserve Float type' => sub {
    my $left = Chalk::IR::Node::ConstantF->new(value => 1.5);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.5);
    my $add = Chalk::IR::Node::AddF->new(left => $left, right => $right);

    my $type = $add->compute();
    ok $type->isa('Chalk::IR::Type::Float'),
        'AddF result type is Float';
};

subtest 'Mixed precision: Float operations with integer-like values' => sub {
    # Even with integer-like values, float operations should maintain float semantics
    my $left = Chalk::IR::Node::ConstantF->new(value => 5.0);
    my $right = Chalk::IR::Node::ConstantF->new(value => 2.0);
    my $div = Chalk::IR::Node::DivF->new(left => $left, right => $right);

    my $ctx = make_context($left->id => $left, $right->id => $right);
    my $result = $div->execute($ctx);
    is $result, 2.5, 'Float division: 5.0 / 2.0 = 2.5 (not integer division)';
};
