#!/usr/bin/env perl
# ABOUTME: Test parsing of eval block syntax (exception handling try-catch)
# ABOUTME: Tests eval { ... } blocks with various statement patterns

use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");


# Initialize parser with grammar and semiring
my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test 1: Simple eval block with single statement
{
    my $code = 'eval { $x = 1 }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse simple eval block: $code")
        or diag("Failed to parse: $code");
}

# Test 2: Eval block with multiple statements separated by semicolons
{
    my $code = 'eval { $x = 1; $y = 2 }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block with multiple statements: $code")
        or diag("Failed to parse: $code");
}

# Test 3: Eval block with statement and return value
{
    my $code = 'eval { $x = 1; 1 }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block with return value: $code")
        or diag("Failed to parse: $code");
}

# Test 4: Eval block in if condition (the actual failing pattern)
{
    my $code = 'if (eval { $x = 1; 1 }) { print "ok" }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block in if condition: $code")
        or diag("Failed to parse: $code");
}

# Test 5: The exact failing line from rs.t
{
    my $code = 'if (eval {$/ = \0; 1}) { print "not ok" }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse exact rs.t eval pattern: $code")
        or diag("Failed to parse: $code");
}

# Test 6: Eval block in if-else
{
    my $code = 'if (eval { $x = 1; 1 }) { print "ok" } else { print "not ok" }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block in if-else: $code")
        or diag("Failed to parse: $code");
}

# Test 7: Eval block as expression in assignment
{
    my $code = 'my $result = eval { $x + 1 }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block in assignment: $code")
        or diag("Failed to parse: $code");
}

# Test 8: Eval block with complex expressions
{
    my $code = 'eval { $hash{key} = $array[0]; return $value }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block with complex expressions: $code")
        or diag("Failed to parse: $code");
}

# Test 9: Nested eval blocks
{
    my $code = 'eval { eval { $x = 1 } }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse nested eval blocks: $code")
        or diag("Failed to parse: $code");
}

# Test 10: Eval block with empty body
{
    my $code = 'eval { }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse empty eval block: $code")
        or diag("Failed to parse: $code");
}

# Test 11: Eval block with bareword die
{
    my $code = 'eval { die }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse eval block with die: $code")
        or diag("Failed to parse: $code");
}

# Test 12: Multiple eval blocks in sequence
{
    my $code = 'eval { $x = 1 }; eval { $y = 2 }';
    my $result = $parser->parse_string($code);
    ok($result, "Parse multiple eval blocks: $code")
        or diag("Failed to parse: $code");
}

done_testing();
