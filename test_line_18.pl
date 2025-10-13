#!/usr/bin/env perl
use 5.42.0;
use utf8;
use lib 'lib';
use Chalk::Grammar::Perl;
use Chalk::Parser;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);
local $SIG{__WARN__} = sub {};

# Read from actual file
my @lines = do { local (@ARGV) = 'perl-tests/base/lex.t'; <> };

# Test just line 18
say "Test 1: Just line 18";
my $code1 = $lines[17];
say "Code: $code1";
my $result1 = $parser->parse_string($code1);
say $result1 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test lines 18-20
say "Test 2: Lines 18-20";
my $code2 = join('', @lines[17..19]);
say "Code:\n$code2";
my $result2 = $parser->parse_string($code2);
say $result2 ? "SUCCESS" : "FAILED";
say "-" x 60;

# Test lines 1-22
say "Test 3: Lines 1-22";
my $code3 = join('', @lines[0..21]);
my $result3 = $parser->parse_string($code3);
say $result3 ? "SUCCESS" : "FAILED";
