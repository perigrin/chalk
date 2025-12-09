#!/usr/bin/env perl
# ABOUTME: Comprehensive type completeness tests for TypeInference semiring
# ABOUTME: Verifies that type-consistent derivations are accepted (not pruned)

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::Composite;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

subtest 'Type completeness: 1 + 2 = Int' => sub {
    # Valid: Int + Int => Int
    my $code = 'my $x = 1 + 2;';

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $type_sr = Chalk::Semiring::TypeInference->new(
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Int + Int parses successfully');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];  # TypeInference is second semiring

        ok($type_elem->valid(), 'Type element is valid');
        ok(!$type_elem->type_obj->is_bottom(), 'Result is not bottom');
    }
};

subtest 'Type completeness: "hello" . "world" = Str' => sub {
    # Valid: Str . Str => Str
    my $code = 'my $greeting = "hello" . "world";';

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $type_sr = Chalk::Semiring::TypeInference->new(
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Str . Str parses successfully');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type element is valid');
        ok(!$type_elem->type_obj->is_bottom(), 'Result is not bottom');
    }
};

subtest 'Type completeness: Num + Str coercion' => sub {
    # Valid with coercion: Num context coerces Str to Num
    my $code = 'my $x = 5; my $y = "3"; my $z = $x + $y;';

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $type_sr = Chalk::Semiring::TypeInference->new(
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Num + Str (with coercion) parses successfully');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type element is valid (coercion accepted)');
        ok(!$type_elem->type_obj->is_bottom(), 'Result is not bottom');
    }
};

subtest 'Type completeness: valid arithmetic operations' => sub {
    my @test_cases = (
        { code => 'my $x = 10 * 2;', desc => 'Int * Int' },
        { code => 'my $x = 100 / 5;', desc => 'Int / Int' },
        { code => 'my $x = 10 - 3;', desc => 'Int - Int' },
        { code => 'my $x = 3.14 * 2.0;', desc => 'Num * Num' },
    );

    for my $test (@test_cases) {
        my $sppf_sr = Chalk::Semiring::SPPF->new();
        my $type_sr = Chalk::Semiring::TypeInference->new(
            shared_context => { forest => $sppf_sr->forest }
        );

        my $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $type_sr]
        );

        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $composite
        );

        my $result = $parser->parse_string($test->{code});
        ok($result, "$test->{desc} parses successfully");

        if ($result && $result->can('elements')) {
            my @elements = $result->elements->@*;
            my $type_elem = $elements[1];

            ok($type_elem->valid(), "$test->{desc} has valid type");
            ok(!$type_elem->type_obj->is_bottom(), "$test->{desc} is not bottom");
        }
    }
};

subtest 'Type completeness: valid string operations' => sub {
    my @test_cases = (
        { code => 'my $x = "a" . "b";', desc => 'Str . Str' },
        { code => 'my $x = "hello" x 3;', desc => 'Str x Int (repetition)' },
        { code => 'my $x = uc("hello");', desc => 'uc(Str)' },
    );

    for my $test (@test_cases) {
        my $sppf_sr = Chalk::Semiring::SPPF->new();
        my $type_sr = Chalk::Semiring::TypeInference->new(
            shared_context => { forest => $sppf_sr->forest }
        );

        my $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $type_sr]
        );

        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $composite
        );

        my $result = $parser->parse_string($test->{code});
        ok($result, "$test->{desc} parses successfully");

        if ($result && $result->can('elements')) {
            my @elements = $result->elements->@*;
            my $type_elem = $elements[1];

            ok($type_elem->valid(), "$test->{desc} has valid type");
        }
    }
};

subtest 'Type completeness: valid comparison operations' => sub {
    my @test_cases = (
        { code => 'my $x = 1 < 2;', desc => 'Int < Int' },
        { code => 'my $x = 5 == 5;', desc => 'Int == Int' },
        { code => 'my $x = "a" eq "b";', desc => 'Str eq Str' },
        { code => 'my $x = "a" lt "b";', desc => 'Str lt Str' },
    );

    for my $test (@test_cases) {
        my $sppf_sr = Chalk::Semiring::SPPF->new();
        my $type_sr = Chalk::Semiring::TypeInference->new(
            shared_context => { forest => $sppf_sr->forest }
        );

        my $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $type_sr]
        );

        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $composite
        );

        my $result = $parser->parse_string($test->{code});
        ok($result, "$test->{desc} parses successfully");

        if ($result && $result->can('elements')) {
            my @elements = $result->elements->@*;
            my $type_elem = $elements[1];

            ok($type_elem->valid(), "$test->{desc} has valid type");
        }
    }
};

subtest 'Type completeness: valid array operations' => sub {
    my @test_cases = (
        { code => 'my @arr = (1, 2, 3);', desc => 'Array literal' },
        { code => 'my @arr = (1, 2); my $elem = $arr[0];', desc => 'Array element access' },
        { code => 'my @arr = (); push @arr, 1;', desc => 'Array push' },
    );

    for my $test (@test_cases) {
        my $sppf_sr = Chalk::Semiring::SPPF->new();
        my $type_sr = Chalk::Semiring::TypeInference->new(
            shared_context => { forest => $sppf_sr->forest }
        );

        my $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $type_sr]
        );

        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $composite
        );

        my $result = $parser->parse_string($test->{code});
        ok($result, "$test->{desc} parses successfully");

        if ($result && $result->can('elements')) {
            my @elements = $result->elements->@*;
            my $type_elem = $elements[1];

            ok($type_elem->valid(), "$test->{desc} has valid type");
        }
    }
};

subtest 'Type completeness: valid hash operations' => sub {
    my @test_cases = (
        { code => 'my %hash = (a => 1, b => 2);', desc => 'Hash literal' },
        { code => 'my %h = (x => 1); my $val = $h{x};', desc => 'Hash value access' },
        { code => 'my %h = (); $h{key} = "value";', desc => 'Hash assignment' },
    );

    for my $test (@test_cases) {
        my $sppf_sr = Chalk::Semiring::SPPF->new();
        my $type_sr = Chalk::Semiring::TypeInference->new(
            shared_context => { forest => $sppf_sr->forest }
        );

        my $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $type_sr]
        );

        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $composite
        );

        my $result = $parser->parse_string($test->{code});
        ok($result, "$test->{desc} parses successfully");

        if ($result && $result->can('elements')) {
            my @elements = $result->elements->@*;
            my $type_elem = $elements[1];

            ok($type_elem->valid(), "$test->{desc} has valid type");
        }
    }
};

subtest 'Type completeness: no false negatives (valid code not rejected)' => sub {
    # Comprehensive test: valid Perl code should not be rejected
    my $valid_program = q{
        my $x = 1;
        my $y = 2;
        my $z = $x + $y;
        my $name = "Alice";
        my $greeting = "Hello, " . $name;
        my @numbers = (1, 2, 3, 4, 5);
        my $first = $numbers[0];
        my %scores = (math => 95, english => 87);
        my $math_score = $scores{math};
        return $z;
    };

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $type_sr = Chalk::Semiring::TypeInference->new(
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($valid_program);
    ok($result, 'Valid program parses successfully (no false negatives)');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Valid program has valid type');
        ok(!$type_elem->type_obj->is_bottom(), 'Valid program is not bottom');
    }
};
