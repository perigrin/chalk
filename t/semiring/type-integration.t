#!/usr/bin/env perl
# ABOUTME: Integration tests for TypeInference with full parsing pipeline
# ABOUTME: Tests TypeInference with Precedence, SPPF, and complete Chalk grammar

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::Composite;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

subtest 'Integration: SPPF + TypeInference' => sub {
    my $code = 'my $x = 1 + 2; my $y = "hello" . "world";';

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
    ok($result, 'SPPF + TypeInference parses successfully');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        is(scalar(@elements), 2, 'Composite has 2 semiring elements');

        my $sppf_elem = $elements[0];
        my $type_elem = $elements[1];

        ok($sppf_elem, 'SPPF element exists');
        ok($type_elem, 'TypeInference element exists');
        ok($type_elem->valid(), 'Type element is valid');
    }
};

subtest 'Integration: SPPF + Precedence + TypeInference (triple composite)' => sub {
    my $code = 'my $result = 1 + 2 * 3 - 4;';

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $prec_sr = Chalk::Semiring::Precedence->new(
        shared_context => { forest => $sppf_sr->forest }
    );
    my $type_sr = Chalk::Semiring::TypeInference->new(
        shared_context => { forest => $sppf_sr->forest }
    );

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $prec_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($code);
    ok($result, 'Triple composite (SPPF + Precedence + TypeInference) parses');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        is(scalar(@elements), 3, 'Composite has 3 semiring elements');

        my $sppf_elem = $elements[0];
        my $prec_elem = $elements[1];
        my $type_elem = $elements[2];

        ok($sppf_elem, 'SPPF element exists');
        ok($prec_elem, 'Precedence element exists');
        ok($type_elem, 'TypeInference element exists');
        ok($type_elem->valid(), 'Type inference validates arithmetic');
    }
};

subtest 'Integration: Full parsing pipeline with complex code' => sub {
    my $complex_code = q{
        my $count = 0;
        my @items = (1, 2, 3, 4, 5);
        for my $item (@items) {
            $count = $count + $item;
        }
        my $result = $count * 2;
        return $result;
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

    my $result = $parser->parse_string($complex_code);
    ok($result, 'Complex program with loops parses with type inference');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Complex program has valid types throughout');
    }
};

subtest 'Integration: Type inference with user-defined functions' => sub {
    my $code = q{
        sub add {
            my ($a, $b) = @_;
            return $a + $b;
        }
        my $sum = add(5, 3);
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

    my $result = $parser->parse_string($code);
    ok($result, 'Function definition and call parse with type inference');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Function code has valid types');
    }
};

subtest 'Integration: Type inference handles all basic types' => sub {
    my $code = q{
        my $int = 42;
        my $float = 3.14;
        my $str = "text";
        my @arr = (1, 2, 3);
        my %hash = (key => "value");
        my $aref = [1, 2];
        my $href = {a => 1};
        my $sub = sub { return 1; };
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

    my $result = $parser->parse_string($code);
    ok($result, 'All basic types parse with type inference');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'All basic type declarations are valid');
    }
};

subtest 'Integration: Existing tests still pass with TypeInference' => sub {
    # Verify that adding TypeInference doesn't break existing functionality
    # Test a simple case that should work with or without type inference

    my $code = 'my $x = 1;';

    # Without TypeInference
    my $sppf_only = Chalk::Semiring::SPPF->new();
    my $parser_plain = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf_only
    );
    my $result_plain = $parser_plain->parse_string($code);

    # With TypeInference
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $type_sr = Chalk::Semiring::TypeInference->new(
        shared_context => { forest => $sppf_sr->forest }
    );
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $type_sr]
    );
    my $parser_typed = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );
    my $result_typed = $parser_typed->parse_string($code);

    ok($result_plain, 'Code parses without TypeInference');
    ok($result_typed, 'Code parses with TypeInference');
    is(!!$result_plain, !!$result_typed,
       'Adding TypeInference doesn\'t change parse success for valid code');
};

subtest 'Integration: Self-hosting capability check' => sub {
    # Verify TypeInference can handle parsing Chalk code (meta-circular)
    # This is a basic check - full self-hosting tested elsewhere

    my $chalk_code = q{
        class Point {
            field $x;
            field $y;
        }
        my $p = Point->new(x => 1, y => 2);
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

    my $result = $parser->parse_string($chalk_code);
    ok($result, 'Chalk syntax (class definition) parses with type inference');

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        ok($type_elem->valid(), 'Chalk syntax has valid types');
    }
};

subtest 'Integration: Error recovery and reporting' => sub {
    todo 'Type error detection during parsing not yet implemented' => sub {
    # When type errors occur, system should handle gracefully
    # Bottom type should propagate correctly

    my $invalid_code = 'my $x = [] + {};';  # Type error

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

    # Parser might still return a result (parse succeeded)
    # but type inference should mark it invalid
    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];

        # Type should be invalid (bottom) or parse should fail
        ok(!$type_elem->valid() || $type_elem->type_obj->is_bottom(),
           'Type inference detects and reports type errors');
    } else {
        pass('Parser rejected type-invalid code');
    }
    };  # end todo
};
