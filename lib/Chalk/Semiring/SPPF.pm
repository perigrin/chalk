# ABOUTME: SPPF (Shared Packed Parse Forest) implementation for Chalk parser
# ABOUTME: Provides classes for representing ambiguous parse forests and Viterbi elements
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

# SPPF (Shared Packed Parse Forest) Node Classes
class Chalk::Semiring::SPPFSymbolNode {
    use overload '""' => 'to_string';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;
    field @packed_nodes;

    method add_packed_node($packed_node) {
        push( @packed_nodes, $packed_node );
    }

    method packed_nodes() { @packed_nodes }

    method to_string(@) {
        return "$symbol\[$start_pos,$end_pos\]";
    }

    method key() { "$symbol|$start_pos|$end_pos" }
}

class Chalk::Semiring::SPPFPackedNode {
    use overload '""' => 'to_string';

    field $rule :param :reader;
    field @children;

    method add_child($child) {
        push( @children, $child );
    }

    method children() { @children }

    method to_string(@) {
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

    method to_string(@) {
        return "'$symbol'\[$start_pos,$end_pos\]";
    }

    method key() { "$symbol|$start_pos|$end_pos" }
}

class Chalk::Semiring::SPPFViterbiElement :isa(Chalk::Element) {
    field $score     :param :reader;
    field $path      :param :reader;
    field $sppf_node :param :reader;
    field $forest    :param :reader;

    method multiply( $other, $swap = undef ) {

        # Create new combined SPPF node representing sequence
        my $combined_node =
          $forest->create_sequence_node( $sppf_node, $other->sppf_node );

        return Chalk::Semiring::SPPFViterbiElement->new(
            score     => $score + $other->score,
            path      => [ $path->@*, $other->path->@* ],
            sppf_node => $combined_node,
            forest    => $forest
        );
    }

    method add( $other, $swap = undef ) {
        my $self_start = $sppf_node->start_pos;
        my $self_end = $sppf_node->end_pos;
        my $other_start = $other->sppf_node->start_pos;
        my $other_end = $other->sppf_node->end_pos;

        if ($self_start == $other_start && $self_end == $other_end) {
            $forest->add_alternative( $sppf_node, $other->sppf_node );
        }

        return $self if $score > $other->score;
        return $other;
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $score == $other->score
          && join( ',', $path->@* ) eq join( ',', $other->path->@* );
    }

    method to_string(@) {
        return sprintf( '%.4f[%s] SPPF:%s',
            exp($score), join( ',', $path->@* ), $sppf_node );
    }

    method probability() { exp($score) }
    method best_path()   { $path->[0] }

    method validate_complete_parse($input_length) {
        return $sppf_node->start_pos == 0 && $sppf_node->end_pos == $input_length;
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
        my $start = $left_node->start_pos;
        my $end = $right_node->end_pos;

        my $seq_node = $self->get_or_create_symbol_node( "SEQ", $start, $end );

        my $packed = Chalk::Semiring::SPPFPackedNode->new( rule => undef );
        $packed->add_child($left_node);
        $packed->add_child($right_node);
        $seq_node->add_packed_node($packed);

        return $seq_node;
    }

    method add_alternative( $node1, $node2 ) {

        # TODO: Implement proper SPPF alternative merging
        # For now, just add the alternative as a packed node (placeholder)
        if ( $node1 isa Chalk::Semiring::SPPFSymbolNode && $node2 isa Chalk::Semiring::SPPFSymbolNode ) {

            # Add packed node representing the alternative
            my $packed = Chalk::Semiring::SPPFPackedNode->new( rule => undef );
            $packed->add_child($node2);
            $node1->add_packed_node($packed);
        }
    }

    method nodes() {
        return \%symbol_nodes;
    }
}

class Chalk::Semiring::SPPFViterbiSemiring :isa(Chalk::Semiring) {
    field $forest :reader;
    field $root_element :reader;
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        $forest = Chalk::Semiring::SPPFForest->new();

        $root_element = Chalk::Semiring::SPPFViterbiElement->new(
            score     => 0,
            path      => [],
            sppf_node => $forest->get_or_create_symbol_node( "ROOT", 0, 0 ),
            forest    => $forest
        );

        $mul_id = Chalk::Semiring::SPPFViterbiElement->new(
            score     => 0,
            path      => ['ε'],
            sppf_node => $forest->get_or_create_symbol_node( "ε", 0, 0 ),
            forest    => $forest
        );

        $add_id = Chalk::Semiring::SPPFViterbiElement->new(
            score     => -1e10,
            path      => [],
            sppf_node => $forest->get_or_create_symbol_node( "⊥", 0, 0 ),
            forest    => $forest
        );
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        my $symbol_node =
          $forest->get_or_create_symbol_node( $rule->lhs, $start_pos, $end_pos );

        return Chalk::Semiring::SPPFViterbiElement->new(
            score     => log( $rule->probability ),
            path      => [$rule],
            sppf_node => $symbol_node,
            forest    => $forest
        );
    }
}

1;
