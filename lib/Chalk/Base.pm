# ABOUTME: Base classes for Chalk parser - Element and Semiring abstractions
# ABOUTME: Provides fundamental algebraic structures used throughout the parser
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);

class Chalk::Element {
    use overload
      '+'        => 'add',
      '*'        => 'multiply',
      '""'       => 'to_string',
      '=='       => 'equals',
      'fallback' => 1;

    method add( $other, $swap = undef )      { ... }
    method multiply( $other, $swap = undef ) { ... }
    method equals( $other, $swap = undef )   { ... }
    method score()                           { ... }
    method to_string()                       { ... }
}

class Chalk::Semiring {
    field $diagnostic_context :reader;

    method init_element_from_rule($rule) { ... }

    # NOOP hook for semirings that need to perform actions when a rule completes parsing
    # Override in subclasses as needed (e.g., Semantic uses this to call evaluate())
    # $metadata_element is optional and provides access to sibling semiring data
    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        return $completed_element;
    }

    # NOOP hook for semirings that need to handle scanned terminal values
    # Override in subclasses as needed (e.g., Semantic accumulates terminal values)
    # Returns the element for the scanned item
    # $pattern_name is optional and contains the name from named regex captures (e.g., 'IDENTIFIER')
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Default: create new element from rule with updated positions
        return $self->init_element_from_rule(
            $item->rule,
            $item->start_pos,
            $pos + length($matched_value),
            $matched_value
        );
    }

    # Set diagnostic context for furthest-failure error reporting
    # Override in subclasses like Composite to propagate to children
    method set_diagnostic_context($ctx) {
        $diagnostic_context = $ctx;
    }

    # Helper to emit an error to the diagnostic context at the furthest position
    # Only records error if position >= current furthest position
    method emit_diagnostic($error_hash) {
        return unless $diagnostic_context;
        my $pos = $error_hash->{start_pos} // 0;

        if ($pos > $diagnostic_context->{furthest_pos}) {
            # New furthest point - replace all previous errors
            $diagnostic_context->{furthest_pos} = $pos;
            $diagnostic_context->{furthest_errors} = [$error_hash];
        } elsif ($pos == $diagnostic_context->{furthest_pos}) {
            # Same position - accumulate
            push $diagnostic_context->{furthest_errors}->@*, $error_hash;
        }
        # else: earlier position - ignore (not relevant)
    }
}

1;
