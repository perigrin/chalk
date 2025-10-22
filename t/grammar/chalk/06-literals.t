#!/usr/bin/env perl
# ABOUTME: Test literal values in chalk.bnf
# ABOUTME: Covers numbers, strings, arrays, hashes, regex literals
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');
my $semiring = Chalk::Semiring::Boolean->new();

sub parses_ok {
    my ($code, $name) = @_;
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok($result, $name) or diag("Failed to parse: $code");
}

# Integer literals
parses_ok(q{ my $x = 0; }, 'zero');
parses_ok(q{ my $x = 42; }, 'positive integer');
parses_ok(q{ my $x = -42; }, 'negative integer');
parses_ok(q{ my $x = 1000000; }, 'large integer');

# Float literals
parses_ok(q{ my $x = 3.14; }, 'float');
parses_ok(q{ my $x = -2.5; }, 'negative float');
parses_ok(q{ my $x = 0.5; }, 'float less than 1');
parses_ok(q{ my $x = 1.0; }, 'float with trailing zero');
parses_ok(q{ my $x = 1e10; }, 'scientific notation');
parses_ok(q{ my $x = 1.5e-3; }, 'scientific notation with fraction');

# Underscore separators in numbers
parses_ok(q{ my $x = 1_000_000; }, 'integer with underscores');
parses_ok(q{ my $x = 3.141_592_653; }, 'float with underscores');

# String literals - single quoted
parses_ok(q{ my $x = 'hello'; }, 'single quoted string');
parses_ok(q{ my $x = 'hello world'; }, 'single quoted with space');
parses_ok(q{ my $x = ''; }, 'empty single quoted string');
parses_ok(q{ my $x = 'can\'t'; }, 'single quoted with escaped quote');
parses_ok(q{ my $x = 'back\\slash'; }, 'single quoted with backslash');

# String literals - double quoted
parses_ok(q{ my $x = "hello"; }, 'double quoted string');
parses_ok(q{ my $x = "hello world"; }, 'double quoted with space');
parses_ok(q{ my $x = ""; }, 'empty double quoted string');
parses_ok(q{ my $x = "say \"hi\""; }, 'double quoted with escaped quotes');
parses_ok(q{ my $x = "line1\nline2"; }, 'double quoted with newline');
parses_ok(q{ my $x = "tab\there"; }, 'double quoted with tab');

# Array literals
parses_ok(q{ my $x = []; }, 'empty array literal');
parses_ok(q{ my $x = [1]; }, 'array literal with one element');
parses_ok(q{ my $x = [1, 2, 3]; }, 'array literal with multiple elements');
parses_ok(q{ my $x = ['a', 'b', 'c']; }, 'array literal with strings');
parses_ok(q{ my $x = [1, 'two', 3.0]; }, 'array literal with mixed types');

# Nested arrays
parses_ok(q{ my $x = [[1, 2], [3, 4]]; }, 'nested array literals');
parses_ok(q{ my $x = [1, [2, 3], 4]; }, 'partially nested arrays');

# Hash literals
parses_ok(q{ my $x = {}; }, 'empty hash literal');
parses_ok(q{ my $x = {'a' => 1}; }, 'hash literal with one pair');
parses_ok(q{ my $x = {'a' => 1, 'b' => 2}; }, 'hash literal with multiple pairs');
parses_ok(q{ my $x = {'key' => 'value'}; }, 'hash literal with string value');

# Nested hashes
parses_ok(q{ my $x = {'outer' => {'inner' => 1}}; }, 'nested hash literals');
parses_ok(q{ my $x = {'a' => 1, 'b' => {'c' => 2}}; }, 'partially nested hashes');

# Mixed nested structures
parses_ok(q{ my $x = {'arr' => [1, 2, 3]}; }, 'hash containing array');
parses_ok(q{ my $x = [{'a' => 1}, {'b' => 2}]; }, 'array containing hashes');

# Regex literals
parses_ok(q{ my $x = qr/pattern/; }, 'regex literal');
parses_ok(q{ my $x = qr/pattern/i; }, 'regex with flags');
parses_ok(q{ my $x = qr/pat\d+/; }, 'regex with escape');
parses_ok(q{ my $x = qr/a|b|c/; }, 'regex with alternation');

# Special values
parses_ok(q{ my $x = undef; }, 'undef');

# Quote operators
parses_ok(q{ my $x = q(hello); }, 'q() operator');
parses_ok(q{ my $x = qq(hello); }, 'qq() operator');
parses_ok(q{ my $x = qw(one two three); }, 'qw() operator');
