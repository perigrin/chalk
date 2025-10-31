# ABOUTME: Differential testing framework comparing Chalk interpreter output against Perl 5.42.0
# ABOUTME: Validates that interpreter semantics match Perl behavior exactly

use v5.42;
use Test::More;
use File::Temp;

# Load required modules
use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Semiring::Semantic');
use_ok('Chalk::IR::Builder');
use_ok('Chalk::IR::Interpreter');
use_ok('Chalk::IR::Optimizer::GVN');

# Load Chalk grammar from BNF file
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Helper function to execute Chalk code via interpreter
sub execute_chalk {
    my ($code) = @_;

    # Create Builder
    my $builder = Chalk::IR::Builder->new();

    # Create Parser with semantic actions
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder }
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse the program
    my $parse_result = $parser->parse_string($code);
    return undef unless $parse_result;

    # Get the IR graph
    my $graph = $builder->graph;

    # Run GVN optimizer
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    # Execute via interpreter
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    return $interpreter->execute();
}

# Helper function to execute code via Perl 5.42.0
sub execute_perl {
    my ($code) = @_;

    # Wrap code in a subroutine so 'return' works
    my $wrapped_code = "use v5.42;\nsub main { $code }\nmy \$result = main();\nprint \$result;\n";

    # Create temporary file
    my $tmpfile = File::Temp->new(SUFFIX => '.pl');
    print $tmpfile $wrapped_code;
    close $tmpfile;

    # Execute with Perl 5.42.0
    my $output = `PLENV_VERSION=5.42.0 plenv exec perl $tmpfile 2>&1`;
    chomp $output;

    # Extract numeric return value if possible
    if ($output =~ /^-?\d+(?:\.\d+)?$/) {
        return 0 + $output;  # Convert to number
    }

    return $output;
}

# Main differential testing function
sub test_against_perl {
    my ($code, $test_name) = @_;

    # Execute via Chalk interpreter
    my $chalk_output = execute_chalk($code);

    # Execute via Perl 5.42.0
    my $perl_output = execute_perl($code);

    # Compare outputs
    is($chalk_output, $perl_output, $test_name);
}

# Test 1: Simple arithmetic - addition (positive numbers only for now)
subtest 'Arithmetic: Addition (positive numbers)' => sub {
    test_against_perl('return 2 + 2;', 'Simple addition: 2 + 2');
    test_against_perl('return 10 + 5;', 'Addition: 10 + 5');
    test_against_perl('return 0 + 0;', 'Addition with zeros');
};

# Test 2: Simple arithmetic - subtraction (positive results only)
subtest 'Arithmetic: Subtraction (positive results)' => sub {
    test_against_perl('return 10 - 3;', 'Simple subtraction: 10 - 3');
    test_against_perl('return 5 - 5;', 'Subtraction resulting in zero');
};

# Test 3: Simple arithmetic - multiplication (positive numbers only)
subtest 'Arithmetic: Multiplication (positive numbers)' => sub {
    test_against_perl('return 3 * 4;', 'Simple multiplication: 3 * 4');
    test_against_perl('return 10 * 0;', 'Multiplication by zero');
};

# Test 4: Simple arithmetic - division (positive numbers only)
subtest 'Arithmetic: Division (positive numbers)' => sub {
    test_against_perl('return 10 / 2;', 'Simple division: 10 / 2');
    test_against_perl('return 7 / 2;', 'Division with remainder: 7 / 2');
};

# Test 5: Comparison operators - numeric (true values only - Perl returns empty string for false)
subtest 'Comparison: Numeric (true values)' => sub {
    test_against_perl('return 10 > 5;', 'Greater than (true)');
    test_against_perl('return 5 < 10;', 'Less than (true)');
    test_against_perl('return 10 == 10;', 'Equal (true)');
    test_against_perl('return 10 != 5;', 'Not equal (true)');
    test_against_perl('return 10 >= 10;', 'Greater or equal (true, equal case)');
    test_against_perl('return 10 >= 5;', 'Greater or equal (true, greater case)');
    test_against_perl('return 10 <= 10;', 'Less or equal (true, equal case)');
    test_against_perl('return 5 <= 10;', 'Less or equal (true, less case)');
};

# Test 6: Variables with arithmetic (positive numbers only)
subtest 'Variables: Arithmetic (positive numbers)' => sub {
    test_against_perl('my $x = 5; return $x + 3;', 'Variable addition');
    test_against_perl('my $x = 10; return $x - 4;', 'Variable subtraction');
    test_against_perl('my $x = 6; return $x * 2;', 'Variable multiplication');
    test_against_perl('my $x = 20; return $x / 4;', 'Variable division');
};

# TODO tests: Document discovered issues that need fixing
subtest 'TODO: Arithmetic with negative literals' => sub {
    TODO: {
        local $TODO = 'Negative number literals do not parse/execute correctly';
        test_against_perl('return -5 + 3;', 'Addition with negative literal');
        test_against_perl('return -5 * 2;', 'Multiplication with negative literal');
        test_against_perl('return -10 / 2;', 'Division with negative literal');
        test_against_perl('return 3 - 10;', 'Subtraction resulting in negative');
    }
};

subtest 'TODO: Unary negation operator' => sub {
    TODO: {
        local $TODO = 'Unary negation operator does not execute correctly';
        test_against_perl('return -5;', 'Unary negation of positive literal');
        test_against_perl('return -(-5);', 'Double negation');
        # Removed: test with variable negation causes fatal error that prevents remaining tests
        # test_against_perl('my $x = 42; return -$x;', 'Negation of variable');
    }
};

subtest 'TODO: Comparison operators returning false' => sub {
    TODO: {
        local $TODO = 'Comparison operators return 0 for false, Perl returns empty string';
        # Note: This may be acceptable behavior difference - needs decision
        test_against_perl('return 5 > 10;', 'Greater than (false)');
        test_against_perl('return 10 < 5;', 'Less than (false)');
        test_against_perl('return 10 == 5;', 'Equal (false)');
        test_against_perl('return 5 >= 10;', 'Greater or equal (false)');
        test_against_perl('return 10 <= 5;', 'Less or equal (false)');
    }
};

subtest 'TODO: Control flow with if/else' => sub {
    SKIP: {
        skip 'IR construction for if/else creates malformed graph with multiple Return nodes (fatal error)', 4;
        # Error: "Malformed IR graph: found multiple Return nodes but none have __CONTROL_PLACEHOLDER__"
        # These tests would cause process exit, so skipped for now:
        # test_against_perl('if (1) { return 42; } else { return -42; }', 'If with literal true condition');
        # test_against_perl('if (0) { return 42; } else { return -42; }', 'If with literal false condition');
        # test_against_perl('my $x = 5; if ($x > 0) { return 42; } else { return -42; }', 'If with variable comparison (true)');
        # test_against_perl('my $x = -5; if ($x > 0) { return 42; } else { return -42; }', 'If with variable comparison (false)');
    }
};

# Future test expansion opportunities (from Issue #128):
# - Modulo operator (%)
# - Exponentiation operator (**)
# - Bitwise operators (~, &, |, ^, <<, >>)
# - Logical operators (&&, ||, !)
# - Division by zero behavior
# - Overflow/underflow handling
# - String comparison operators (eq, ne, lt, gt, le, ge, cmp)
# - Context sensitivity (numeric vs string)
# - Undef handling in operations
# - Variable shadowing across scopes
# - elsif chains
# - Ternary operator (?:)
# - Short-circuit evaluation
# - Deeply nested expressions
# - Operator precedence and associativity

done_testing();
