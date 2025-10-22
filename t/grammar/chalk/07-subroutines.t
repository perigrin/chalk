#!/usr/bin/env perl
# ABOUTME: Test subroutine declarations and calls in chalk.bnf
# ABOUTME: Covers sub, lexical subs, signatures, attributes
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

# Simple subroutine
parses_ok(q{
    sub foo() {
        return 1;
    }
}, 'simple subroutine');

# Subroutine with parameter
parses_ok(q{
    sub add($x, $y) {
        return $x + $y;
    }
}, 'subroutine with parameters');

# Subroutine with optional parameters
parses_ok(q{
    sub greet($name = 'World') {
        return "Hello, $name";
    }
}, 'subroutine with default parameter');

# Lexical subroutine
parses_ok(q{
    my sub helper() {
        return 42;
    }
}, 'lexical subroutine');

# Subroutine calls
parses_ok(q{
    sub foo() { return 1; }
    foo();
}, 'subroutine call');

parses_ok(q{
    sub add($x, $y) { return $x + $y; }
    add(1, 2);
}, 'subroutine call with arguments');

# Method declarations (in classes)
parses_ok(q{
    class Foo {
        method bar() {
            return 1;
        }
    }
}, 'method declaration');

parses_ok(q{
    class Foo {
        method calculate($x, $y) {
            return $x + $y;
        }
    }
}, 'method with parameters');

# Method calls
parses_ok(q{
    class Foo {
        method value() { return 42; }
    }
    my $obj = Foo->new();
    $obj->value();
}, 'method call');

# Anonymous subroutines
parses_ok(q{
    my $sub = sub { return 42; };
}, 'anonymous subroutine');

parses_ok(q{
    my $sub = sub ($x) { return $x * 2; };
}, 'anonymous subroutine with parameter');

# Note: Subroutine attributes not yet fully supported in chalk.bnf
# parses_ok(q{
#     sub foo() :prototype() {
#         return 1;
#     }
# }, 'subroutine with attribute');

# Complex subroutine bodies
parses_ok(q{
    sub process($data) {
        my $result = 0;

        for my $item (@{$data}) {
            if ($item > 0) {
                $result = $result + $item;
            }
        }

        return $result;
    }
}, 'complex subroutine body');
