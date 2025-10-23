#!/usr/bin/env perl
# ABOUTME: Test modern Perl syntax patterns used in chalk
# ABOUTME: Isolate and fix each syntax element individually
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Variable types' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'VarDecl' => [qw(field Variable ;)] ],
            [ 'Variable' => ['$scalar'] ],
            [ 'Variable' => ['@array'] ],
            [ 'Variable' => ['%hash'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('field$scalar;');
    ok $result, 'Parse scalar variable';

    $result = $parser->parse_string('field@array;');
    ok $result, 'Parse array variable';

    $result = $parser->parse_string('field%hash;');
    ok $result, 'Parse hash variable';
};

subtest 'Postfix dereference syntax' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'Expression' => [qw(Variable -> PostfixDeref)] ],
            [ 'Expression' => ['Variable'] ],
            [ 'PostfixDeref' => ['@*'] ],
            [ 'PostfixDeref' => ['%*'] ],
            [ 'Variable' => ['$var'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('$var');
    ok $result, 'Parse simple variable';

    $result = $parser->parse_string('$var->@*');
    ok $result, 'Parse postfix array dereference';

    $result = $parser->parse_string('$var->%*');
    ok $result, 'Parse postfix hash dereference';
};

subtest 'String concatenation' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'Expression' => [qw(Expression . Expression)] ],
            [ 'Expression' => ['String'] ],
            [ 'Expression' => ['Variable'] ],
            [ 'String' => ['"literal"'] ],
            [ 'String' => ['|'] ],
            [ 'Variable' => ['$var'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('"literal"');
    ok $result, 'Parse string literal';

    $result = $parser->parse_string('$var."literal"');
    ok $result, 'Parse string concatenation';

    $result = $parser->parse_string('"literal".$var.|');
    ok $result, 'Parse complex string concatenation';
};

subtest 'Method calls and constructors' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
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
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('Constructor->new()');
    ok $result, 'Parse constructor with no args';

    $result = $parser->parse_string('Constructor->new(value)');
    ok $result, 'Parse constructor with simple arg';

    $result = $parser->parse_string('Constructor->new(key=>value)');
    ok $result, 'Parse constructor with key-value arg';

    $result = $parser->parse_string('$obj->method(key=>value,value)');
    ok $result, 'Parse method call with mixed args';
};

subtest 'Hash subscript and assignment' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'Expression' => [qw(Variable { Key } //= Value)] ],
            [ 'Expression' => [qw(Variable { Key })] ],
            [ 'Variable' => ['%hash'] ],
            [ 'Variable' => ['$hash'] ],
            [ 'Key' => ['$key'] ],
            [ 'Value' => ['value'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('%hash{$key}');
    ok $result, 'Parse hash subscript';

    $result = $parser->parse_string('$hash{$key}//=value');
    ok $result, 'Parse hash assignment with //= operator';
};