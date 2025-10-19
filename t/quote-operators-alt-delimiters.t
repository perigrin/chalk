#!/usr/bin/env perl
# ABOUTME: Test alternative quote operator delimiters
# ABOUTME: Verify qq(), qq[], q<>, q{} forms are supported
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc'],
);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test forms from lex.t lines 63-70
ok($parser->parse_string(q{print qq(ok 15\n);}), 'qq(text)');
ok($parser->parse_string(q{print qq[ok 16\n];}), 'qq[text]');
ok($parser->parse_string(q{print q<ok 17>;}), 'q<text>');
ok($parser->parse_string(q{print q{ok 18};}), 'q{text}');
ok($parser->parse_string(q{print qq{ok 19};}), 'qq{text}');
