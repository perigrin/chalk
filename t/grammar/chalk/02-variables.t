#!/usr/bin/env perl
# ABOUTME: Test variable declarations and usage in chalk.bnf
# ABOUTME: Covers my, state, field declarations, scalars, arrays, hashes
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

sub parse_fails {
    my ($code, $name) = @_;
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok(!$result, $name) or diag("Unexpectedly parsed: $code");
}

# Test: Scalar declaration
parses_ok(q{
    my $x;
}, 'scalar variable declaration');

# Test: Scalar with initialization
parses_ok(q{
    my $x = 42;
}, 'scalar with initialization');

# Test: Array declaration
parses_ok(q{
    my @arr;
}, 'array variable declaration');

# Test: Array with initialization
parses_ok(q{
    my @arr = (1, 2, 3);
}, 'array with initialization');

# Test: Hash declaration
parses_ok(q{
    my %hash;
}, 'hash variable declaration');

# Test: Hash with initialization
parses_ok(q{
    my %hash = ('a' => 1, 'b' => 2);
}, 'hash with initialization');

# Test: State variable
parses_ok(q{
    state $counter = 0;
}, 'state variable');

# Test: Multiple variable declaration
parses_ok(q{
    my ($x, $y, $z) = (1, 2, 3);
}, 'multiple variable declaration');

# Test: Field declaration (in class context)
parses_ok(q{
    class Foo {
        field $x;
    }
}, 'field declaration in class');

# Test: Field with attributes
parses_ok(q{
    class Foo {
        field $x :param :reader;
    }
}, 'field with attributes');

# Test: Variable access - scalar
parses_ok(q{
    my $x = 1;
    $x;
}, 'scalar variable access');

# Test: Array element access
parses_ok(q{
    my @arr = (1, 2, 3);
    $arr[0];
}, 'array element access');

# Test: Hash element access
parses_ok(q{
    my %hash = ('key' => 'value');
    $hash{'key'};
}, 'hash element access');

# Test: Array slice
parses_ok(q{
    my @arr = (1, 2, 3, 4, 5);
    @arr[0, 2, 4];
}, 'array slice');

# Test: Hash slice
parses_ok(q{
    my %hash = ('a' => 1, 'b' => 2);
    @hash{'a', 'b'};
}, 'hash slice');

# Test: Array dereference with braces
parses_ok(q{
    my $ref = [1, 2, 3];
    @{$ref};
}, 'array dereference with braces');

# Test: Hash dereference with braces
parses_ok(q{
    my $ref = {'a' => 1};
    %{$ref};
}, 'hash dereference with braces');

# Test: Postfix dereference
parses_ok(q{
    my $ref = [1, 2, 3];
    $ref->@*;
}, 'postfix array dereference');

# Test: Hash postfix dereference
parses_ok(q{
    my $ref = {'a' => 1};
    $ref->%*;
}, 'postfix hash dereference');
