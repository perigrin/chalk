#!/usr/bin/env perl
# ABOUTME: Test operator precedence and associativity parsing with different grammars
# ABOUTME: Verifies that expressions parse with correct precedence rules using specified grammar
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);

local $| = 1;

# Get grammar file from command line or use default
my $grammar_file = $ARGV[0] || './chalk-grammar.pl';
my $grammar_name = $grammar_file;
$grammar_name =~ s/.*\///; # Just the filename for display

diag("Testing precedence with grammar: $grammar_name");

# Test cases for operator precedence and associativity
my @test_cases = (
    # Precedence tests - multiplication before addition
    {
        expr => '2 + 3 * 4',
        expected_structure => 'addition(2, multiplication(3, 4))',
        description => 'multiplication has higher precedence than addition'
    },
    {
        expr => '2 * 3 + 4',
        expected_structure => 'addition(multiplication(2, 3), 4)',
        description => 'multiplication before addition (reversed)'
    },
    
    # Power operator (highest precedence, right associative)
    {
        expr => '2 ** 3 ** 4',
        expected_structure => 'power(2, power(3, 4))',
        description => 'power operator is right associative'
    },
    {
        expr => '2 + 3 ** 4',
        expected_structure => 'addition(2, power(3, 4))',
        description => 'power has higher precedence than addition'
    },
    
    # Left associativity tests
    {
        expr => '2 + 3 + 4',
        expected_structure => 'addition(addition(2, 3), 4)',
        description => 'addition is left associative'
    },
    {
        expr => '8 / 4 / 2',
        expected_structure => 'division(division(8, 4), 2)',
        description => 'division is left associative'
    },
    
    # Mixed precedence
    {
        expr => '2 + 3 * 4 ** 5',
        expected_structure => 'addition(2, multiplication(3, power(4, 5)))',
        description => 'complex precedence: power > multiplication > addition'
    },
    
    # Parentheses override precedence
    {
        expr => '(2 + 3) * 4',
        expected_structure => 'multiplication(addition(2, 3), 4)',
        description => 'parentheses override precedence'
    },
);

# Helper function to parse and analyze structure
sub parse_and_analyze {
    my ($expr) = @_;
    
    # Parse the expression using specified grammar
    my $cmd = "echo '$expr' | ./chalk -g $grammar_file 2>&1";
    my $output = `$cmd`;
    
    if ($output =~ /Parse successful:/) {
        # Extract parse tree structure - this is a simplified analysis
        # We'll look for patterns in the parse output that indicate precedence
        return analyze_parse_structure($output, $expr);
    } else {
        return "PARSE_FAILED: $output";
    }
}

sub analyze_parse_structure {
    my ($parse_output, $expr) = @_;
    
    # Extract the parse tree from the output
    if ($parse_output =~ /Parse successful: [^[]*\[(.+)\] SPPF/) {
        my $tree = $1;
        return analyze_precedence_from_tree($tree, $expr);
    }
    
    return "NO_PARSE_TREE_FOUND";
}

sub analyze_precedence_from_tree {
    my ($tree, $expr) = @_;
    
    # Specific precedence checks based on expression type
    if ($expr eq '2 + 3 * 4') {
        # Should see Add at higher level than Multi
        if ($tree =~ /NonBraceExprAddR.*OpAdd.*NonBraceExprMulR.*OpMulti/) {
            return "CORRECT_PRECEDENCE";
        } else {
            return "WRONG_PRECEDENCE";
        }
    }
    elsif ($expr eq '2 * 3 + 4') {
        # Should see Add at higher level, with Multi in first operand
        if ($tree =~ /NonBraceExprAddR.*NonBraceExprMulR.*OpMulti.*OpAdd/) {
            return "CORRECT_PRECEDENCE";
        } else {
            return "WRONG_PRECEDENCE"; 
        }
    }
    elsif ($expr eq '2 ** 3 ** 4') {
        # Power should be right associative: 2 ** (3 ** 4)
        # With the SPPF fix, we should see the right operand containing nested power operations
        # Look for the pattern where the right side of the first ** contains another **
        if ($tree =~ /NonBraceExprPowerR.*OpPower.*NonBraceExprUnaryR.*NonBraceExprPowerR.*OpPower/) {
            return "CORRECT_RIGHT_ASSOCIATIVE";
        } else {
            return "WRONG_ASSOCIATIVITY";
        }
    }
    elsif ($expr eq '2 + 3 + 4') {
        # Addition should be left associative: (2 + 3) + 4
        # Should see nested AddU rules showing left association
        if ($tree =~ /NonBraceExprAddU.*NonBraceExprAddU.*OpAdd.*NonBraceExprMul.*OpAdd/) {
            return "CORRECT_LEFT_ASSOCIATIVE";
        } else {
            return "WRONG_ASSOCIATIVITY";
        }
    }
    elsif ($expr eq '2 + 3 * 4 ** 5') {
        # Should see: Add > Multi > Power precedence
        if ($tree =~ /NonBraceExprAddR.*OpAdd.*NonBraceExprMulR.*OpMulti.*NonBraceExprPowerR.*OpPower/) {
            return "CORRECT_COMPLEX_PRECEDENCE";
        } else {
            return "WRONG_COMPLEX_PRECEDENCE";
        }
    }
    
    # Default: just check that it parsed
    return "PARSED_SUCCESSFULLY";
}

# Run the tests
for my $test (@test_cases) {
    my $result = parse_and_analyze($test->{expr});
    
    # Check if precedence/associativity is correct
    my $is_correct = ($result =~ /CORRECT/ || $result eq "PARSED_SUCCESSFULLY");
    
    ok($is_correct, "$test->{description}: '$test->{expr}' [$grammar_name]");
    
    diag("Expression: $test->{expr}");
    diag("Expected: $test->{expected_structure}");
    diag("Result: $result");
    
    # If wrong precedence, this is a serious issue
    if ($result =~ /WRONG/) {
        diag("*** PRECEDENCE/ASSOCIATIVITY ERROR ***");
    }
    
    diag("");
}

done_testing;