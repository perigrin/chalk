#!/usr/bin/env perl
# ABOUTME: Test modern Perl syntax patterns used in chalk
# ABOUTME: Isolate and fix each syntax element individually
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Variable types' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'VarDecl' => [qw(field Variable ;)] ],
        [ 'Variable' => ['$scalar'] ],
        [ 'Variable' => ['@array'] ],
        [ 'Variable' => ['%hash'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse('field', '$scalar', ';');
    ok $result, 'Parse scalar variable';
    
    $result = $parser->parse('field', '@array', ';');
    ok $result, 'Parse array variable';
    
    $result = $parser->parse('field', '%hash', ';');
    ok $result, 'Parse hash variable';
};

subtest 'Postfix dereference syntax' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Expression' => [qw(Variable -> PostfixDeref)] ],
        [ 'Expression' => ['Variable'] ],
        [ 'PostfixDeref' => ['@*'] ],
        [ 'PostfixDeref' => ['%*'] ],
        [ 'Variable' => ['$var'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse('$var');
    ok $result, 'Parse simple variable';
    
    $result = $parser->parse('$var', '->', '@*');
    ok $result, 'Parse postfix array dereference';
    
    $result = $parser->parse('$var', '->', '%*');
    ok $result, 'Parse postfix hash dereference';
};

subtest 'String concatenation' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Expression' => [qw(Expression . Expression)] ],
        [ 'Expression' => ['String'] ],
        [ 'Expression' => ['Variable'] ],
        [ 'String' => ['"literal"'] ],
        [ 'String' => ['|'] ],
        [ 'Variable' => ['$var'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse('"literal"');
    ok $result, 'Parse string literal';
    
    $result = $parser->parse('$var', '.', '"literal"');
    ok $result, 'Parse string concatenation';
    
    $result = $parser->parse('"literal"', '.', '$var', '.', '|');
    ok $result, 'Parse complex string concatenation';
};

subtest 'Method calls and constructors' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Expression' => [qw(Class -> new ( ArgList ))] ],
        [ 'Expression' => [qw(Class -> new ( ))] ],
        [ 'Expression' => [qw(Variable -> method ( ArgList ))] ],
        [ 'Expression' => [qw(Variable -> method ( ))] ],
        [ 'ArgList' => ['Arg'] ],
        [ 'ArgList' => ['Arg', ',', 'ArgList'] ],
        [ 'Arg' => [qw(Key => Value)] ],
        [ 'Arg' => ['Value'] ],
        [ 'Key' => ['key'] ],
        [ 'Value' => ['value'] ],
        [ 'Class' => ['Constructor'] ],
        [ 'Variable' => ['$obj'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse('Constructor', '->', 'new', '(', ')');
    ok $result, 'Parse constructor with no args';
    
    $result = $parser->parse('Constructor', '->', 'new', '(', 'value', ')');
    ok $result, 'Parse constructor with simple arg';
    
    $result = $parser->parse('Constructor', '->', 'new', '(', 'key', '=>', 'value', ')');
    ok $result, 'Parse constructor with key-value arg';
    
    $result = $parser->parse('$obj', '->', 'method', '(', 'key', '=>', 'value', ',', 'value', ')');
    ok $result, 'Parse method call with mixed args';
};

subtest 'Hash subscript and assignment' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Expression' => [qw(Variable { Key } //= Value)] ],
        [ 'Expression' => [qw(Variable { Key })] ],
        [ 'Variable' => ['%hash'] ],
        [ 'Variable' => ['$hash'] ],
        [ 'Key' => ['$key'] ],
        [ 'Value' => ['value'] ],
    );
    
    my $parser = Parser->new(grammar => $grammar);
    
    my $result = $parser->parse('%hash', '{', '$key', '}');
    ok $result, 'Parse hash subscript';
    
    $result = $parser->parse('$hash', '{', '$key', '}', '//=', 'value');
    ok $result, 'Parse hash assignment with //= operator';
};