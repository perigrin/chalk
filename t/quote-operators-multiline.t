#!/usr/bin/env perl
# ABOUTME: Test multi-line quote operators (qq on separate line from delimiter)
# ABOUTME: Verify \s* in regex allows newlines between operator and delimiter
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 3;
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    preprocess => ['Chalk::Preprocessor::HeredocV2'],
);

# Suppress warnings during parsing
local $SIG{__WARN__} = sub {};

# Test 1: qq on same line (already worked)
my $same_line = q{print qq[ok 16\n];};
ok($parser->parse_string($same_line), 'qq and delimiter on same line');

# Test 2: qq on separate line from delimiter (lex.t lines 65-67)
my $multi_line = q{print qq
[ok 16\n]
;};
ok($parser->parse_string($multi_line), 'qq on separate line from delimiter');

# Test 3: q with newline
my $q_multi = q{print q
<ok 17>
;};
ok($parser->parse_string($q_multi), 'q on separate line from delimiter');
