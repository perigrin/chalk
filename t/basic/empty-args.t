#!/usr/bin/env perl
# ABOUTME: Debug empty argument list parsing issue
# ABOUTME: Test minimal case for constructor with empty args
use 5.42.0;
use Test2::V0;
use FindBin      qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;

subtest 'Empty argument lists' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'Call' => [qw(name ( ))] ],
            [ 'Call' => [qw(name ( ArgList ))] ],
            [ 'ArgList' => ['arg'] ],
            [ 'ArgList' => [qw(arg , ArgList)] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('name(arg)');
    ok $result, 'Parse call with args';

    $result = $parser->parse_string('name()');
    ok $result, 'Parse call with empty args';
};

subtest 'Optional argument lists' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'Call' => [qw(name ( OptArgList ))] ],
            [ 'OptArgList' => ['ArgList'] ],
            [ 'OptArgList' => [] ],  # Empty production
            [ 'ArgList' => ['arg'] ],
            [ 'ArgList' => [qw(arg , ArgList)] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('name(arg)');
    ok $result, 'Parse call with args using optional';

    $result = $parser->parse_string('name()');
    ok $result, 'Parse call with empty args using optional';
};

subtest 'Method chain debugging' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'Expression' => [qw(Object -> Method)] ],
            [ 'Object' => ['Class'] ],
            [ 'Method' => [qw(new ( ))] ],
            [ 'Method' => [qw(new ( ArgList ))] ],
            [ 'ArgList' => ['arg'] ],
        ]
    );
    
    my $parser = Chalk::Parser->new(grammar => $grammar);
    
    my $result = $parser->parse_string('Class->new(arg)');
    ok $result, 'Parse method with args';

    $result = $parser->parse_string('Class->new()');
    ok $result, 'Parse method with empty args';
};