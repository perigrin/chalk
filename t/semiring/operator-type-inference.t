# ABOUTME: Test that comparison operators infer Bool result type through TypeInference semiring
# ABOUTME: Validates Phase 1 of #433 - operator pattern recognition for numeric and string comparisons

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Grammar::Chalk;  # Pre-load Chalk rule classes for semantic actions
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
# This allows the custom rule classes (like ComparisonOp) to have their infer_type() methods called
my $type_sr = Chalk::Semiring::TypeInference->new();
my $sem_sr = Chalk::Semiring::Semantic->new(grammar => $grammar);
my $semiring = Chalk::Semiring::Composite->new(
    semirings => [$type_sr, $sem_sr]
);

subtest 'Numeric comparison operators infer Bool result' => sub {
    # Test each numeric comparison operator
    my @numeric_ops = (
        ['>', 'greater than'],
        ['<', 'less than'],
        ['>=', 'greater than or equal'],
        ['<=', 'less than or equal'],
        ['==', 'equal'],
        ['!=', 'not equal'],
    );

    for my $op_pair (@numeric_ops) {
        my ($op, $desc) = @$op_pair;
        my $code = "5 $op 3";

        my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
        my $result = $parser->parse_string($code);

        ok($result, "Parse succeeded for numeric $desc ($op)") or next;

        # Extract TypeInference element from composite (index 0)
        my $type_elem = $result->element_at(0);
        ok($type_elem, "TypeInference element exists for $op") or next;

        my $type = $type_elem->type_obj;
        ok($type, "Type object exists for $op") or next;

        # Check that the result type is Boolean
        is($type->name, 'Boolean', "Numeric $desc ($op) infers Boolean type");
    }
};

subtest 'String comparison operators infer Bool result' => sub {
    # Test each string comparison operator
    my @string_ops = (
        ['gt', 'greater than'],
        ['lt', 'less than'],
        ['ge', 'greater than or equal'],
        ['le', 'less than or equal'],
        ['eq', 'equal'],
        ['ne', 'not equal'],
    );

    for my $op_pair (@string_ops) {
        my ($op, $desc) = @$op_pair;
        my $code = "'hello' $op 'world'";

        my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
        my $result = $parser->parse_string($code);

        ok($result, "Parse succeeded for string $desc ($op)") or next;

        # Extract TypeInference element from composite (index 0)
        my $type_elem = $result->element_at(0);
        ok($type_elem, "TypeInference element exists for $op") or next;

        my $type = $type_elem->type_obj;
        ok($type, "Type object exists for $op") or next;

        # Check that the result type is Boolean
        is($type->name, 'Boolean', "String $desc ($op) infers Boolean type");
    }
};

subtest 'Comparison operators with variables' => sub {
    # Test that comparison operators work with variables
    my $code = '$x > $y';

    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);

    ok($result, "Parse succeeded for comparison with variables");

    if ($result) {
        my $type_elem = $result->element_at(0);
        ok($type_elem, "TypeInference element exists for variable comparison");

        if ($type_elem) {
            my $type = $type_elem->type_obj;
            ok($type, "Type object exists for variable comparison");

            if ($type) {
                is($type->name, 'Boolean', "Variable comparison infers Boolean type");
            }
        }
    }
};

subtest 'Nested comparisons' => sub {
    # Test compound expressions involving comparisons
    # Note: This may not parse as ComparisonOp directly due to precedence
    my $code = '(5 > 3)';

    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);

    ok($result, "Parse succeeded for nested comparison");

    if ($result) {
        my $type_elem = $result->element_at(0);
        ok($type_elem, "TypeInference element exists for nested comparison");

        if ($type_elem) {
            my $type = $type_elem->type_obj;
            ok($type, "Type object exists for nested comparison");

            if ($type) {
                # The type should propagate through the parentheses
                ok($type->name eq 'Boolean' || $type->name eq 'Any',
                   "Nested comparison has appropriate type: " . $type->name);
            }
        }
    }
};

# done_testing handled by defer at top
