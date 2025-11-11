# ABOUTME: Composite semiring for Chalk syntax checking (SPPF + Precedence validation)
# ABOUTME: Used by -c mode for syntax checking without IR generation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Composite;

class Chalk::Semiring::ChalkSyntax :isa(Chalk::Semiring) {
    field $grammar :param :reader;
    field $composite :reader;

    ADJUST {
        # Create SPPF semiring for parse forest
        my $sppf_sr = Chalk::Semiring::SPPF->new();

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

        # Create Composite semiring with SPPF and Precedence
        # This validates syntax and precedence without building IR
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $precedence_sr]
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
    method on_complete($completed_item, $completed_element) {
        $composite->on_complete($completed_item, $completed_element)
    }

    # Delegate on_scan() to composite
    method on_scan($item, $element, $pos, $matched_value) {
        $composite->on_scan($item, $element, $pos, $matched_value)
    }
}

1;
