# ABOUTME: SPPF (Shared Packed Parse Forest) implementation for Chalk parser
# ABOUTME: Provides classes for representing ambiguous parse forests and Viterbi elements
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

# SPPF (Shared Packed Parse Forest) Node Classes
class Chalk::SPPFSymbolNode {
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

class Chalk::SPPFPackedNode {
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

class Chalk::SPPFTerminalNode {
    use overload '""' => 'to_string';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;

    method to_string(@) {
        return "'$symbol'\[$start_pos,$end_pos\]";
    }

    method key() { "$symbol|$start_pos|$end_pos" }
}

class Chalk::SPPFViterbiElement :isa(Chalk::Element) {
    field $score     :param :reader;
    field $path      :param :reader;
    field $sppf_node :param :reader;
    field $forest    :param :reader;

    method multiply( $other, $swap = undef ) {

        # Create new combined SPPF node representing sequence
        my $combined_node =
          $forest->create_sequence_node( $sppf_node, $other->sppf_node );

        return Chalk::SPPFViterbiElement->new(
            score     => $score + $other->score,
            path      => [ $path->@*, $other->path->@* ],
            sppf_node => $combined_node,
            forest    => $forest
        );
    }

    method add( $other, $swap = undef ) {

        # Add alternative to SPPF while keeping best score
        $forest->add_alternative( $sppf_node, $other->sppf_node );

        # Return the better scoring element (classic Viterbi behavior)
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
}

class Chalk::SPPFForest {
    field %symbol_nodes;
    field %terminal_nodes;

    method get_or_create_symbol_node( $symbol, $start_pos, $end_pos ) {
        my $key = "$symbol|$start_pos|$end_pos";
        return $symbol_nodes{$key} //= Chalk::SPPFSymbolNode->new(
            symbol    => $symbol,
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method get_or_create_terminal_node( $symbol, $start_pos, $end_pos ) {
        my $key = "$symbol|$start_pos|$end_pos";
        return $terminal_nodes{$key} //= Chalk::SPPFTerminalNode->new(
            symbol    => $symbol,
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method create_sequence_node( $left_node, $right_node ) {

 # TODO: Implement proper SPPF sequence node construction
 # For now, just return the left node (placeholder for proper SPPF construction)
        return $left_node;
    }

    method add_alternative( $node1, $node2 ) {

        # TODO: Implement proper SPPF alternative merging
        # For now, just add the alternative as a packed node (placeholder)
        if ( $node1 isa Chalk::SPPFSymbolNode && $node2 isa Chalk::SPPFSymbolNode ) {

            # Add packed node representing the alternative
            my $packed = Chalk::SPPFPackedNode->new( rule => undef );
            $packed->add_child($node2);
            $node1->add_packed_node($packed);
        }
    }

    method nodes() {
        return \%symbol_nodes;
    }
}

class Chalk::SPPFViterbiSemiring :isa(Chalk::Semiring) {
    field $forest :reader;
    field $root_element :reader;
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        $forest = Chalk::SPPFForest->new();

        $root_element = Chalk::SPPFViterbiElement->new(
            score     => 0,
            path      => [],
            sppf_node => $forest->get_or_create_symbol_node( "ROOT", 0, 0 ),
            forest    => $forest
        );

        $mul_id = Chalk::SPPFViterbiElement->new(
            score     => 0,
            path      => ['ε'],
            sppf_node => $forest->get_or_create_symbol_node( "ε", 0, 0 ),
            forest    => $forest
        );

        $add_id = Chalk::SPPFViterbiElement->new(
            score     => -1e10,
            path      => [],
            sppf_node => $forest->get_or_create_symbol_node( "⊥", 0, 0 ),
            forest    => $forest
        );
    }

    method init_element_from_rule($rule) {
        my $symbol_node =
          $forest->get_or_create_symbol_node( $rule->lhs, 0, 0 );

        return Chalk::SPPFViterbiElement->new(
            score     => log( $rule->probability ),
            path      => [$rule],
            sppf_node => $symbol_node,
            forest    => $forest
        );
    }
}

1;
