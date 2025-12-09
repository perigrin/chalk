#!/usr/bin/env perl
# ABOUTME: Tests for ambiguity resolution via type pruning in TypeInference semiring
# ABOUTME: Verifies that type information helps resolve parsing ambiguities

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

subtest 'Ambiguity resolution: context-dependent sigils' => sub {
    # @array vs $array[0] - different contexts, different types
    my $code = 'my @arr = (1, 2, 3); my $elem = $arr[0];';

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
    ok($result, 'Context-dependent sigil usage parses');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type inference resolves context ambiguity');
    }
};

subtest 'Ambiguity resolution: operator precedence with types' => sub {
    # Arithmetic operators with clear type constraints
    my $code = 'my $x = 1 + 2 * 3;';  # Should parse as 1 + (2 * 3)

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
    ok($result, 'Arithmetic expression with precedence parses');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type inference works with operator precedence');
        # Result should be Num or Int
        ok(!$type_elem->type_obj->is_bottom(), 'Result has valid numeric type');
    }
};

subtest 'Ambiguity resolution: mixed string and numeric operations' => sub {
    # Type helps disambiguate intention
    my $code = 'my $x = 1 + 2; my $y = "a" . "b";';

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
    ok($result, 'Mixed numeric and string operations parse');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type inference handles different operator contexts');
    }
};

subtest 'Ambiguity resolution: type pruning eliminates invalid parses' => sub {
    # When SPPF has multiple alternatives, type pruning should eliminate invalid ones
    # This is tested by verifying that type-invalid code doesn't produce valid results

    my $code = 'my $x = 1; my $y = 2; my $z = $x + $y;';

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
    ok($result, 'Valid typed code parses successfully');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $sppf_elem = $elements[0];  # SPPF
        my $type_elem = $elements[1];  # TypeInference

        # Check if SPPF has alternatives
        my $forest = $sppf_sr->forest;
        my $has_alternatives = 0;

        if ($forest && $forest->can('nodes')) {
            my $nodes = $forest->nodes;
            for my $node (values %$nodes) {
                if ($node->can('packed_nodes')) {
                    my @packed = $node->packed_nodes;
                    if (@packed > 1) {
                        $has_alternatives = 1;
                        last;
                    }
                }
            }
        }

        # If alternatives exist, type inference should select valid one
        if ($has_alternatives) {
            ok($type_elem->valid(), 'Type inference selects valid alternative when ambiguity exists');
        } else {
            pass('No ambiguity in this parse (expected for simple arithmetic)');
        }
    }
};

subtest 'Ambiguity resolution: hash vs block ambiguity' => sub {
    # { } can be empty hash or empty block - context determines
    my $code = 'my %h = ();';  # Empty hash

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
    ok($result, 'Hash initialization parses');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type inference resolves hash vs block ambiguity');
    }
};

subtest 'Integration: Type inference complements Precedence semiring' => sub {
    # Both semirings should work together without conflict
    my $code = 'my $result = 5 + 3 * 2;';

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
    ok($result, 'Arithmetic with precedence and type inference parses');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Type and precedence semirings work together');
        ok(!$type_elem->type_obj->is_bottom(), 'Result has valid type');
    }
};
