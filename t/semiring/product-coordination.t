#!/usr/bin/env perl
# ABOUTME: Test product semiring coordination between TypeInference, Precedence, and SemanticValidation
# ABOUTME: Validates that type-invalid operators are pruned before precedence resolution (Issue #355)

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Composite;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::SemanticValidation;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Perl precedence table for testing
my @perl_precedence_table = (
    { assoc => 'left',    ops => ['->'] },
    { assoc => 'nonassoc', ops => ['++', '--'] },
    { assoc => 'right',   ops => ['**'] },
    { assoc => 'right',   ops => ['!', '~', '\\', 'unary +', 'unary -'] },
    { assoc => 'left',    ops => ['=~', '!~'] },
    { assoc => 'left',    ops => ['*', '/', '%', 'x'] },      # Index 5
    { assoc => 'left',    ops => ['+', '-', '.'] },           # Index 6
    { assoc => 'left',    ops => ['<<', '>>'] },
    { assoc => 'nonassoc', ops => ['named unary'] },
    { assoc => 'nonassoc', ops => ['isa'] },
    { assoc => 'chained', ops => ['<', '>', '<=', '>=', 'lt', 'gt', 'le', 'ge'] },
    { assoc => 'chain/na', ops => ['==', '!=', 'eq', 'ne', '<=>', 'cmp', '~~'] },
    { assoc => 'left',    ops => ['&'] },
    { assoc => 'left',    ops => ['|', '^'] },
    { assoc => 'left',    ops => ['&&'] },
    { assoc => 'left',    ops => ['||', '^^', '//'] },
    { assoc => 'nonassoc', ops => ['..', '...'] },
    { assoc => 'right',   ops => ['?:'] },
    { assoc => 'right',   ops => ['=', '+=', '-=', '*=', '/=', '%=', '**=', '&=', '|=', '^=', '.=', '<<=', '>>=', '&&=', '||=', '//='] },
    { assoc => 'left',    ops => [',', '=>'] },
    { assoc => 'right',   ops => ['not'] },
    { assoc => 'left',    ops => ['and'] },
    { assoc => 'left',    ops => ['or', 'xor'] },
);

subtest 'TypeInference × Precedence: Type-valid operators participate in precedence' => sub {
    # Test: 1 + 2 * 3
    # All operators are type-valid (numeric)
    # Precedence should resolve correctly: 1 + (2 * 3)

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table
    );
    my $type_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string('1 + 2 * 3');
    ok $result, 'Type-valid arithmetic expression parses';

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $prec_elem = $elements[0];  # Precedence element
        my $type_elem = $elements[1];  # TypeInference element

        ok $prec_elem->valid, 'Precedence validates correct grouping';
        ok $type_elem->valid, 'TypeInference validates numeric types';
    }
};

subtest 'TypeInference × Precedence: Type-invalid operators are pruned' => sub {
    # TODO: This test requires symbol table integration to know variable types
    # TypeInference currently only infers types from literal tokens (Int, Num)
    # Detecting that @array is Array type requires a type environment
    # For now, skip this test - the coordination mechanism is tested in test #6

    plan skip_all => 'Requires symbol table integration (out of scope for #355)';

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table
    );
    my $type_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $type_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    # This should fail to parse or return invalid result
    my $result = $parser->parse_string('@array + $scalar');

    # Either parse fails (no result) or result is marked invalid
    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        my $type_elem = $elements[1];  # TypeInference element

        # TypeInference should detect type incompatibility
        ok !$type_elem->valid, 'TypeInference marks Array + Scalar as invalid';
    } else {
        ok !$result, 'Type-invalid expression fails to parse';
    }
};

subtest 'TypeInference × Precedence: Composite short-circuits on type-invalid multiply' => sub {
    # Test that Composite.multiply() short-circuits when TypeInference returns bottom
    # This prevents invalid parses from consuming resources in precedence checks

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table
    );
    my $type_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $type_sr]
    );

    # Create elements: precedence valid, type invalid
    my $prec_valid = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $type_invalid = $type_sr->add_id;  # Bottom type (invalid)

    my $elem1 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid, $type_invalid],
        parent_semiring => $composite
    );

    my $prec_valid2 = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $type_valid = $type_sr->mul_id;  # Top type (Any)

    my $elem2 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid2, $type_valid],
        parent_semiring => $composite
    );

    # Multiply should short-circuit because type element is invalid
    my $result = $elem1->multiply($elem2);

    ok $result->equals($composite->add_id),
       'Composite short-circuits to add_id when TypeInference is invalid';
};

subtest 'TypeInference × Precedence: Coordination via Composite.add()' => sub {
    # Test that when Precedence chooses a derivation, TypeInference follows
    # This ensures type-invalid parses are pruned from ambiguity resolution

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table
    );
    my $type_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $type_sr]
    );

    # Create two alternative parses:
    # Parse 1: precedence valid, type valid
    my $prec_valid = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 6
    );
    my $type_valid = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Num')
    );
    my $parse1 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid, $type_valid],
        parent_semiring => $composite
    );

    # Parse 2: precedence invalid, type valid
    my $prec_invalid = Chalk::Semiring::PrecedenceElement->new(valid => 0);
    my $type_valid2 = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $type_sr->type_from_name('Num')
    );
    my $parse2 = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_invalid, $type_valid2],
        parent_semiring => $composite
    );

    # add() should choose parse1 (valid precedence)
    # Sequential filtering: Precedence filters first, TypeInference follows consensus
    my $result = $parse1->add($parse2);

    # Verify sequential filtering via reference equality (not just value equality)
    # This ensures TypeInference.add() returns original references for consensus detection
    ok $result == $parse1, 'Sequential filtering: Composite.add() returns parse1 by reference';
};

subtest 'TypeInference × SemanticValidation: Both validate at different levels' => sub {
    # TypeInference validates type lattice operations
    # SemanticValidation validates grammar-specific rules
    # Both should work together in product semiring

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table
    );
    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $sem_sr = Chalk::Semiring::SemanticValidation->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $type_sr, $sem_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    # Simple valid expression
    my $result = $parser->parse_string('1 + 2');
    ok $result, 'Triple product semiring parses simple expression';

    if ($result && $result->can('elements')) {
        my @elements = $result->elements->@*;
        is scalar(@elements), 3, 'Result has all three semiring elements';

        ok $elements[0]->valid, 'Precedence validates';
        ok $elements[1]->valid, 'TypeInference validates';
        ok $elements[2]->valid, 'SemanticValidation validates';
    }
};

subtest 'Cross-semiring pruning: Invalid type prevents precedence comparison' => sub {
    # When TypeInference marks an operator as invalid (bottom type),
    # it should be pruned BEFORE Precedence.multiply() compares precedence levels
    # This is the key interaction described in Issue #355

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table
    );
    my $type_sr = Chalk::Semiring::TypeInference->new();

    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$prec_sr, $type_sr]
    );

    # Simulate parsing: create type-invalid operator element
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $bottom_type = $lattice->bottom_type();  # Type contradiction

    my $prec_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        operator => '+',
        precedence_level => 6
    );
    my $type_elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $bottom_type  # Invalid type
    );

    my $invalid_op = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_elem, $type_elem],
        parent_semiring => $composite
    );

    # When multiplied with another element, should short-circuit to add_id
    my $prec_valid = Chalk::Semiring::PrecedenceElement->new(valid => 1);
    my $type_valid = $type_sr->mul_id;

    my $valid_elem = Chalk::Semiring::CompositeElement->new(
        elements => [$prec_valid, $type_valid],
        parent_semiring => $composite
    );

    my $result = $invalid_op->multiply($valid_elem);

    # Should equal add_id (pruned), not attempt precedence comparison
    ok $result->equals($composite->add_id),
       'Type-invalid operator is pruned before precedence comparison';
};
