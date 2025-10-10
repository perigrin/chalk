#!/usr/bin/env perl
# ABOUTME: Complete chalk grammar test with all modern Perl constructs
# ABOUTME: Build up the grammar systematically to handle self-hosting
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin      qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;

# Build a comprehensive grammar for chalk's modern Perl syntax
my $chalk_grammar = Chalk::Grammar->build_grammar(
    rules => [
        # Top-level program structure
        [ 'Program' => ['TopLevelDecls'] ],
        [ 'TopLevelDecls' => ['TopLevelDecl'] ],
        [ 'TopLevelDecls' => [qw(TopLevelDecl TopLevelDecls)] ],

        # Top-level declarations
        [ 'TopLevelDecl' => ['PragmaDecl'] ],
        [ 'TopLevelDecl' => ['ClassDecl'] ],

        # Pragma declarations (use statements)
        [ 'PragmaDecl' => [qw(use Version ;)] ],
        [ 'PragmaDecl' => [qw(use experimental List ;)] ],
        [ 'PragmaDecl' => [qw(use ModuleName ;)] ],

        # Class declarations
        [ 'ClassDecl' => [qw(class Identifier InheritanceClause { ClassBody })] ],
        [ 'ClassDecl' => [qw(class Identifier { ClassBody })] ],
        [ 'InheritanceClause' => [qw(:isa( Identifier ))] ],

        # Class body
        [ 'ClassBody' => ['ClassMember'] ],
        [ 'ClassBody' => [qw(ClassMember ClassBody)] ],
        [ 'ClassMember' => ['UseOverload'] ],
        [ 'ClassMember' => ['FieldDecl'] ],
        [ 'ClassMember' => ['MethodDecl'] ],

        # Use overload declarations
        [ 'UseOverload' => [qw(use overload OverloadList ;)] ],
        [ 'OverloadList' => ['OverloadSpec'] ],
        [ 'OverloadList' => ['OverloadSpec', ',', 'OverloadList'] ],
        [ 'OverloadSpec' => [qw(QuotedString => QuotedString)] ],
        [ 'OverloadSpec' => [qw(Identifier => Number)] ],

        # Field declarations
        [ 'FieldDecl' => [qw(field Variable AttributeList = Expression ;)] ],
        [ 'FieldDecl' => [qw(field Variable AttributeList ;)] ],
        [ 'FieldDecl' => [qw(field Variable = Expression ;)] ],
        [ 'FieldDecl' => [qw(field Variable ;)] ],
        [ 'AttributeList' => ['Attribute'] ],
        [ 'AttributeList' => [qw(Attribute AttributeList)] ],
        [ 'Attribute' => [':param'] ],
        [ 'Attribute' => [':reader'] ],

        # Method declarations
        [ 'MethodDecl' => [qw(method Identifier ( ParamList ) Block)] ],
        [ 'MethodDecl' => [qw(method Identifier ( ) Block)] ],
        [ 'MethodDecl' => [qw(method Identifier (@) Block)] ],
        [ 'ParamList' => ['Param'] ],
        [ 'ParamList' => ['Param', ',', 'ParamList'] ],
        [ 'Param' => [qw(Variable = Default)] ],
        [ 'Param' => ['Variable'] ],
        [ 'Default' => ['undef'] ],
        [ 'Default' => ['Number'] ],

        # Blocks and statements
        [ 'Block' => [qw({ StatementList })] ],
        [ 'Block' => [qw({ })] ],
        [ 'StatementList' => ['Statement'] ],
        [ 'StatementList' => [qw(Statement StatementList)] ],
        [ 'Statement' => [qw(return Expression ;)] ],
        [ 'Statement' => [qw(my Variable = Expression ;)] ],
        [ 'Statement' => [qw(state Variable = Expression ;)] ],
        [ 'Statement' => [qw(for my Variable ( Expression ) Block)] ],
        [ 'Statement' => [qw(if ( Expression ) Block)] ],
        [ 'Statement' => [qw(Expression ;)] ],
        [ 'Statement' => [qw({ StatementList })] ],  # Nested block
        [ 'Statement' => ['Ellipsis'] ],

        # Expressions
        [ 'Expression' => ['MethodCall'] ],
        [ 'Expression' => ['Constructor'] ],
        [ 'Expression' => ['HashAccess'] ],
        [ 'Expression' => ['StringConcat'] ],
        [ 'Expression' => ['PostfixDeref'] ],
        [ 'Expression' => ['BuiltinCall'] ],
        [ 'Expression' => ['Variable'] ],
        [ 'Expression' => ['Literal'] ],
        [ 'Expression' => [qw(( Expression ))] ],

        # Method calls and constructors
        [ 'MethodCall' => [qw(Expression -> Identifier ( ArgList ))] ],
        [ 'MethodCall' => [qw(Expression -> Identifier ( ))] ],
        [ 'Constructor' => [qw(Identifier -> new ( ArgList ))] ],
        [ 'Constructor' => [qw(Identifier -> new ( ))] ],

        # Hash access and assignment
        [ 'HashAccess' => [qw(Variable { Expression })] ],
        [ 'HashAccess' => [qw(Variable { Expression } //= Expression)] ],

        # String concatenation
        [ 'StringConcat' => [qw(Expression . Expression)] ],

        # Postfix dereference
        [ 'PostfixDeref' => [qw(Expression -> ArrayDeref)] ],
        [ 'PostfixDeref' => [qw(Expression -> HashDeref)] ],
        [ 'ArrayDeref' => ['@*'] ],
        [ 'HashDeref' => ['%*'] ],

        # Builtin function calls
        [ 'BuiltinCall' => [qw(all { Block } Expression)] ],
        [ 'BuiltinCall' => [qw(any { Block } Expression)] ],

        # Argument lists
        [ 'ArgList' => ['Argument'] ],
        [ 'ArgList' => ['Argument', ',', 'ArgList'] ],
        [ 'Argument' => [qw(Identifier => Expression)] ],
        [ 'Argument' => ['Expression'] ],

        # Variables
        [ 'Variable' => ['ScalarVar'] ],
        [ 'Variable' => ['ArrayVar'] ],
        [ 'Variable' => ['HashVar'] ],
        [ 'ScalarVar' => ['$var'] ],
        [ 'ArrayVar' => ['@var'] ],
        [ 'HashVar' => ['%var'] ],

        # Literals and identifiers
        [ 'Literal' => ['Number'] ],
        [ 'Literal' => ['QuotedString'] ],
        [ 'Literal' => ['ArrayRef'] ],
        [ 'Literal' => ['HashRef'] ],
        [ 'ArrayRef' => [qw([ ])] ],
        [ 'ArrayRef' => [qw([ ExprList ])] ],
        [ 'HashRef' => [qw({ })] ],
        [ 'HashRef' => [qw({ HashPairs })] ],
        [ 'ExprList' => ['Expression'] ],
        [ 'ExprList' => ['Expression', ',', 'ExprList'] ],
        [ 'HashPairs' => ['HashPair'] ],
        [ 'HashPairs' => ['HashPair', ',', 'HashPairs'] ],
        [ 'HashPair' => [qw(Expression => Expression)] ],

        # Terminal symbols
        [ 'Identifier' => ['Element'] ],
        [ 'Identifier' => ['ViterbiElement'] ],
        [ 'Identifier' => ['SPPFForest'] ],
        [ 'Identifier' => ['new'] ],
        [ 'Identifier' => ['method'] ],
        [ 'ModuleName' => ['overload'] ],
        [ 'ModuleName' => ['experimental'] ],
        [ 'Number' => ['0'] ],
        [ 'Number' => ['1'] ],
        [ 'Number' => ['-1e10'] ],
        [ 'QuotedString' => ["'+'"] ],
        [ 'QuotedString' => ["'add'"] ],
        [ 'QuotedString' => ["'ε'"] ],
        [ 'QuotedString' => ['"string"'] ],
        [ 'Version' => ['5.42.0'] ],
        [ 'List' => [qw(( StringList ))] ],
        [ 'StringList' => ['QuotedString'] ],
        [ 'StringList' => [qw(QuotedString StringList)] ],
        [ 'Ellipsis' => ['...'] ],
    ]
);

subtest 'Basic class structure' => sub {
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    
    # Simple class
    my $result = $parser->parse_string(
        'classElement{field$var;}'
    );
    ok $result, 'Parse simple class';

    # Class with inheritance
    $result = $parser->parse_string(
        'classViterbiElement:isa(Element){field$var:param;}'
    );
    ok $result, 'Parse class with inheritance and field attributes';
};

subtest 'Overload declarations' => sub {
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    
    my $result = $parser->parse_string(
        'classElement{useoverload\'+\'=>\'add\';}'
    );
    ok $result, 'Parse class with simple overload';

    todo "multiple overload specs need lexeme support" => sub {
        $result = $parser->parse_string(
            'classElement{useoverload\'+\'=>\'add\',Identifier=>1;}'
        );
        ok $result, 'Parse class with multiple overload specs';
    };
};

subtest 'Method declarations' => sub {
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    
    # Method with empty parameter list
    my $result = $parser->parse_string(
        'classElement{methodmethod(){...}}'
    );
    ok $result, 'Parse method with empty parameters';

    # Method with parameters
    $result = $parser->parse_string(
        'classElement{methodmethod($var){return$var;}}'
    );
    ok $result, 'Parse method with parameter';

    # Method with default parameter
    $result = $parser->parse_string(
        'classElement{methodmethod($var=undef){return$var;}}'
    );
    ok $result, 'Parse method with default parameter';
};

subtest 'Complex expressions' => sub {
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    
    # Constructor call
    my $result = $parser->parse_string(
        'classElement{methodmethod(){returnViterbiElement->new();}}'
    );
    ok $result, 'Parse method with constructor call';
    
    # Constructor with arguments
    todo "constructor with named argument needs lexeme support" => sub {
        $result = $parser->parse_string(
            'classElement{methodmethod(){returnViterbiElement->new(Identifier=>$var);}}'
        );
        ok $result, 'Parse constructor with named argument';
    };
};

subtest 'Field initialization' => sub {
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    
    # Field with array reference initialization
    my $result = $parser->parse_string(
        'classElement{field$var=[];}'
    );
    ok $result, 'Parse field with empty array reference';

    # Field with constructor initialization
    todo "field with constructor initialization needs lexeme support" => sub {
        $result = $parser->parse_string(
            'classElement{field$var=ViterbiElement->new(Identifier=>0);}'
        );
        ok $result, 'Parse field with constructor initialization';
    };
};

subtest 'Complete chalk class pattern' => sub {
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    
    # Parse a complete class like ViterbiSemiring
    todo "complete ViterbiElement-style class needs lexeme support" => sub {
        my $result = $parser->parse_string(
            'classViterbiElement:isa(Element){useoverload\'+\'=>\'add\';field$var:param:reader;field$var=ViterbiElement->new(Identifier=>0);methodmethod($var=undef){returnViterbiElement->new();}}'
        );
        ok $result, 'Parse complete ViterbiElement-style class';
    };
};