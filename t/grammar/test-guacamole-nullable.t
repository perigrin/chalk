#!/usr/bin/env perl
# ABOUTME: Test Guacamole-style nullable and optional production patterns
# ABOUTME: Stress test nullability analysis with complex optional syntax
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Optional semicolon patterns' => sub {
    # Pattern where semicolons are optional in many contexts
    my $grammar = Grammar->build_grammar(
        [ 'Program' => ['StatementList'] ],
        [ 'StatementList' => ['Statement'] ],
        [ 'StatementList' => [qw(Statement OptSemi StatementList)] ],
        [ 'OptSemi' => [';'] ],
        [ 'OptSemi' => [] ],  # Epsilon production - optional semicolon
        [ 'Statement' => ['cmd'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Statements without semicolons
    my $result = $parser->parse_string('cmdcmdcmd');
    ok $result, 'Parse statements without semicolons';

    # Statements with some semicolons
    $result = $parser->parse_string('cmd;cmdcmd');
    ok $result, 'Parse statements with some semicolons';

    # All statements with semicolons
    $result = $parser->parse_string('cmd;cmd;cmd');
    ok $result, 'Parse all statements with semicolons';
};

subtest 'Optional parameter lists' => sub {
    # Pattern like function calls with optional parameter lists
    my $grammar = Grammar->build_grammar(
        [ 'FuncCall' => [qw(name ( ParamList ))] ],
        [ 'FuncCall' => [qw(name ( ))] ],  # Empty params
        [ 'ParamList' => ['Param'] ],
        [ 'ParamList' => [qw(Param , ParamList)] ],
        [ 'Param' => ['arg'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Function with no parameters
    my $result = $parser->parse_string('name()');
    ok $result, 'Parse function with no parameters';

    # Function with one parameter
    $result = $parser->parse_string('name(arg)');
    ok $result, 'Parse function with one parameter';

    # Function with multiple parameters
    $result = $parser->parse_string('name(arg,arg,arg)');
    ok $result, 'Parse function with multiple parameters';
};

subtest 'Nested optional structures' => sub {
    # Complex nesting like Guacamole conditional expressions
    my $grammar = Grammar->build_grammar(
        [ 'IfStmt' => [qw(if ( Expr ) Block ElseClause)] ],
        [ 'IfStmt' => [qw(if ( Expr ) Block)] ],  # No else
        [ 'ElseClause' => [qw(else Block)] ],
        [ 'ElseClause' => [qw(else IfStmt)] ],  # elsif chain
        [ 'Block' => [qw({ StmtList })] ],
        [ 'Block' => [qw({ })] ],  # Empty block
        [ 'StmtList' => ['stmt'] ],
        [ 'StmtList' => [qw(stmt StmtList)] ],
        [ 'Expr' => ['test'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Simple if without else
    my $result = $parser->parse_string('if(test){stmt}');
    ok $result, 'Parse simple if without else';

    # If with else
    $result = $parser->parse_string('if(test){stmt}else{stmt}');
    ok $result, 'Parse if with else';

    # If with elsif chain
    $result = $parser->parse_string('if(test){}elseif(test){stmt}');
    ok $result, 'Parse if with elsif chain';

    # Empty blocks
    $result = $parser->parse_string('if(test){}else{}');
    ok $result, 'Parse if/else with empty blocks';
};

subtest 'Highly nullable expression chains' => sub {
    # Pattern with many nullable elements that could cause combinatorial explosion
    my $grammar = Grammar->build_grammar(
        [ 'Expr' => [qw(Prefix Term Suffix)] ],
        [ 'Prefix' => ['!'] ],
        [ 'Prefix' => ['-'] ],
        [ 'Prefix' => [] ],  # Nullable
        [ 'Term' => ['var'] ],
        [ 'Term' => [qw(( Expr ))] ],
        [ 'Suffix' => [qw([ Index ])] ],
        [ 'Suffix' => [qw(. Method)] ],
        [ 'Suffix' => [] ],  # Nullable
        [ 'Index' => ['idx'] ],
        [ 'Method' => ['method'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # Minimal expression
    my $result = $parser->parse_string('var');
    ok $result, 'Parse minimal expression';

    # Expression with prefix
    $result = $parser->parse_string('!var');
    ok $result, 'Parse expression with prefix';

    # Expression with suffix
    $result = $parser->parse_string('var[idx]');
    ok $result, 'Parse expression with suffix';

    # Full expression
    $result = $parser->parse_string('-var.method');
    ok $result, 'Parse full expression';

    # Parenthesized with nullable elements
    $result = $parser->parse_string('(var)');
    ok $result, 'Parse parenthesized expression';

    # Complex nested case
    $result = $parser->parse_string('!(-var[idx]).method');
    ok $result, 'Parse complex nested expression';
};

subtest 'Performance with nullable chains' => sub {
    # Test that our nullability optimization handles complex cases efficiently
    my $grammar = Grammar->build_grammar(
        [ 'S' => [qw(A B C D E)] ],
        [ 'A' => ['a'] ],
        [ 'A' => [] ],  # Nullable
        [ 'B' => ['b'] ],
        [ 'B' => [] ],  # Nullable
        [ 'C' => ['c'] ],
        [ 'C' => [] ],  # Nullable
        [ 'D' => ['d'] ],
        [ 'D' => [] ],  # Nullable
        [ 'E' => ['e'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    # All elements present
    my $result = $parser->parse_string('abcde');
    ok $result, 'Parse with all elements present';

    # Some elements missing (testing nullable handling)
    $result = $parser->parse_string('ace');  # B and D are nullable
    ok $result, 'Parse with some nullable elements missing';

    # Minimal case
    $result = $parser->parse_string('e');  # A, B, C, D all nullable
    ok $result, 'Parse with maximum nullable elements';

    # Test with Boolean semiring for performance
    my $bool_parser = Parser->new(
        grammar => $grammar,
        semiring => BooleanSemiring->new()
    );

    $result = $bool_parser->parse_string('e');
    ok $result, 'Boolean parse with maximum nullable elements';
    isa_ok $result, 'BooleanElement';
};