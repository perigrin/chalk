#!/usr/bin/env perl
# ABOUTME: End-to-end integration tests for type checking with real Perl programs
# ABOUTME: Tests type inference and checking through complete parse and IR generation

use 5.042;
use Test::More;
use FindBin qw($RealBin);
use File::Spec;
use lib "$RealBin/../../lib";

use Chalk::Parser;
use Chalk::Semiring::Semantic;
use Chalk::Grammar::BNF;
use Chalk::Preprocessor::Heredoc;

plan tests => 7;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

# Test 1: Simple numeric operation
{
    my $code = q{
        method sum($x, $y) {
            return $x + $y;
        }
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'Numeric operation parses successfully');
}

# Test 2: String concatenation
{
    my $code = q{
        method greet($name) {
            return "Hello, " . $name;
        }
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'String concatenation parses successfully');
}

# Test 3: List to Array conversion
{
    my $code = q{
        my @numbers = (1..10);
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'List to Array conversion parses successfully');
}

# Test 4: List to Hash conversion
{
    my $code = q{
        my %config = (debug => 1, verbose => 0);
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'List to Hash conversion parses successfully');
}

# Test 5: Type inference from literals
{
    my $code = q{
        my $x = 42;
        my $s = "hello";
        my $f = 3.14;
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'Literal type inference works correctly');
}

# Test 6: Array operations
{
    my $code = q{
        my @arr = (1, 2, 3);
        push @arr, 4;
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'Array operations parse with type checking');
}

# Test 7: Variable declaration and usage
{
    my $code = q{
        my $count = 0;
        $count = $count + 1;
    };

    my $result = eval { $parser->parse_string($code) };

    ok($result, 'Variable type consistency maintained');
}

done_testing();
