#!/usr/bin/env perl
# ABOUTME: Test class declarations and basic class structure in chalk.bnf
# ABOUTME: Covers class keyword, field declarations, methods, ADJUST blocks
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

# Test: Simple class declaration
parses_ok(q{
    class Point {}
}, 'simple empty class');

# Test: Class with field
parses_ok(q{
    class Point {
        field $x;
    }
}, 'class with single field');

# Test: Class with multiple fields
parses_ok(q{
    class Point {
        field $x;
        field $y;
    }
}, 'class with multiple fields');

# Test: Class with field attributes
parses_ok(q{
    class Point {
        field $x :param :reader;
        field $y :param :reader;
    }
}, 'class with field attributes');

# Test: Class with field initialization
parses_ok(q{
    class Point {
        field $x :param = 0;
        field $y :param = 0;
    }
}, 'class with field initialization');

# Test: Class with method
parses_ok(q{
    class Point {
        field $x;
        method get_x() {
            return $x;
        }
    }
}, 'class with method');

# Test: Class with ADJUST block
parses_ok(q{
    class Point {
        field $x :param;
        ADJUST {
            $x = $x * 2;
        }
    }
}, 'class with ADJUST block');

# Test: Class with inheritance
parses_ok(q{
    class Point3D :isa(Point) {
        field $z :param :reader;
    }
}, 'class with inheritance');

# Test: Class with complete structure
parses_ok(q{
    class Point {
        field $x :param :reader = 0;
        field $y :param :reader = 0;

        ADJUST {
            $x = $x * 1;
        }

        method distance() {
            return sqrt($x * $x + $y * $y);
        }
    }
}, 'complete class with fields, ADJUST, and method');

# Test: Multiple classes in one file
parses_ok(q{
    class Point {
        field $x :param;
    }

    class Circle {
        field $center :param;
        field $radius :param;
    }
}, 'multiple classes in one file');

# Test: Nested class (currently parses - may want to restrict in future)
# Note: Grammar allows this, but semantics are unclear
parses_ok(q{
    class Outer {
        class Inner {
            field $x;
        }
    }
}, 'nested class declaration (parses but semantics TBD)');

# Test: Package declaration (currently parses for backward compat)
# Note: Goal is to remove package support in final chalk.bnf
parses_ok(q{
    package Foo;
    use 5.42.0;
}, 'package declaration (temporary backward compat)');
