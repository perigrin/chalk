# ABOUTME: AST semiring for building abstract syntax trees during parsing
# ABOUTME: Produces tree structure mirroring grammar rules for parse verification

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::ASTElement :isa(Chalk::Element) {
    field $rule_name :param :reader =
      undef;    # Grammar rule name (e.g., 'ArithmeticOp')
    field $children :param :reader =
      [];       # Array of child ASTElements or terminal values
    field $terminal :param :reader  = undef;   # Terminal value (for leaf nodes)
    field $start_pos :param :reader = 0;
    field $end_pos :param :reader   = 0;

    method add( $other, $swap = undef ) {

        # Choose between alternative parses
        # Handle undef or wrong type
        return $self unless defined $other;
        return $self
          unless ref($other) && $other->isa('Chalk::Semiring::ASTElement');

        # If self has no rule (is identity), return other
        return $other
          if !defined($rule_name)
          && !defined($terminal)
          && scalar( $children->@* ) == 0;

        # If other has no content, return self
        return $self
          if !defined( $other->rule_name )
          && !defined( $other->terminal )
          && scalar( $other->children->@* ) == 0;

        # Both have content - prefer self (first alternative)
        return $self;
    }

    method multiply( $other, $swap = undef ) {

        # Build up children during parsing
        return $self unless defined $other;
        return $self
          unless ref($other) && $other->isa('Chalk::Semiring::ASTElement');

        # Debug: trace multiply
        if ( $ENV{DEBUG_AST_MUL} ) {
            my $self_rule  = $self->rule_name // 'undef';
            my $other_rule = $other->rule_name
              // ( $other->terminal ? "term:" . $other->terminal : 'undef' );
            warn "AST multiply: self=$self_rule, other=$other_rule\n";
        }

        # Accumulate children
        my @new_children = ( $self->children->@*, $other );

        return Chalk::Semiring::ASTElement->new(
            rule_name => $self->rule_name,
            children  => \@new_children,
            start_pos => $self->start_pos,
            end_pos   => $other->end_pos
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);
        return refaddr($self) == refaddr($other) ? 1 : 0;
    }

    method score() {
        return 1;
    }

    method to_string(@args) {
        if ( defined($terminal) ) {
            return "Terminal($terminal)";
        }
        elsif ( defined($rule_name) ) {
            return "AST($rule_name)";
        }
        else {
            return "ASTElement";
        }
    }

    # Convert AST to nested hash structure for JSON serialization
    method to_hash() {
        if ( defined( $self->terminal ) ) {

            # Leaf node - just return the terminal value
            return $self->terminal;
        }

        my $result = {
            rule => $self->rule_name,
            span => [ $self->start_pos, $self->end_pos ]
        };

        # Process children
        my $my_children = $self->children;
        if ( scalar( $my_children->@* ) > 0 ) {
            my @child_hashes;
            for my $child ( $my_children->@* ) {
                if ( ref($child) && $child->can('to_hash') ) {
                    push @child_hashes, $child->to_hash();
                }
                elsif ( ref($child) ) {

                    # Fallback for other refs
                    push @child_hashes, "$child";
                }
                else {
                    # Scalar value
                    push @child_hashes, $child;
                }
            }
            $result->{children} = \@child_hashes;
        }

        return $result;
    }
}

class Chalk::Semiring::AST :isa(Chalk::Semiring) {

    field $mul_id :reader = Chalk::Semiring::ASTElement->new(
        rule_name => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0
    );

    field $add_id :reader = Chalk::Semiring::ASTElement->new(
        rule_name => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0
    );

    method zero() {
        return $add_id;
    }

    method one() {
        return $mul_id;
    }

    method init_element_from_rule(
        $rule,
        $start_pos     = 0,
        $end_pos       = 0,
        $matched_value = undef
      )
    {
        # Create element for rule with rule_name set immediately
        # Stringify lhs in case it's a blessed object
        my $rule_name = "" . ( $rule->lhs // 'UNKNOWN' );
        return Chalk::Semiring::ASTElement->new(
            rule_name => $rule_name,
            children  => [],
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method multiply( $x, $y ) {
        return $x->multiply($y);
    }

    method plus( $x, $y ) {
        return $x->add($y);
    }

# Called when a token is scanned - create terminal node and multiply with element
    method on_scan( $item, $element, $pos, $matched_value,
        $pattern_name = undef )
    {
        my $value        = defined($matched_value) ? "$matched_value" : '';
        my $match_length = length($value);

        # Create terminal element
        my $terminal_element = Chalk::Semiring::ASTElement->new(
            terminal  => $value,
            start_pos => $pos,
            end_pos   => $pos + $match_length
        );

        # Multiply to accumulate terminal into the rule element
        return $element->multiply($terminal_element);
    }

    # Called when a rule completes - finalize node with rule name
    method on_complete( $completed_item, $completed_element,
        $metadata_element = undef )
    {
        # Stringify lhs in case it's a blessed object
        my $rule_name = "" . ( $completed_item->rule->lhs // 'UNKNOWN' );

        # Debug: trace on_complete calls
        if ( $ENV{DEBUG_AST} ) {
            warn "AST on_complete: $rule_name, element rule="
              . ( $completed_element->rule_name // 'undef' ) . "\n";
        }

        # Filter out whitespace-only children for cleaner AST
        my @filtered_children;
        for my $child ( $completed_element->children->@* ) {

            # Skip whitespace terminals
            if (   ref($child)
                && $child->can('terminal')
                && defined( $child->terminal ) )
            {
                my $term = $child->terminal;
                next if $term =~ m/^\s*$/;    # Skip whitespace-only
            }

            # Skip WS_OPT and WS_ELEMENT rule nodes
            if (   ref($child)
                && $child->can('rule_name')
                && defined( $child->rule_name ) )
            {
                my $rn = $child->rule_name;
                next if $rn eq 'WS_OPT' || $rn eq 'WS_ELEMENT';
            }
            push @filtered_children, $child;
        }

# Create new element with this rule's name (may override init_element_from_rule)
        return Chalk::Semiring::ASTElement->new(
            rule_name => $rule_name,
            children  => \@filtered_children,
            start_pos => $completed_element->start_pos,
            end_pos   => $completed_element->end_pos
        );
    }
}

1;
