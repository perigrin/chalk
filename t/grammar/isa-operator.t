#!/usr/bin/env perl
# ABOUTME: Tests for isa operator grammar support
# ABOUTME: Verifies that isa accepts expressions on both LHS and RHS
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
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

# Test: isa with bareword on RHS (already working)
parses_ok(q{
    $obj isa Foo;
}, 'isa with bareword on RHS');

# Test: isa with variable on RHS (already working per issue)
parses_ok(q{
    $obj isa $class;
}, 'isa with variable on RHS');

# Test: isa with expression on LHS (already working)
parses_ok(q{
    get_obj() isa Foo;
}, 'isa with function call on LHS');

# Test: isa with function call on RHS (FAILING - this is what we need to fix)
parses_ok(q{
    $obj isa get_class();
}, 'isa with function call on RHS');

# Test: isa with both sides being function calls (FAILING)
parses_ok(q{
    get_obj() isa get_class();
}, 'isa with function calls on both sides');

# Test: isa with ternary on RHS (FAILING)
parses_ok(q{
    $obj isa ($cond ? "Foo" : "Bar");
}, 'isa with ternary expression on RHS');

# Test: isa with method call on RHS (FAILING)
parses_ok(q{
    $obj isa blessed($obj);
}, 'isa with method call on RHS');

# Note: done_testing() is called automatically by the defer block
