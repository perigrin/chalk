# ABOUTME: Tests for arithmetic operator precedence handling
# ABOUTME: Verifies correct evaluation order for +, *, and parentheses

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(blessed);

use_ok('Chalk::Parser');
use_ok('Chalk::Grammar');
use_ok('Chalk::Semiring::ChalkIR');

# Helper to create parser
sub make_parser {
    open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Can't open grammar: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);

    return Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );
}

# Helper to extract numeric result from parsed code
sub extract_result {
    my ($result) = @_;

    return undef unless $result && $result->can('context');
    my $ctx = $result->context;
    return undef unless $ctx && $ctx->can('focus');
    my $winning_node = $ctx->focus;
    return undef unless blessed($winning_node) && $winning_node->can('id');

    # For Return nodes, extract the value
    if ($winning_node->op eq 'Return' && $winning_node->can('value')) {
        my $val = $winning_node->value;
        if ($val && $val->can('op') && $val->op eq 'Constant' && $val->can('value')) {
            return $val->value;
        }
    }
    return undef;
}

# Test cases for arithmetic precedence
my @tests = (
    # Basic operator ordering tests
    { code => 'return 2 * 3 + 1;', expected => 7, desc => 'multiply first (2*3)+1' },
    { code => 'return 1 + 2 * 3;', expected => 7, desc => 'add first 1+(2*3)' },

    # Chained operators - same precedence
    { code => 'return 1 + 2 + 3;', expected => 6, desc => 'chained addition' },
    { code => 'return 2 * 3 * 4;', expected => 24, desc => 'chained multiplication' },

    # Chained operators - mixed precedence
    { code => 'return 1 + 2 * 3 + 4;', expected => 11, desc => 'mixed chain: 1+(2*3)+4' },
    { code => 'return 2 * 3 + 4 * 5;', expected => 26, desc => 'two multiplies: (2*3)+(4*5)' },

    # Triple operators with precedence
    { code => 'return 1 + 2 * 3 * 4;', expected => 25, desc => 'triple: 1+(2*3*4)' },
    { code => 'return 2 * 3 * 4 + 1;', expected => 25, desc => 'triple reversed: (2*3*4)+1' },

    # Subtraction (same precedence as addition, left-associative)
    { code => 'return 10 - 3 - 2;', expected => 5, desc => 'left-assoc subtraction: (10-3)-2' },
    { code => 'return 10 - 2 * 3;', expected => 4, desc => 'subtract after multiply: 10-(2*3)' },

    # Division (same precedence as multiplication)
    { code => 'return 12 / 3 / 2;', expected => 2, desc => 'left-assoc division: (12/3)/2' },
    { code => 'return 1 + 12 / 3;', expected => 5, desc => 'add after divide: 1+(12/3)' },
);

# Parentheses override precedence (Issue #213)
my @paren_tests = (
    { code => 'return (1 + 2) * 3;', expected => 9, desc => 'parentheses: (1+2)*3' },
    { code => 'return 3 * (1 + 2);', expected => 9, desc => 'parentheses after: 3*(1+2)' },
    { code => 'return (2 + 3) * (4 + 1);', expected => 25, desc => 'double parens: (2+3)*(4+1)' },
);

# Run passing tests
for my $test (@tests) {
    subtest $test->{desc} => sub {
        my $parser = make_parser();

        diag "Parsing: $test->{code}";
        my $result = $parser->parse_string($test->{code});

        ok($result, 'Parse succeeded');

        my $actual = extract_result($result);
        if (defined $actual) {
            is($actual, $test->{expected}, "Correct value: $test->{expected}");
        } else {
            fail("Could not extract result from parse");
        }
    };
}

# Run parentheses tests (Issue #213)
for my $test (@paren_tests) {
    subtest $test->{desc} => sub {
        my $parser = make_parser();

        diag "Parsing: $test->{code}";
        my $result = $parser->parse_string($test->{code});

        ok($result, 'Parse succeeded');

        my $actual = extract_result($result);
        if (defined $actual) {
            is($actual, $test->{expected}, "Correct value: $test->{expected}");
        } else {
            fail("Could not extract result from parse");
        }
    };
}

done_testing();
