# ABOUTME: Composite semiring for Chalk syntax validation with progressive filtering (Boolean → Precedence → TypeInference → SemanticValidation)
# ABOUTME: Pure validation composite - filters from least to most restrictive, short-circuiting on first invalid result
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::SemanticValidation;
use Chalk::Semiring::TypeInference;
use Chalk::Grammar::Chalk::SemanticRules;
use Chalk::Semiring::Composite;

class Chalk::Semiring::ChalkSyntax :isa(Chalk::Semiring) {
    field $grammar :param :reader;
    field $composite :reader;

    ADJUST {
        # Progressive filtering: least restrictive → most restrictive
        # Each semiring filters independently, short-circuiting on first invalid result

        # Filter 1: Boolean - Grammar syntax validation (least restrictive)
        # Validates that the parse tree matches BNF grammar rules
        my $bool_sr = Chalk::Semiring::Boolean->new();

        # Filter 2: Precedence - Operator precedence validation
        # Validates operator precedence and associativity per Perl's precedence table
        # Reference: perldoc perlop - Operator Precedence and Associativity
        my @perl_precedence_table = (
            # Index 0 - Highest precedence
            # NOTE: '->' removed from precedence table - it's a postfix dereference
            # operator, not a binary expression operator. The grammar structure
            # already enforces its binding. Including it caused conflicts with
            # operators inside subscripts like $ref->[1 + 2].
            { assoc => 'nonassoc', ops => ['++', '--'] },  # postfix
            { assoc => 'right',   ops => ['**'] },
            { assoc => 'right',   ops => ['!', '~', '\\', 'unary +', 'unary -'] },
            { assoc => 'left',    ops => ['=~', '!~'] },
            { assoc => 'left',    ops => ['*', '/', '%', 'x'] },
            { assoc => 'left',    ops => ['+', '-', '.'] },
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
            # Index 22 - Lowest precedence
        );

        my $precedence_sr = Chalk::Semiring::Precedence->new(
            precedence_table => \@perl_precedence_table
        );

        # Filter 3: TypeInference - Type checking during parsing
        # Validates type compatibility using tropical semiring (join/meet) for type lattice
        my $type_sr = Chalk::Semiring::TypeInference->new();

        # Filter 4: SemanticValidation - Semantic constraint validation (most restrictive)
        # Validates Chalk-specific semantic rules like variable scoping, control flow
        my $semantic_rules = Chalk::Grammar::Chalk::SemanticRules->new();
        my $semantic_sr = Chalk::Semiring::SemanticValidation->new(
            rules => $semantic_rules
        );

        # Composite: Boolean → Precedence → TypeInference → SemanticValidation
        # Progressive filtering from least to most restrictive
        # Sequential filtering short-circuits on first invalid result
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$bool_sr, $precedence_sr, $type_sr, $semantic_sr]
        );
    }

    # Delegate semiring methods to composite
    method mul_id() { $composite->mul_id }
    method add_id() { $composite->add_id }
    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        $composite->init_element_from_rule($rule, $start_pos, $end_pos, $matched_value)
    }
    method multiply($x, $y) { $composite->multiply($x, $y) }
    method plus($x, $y) { $composite->plus($x, $y) }
    method semirings() { $composite->semirings }

    # Delegate on_complete() to composite
    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        $composite->on_complete($completed_item, $completed_element, $metadata_element)
    }

    # Delegate on_scan() to composite
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        $composite->on_scan($item, $element, $pos, $matched_value, $pattern_name)
    }

    # Delegate set_diagnostic_context to composite (which propagates to children)
    method set_diagnostic_context($ctx) {
        $composite->set_diagnostic_context($ctx);
    }
}

1;
