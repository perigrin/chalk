# ABOUTME: SPPF (Shared Packed Parse Forest) semiring implementation for Chalk parser
# ABOUTME: Provides semiring elements that operate on shared ParseForest structure
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::ParseForest;
use Chalk::Semiring::Viterbi;
use Chalk::Semiring::Composite;

# Pure SPPF Element - only tracks forest structure, no scoring
class Chalk::Semiring::SPPFElement :isa(Chalk::Element) {
    field $sppf_node :param :reader;
    field $forest    :param :reader;

    method multiply( $other, $swap = undef ) {
        # Create new combined SPPF node representing sequence
        my $other_node = $other->sppf_node();
        my $combined_node =
          $forest->create_sequence_node( $sppf_node, $other_node );

        return Chalk::Semiring::SPPFElement->new(
            sppf_node => $combined_node,
            forest    => $forest
        );
    }

    method add( $other, $swap = undef ) {
        my $self_start = $sppf_node->start_pos();
        my $self_end = $sppf_node->end_pos();
        my $other_node = $other->sppf_node();
        my $other_start = $other_node->start_pos();
        my $other_end = $other_node->end_pos();

        # Merge alternatives if they span the same range
        if ($self_start == $other_start && $self_end == $other_end) {
            $forest->add_alternative( $sppf_node, $other_node );
        }

        # Prefer element that went further (for consistency with composite pattern)
        # This allows SPPF to work correctly when composed with scoring semirings
        return $self_end >= $other_end ? $self : $other;
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        # Two SPPF elements are equal if they reference the same node
        my $other_node = $other->sppf_node();
        return refaddr($sppf_node) == refaddr($other_node);
    }

    method to_string(@args) {
        return "SPPF:$sppf_node";
    }
}

# Pure SPPF Semiring - only forest tracking, no Viterbi scoring
class Chalk::Semiring::SPPF :isa(Chalk::Semiring) {
    field $shared_context :param :reader = undef;
    field $forest :reader;
    field $root_element :reader;
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        # Use shared forest if provided, otherwise create own
        $forest = defined($shared_context) && exists($shared_context->{forest})
            ? $shared_context->{forest}
            : Chalk::ParseForest->new();

        $root_element = Chalk::Semiring::SPPFElement->new(
            sppf_node => $forest->get_or_create_symbol_node( "ROOT", 0, 0 ),
            forest    => $forest
        );

        $mul_id = Chalk::Semiring::SPPFElement->new(
            sppf_node => $forest->get_or_create_symbol_node( "ε", 0, 0 ),
            forest    => $forest
        );

        $add_id = Chalk::Semiring::SPPFElement->new(
            sppf_node => $forest->get_or_create_symbol_node( "⊥", 0, 0 ),
            forest    => $forest
        );
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        my $lhs = $rule->lhs();
        my $symbol_node =
          $forest->get_or_create_symbol_node( $lhs, $start_pos, $end_pos );

        return Chalk::Semiring::SPPFElement->new(
            sppf_node => $symbol_node,
            forest    => $forest
        );
    }
}

# SPPFViterbi Element - now a wrapper around Composite(SPPF, Viterbi)
# Provides backward compatibility with previous SPPFViterbiElement API
class Chalk::Semiring::SPPFViterbiElement :isa(Chalk::Element) {
    field $composite :param :reader;

    # Convenience accessors for backward compatibility
    method score() {
        return $composite->element_at(1)->score();
    }

    method path() {
        return $composite->element_at(1)->path();
    }

    method sppf_node() {
        return $composite->element_at(0)->sppf_node();
    }

    method forest() {
        return $composite->element_at(0)->forest();
    }

    # Delegate core operations to composite
    method multiply( $other, $swap = undef ) {
        my $other_composite = $other->composite();
        my $result = $composite->multiply($other_composite);
        return Chalk::Semiring::SPPFViterbiElement->new(
            composite => $result
        );
    }

    method add( $other, $swap = undef ) {
        my $other_composite = $other->composite();
        my $result = $composite->add($other_composite);
        return Chalk::Semiring::SPPFViterbiElement->new(
            composite => $result
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        my $other_composite = $other->composite();
        return $composite->equals($other_composite);
    }

    method to_string(@args) {
        my $score = $self->score();
        my $path = $self->path();
        my $node = $self->sppf_node();
        return sprintf( '%.4f[%s] SPPF:%s',
            exp($score), join( ',', $path->@* ), $node );
    }

    # Backward compatibility helpers
    method probability() {
        my $score = $self->score();
        return exp($score);
    }
    method best_path() {
        my $path = $self->path();
        return $path->[0];
    }

    method validate_complete_parse($input_length) {
        my $node = $self->sppf_node();
        return $node->start_pos() == 0 && $node->end_pos() == $input_length;
    }
}

# SPPFViterbi Semiring - now implemented as Composite(SPPF, Viterbi)
# Provides backward compatibility while using clean separation of concerns
class Chalk::Semiring::SPPFViterbiSemiring :isa(Chalk::Semiring) {
    field $composite :reader;
    field $sppf_semiring :reader;
    field $viterbi_semiring :reader;
    field $forest :reader;
    field $root_element :reader;
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        # Create child semirings
        $sppf_semiring = Chalk::Semiring::SPPF->new();
        $viterbi_semiring = Chalk::Semiring::Viterbi->new();

        # Create composite
        $composite = Chalk::Semiring::Composite->new(
            semirings => [$sppf_semiring, $viterbi_semiring]
        );

        # Expose forest for backward compatibility
        $forest = $sppf_semiring->forest();

        # Wrap identity elements
        my $comp_mul_id = $composite->mul_id();
        $mul_id = Chalk::Semiring::SPPFViterbiElement->new(
            composite => $comp_mul_id
        );

        my $comp_add_id = $composite->add_id();
        $add_id = Chalk::Semiring::SPPFViterbiElement->new(
            composite => $comp_add_id
        );

        $root_element = $mul_id;  # For compatibility
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        my $composite_elem = $composite->init_element_from_rule($rule, $start_pos, $end_pos, $matched_value);

        return Chalk::Semiring::SPPFViterbiElement->new(
            composite => $composite_elem
        );
    }
}

1;
