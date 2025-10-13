#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

my $file = 'perl-tests/base/lex.t';
my $content = do { local (@ARGV, $/) = $file; <> };

my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $content);
$preprocessor->transform();
my $preprocessed = $preprocessor->output;

my @lines = split /\n/, $preprocessed, -1;

# Test lines 1-100
my $test_100 = join("\n", @lines[0..99]);
say "Lines 1-100: " . ($parser->parse_string($test_100) ? "PASS" : "FAIL");

# Test lines 1-101
my $test_101 = join("\n", @lines[0..100]);
say "Lines 1-101: " . ($parser->parse_string($test_101) ? "PASS" : "FAIL");

# Show line 101
say "\nLine 101: " . $lines[100];

# Test just line 101 in isolation
say "\nTesting line 101 alone:";
my $result = $parser->parse_string($lines[100]) ? "PASS" : "FAIL";
say "Result: $result";

# Test a complete block with line 101
say "\nTesting line 101 with context:";
my @test_lines = (
    'my $test = 31;',
    '',
    '{ my $CX = "\cX";',
    '}'
);
my $test_with_context = join("\n", @test_lines);
say "Test: " . ($parser->parse_string($test_with_context) ? "PASS" : "FAIL");
