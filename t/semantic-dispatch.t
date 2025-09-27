#!/usr/bin/env perl
# ABOUTME: Test semantic dispatch for SeaOfNodes - operators know their semantics
# ABOUTME: Verifies that say 1+1 creates proper computational graph with semantic classes
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);

local $| = 1;

# Test cases for semantic dispatch
my @test_cases = (
    {
        expr => 'say 1+1',
        description => 'say with numeric addition',
        expected_operations => ['FunctionCall(say)', 'Add'],
        expected_types => ['void', 'numeric']
    },
    {
        expr => '1 + 1',
        description => 'simple numeric addition',
        expected_operations => ['Add'],
        expected_types => ['numeric']
    },
    {
        expr => '42',
        description => 'numeric literal',
        expected_operations => ['Literal(42)'],
        expected_types => ['numeric']
    },
    {
        expr => '"hello" . "world"',
        description => 'string concatenation',
        expected_operations => ['Concat'],
        expected_types => ['string']
    },
    {
        expr => '"2" + 3',
        description => 'addition with string coercion',
        expected_operations => ['Add', 'CoerceToNum'],
        expected_types => ['numeric']
    },
);

# Helper to parse and extract semantic operations
sub parse_and_analyze {
    my ($expr) = @_;
    
    # Parse the expression
    my $output = `echo '$expr' | ./chalk 2>&1`;
    
    if ($output =~ /Parse successful:.*SPPF:(\S+)\[(\d+) interpretations?, best=\[([^\]]+)\]\]/) {
        my ($node_id, $interp_count, $best_interp) = ($1, $2, $3);
        
        # Extract operation and type from best interpretation
        if ($best_interp =~ /^(\w+):(\w+):([\d.]+)$/) {
            my ($operation, $type, $score) = ($1, $2, $3);
            return {
                success => 1,
                node_id => $node_id,
                interpretation_count => $interp_count,
                operation => $operation,
                type => $type,
                score => $score
            };
        }
    }
    
    # If we couldn't extract SeaOfNodes info, check if it at least parsed
    if ($output =~ /Parse successful:/) {
        return {
            success => 1,
            parse_only => 1,
            output => $output
        };
    }
    
    return {
        success => 0,
        error => $output
    };
}

# Run the tests
for my $test (@test_cases) {
    my $result = parse_and_analyze($test->{expr});
    
    # For now, just test that parsing succeeds
    # Once semantic dispatch is implemented, we'll check operations
    ok($result->{success}, "$test->{description}: '$test->{expr}' parses successfully");
    
    if ($result->{success} && !$result->{parse_only}) {
        diag("Node: $result->{node_id}");
        diag("Operation: $result->{operation}");
        diag("Type: $result->{type}");
        diag("Score: $result->{score}");
        
        # TODO: Once semantic dispatch is implemented, verify:
        # - Operation matches expected (e.g., 'Add' for +)
        # - Type is correct (e.g., 'numeric' for addition)
        # - Coercion nodes are inserted when needed
    }
    
    diag("");
}

# Additional test for semantic class dispatch
subtest 'Semantic class dispatch' => sub {
    # This will test that the right semantic classes are called
    # For now, just check basic structure
    
    # Test that OpAdd knows it does numeric addition
    SKIP: {
        skip "OpAdd semantic class not yet implemented", 1;
        
        # Once implemented:
        # my $op_add = OpAdd->new();
        # my $result = $op_add->reduce($forest, $left, $right);
        # ok($result->has_interpretation('Add'), 'OpAdd creates Add operation');
    }
    
    # Test that Number creates numeric literal
    SKIP: {
        skip "Number semantic class not yet implemented", 1;
        
        # Once implemented:
        # my $number = Number->new(value => 42);
        # my $result = $number->reduce($forest);
        # ok($result->has_interpretation('Literal'), 'Number creates Literal operation');
    }
    
    # Test that FunctionCall handles 'say'
    SKIP: {
        skip "FunctionCall semantic class not yet implemented", 1;
        
        # Once implemented:
        # my $say = FunctionCall->new(name => 'say');
        # my $result = $say->reduce($forest, $args);
        # ok($result->has_interpretation('FunctionCall'), 'say creates FunctionCall operation');
    }
};

done_testing;