#!/usr/bin/env perl
# ABOUTME: Test q{}/qq{} quote operator parsing support in Chalk grammar
# ABOUTME: Verify preprocessed heredocs can be parsed successfully
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

require "$RealBin/../chalk";

subtest 'Single q{} operator parsing' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Statement' => ['my', 'Variable', '=', 'QuotedString', ';'] ],
        [ 'Variable' => ['$text'] ],
        [ 'QuotedString' => [qr/q\{[^}]*\}/] ],
    );

    my $parser = Parser->new(grammar => $grammar);
    my $result = $parser->parse_string('my$text=q{HelloWorld};');
    ok $result, 'Parse q{} operator';
};

subtest 'Single qq{} operator parsing' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Statement' => ['my', 'Variable', '=', 'QuotedString', ';'] ],
        [ 'Variable' => ['$text'] ],
        [ 'QuotedString' => [qr/qq\{[^}]*\}/] ],
    );

    my $parser = Parser->new(grammar => $grammar);
    my $result = $parser->parse_string('my$text=qq{HelloWorld};');
    ok $result, 'Parse qq{} operator';
};

subtest 'Mixed quote operators' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Statement' => ['my', 'Variable', '=', 'QuotedString', ';'] ],
        [ 'Variable' => ['$text'] ],
        [ 'QuotedString' => [qr/q\{[^}]*\}/] ],
        [ 'QuotedString' => [qr/qq\{[^}]*\}/] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    my $result = $parser->parse_string('my$text=q{singlequoted};');
    ok $result, 'Parse q{} in mixed grammar';

    $result = $parser->parse_string('my$text=qq{doublequoted};');
    ok $result, 'Parse qq{} in mixed grammar';
};

subtest 'Empty quote operators' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Statement' => ['my', 'Variable', '=', 'QuotedString', ';'] ],
        [ 'Variable' => ['$text'] ],
        [ 'QuotedString' => [qr/q\{[^}]*\}/] ],
        [ 'QuotedString' => [qr/qq\{[^}]*\}/] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    my $result = $parser->parse_string('my$text=q{};');
    ok $result, 'Parse empty q{}';

    $result = $parser->parse_string('my$text=qq{};');
    ok $result, 'Parse empty qq{}';
};

subtest 'Quote operators with newlines' => sub {
    my $grammar = Grammar->build_grammar(
        [ 'Statement' => ['my', 'Variable', '=', 'QuotedString', ';'] ],
        [ 'Variable' => ['$text'] ],
        [ 'QuotedString' => [qr/q\{(?:[^}]|\n)*\}/] ],
        [ 'QuotedString' => [qr/qq\{(?:[^}]|\n)*\}/] ],
    );

    my $parser = Parser->new(grammar => $grammar);

    my $result = $parser->parse_string("my\$text=q{line1\nline2};");
    ok $result, 'Parse q{} with newline';

    $result = $parser->parse_string("my\$text=qq{line1\nline2};");
    ok $result, 'Parse qq{} with newline';
};
