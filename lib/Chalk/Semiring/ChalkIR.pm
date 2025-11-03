# ABOUTME: Specialized composite semiring for Chalk IR generation
# ABOUTME: Combines SPPF parse forest with semantic IR building
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::IR::Builder;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Semantic;
use Chalk::Semiring::Composite;

class Chalk::Semiring::ChalkIR {
    field $grammar :param :reader;
    field $builder :reader;
    field $composite :reader;

    ADJUST {
        # Create IR Builder BEFORE creating composite semiring
        $builder = Chalk::IR::Builder->new();

        # Create SPPF semiring for parse forest
        my $sppf_sr = Chalk::Semiring::SPPF->new();

        # Create Semantic semiring with IR builder in environment
        my $semantic_sr = Chalk::Semiring::Semantic->new(
            grammar => $grammar,
            env => { ir_builder => $builder }
        );

        # Create Composite semiring with both components
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $semantic_sr]
        );
    }

    # Delegate semiring methods to composite
    method mul_id() { $composite->mul_id }
    method add_id() { $composite->add_id }
    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        $composite->init_element_from_rule($rule, $start_pos, $end_pos)
    }
    method multiply($x, $y) { $composite->multiply($x, $y) }
    method plus($x, $y) { $composite->plus($x, $y) }
    method semirings() { $composite->semirings }
}

1;
