#!/usr/bin/env perl
# ABOUTME: Tests for chalk.bnf - the simplified Chalk-specific grammar
# ABOUTME: Verifies that chalk.bnf can parse restricted Perl subset for compilation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar::BNF;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar file
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');

# Test will fail initially because chalk.bnf doesn't exist yet
my $chalk_grammar;
eval {
    open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;
    $chalk_grammar = Chalk::Grammar->build_from_bnf($content, 'Program');
};

my $error = $@;
if ($error) {
    fail "Failed to load chalk.bnf: $error";
    skip_all "Cannot continue without chalk.bnf grammar";
}

ok $chalk_grammar, 'chalk.bnf grammar loaded successfully';

subtest 'Phase 1: Core Structure - Class declarations' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # Test 1: Simple class with field
    my $code = q{
        class Point {
            field $x :param :reader;
        }
    };
    my $result = $parser->parse_string($code);
    ok $result, 'Parse simple class with field and attributes';

    # Test 2: Class with multiple fields
    $code = q{
        class Point {
            field $x :param :reader;
            field $y :param :reader;
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse class with multiple fields';

    # Test 3: Class with method
    $code = q{
        class Point {
            field $x :param :reader;
            method calculate($value) {
                return $value;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse class with field and method';

    # Test 4: Class with ADJUST block
    $code = q{
        class Point {
            field $x :param;
            ADJUST {
                my $temp = $x;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse class with ADJUST block';

    # Test 5: Class with inheritance
    $code = q{
        class ViterbiElement :isa(Element) {
            field $value :param :reader;
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse class with inheritance';
};

subtest 'Phase 1: Core Structure - Use statements' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # Test: use statement with version
    my $code = q{
        use 5.42.0;
        class Point { field $x; }
    };
    my $result = $parser->parse_string($code);
    ok $result, 'Parse program with use version statement';

    # Test: use experimental
    $code = q{
        use experimental qw(class);
        class Point { field $x; }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse program with use experimental';
};

subtest 'Phase 2: Expressions - Arithmetic and comparison' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # Test: Method with arithmetic
    my $code = q{
        class Calculator {
            method calculate($x) {
                my $temp = $x * 2;
                return $temp + 10;
            }
        }
    };
    my $result = $parser->parse_string($code);
    ok $result, 'Parse method with arithmetic expressions';

    # Test: Comparison operators
    $code = q{
        class Comparator {
            method compare($a, $b) {
                return $a == $b;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse method with comparison operator';

    # Test: Method calls
    $code = q{
        class Caller {
            method call_method() {
                my $obj = $self->get_object();
                return $obj->method($x);
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse method with method calls';

    # Test: Array and hash access
    # TODO #173
    todo "complex array/hash subscripting requires additional grammar rules (#173)" => sub {
        $code = q{
            class Accessor {
                method access() {
                    my @arr = [1, 2, 3];
                    my %hash = {key => 'value'};
                    my $elem = $arr[0];
                    my $val = $hash{key};
                    return $elem;
                }
            }
        };
        $result = $parser->parse_string($code);
        ok $result, 'Parse method with array and hash access';
    };
};

subtest 'Phase 3: Control Flow - if/elsif/else' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # Test: if statement
    my $code = q{
        class Classifier {
            method classify($value) {
                if ($value > 0) {
                    return 'positive';
                }
                return 'unknown';
            }
        }
    };
    my $result = $parser->parse_string($code);
    ok $result, 'Parse method with if statement';

    # Test: if/elsif/else chain
    $code = q{
        class Classifier {
            method classify($value) {
                if ($value > 0) {
                    return 'positive';
                } elsif ($value < 0) {
                    return 'negative';
                } else {
                    return 'zero';
                }
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse method with if/elsif/else chain';
};

subtest 'Phase 3: Control Flow - Loops' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # Test: while loop
    my $code = q{
        class Counter {
            method loop() {
                while ($x > 0) {
                    $x = $x - 1;
                }
                return $x;
            }
        }
    };
    my $result = $parser->parse_string($code);
    ok $result, 'Parse method with while loop';

    # Test: for loop
    $code = q{
        class Iterator {
            method iterate() {
                for my $item (@items) {
                    $self->process($item);
                }
                return;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse method with for loop';

    # Test: Control flow keywords
    $code = q{
        class FlowControl {
            method process() {
                for my $item (@items) {
                    next if $item == 0;
                    last if $item > 10;
                    $sum = $sum + $item;
                }
                return $sum;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok $result, 'Parse method with next/last';
};

subtest 'Self-hosting: Parse actual Chalk files' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # Test parsing a simple Chalk module
    # TODO #174
    todo "named constructor arguments require additional grammar rules (#174)" => sub {
        my $simple_module = q{
            use 5.42.0;
            use experimental qw(class);

            class Element {
                field $value :param :reader;

                method new_element() {
                    return Element->new(value => 0);
                }
            }
        };

        my $result = $parser->parse_string($simple_module);
        ok $result, 'Parse simple Chalk module with named arguments';
    };

    # Test a simpler version without named arguments
    my $simple_module = q{
        use 5.42.0;
        use experimental qw(class);

        class Element {
            field $value :param :reader;

            method get_value() {
                return $value;
            }
        }
    };

    my $result = $parser->parse_string($simple_module);
    ok $result, 'Parse simple Chalk module';
};

subtest 'Exclusions: Verify restricted features are NOT parsed' => sub {
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    # These should fail to parse as they're excluded from chalk.bnf
    my $todo = todo "Grammar exclusions not yet implemented - eval STRING, symbolic refs, goto";

    # Test: eval STRING should fail
    my $code = q{
        class Bad {
            method bad() {
                eval "some code";
            }
        }
    };
    my $result = $parser->parse_string($code);
    ok !$result, 'Correctly reject eval STRING';

    # Test: symbolic reference should fail
    $code = q{
        class Bad {
            method bad() {
                my $ref = $$var;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok !$result, 'Correctly reject symbolic references';

    # Test: goto should fail
    $code = q{
        class Bad {
            method bad() {
                goto LABEL;
            }
        }
    };
    $result = $parser->parse_string($code);
    ok !$result, 'Correctly reject goto';
};
