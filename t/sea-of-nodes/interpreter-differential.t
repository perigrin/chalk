# ABOUTME: Differential testing framework comparing Chalk interpreter output against Perl 5.42.0
# ABOUTME: Validates that interpreter semantics match Perl behavior exactly

use v5.42;
use Test::More;
use File::Temp;
use lib 'lib';

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

    # Prune graph to only include nodes from the winning parse
    # The parse result's focus points to the winning Return node
    if ($parse_result->can('context')) {
        my $ctx = $parse_result->context;
        if ($ctx->can('focus')) {
            my $winning_node = $ctx->focus;
            if ($winning_node && $winning_node->can('id')) {
                $graph->prune_to_reachable($winning_node->id);
            }
        }
    }

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

# Test 2: Simple arithmetic - subtraction (including negative results)
subtest 'Arithmetic: Subtraction' => sub {
    test_against_perl('return 10 - 3;', 'Simple subtraction: 10 - 3');
    test_against_perl('return 5 - 5;', 'Subtraction resulting in zero');
    test_against_perl('return 3 - 10;', 'Subtraction resulting in negative');
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

# Test 7: Control flow (limited - see TODO section for issues)
subtest 'Control Flow: Simple if without else' => sub {
    test_against_perl('my $x = 0; my $result = 0; if ($x > 0) { $result = 10; } return $result;',
        'If with false condition, no assignment (skips branch)');
    # Note: if with true condition fails - assignment in branch doesn't work correctly
};

# Test 8: Operator precedence (without parentheses for now)
subtest 'Operator precedence' => sub {
    test_against_perl('return 3 + 5 * 2;', 'Multiplication before addition (precedence)');
    test_against_perl('return 10 / 2 + 3;', 'Division then addition');
    test_against_perl('return 20 - 10 - 5;', 'Left-to-right subtraction');
};

# Test 9: Logical operators - Not operator (passing tests)
subtest 'Logical: Not operator (basic functionality)' => sub {
    test_against_perl('return !0;', 'Not false (0) returns true');
    test_against_perl('my $x = 0; return !$x;', 'Not false variable returns true');
};

subtest 'TODO: Not operator returning false' => sub {
    TODO: {
        local $TODO = 'Semantic difference: Chalk returns 0 for false, Perl returns empty string';
        test_against_perl('return !1;', 'Not true (1)');
        test_against_perl('return !5;', 'Not truthy value');
        test_against_perl('my $x = 10; return !$x;', 'Not true variable');
    }
};

subtest 'TODO: Not operator with comparison expressions' => sub {
    TODO: {
        local $TODO = 'Comparison operators need full integration to return proper IR nodes';
        test_against_perl('return !(5 > 10);', 'Not false comparison');
        test_against_perl('return !(10 > 5);', 'Not true comparison');
    }
};

# TODO tests: Document discovered issues that need fixing
subtest 'TODO: Negative literals cause parser ambiguity' => sub {
    SKIP: {
        skip 'Negative literals cause parser to create multiple Return nodes (fatal error)', 4;
        # Parser creates 4 different Return nodes for `return -5;`
        # This is a grammar ambiguity issue, not an interpreter issue
        # test_against_perl('return -5;', 'Unary negation of positive literal');
        # test_against_perl('return -(-5);', 'Double negation');
        # test_against_perl('return -5 + 3;', 'Addition with negative literal');
        # test_against_perl('return -10 / 2;', 'Division with negative literal');
    }
};

subtest 'Variable reassignment' => sub {
    test_against_perl('my $x = 5; $x = 10; return $x;', 'Simple reassignment');
    test_against_perl('my $x = 5; $x = 0 - 5; return $x;', 'Reassignment with arithmetic');
    test_against_perl('my $x = 5; my $y = 10; $x = $y; return $x;', 'Reassignment from another variable');
    test_against_perl('my $x = 5; $x = 10; $x = 15; return $x;', 'Multiple reassignments');
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

subtest 'TODO: Control flow issues' => sub {
    TODO: {
        local $TODO = 'Assignment in if branch with true condition does not execute correctly';
        test_against_perl('my $x = 5; my $result = 0; if ($x > 0) { $result = 10; } return $result;',
            'If with true condition, assign in branch');
    }

    SKIP: {
        skip 'IR construction for if/else creates malformed graph with multiple Return nodes (fatal error)', 4;
        # Error: "Malformed IR graph: found multiple Return nodes but none have __CONTROL_PLACEHOLDER__"
        # These tests would cause process exit, so skipped for now:
        # test_against_perl('my $x = 5; my $result; if ($x > 0) { $result = 10; } else { $result = 20; } return $result;', 'If-else with true condition');
        # test_against_perl('my $x = 0; my $result; if ($x > 0) { $result = 10; } else { $result = 20; } return $result;', 'If-else with false condition');
        # test_against_perl('if (1) { return 42; } else { return -42; }', 'If with literal true condition, return in branches');
        # test_against_perl('if (0) { return 42; } else { return -42; }', 'If with literal false condition, return in branches');
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
