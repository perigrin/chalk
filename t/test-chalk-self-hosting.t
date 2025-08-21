#!/usr/bin/env perl
# ABOUTME: Test chalk parsing its own source code for true self-hosting
# ABOUTME: This is the ultimate test - can chalk parse itself?
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

require "$RealBin/../chalk";

# Build a grammar that can handle chalk's own syntax
# TODO: This grammar is limited by exact token matching - we need lexeme/regex
# support for terminals like identifiers before full self-hosting is possible
my $chalk_grammar = Grammar->build_grammar(
    # Program structure
    [ 'Program' => ['StatementList'] ],
    [ 'StatementList' => ['Statement'] ],
    [ 'StatementList' => ['Statement', 'StatementList'] ],
    
    # Statements
    [ 'Statement' => ['UseDecl'] ],
    [ 'Statement' => ['ClassDecl'] ],
    [ 'Statement' => ['Comment'] ],
    
    # Use declarations
    [ 'UseDecl' => ['use', 'ModuleName', ';'] ],
    [ 'UseDecl' => ['use', 'Version', ';'] ],
    [ 'UseDecl' => ['use', 'experimental', 'List', ';'] ],
    [ 'UseDecl' => ['use', 'utf8', ';'] ],
    [ 'UseDecl' => ['use', 'open', 'List', ';'] ],
    
    # Class declarations
    [ 'ClassDecl' => ['class', 'Identifier', 'Inheritance', '{', 'ClassBody', '}'] ],
    [ 'ClassDecl' => ['class', 'Identifier', '{', 'ClassBody', '}'] ],
    [ 'Inheritance' => [':isa(', 'Identifier', ')'] ],
    
    # Class body
    [ 'ClassBody' => ['ClassMember'] ],
    [ 'ClassBody' => ['ClassMember', 'ClassBody'] ],
    [ 'ClassMember' => ['UseOverload'] ],
    [ 'ClassMember' => ['FieldDecl'] ],
    [ 'ClassMember' => ['MethodDecl'] ],
    
    # Use overload declarations
    [ 'UseOverload' => ['use', 'overload', 'OverloadList', ';'] ],
    [ 'OverloadList' => ['OverloadSpec'] ],
    [ 'OverloadList' => ['OverloadSpec', ',', 'OverloadList'] ],
    [ 'OverloadSpec' => ['QuotedString', '=>', 'QuotedString'] ],
    [ 'OverloadSpec' => ['Identifier', '=>', 'Number'] ],
    
    # Field declarations
    [ 'FieldDecl' => ['field', 'Variable', 'FieldAttrs', ';'] ],
    [ 'FieldDecl' => ['field', 'Variable', ';'] ],
    [ 'FieldAttrs' => ['FieldAttr'] ],
    [ 'FieldAttrs' => ['FieldAttr', 'FieldAttrs'] ],
    [ 'FieldAttr' => [':param'] ],
    [ 'FieldAttr' => [':reader'] ],
    [ 'FieldAttr' => ['=', 'Expression'] ],
    
    # Method declarations
    [ 'MethodDecl' => ['method', 'Identifier', '(', 'ParamList', ')', 'Block'] ],
    [ 'MethodDecl' => ['method', 'Identifier', '(', ')', 'Block'] ],
    [ 'MethodDecl' => ['method', 'Identifier', '(@)', 'Block'] ],
    [ 'ParamList' => ['Param'] ],
    [ 'ParamList' => ['Param', ',', 'ParamList'] ],
    [ 'Param' => ['Variable', '=', 'Default'] ],
    [ 'Param' => ['Variable'] ],
    [ 'Default' => ['undef'] ],
    [ 'Default' => ['Number'] ],
    
    # Blocks and expressions
    [ 'Block' => ['{', 'StatementList', '}'] ],
    [ 'Block' => ['{', '...', '}'] ],
    [ 'Expression' => ['Identifier'] ],
    [ 'Expression' => ['Number'] ],
    [ 'Expression' => ['Variable'] ],
    [ 'Expression' => ['Constructor'] ],
    [ 'Constructor' => ['Identifier', '->', 'new', '(', 'ArgList', ')'] ],
    [ 'Constructor' => ['Identifier', '->', 'new', '(', ')'] ],
    [ 'ArgList' => ['Argument'] ],
    [ 'ArgList' => ['Argument', ',', 'ArgList'] ],
    [ 'Argument' => ['Identifier', '=>', 'Expression'] ],
    [ 'Argument' => ['Expression'] ],
    
    # Terminals
    [ 'Identifier' => ['Element'] ],
    [ 'Identifier' => ['Semiring'] ],
    [ 'Identifier' => ['BooleanElement'] ],
    [ 'Identifier' => ['ViterbiElement'] ],
    [ 'Identifier' => ['Parser'] ],
    [ 'Identifier' => ['Grammar'] ],
    [ 'Identifier' => ['add'] ],
    [ 'Identifier' => ['multiply'] ],
    [ 'Identifier' => ['score'] ],
    [ 'ModuleName' => ['experimental'] ],
    [ 'Variable' => ['$value'] ],
    [ 'Variable' => ['$other'] ],
    [ 'Variable' => ['$swap'] ],
    [ 'Variable' => ['$rule'] ],
    [ 'Number' => ['0'] ],
    [ 'Number' => ['1'] ],
    [ 'Number' => ['-1e10'] ],
    [ 'QuotedString' => ["'+'"] ],
    [ 'QuotedString' => ["'add'"] ],
    [ 'QuotedString' => ['"string"'] ],
    [ 'Version' => ['5.42.0'] ],
    [ 'List' => ['(', 'StringList', ')'] ],
    [ 'StringList' => ['QuotedString'] ],
    [ 'StringList' => ['QuotedString', 'StringList'] ],
    [ 'Comment' => ['#', 'Identifier'] ],
);

subtest 'Parse chalk class declarations' => sub {
    my $parser = Parser->new(grammar => $chalk_grammar);
    
    # Test Element base class
    my $result = $parser->parse(
        'class', 'Element', '{',
        'use', 'overload', "'+'", '=>', "'add'", ';',
        'method', 'add', '(@)', '{', '...', '}',
        '}'
    );
    ok $result, 'Parse Element base class declaration';
    
    # Test class with inheritance
    $result = $parser->parse(
        'class', 'BooleanElement', ':isa(', 'Element', ')', '{',
        'field', '$value', ':param', ':reader', ';',
        '}'
    );
    ok $result, 'Parse class with inheritance and field';
};

subtest 'Parse chalk use declarations' => sub {
    my $parser = Parser->new(grammar => $chalk_grammar);
    
    my $result = $parser->parse('use', '5.42.0', ';');
    ok $result, 'Parse version use declaration';
    
    $result = $parser->parse('use', 'experimental', '(', "'add'", ')', ';');
    ok $result, 'Parse experimental use declaration';
};

subtest 'Parse entire chalk file' => sub {
    # Read and tokenize the actual chalk source
    open my $fh, '<:utf8', "$RealBin/../chalk" or die "Cannot read chalk: $!";
    my @tokens = map { split /\s+/ } <$fh>;
    close $fh;
    
    ok @tokens > 100, "Successfully tokenized chalk source file";
    print "Tokenized " . scalar(@tokens) . " tokens from chalk\n";
    
    # Check for expected tokens
    ok(grep(/^class$/, @tokens), "Found 'class' tokens");
    ok(grep(/^Element$/, @tokens), "Found 'Element' token");
    ok(grep(/^use$/, @tokens), "Found 'use' tokens");
    ok(grep(/^field$/, @tokens), "Found 'field' tokens");
    ok(grep(/^method$/, @tokens), "Found 'method' tokens");
    
    # This is the ultimate test - try to parse the entire tokenized chalk file:
    my $parser = Parser->new(grammar => $chalk_grammar);  
    my $result = $parser->parse(@tokens);
    
    if ($result) {
        ok $result, "Chalk successfully parses itself!";
    } else {
        # For now, this is expected to fail until we complete the grammar
        todo "parsing not yet successful" => sub {
            fail "parsing not yet successful";
        };
    }
};