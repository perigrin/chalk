# ABOUTME: Diagnostic test for Issue #199 - trace precedence handling
# ABOUTME: Traces why valid outer parse 1+(2*3) fails to complete

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

# Test both orderings
my @tests = (
    { code => 'return 2 * 3 + 1;', expected => 7, desc => 'multiply first (2*3)+1' },
    { code => 'return 1 + 2 * 3;', expected => 7, desc => 'add first 1+(2*3)' },
);

for my $test (@tests) {
    subtest $test->{desc} => sub {
        my $parser = make_parser();

        diag "Parsing: $test->{code}";
        my $result = $parser->parse_string($test->{code});

        ok($result, 'Parse succeeded');

        # Get the context and focus
        if ($result && $result->can('context')) {
            my $ctx = $result->context;
            if ($ctx && $ctx->can('focus')) {
                my $winning_node = $ctx->focus;
                if (blessed($winning_node) && $winning_node->can('id')) {
                    diag "Winning node: " . $winning_node->op . " id=" . $winning_node->id;

                    # For Return nodes, check the value
                    if ($winning_node->op eq 'Return') {
                        diag "Got Return node";
                        if ($winning_node->can('value')) {
                            my $val = $winning_node->value;
                            diag "value_node: " . (defined $val ? ref($val) : "undef");
                            if ($val && $val->can('op')) {
                                diag "Return value op: " . $val->op;
                                if ($val->op eq 'Constant' && $val->can('value')) {
                                    my $actual = $val->value;
                                    diag "Actual value: $actual (expected: $test->{expected})";
                                    is($actual, $test->{expected}, "Correct value");
                                } else {
                                    diag "Non-constant return value: " . $val->op;
                                    fail("Expected constant value, got " . $val->op);
                                }
                            } else {
                                diag "value_node has no op method";
                                fail("value_node has no op");
                            }
                        } else {
                            diag "Return has no value method";
                            fail("Return has no value method");
                        }
                    } else {
                        diag "Winning node is not Return: " . $winning_node->op;
                        fail("Expected Return node");
                    }
                } else {
                    diag "No winning node with id method (got: " . (blessed($winning_node) // "not blessed") . ")";
                    fail("No winning IR node");
                }
            } else {
                diag "No focus in context";
                fail("No focus");
            }
        } else {
            diag "No context in result";
            fail("No context");
        }
    };
}

done_testing();
