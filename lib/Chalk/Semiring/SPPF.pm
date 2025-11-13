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
# Lazy SPPF construction: accumulates children during multiply,
# creates actual forest nodes only when rules complete in on_complete()
class Chalk::Semiring::SPPFElement :isa(Chalk::Element) {
    field $sppf_node :param :reader = undef;  # SPPF node (symbol or intermediate)
    field $children :param :reader = [];       # Child elements for lazy construction
    field $forest    :param :reader;
    field $rule      :param :reader = undef;   # Grammar rule this element is parsing
    field $position  :param :reader = undef;   # Dot position in rule (how many RHS symbols processed)
    field $start_pos :param :reader = undef;   # Track span even without node
    field $end_pos   :param :reader = undef;

    method multiply( $other, $swap = undef ) {
        # Scott's algorithm: create nodes during parsing with full rule context
        # Key insight: each child should already have its own SPPF node

        # Determine span of combined element
        my $self_start = $start_pos // ($sppf_node ? $sppf_node->start_pos : 0);
        my $self_end = $end_pos // ($sppf_node ? $sppf_node->end_pos : 0);
        my $other_start = $other->start_pos // ($other->sppf_node ? $other->sppf_node->start_pos : 0);
        my $other_end = $other->end_pos // ($other->sppf_node ? $other->sppf_node->end_pos : 0);

        # If we have rule context, track position advancement
        my $new_position = defined($position) ? $position + 1 : undef;

        # For now, keep lazy construction but propagate rule context
        # Children will be converted to packed nodes in on_complete()
        return Chalk::Semiring::SPPFElement->new(
            children  => [$self, $other],
            forest    => $forest,
            rule      => $rule,           # Propagate rule context
            position  => $new_position,   # Track how many RHS symbols processed
            start_pos => $self_start,
            end_pos   => $other_end,
        );
    }

    method add( $other, $swap = undef ) {
        # Get spans - use stored positions if no node yet
        my $self_start = $start_pos // ($sppf_node ? $sppf_node->start_pos : 0);
        my $self_end = $end_pos // ($sppf_node ? $sppf_node->end_pos : 0);
        my $other_start = $other->start_pos // ($other->sppf_node ? $other->sppf_node->start_pos : 0);
        my $other_end = $other->end_pos // ($other->sppf_node ? $other->sppf_node->end_pos : 0);

        # Merge alternatives if they span the same range AND both have nodes
        if ($self_start == $other_start && $self_end == $other_end) {
            if ($sppf_node && $other->sppf_node) {
                $forest->add_alternative( $sppf_node, $other->sppf_node );

                # Prefer elements with nodes over those without
                # (nodes are created in on_complete, so they have proper LHS symbols)
                return $self;  # Both have nodes, return self
            }
            # If only one has a node, prefer it
            return $sppf_node ? $self : $other;
        }

        # Prefer element that went further (for consistency with composite pattern)
        return $self_end >= $other_end ? $self : $other;
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        # Two SPPF elements are equal if they reference the same node
        my $other_node = $other->sppf_node();
        # Handle cases where nodes might be undef (lazy construction)
        return 0 unless defined($sppf_node) && defined($other_node);
        return refaddr($sppf_node) == refaddr($other_node);
    }

    method to_string(@args) {
        if ($sppf_node) {
            return "SPPF:$sppf_node";
        } else {
            my $child_count = scalar(@{$children // []});
            return "SPPF:lazy($child_count children)";
        }
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
        # Create terminal/leaf node for matched input
        # This is called when a terminal symbol is matched
        my $lhs = $rule->lhs();
        my $symbol_node =
          $forest->get_or_create_symbol_node( $lhs, $start_pos, $end_pos );

        return Chalk::Semiring::SPPFElement->new(
            sppf_node => $symbol_node,
            forest    => $forest,
            rule      => $rule,       # Track rule context from the start
            position  => 0,           # Just started parsing this rule
            start_pos => $start_pos,
            end_pos   => $end_pos,
        );
    }

    method on_complete($completed_item, $completed_element) {
        # THIS is where we create actual SPPF nodes!
        # We have the complete rule context including LHS symbol
        my $lhs = $completed_item->rule->lhs;
        my $start = $completed_item->start_pos;
        my $end = $completed_item->end_pos;

        # Check if the completed element already has the correct LHS node
        if ($completed_element->sppf_node &&
            $completed_element->sppf_node->symbol eq $lhs &&
            $completed_element->sppf_node->start_pos == $start &&
            $completed_element->sppf_node->end_pos == $end) {
            # Already created (shouldn't happen with lazy construction, but be safe)
            return $completed_element;
        }

        # Create LHS symbol node
        my $lhs_node = $forest->get_or_create_symbol_node($lhs, $start, $end);

        # Extract child nodes from accumulated children
        # Key insight: recursively ensure all children have SPPF nodes
        my @child_nodes = $self->_extract_child_nodes($completed_element, $completed_item->rule);

        sub _extract_child_nodes {
            my ($self, $element, $rule) = @_;
            my @nodes;

            my $elem_children = $element->children // [];
            if (@$elem_children) {
                # Element has children from multiply operations
                for my $child (@$elem_children) {
                    if ($child->sppf_node) {
                        # Child already has a node (terminal or completed rule)
                        push @nodes, $child->sppf_node;
                    } else {
                        # Child has no node - recursively process its children
                        my @grandchild_nodes = $self->_extract_child_nodes($child, $rule);
                        if (@grandchild_nodes) {
                            # Create intermediate node for this child's sequence
                            # For now, just flatten the grandchildren
                            push @nodes, @grandchild_nodes;
                        }
                    }
                }
            } elsif ($element->sppf_node) {
                # Element is a terminal or already-completed non-terminal
                @nodes = ($element->sppf_node);
            }
            # Empty case: no children and no node = epsilon

            return @nodes;
        }

        # Create packed node with children
        my $packed = Chalk::ParseForest::PackedNode->new(rule => $completed_item->rule);
        for my $child_node (@child_nodes) {
            $packed->add_child($child_node);
        }
        $lhs_node->add_packed_node($packed);

        return Chalk::Semiring::SPPFElement->new(
            sppf_node => $lhs_node,
            forest => $forest,
            start_pos => $start,
            end_pos => $end,
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
        my $node_str = $node ? "$node" : "lazy";
        return sprintf( '%.4f[%s] SPPF:%s',
            exp($score), join( ',', $path->@* ), $node_str );
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

    method on_complete($completed_item, $completed_element) {
        # Unwrap SPPFViterbiElement to get composite
        my $composite_elem = $completed_element->composite();

        # Delegate to composite semiring (which delegates to SPPF and Viterbi)
        my $result_composite = $composite->on_complete($completed_item, $composite_elem);

        # Wrap result back into SPPFViterbiElement
        return Chalk::Semiring::SPPFViterbiElement->new(
            composite => $result_composite
        );
    }
}

1;
