#!/usr/bin/env perl
# ABOUTME: Test Type Inference semiring for semantic validation
# ABOUTME: Verifies postfix conditional validation and equivalence of Boolean vs SPPF

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::Composite;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

subtest 'Type Inference validates postfix conditionals' => sub {
    # Valid: postfix conditional on simple statement
    my $valid_code = 'return 42 if $x > 0;';

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

    my $result = $parser->parse_string($valid_code);
    ok $result, 'Valid postfix conditional parses successfully';

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];  # TypeInference is second semiring
        ok $type_elem->valid, 'Type Inference marks valid postfix as valid';
    }
};

subtest 'Issue #195: Block-form if cannot have postfix modifier' => sub {
    # INVALID: trying to apply postfix to block-form if
    # This parses as: if ($x > 0) { return 42; } <INVALID POSTFIX> return -42;
    my $invalid_code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

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

    my $result = $parser->parse_string($invalid_code);
    ok $result, 'Code parses (may have multiple alternatives)';

    SKIP: {
        skip 'Parse failed' unless $result;

        # Check SPPF has alternatives
        my $forest = $sppf_sr->forest;
        my @statement_lists = grep {
            $_->isa('Chalk::ParseForest::SymbolNode') &&
            $_->symbol eq 'StatementList' &&
            $_->start_pos == 0 &&
            $_->end_pos == length($invalid_code)
        } values %{$forest->nodes};

        if (@statement_lists) {
            my $root = $statement_lists[0];
            my @packed = $root->packed_nodes;
            note("SPPF has " . scalar(@packed) . " alternatives");

            # Type Inference should have validated and chosen correct alternative
            if ($result->can('elements')) {
                my @elements = $result->elements->@*;
                my $type_elem = $elements[1];  # TypeInference element

                # The semantically valid parse is the 3-statement parse
                # Type Inference should reject the 2-statement parse (block-form if with postfix)
                ok $type_elem->valid, 'Type Inference selects valid alternative';
            }
        }
    }
};

subtest 'Baseline: Simple statements without conditionals' => sub {
    my $code = 'my $x = 1; $x = 2; $x = 3; return $x;';

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
    ok $result, 'Simple statements parse successfully';

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];
        ok $type_elem->valid, 'Type Inference marks simple statements as valid';
    }
};

subtest 'Equivalence: Boolean vs SPPF with Precedence+TypeInference' => sub {
    # Test that Boolean+Precedence+TypeInference produces same validation
    # as SPPF+Precedence+TypeInference
    # The only difference should be SPPF stores the parse forest

    my @test_cases = (
        { code => 'return 42;', desc => 'Simple return', should_parse => 1 },
        { code => 'return 42 if $x > 0;', desc => 'Valid postfix conditional', should_parse => 1 },
        { code => 'my $x = 1; $x = 2; return $x;', desc => 'Multiple statements', should_parse => 1 },
        { code => 'my $x = -5; if ($x > 0) { return 42; } return -42;', desc => 'Issue #195 case', should_parse => 1 },
    );

    for my $test (@test_cases) {
        my $code = $test->{code};
        my $desc = $test->{desc};

        # Parse with Boolean + Precedence + TypeInference
        my $bool_sr = Chalk::Semiring::Boolean->new();
        my $bool_type_sr = Chalk::Semiring::TypeInference->new();

        my $bool_composite = Chalk::Semiring::Composite->new(
            semirings => [$bool_sr, $bool_type_sr]
        );

        my $bool_parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $bool_composite
        );

        my $bool_result = $bool_parser->parse_string($code);

        # Parse with SPPF + Precedence + TypeInference
        my $sppf_sr = Chalk::Semiring::SPPF->new();
        my $sppf_type_sr = Chalk::Semiring::TypeInference->new(
            shared_context => { forest => $sppf_sr->forest }
        );

        my $sppf_composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $sppf_type_sr]
        );

        my $sppf_parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $sppf_composite
        );

        my $sppf_result = $sppf_parser->parse_string($code);

        # Both should succeed or both should fail
        my $bool_success = defined($bool_result) && $bool_result;
        my $sppf_success = defined($sppf_result) && $sppf_result;

        is($bool_success, $sppf_success,
           "$desc: Boolean and SPPF composites give equivalent parse results");

        if ($test->{should_parse}) {
            ok($bool_success, "$desc: Boolean composite parses successfully");
            ok($sppf_success, "$desc: SPPF composite parses successfully");
        }
    }
};
