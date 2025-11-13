# ABOUTME: Specialized composite semiring for Chalk IR generation
# ABOUTME: Combines SPPF parse forest, precedence validation, and semantic IR building
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::IR::Builder;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;

class Chalk::Semiring::ChalkIR :isa(Chalk::Semiring) {
    field $grammar :param :reader;
    field $builder :reader;
    field $composite :reader;

    ADJUST {
        # Create IR Builder BEFORE creating composite semiring
        $builder = Chalk::IR::Builder->new();

        # Create SPPF semiring for parse forest
        # This builds the complete ambiguous parse forest
        my $sppf_sr = Chalk::Semiring::SPPF->new();

        # Get the forest from SPPF to share with Semantic
        # This allows semantic actions to query alternatives via EvalContext
        my $forest = $sppf_sr->forest();

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
            precedence_table => \@perl_precedence_table,
            shared_context => { forest => $forest }
        );

        # Create Semantic semiring with IR builder in environment
        # Pass forest via shared_context so it's available in EvalContext
        my $semantic_sr = Chalk::Semiring::Semantic->new(
            grammar => $grammar,
            env => { ir_builder => $builder },
            shared_context => { forest => $forest }
        );

        # Use Composite with SPPF, Precedence, and Semantic
        # SPPF builds complete ambiguous forest
        # Precedence validates operator precedence during parsing (returns invalid for bad parses)
        # Semantic builds IR
        # Precedence.add() prefers valid over invalid, so invalid parses are automatically filtered
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $precedence_sr, $semantic_sr]
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
    method on_complete($completed_item, $completed_element) {
        $composite->on_complete($completed_item, $completed_element)
    }

    # Delegate on_scan() to composite (which delegates to wrapped semirings)
    method on_scan($item, $element, $pos, $matched_value) {
        $composite->on_scan($item, $element, $pos, $matched_value)
    }
}

1;
