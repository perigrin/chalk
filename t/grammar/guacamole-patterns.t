#!/usr/bin/env perl
# ABOUTME: Test complex grammar patterns found in Guacamole Perl parser
# ABOUTME: Verify chalk parser handles real-world grammar complexity
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;

subtest 'Statement sequence patterns' => sub {
    # Based on Guacamole: StatementSeq ::= Statement | Statement Semicolon | Statement Semicolon StatementSeq
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'StatementSeq' => ['Statement'] ],
            [ 'StatementSeq' => [qw(Statement Semicolon)] ],
            [ 'StatementSeq' => [qw(Statement Semicolon StatementSeq)] ],  # Right-recursive
            [ 'Statement' => ['print'] ],
            [ 'Semicolon' => [';'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # Single statement
    my $result = $parser->parse_string('print');
    ok $result, 'Parse single statement';

    # Statement with semicolon
    $result = $parser->parse_string('print;');
    ok $result, 'Parse statement with semicolon';

    # Multiple statements
    $result = $parser->parse_string('print;print');
    ok $result, 'Parse statement sequence';

    # Long sequence
    $result = $parser->parse_string('print;print;print');
    ok $result, 'Parse long statement sequence';
};

subtest 'Complex for statement patterns' => sub {
    # Simplified version of Guacamole ForStatement with multiple alternatives
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'ForStatement' => [qw(for LParen Statement Semicolon Statement Semicolon Statement RParen Block)] ],
            [ 'ForStatement' => [qw(for LParen Statement Semicolon Statement Semicolon RParen Block)] ],
            [ 'ForStatement' => [qw(for LParen Semicolon Statement Semicolon Statement RParen Block)] ],
            [ 'ForStatement' => [qw(for LParen Semicolon Semicolon Statement RParen Block)] ],
            [ 'ForStatement' => [qw(for LParen Expression RParen Block)] ],
            [ 'Statement' => ['var'] ],
            [ 'Expression' => ['expr'] ],
            [ 'Block' => ['{}'] ],
            [ 'LParen' => ['('] ],
            [ 'RParen' => [')'] ],
            [ 'Semicolon' => [';'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # C-style for loop
    my $result = $parser->parse_string('for(var;var;var){}');
    ok $result, 'Parse C-style for loop';

    # For loop with missing init
    $result = $parser->parse_string('for(;var;var){}');
    ok $result, 'Parse for loop with missing init';

    # For loop with missing condition and increment
    $result = $parser->parse_string('for(;;var){}');
    ok $result, 'Parse for loop with missing condition and increment';

    # Foreach-style loop
    $result = $parser->parse_string('for(expr){}');
    ok $result, 'Parse foreach-style loop';
};

subtest 'Deeply nested optional elements' => sub {
    # Pattern with many optional elements like Guacamole UseStatement
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'UseStatement' => [qw(use Class Version Expression)] ],
            [ 'UseStatement' => [qw(use Class Version)] ],
            [ 'UseStatement' => [qw(use Class Expression)] ],
            [ 'UseStatement' => [qw(use Version)] ],
            [ 'UseStatement' => [qw(use Class)] ],
            [ 'Class' => ['Module'] ],
            [ 'Version' => ['v1.0'] ],
            [ 'Expression' => ['args'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # Full use statement
    my $result = $parser->parse_string('useModulev1.0args');
    ok $result, 'Parse full use statement';

    # Use with version only
    $result = $parser->parse_string('usev1.0');
    ok $result, 'Parse use with version only';

    # Use with module only
    $result = $parser->parse_string('useModule');
    ok $result, 'Parse use with module only';

    # Use with module and args
    $result = $parser->parse_string('useModuleargs');
    ok $result, 'Parse use with module and args';
};

subtest 'Highly ambiguous expression hierarchy' => sub {
    # Simplified version of Guacamole's expression precedence
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'Expression' => [qw(Expression + Expression)] ],
            [ 'Expression' => [qw(Expression * Expression)] ],
            [ 'Expression' => [qw(Expression - Expression)] ],
            [ 'Expression' => [qw(Expression / Expression)] ],
            [ 'Expression' => [qw(Expression % Expression)] ],
            [ 'Expression' => [qw(Expression ** Expression)] ],
            [ 'Expression' => [qw(Expression && Expression)] ],
            [ 'Expression' => [qw(Expression || Expression)] ],
            [ 'Expression' => [qw(( Expression ))] ],
            [ 'Expression' => ['term'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # Simple expression
    my $result = $parser->parse_string('term');
    ok $result, 'Parse simple term';

    # Binary operation
    $result = $parser->parse_string('term+term');
    ok $result, 'Parse binary addition';

    # Highly ambiguous expression
    $result = $parser->parse_string('term+term*term-term');
    ok $result, 'Parse highly ambiguous expression';

    # Expression with parentheses
    $result = $parser->parse_string('(term+term)*term');
    ok $result, 'Parse parenthesized expression';

    # Complex mixed operators
    $result = $parser->parse_string('term**term&&term||term');
    ok $result, 'Parse complex mixed operators';

    # Test with SPPF semiring for ambiguous handling
    my $sppf_parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::SPPFViterbiSemiring->new()
    );

    $result = $sppf_parser->parse_string('term+term*term');
    ok $result, 'SPPF parse ambiguous expression';
    isa_ok $result, 'Chalk::Semiring::SPPFViterbiElement';
};

subtest 'Recursive block structures' => sub {
    # Pattern like Guacamole BlockStatement with nested blocks
    my $grammar = Chalk::Grammar->build_grammar(
        rules => [
            [ 'Block' => [qw({ StatementList })] ],
            [ 'Block' => [qw({ })] ],  # Empty block
            [ 'StatementList' => ['Statement'] ],
            [ 'StatementList' => [qw(Statement StatementList)] ],
            [ 'Statement' => ['simple'] ],
            [ 'Statement' => ['Block'] ],  # Recursive: statements can contain blocks
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    # Empty block
    my $result = $parser->parse_string('{}');
    ok $result, 'Parse empty block';

    # Simple block
    $result = $parser->parse_string('{simple}');
    ok $result, 'Parse simple block';

    # Nested blocks
    $result = $parser->parse_string('{simple{simple}simple}');
    ok $result, 'Parse nested blocks';

    # Deeply nested blocks
    $result = $parser->parse_string('{{{simple}}}');
    ok $result, 'Parse deeply nested blocks';
};