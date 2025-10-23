# ABOUTME: SPPF (Shared Packed Parse Forest) implementation for Chalk parser
# ABOUTME: Provides classes for representing ambiguous parse forests and Viterbi elements
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Semiring::Viterbi;
use Chalk::Semiring::Composite;

# SPPF (Shared Packed Parse Forest) Node Classes
class Chalk::Semiring::SPPFSymbolNode {
    use overload '""' => 'to_string';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;
    field @packed_nodes;

    method add_packed_node($packed_node) {
        my @new_children = $packed_node->children();

        # Check if we already have a packed node with the same children
        for my $existing (@packed_nodes) {
            my @existing_children = $existing->children();

            # Different sizes can't be duplicates, skip
            next unless @existing_children == @new_children;

            # Same size - check if all children are identical references
            my $all_match = 1;
            for my $i (0..$#existing_children) {
                unless (refaddr($existing_children[$i]) == refaddr($new_children[$i])) {
                    $all_match = 0;
                    last;
                }
            }
            return if $all_match;  # Found exact duplicate, don't add
        }

        push( @packed_nodes, $packed_node );
    }

    method packed_nodes() { @packed_nodes }

    method to_string(@args) {
        return "$symbol\[$start_pos(),$end_pos()\]";
    }

    method key() { "$symbol()|$start_pos()|$end_pos()" }
}

class Chalk::Semiring::SPPFPackedNode {
    use overload '""' => 'to_string';

    field $rule :param :reader;
    field @children;

    method add_child($child) {
        push( @children, $child );
    }

    method children() { @children }

    method to_string(@args) {
        my $rule_str     = $rule ? $rule->to_string : "terminal";
        my $children_str = join( ", ", map { "$_" } @children );
        return "$rule_str -> [$children_str]";
    }
}

class Chalk::Semiring::SPPFTerminalNode {
    use overload '""' => 'to_string';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;

    method to_string(@args) {
        return "'$symbol'\[$start_pos(),$end_pos()\]";
    }

    method key() { "$symbol()|$start_pos()|$end_pos()" }
}

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
    field $forest :reader;
    field $root_element :reader;
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        $forest = Chalk::Semiring::SPPFForest->new();

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

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
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

class Chalk::Semiring::SPPFForest {
    field %symbol_nodes;
    field %terminal_nodes;

    method get_or_create_symbol_node( $symbol, $start_pos, $end_pos ) {
        my $key = "$symbol|$start_pos|$end_pos";
        return $symbol_nodes{$key} //= Chalk::Semiring::SPPFSymbolNode->new(
            symbol    => $symbol,
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method get_or_create_terminal_node( $symbol, $start_pos, $end_pos ) {
        my $key = "$symbol|$start_pos|$end_pos";
        return $terminal_nodes{$key} //= Chalk::Semiring::SPPFTerminalNode->new(
            symbol    => $symbol,
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method create_sequence_node( $left_node, $right_node ) {
        my $start = $left_node->start_pos();
        my $end = $right_node->end_pos();

        my $seq_node = $self->get_or_create_symbol_node( "SEQ", $start, $end );

        my $packed = Chalk::Semiring::SPPFPackedNode->new( rule => undef );
        $packed->add_child($left_node);
        $packed->add_child($right_node);
        $seq_node->add_packed_node($packed);  # add_packed_node handles de-duplication

        return $seq_node;
    }

    method add_alternative( $node1, $node2 ) {
        my $class = 'Chalk::Semiring::SPPFSymbolNode';
        return unless ref($node1) eq $class && ref($node2) eq $class;

        # Merge all packed nodes from node2 into node1
        my @nodes = $node2->packed_nodes();
        for my $packed (@nodes) {
            $node1->add_packed_node($packed);  # add_packed_node handles de-duplication
        }
    }

    method nodes() {
        return \%symbol_nodes;
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

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        my $composite_elem = $composite->init_element_from_rule($rule, $start_pos, $end_pos);

        return Chalk::Semiring::SPPFViterbiElement->new(
            composite => $composite_elem
        );
    }
}

1;
