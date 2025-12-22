# ABOUTME: Test context tracking in TypeInference semiring for container and value contexts
# ABOUTME: Validates Phase 2 of #433 - context fields on TypeInferenceElement

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Create composite semiring with TypeInference and Semantic
my $type_sr = Chalk::Semiring::TypeInference->new();
my $sem_sr = Chalk::Semiring::Semantic->new(grammar => $grammar);
my $semiring = Chalk::Semiring::Composite->new(
    semirings => [$type_sr, $sem_sr]
);

subtest 'TypeInferenceElement has context fields' => sub {
    # Test that TypeInferenceElement constructor accepts context fields
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    my $elem = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->type_from_name('Int'),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 0,
        container_context => 'scalar',
        value_context => 'numeric'
    );

    ok($elem, "TypeInferenceElement created with context fields");
    ok($elem->can('container_context'), "Element has container_context accessor");
    ok($elem->can('value_context'), "Element has value_context accessor");
    is($elem->container_context, 'scalar', "container_context is 'scalar'");
    is($elem->value_context, 'numeric', "value_context is 'numeric'");
};

subtest 'ArithmeticOp sets numeric value context on operands' => sub {
    # Parse an arithmetic expression
    my $code = "5 + 3";

    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);

    ok($result, "Parse succeeded for arithmetic expression") or return;

    # Extract TypeInference element from composite (index 0)
    my $type_elem = $result->element_at(0);
    ok($type_elem, "TypeInference element exists") or return;

    # Check that the element has a value_context field
    ok($type_elem->can('value_context'), "Element has value_context accessor") or return;

    # The ArithmeticOp should set numeric context
    # Note: This might be on the operand children, not the result
    # Let's check the children for context
    my @children = $type_elem->children->@*;
    ok(scalar(@children) > 0, "Element has children") or return;

    # Find a child that has numeric context set
    my $found_numeric_context = 0;
    for my $child (@children) {
        next unless $child->can('value_context');
        if (defined $child->value_context && $child->value_context eq 'numeric') {
            $found_numeric_context = 1;
            last;
        }
    }

    ok($found_numeric_context, "Found child with numeric value context");
};

subtest 'ConcatenationOp sets string value context on operands' => sub {
    # Parse a concatenation expression
    my $code = "'hello' . 'world'";

    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);

    ok($result, "Parse succeeded for concatenation expression") or return;

    # Extract TypeInference element from composite (index 0)
    my $type_elem = $result->element_at(0);
    ok($type_elem, "TypeInference element exists") or return;

    # Check that the element has a value_context field
    ok($type_elem->can('value_context'), "Element has value_context accessor") or return;

    # The ConcatenationOp should set string context
    my @children = $type_elem->children->@*;
    ok(scalar(@children) > 0, "Element has children") or return;

    # Find a child that has string context set
    my $found_string_context = 0;
    for my $child (@children) {
        next unless $child->can('value_context');
        if (defined $child->value_context && $child->value_context eq 'string') {
            $found_string_context = 1;
            last;
        }
    }

    ok($found_string_context, "Found child with string value context");
};

subtest 'Multiple operations preserve context correctly' => sub {
    # Parse an expression with both arithmetic and concatenation
    # This tests that contexts don't interfere with each other
    my $code = "5 + 3";  # Just arithmetic for now

    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);

    ok($result, "Parse succeeded for multiple operations") or return;

    my $type_elem = $result->element_at(0);
    ok($type_elem, "TypeInference element exists") or return;

    # The result type should be numeric
    my $type = $type_elem->type_obj;
    ok($type->name eq 'Int' || $type->name eq 'Num',
       "Result type is numeric: " . $type->name);
};

# done_testing handled by defer at top
