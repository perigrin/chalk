# ABOUTME: Specialized composite semiring for Chalk IR generation
# ABOUTME: Combines precedence validation and semantic IR building
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::IR::Node::Scope;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;

class Chalk::Semiring::ChalkIR :isa(Chalk::Semiring) {
    field $grammar :param :reader;
    field $scope :reader;
    field $composite :reader;

    ADJUST {
        # Create Scope for variable tracking (replaces Builder)
        $scope = Chalk::IR::Node::Scope->new();

        # Create Precedence semiring with full Perl operator precedence table
        # Reference: perldoc perlop - Operator Precedence and Associativity
        my @perl_precedence_table = (
            # Index 0 - Highest precedence
            { assoc => 'left',    ops => ['->'] },
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

        # Create Semantic semiring with scope in environment (no Builder needed)
        my $semantic_sr = Chalk::Semiring::Semantic->new(
            grammar => $grammar,
            env => { scope => $scope }
        );

        # Use Composite with Precedence and Semantic
        # Precedence validates operator precedence during parsing (returns invalid for bad parses)
        # Semantic builds IR via Rule classes creating nodes directly
        # Precedence.add() prefers valid over invalid, so invalid parses are automatically filtered
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$precedence_sr, $semantic_sr]
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

    # Delegate on_complete() to composite (which delegates to wrapped semirings)
    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        $composite->on_complete($completed_item, $completed_element, $metadata_element)
    }

    # Delegate on_scan() to composite (which delegates to wrapped semirings)
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        $composite->on_scan($item, $element, $pos, $matched_value, $pattern_name)
    }
}

1;
