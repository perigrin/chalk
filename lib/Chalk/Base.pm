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
    method init_element_from_rule($rule) { ... }

    # NOOP hook for semirings that need to perform actions when a rule completes parsing
    # Override in subclasses as needed (e.g., Semantic uses this to call evaluate())
    # $composite_element is optional and provides access to sibling semiring data
    method on_complete($completed_item, $completed_element, $composite_element = undef) {
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
}

1;
