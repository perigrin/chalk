# ABOUTME: Tests for single-expression method bodies without explicit return
# ABOUTME: Validates that methods with implicit returns generate correct IR (#558)

use v5.42;
use Test::More;
use FindBin qw($RealBin);
use Scalar::Util 'blessed';

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

# Load grammar once for all tests
my $bnf_file = "$RealBin/../../grammar/chalk.bnf";
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

sub parse_class {
    my ($code) = @_;

    # Reset TypeRegistry to avoid state leaking between tests
    Chalk::Grammar::Chalk::TypeRegistry->instance->reset();

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    my $result = $parser->parse_string($code);
    return undef unless $result;

    # Extract IR from parse result
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx && $ctx->can('focus')) {
            return $ctx->focus;
        }
    }

    return $result;
}

sub extract_method_body {
    my ($ir, $method_name) = @_;

    # Navigate: Stop -> class_defs[0] -> methods -> find by name
    return undef unless $ir && blessed($ir) && $ir->can('class_defs');

    my $classes = $ir->class_defs // [];
    return undef unless @$classes;

    my $class = $classes->[0];
    my $methods = $class->methods // [];

    for my $method (@$methods) {
        if ($method->name eq $method_name) {
            return $method;
        }
    }

    return undef;
}

# Test 1: Simple literal expression
subtest 'Simple literal without return' => sub {
    my $code = q{
        class Test {
            method get_answer() { 42 }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'get_answer');
    ok(defined $method, 'Found get_answer method');

    # Check body_statements
    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");

        if (@$stmts > 0) {
            my $stmt = $stmts->[0];
            ok(blessed($stmt) && $stmt->can('op'), 'First statement is IR node');
            is($stmt->op, 'Constant', 'Statement is Constant node');
            is($stmt->value, 42, 'Constant has value 42');
        }
    }
};

# Test 2: Simple ternary without return
subtest 'Simple ternary without return' => sub {
    my $code = q{
        class Test {
            method is_positive($x) { $x > 0 ? 1 : 0 }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully')
        or do { diag("Parse failed completely"); return; };

    # Debug IR structure
    if (!$ir || !blessed($ir)) {
        diag("IR is not blessed: " . ($ir // 'undef'));
        return;
    }
    if (!$ir->can('class_defs')) {
        my $op = $ir->can('op') ? $ir->op : 'NO OP';
        my $type = ref($ir);
        diag("IR cannot call class_defs, op=$op, type=$type");
        return;
    }
    my $classes = $ir->class_defs // [];
    unless (@$classes) {
        diag("IR has class_defs method but it returned empty array");
        diag("IR op: " . ($ir->can('op') ? $ir->op : 'unknown'));
        return;
    }

    my $method = extract_method_body($ir, 'is_positive');
    ok(defined $method, 'Found is_positive method')
        or do {
            # Debug: show what methods we got
            my $classes = $ir->class_defs // [];
            if (@$classes) {
                my $class = $classes->[0];
                my $methods = $class->methods // [];
                diag("Methods found: " . join(', ', map { $_->name } @$methods));
            } else {
                diag("No classes found in IR");
            }
            return;  # Skip rest of subtest if method not found
        };

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");

        if (@$stmts > 0) {
            my $stmt = $stmts->[0];
            ok(blessed($stmt) && $stmt->can('op'), 'First statement is IR node');
            is($stmt->op, 'Phi', 'Statement is Phi node (from ternary)');
        }
    }
};

# Test 3: Complex expression - the actual failing case from #558
subtest 'Complex expression with logical operators and ternary' => sub {
    my $code = q{
        class Test {
            field $value;
            field $is_bottom;

            method is_constant() { (defined($value) && !$is_bottom) ? 1 : 0 }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'is_constant');
    ok(defined $method, 'Found is_constant method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");

        if (@$stmts > 0) {
            my $stmt = $stmts->[0];
            ok(blessed($stmt) && $stmt->can('op'), 'First statement is IR node');
            # Should be Phi from ternary
            like($stmt->op, qr/^(Phi|Region|If)$/, 'Statement is control flow node');
        }
    }
};

# Test 4: Logical AND expression
subtest 'Logical AND expression' => sub {
    my $code = q{
        class Test {
            field $x;
            field $y;

            method both_set() { $x && $y }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'both_set');
    ok(defined $method, 'Found both_set method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");
    }
};

# Test 5: Logical OR expression
subtest 'Logical OR expression' => sub {
    my $code = q{
        class Test {
            field $x;
            field $y;

            method either_set() { $x || $y }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'either_set');
    ok(defined $method, 'Found either_set method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");
    }
};

# Test 6: Comparison expression
subtest 'Comparison expression' => sub {
    my $code = q{
        class Test {
            field $count;

            method is_zero() { $count == 0 }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'is_zero');
    ok(defined $method, 'Found is_zero method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");

        if (@$stmts > 0) {
            my $stmt = $stmts->[0];
            ok(blessed($stmt) && $stmt->can('op'), 'First statement is IR node');
            like($stmt->op, qr/^(EQ|Compare)$/, 'Statement is comparison node');
        }
    }
};

# Test 7: Arithmetic expression
subtest 'Arithmetic expression' => sub {
    my $code = q{
        class Test {
            field $x;
            field $y;

            method sum() { $x + $y }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'sum');
    ok(defined $method, 'Found sum method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");

        if (@$stmts > 0) {
            my $stmt = $stmts->[0];
            ok(blessed($stmt) && $stmt->can('op'), 'First statement is IR node');
            is($stmt->op, 'Add', 'Statement is Add node');
        }
    }
};

# Test 8: Method call expression
subtest 'Method call expression' => sub {
    my $code = q{
        class Test {
            method get_value() { 42 }
            method double_value() { $self->get_value() * 2 }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'double_value');
    ok(defined $method, 'Found double_value method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");
    }
};

# Test 9: Nested ternary
subtest 'Nested ternary expression' => sub {
    my $code = q{
        class Test {
            field $x;

            method classify() { $x < 0 ? -1 : ($x > 0 ? 1 : 0) }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    my $method = extract_method_body($ir, 'classify');
    ok(defined $method, 'Found classify method');

    if ($method->can('body_statements')) {
        my $stmts = $method->body_statements;
        isnt(scalar(@$stmts), 0, 'Body has statements (not empty)')
            or diag("FAIL: Empty body - this is the bug from #558");

        if (@$stmts > 0) {
            my $stmt = $stmts->[0];
            ok(blessed($stmt) && $stmt->can('op'), 'First statement is IR node');
            is($stmt->op, 'Phi', 'Statement is Phi node (from ternary)');
        }
    }
};

# Test 10: Multiple simple methods (regression test)
subtest 'Multiple single-expression methods in same class' => sub {
    my $code = q{
        class Test {
            method is_constant() { 1 }
            method is_top() { 0 }
            method is_bottom() { 0 }
        }
    };

    my $ir = parse_class($code);
    ok(defined $ir, 'Parsed successfully');

    for my $method_name (qw(is_constant is_top is_bottom)) {
        my $method = extract_method_body($ir, $method_name);
        ok(defined $method, "Found $method_name method");

        if ($method && $method->can('body_statements')) {
            my $stmts = $method->body_statements;
            isnt(scalar(@$stmts), 0, "$method_name has statements (not empty)")
                or diag("FAIL: Empty body for $method_name - this is the bug from #558");
        }
    }
};

done_testing();
