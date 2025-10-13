#!/usr/bin/env perl
# ABOUTME: Test backslash-quoted heredoc support (<<\EOF syntax)
# ABOUTME: Verify preprocessor handles backslash-quoted heredoc delimiters
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 2;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test 1: Parse backslash heredoc in comma expression
my $input = q{eval <<\EOE, print $@;
print "test";
EOE
};

ok($parser->parse_string($input), 'backslash heredoc in comma expression');

# Test 2: Simple <<\EOF without eval
my $simple = q{print <<\EOF;
Hello
EOF
};

ok($parser->parse_string($simple), 'simple backslash heredoc');
