# ABOUTME: Semantic semiring for building values during parsing with evaluation contexts
# ABOUTME: Tracks contexts and enables semantic actions via EvalContext comonad

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Scalar;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Type::Any;

class Chalk::Semiring::SemanticElement :isa(Chalk::Element) {
    field $value     :param :reader;    # Computed semantic value
    field $context   :param :reader;    # Evaluation context
    field $sppf_node :param = undef;    # Optional SPPF node

    method add( $other, $swap = undef ) {

        # Handle undef or wrong type for $other
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('context');

        # For alternatives (choice), prefer non-zero value
        # If self has value 0 (is add_id), return other
        if ( $value == 0 ) {
            return $other;
        }

       # Prefer elements with evaluated focus (defined) over unevaluated (undef)
       # This handles the case where we update the chart after evaluation
        my $self_focus  = $self->context->focus;
        my $other_focus = $other->context->focus;

        if ( !defined($self_focus) && defined($other_focus) ) {
            return $other;
        }
        if ( defined($self_focus) && !defined($other_focus) ) {
            return $self;
        }

        # For semantic values, prefer the alternative that consumed more input
        # (this handles ambiguous parses - longer parse is more complete)
        # Use parse span (end_pos - start_pos) as primary ranking
        my $self_span  = $self->context->end_pos - $self->context->start_pos;
        my $other_span = $other->context->end_pos - $other->context->start_pos;

        if ( $other_span > $self_span ) {
            return $other;    # Other consumed more input, prefer it
        }
        if ( $self_span > $other_span ) {
            return $self;     # Self consumed more input, prefer it
        }

     # If spans are equal, prefer the alternative with more children
     # (handles cases where both consumed same input but one has more structure)
        my $self_children  = scalar( @{ $self->context->children } );
        my $other_children = scalar( @{ $other->context->children } );

        if ( $other_children > $self_children ) {
            return $other;
        }

        # Otherwise prefer self (first alternative)
        return $self;
    }

    method multiply( $other, $swap = undef ) {

        # Handle undef or wrong type for $other
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('context');

       # For sequences, append other's context to self's children
       # This builds up the children list as we advance the dot through the rule
        my @new_children = ( @{ $self->context->children }, $other->context );

    # Type propagation: keep the type from self's context (the rule being built)
        my $combined_ctx = Chalk::EvalContext->new(
            focus     => undef,                       # Not yet evaluated
            children  => \@new_children,
            start_pos => $self->context->start_pos,
            end_pos   => $other->context->end_pos,
            env       => $self->context->env,
            grammar   => $self->context->grammar,
            rule      => $self->context->rule,
            forest    => $self->context->forest,
            type      => $self->context->type,        # Propagate type from rule
            metadata_element => $self->context->metadata_element  # Propagate metadata
        );

        return Chalk::Semiring::SemanticElement->new(
            value     => 1,                           # Success value
            context   => $combined_ctx,
            sppf_node => $sppf_node
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);

        # Use refaddr for reference equality to avoid recursion
        # For semantic semiring, we want elements to be considered non-equal
        # to add_id unless they are literally the same object
        return refaddr($self) == refaddr($other) ? 1 : 0;
    }

    method score() {

        # Semantic semiring doesn't use numeric scores
        return 1;
    }

    method to_string(@args) {

    # Return value (0 for add_id, 1 for others) for Parser's numeric comparisons
        return defined($value) ? "$value" : '1';
    }
}

class Chalk::Semiring::Semantic :isa(Chalk::Semiring) {
    field $env            :param = {};
    field $grammar        :param :reader;
    field $shared_context :param :reader = undef;
    field $type_env       :param :reader =
      {};    # Maps variable names to Chalk::Type objects
    field $forest :reader =
      defined($shared_context)
      && exists( $shared_context->{forest} )
      ? $shared_context->{forest}
      : undef;

    field $mul_id :reader = Chalk::Semiring::SemanticElement->new(
        value   => 1,                         # mul_id has value 1
        context => Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => 0,
            end_pos   => 0,
            env       => $env,
            grammar   => $grammar,
            rule      => undef,
            forest    => $forest,
            metadata_element => undef        # Identity elements have no metadata
        )
    );
    field $add_id :reader = Chalk::Semiring::SemanticElement->new(
        value   => 0,    # add_id has value 0 (failure/no parse)
        context => Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => 0,
            end_pos   => 0,
            env       => $env,
            grammar   => $grammar,
            rule      => undef,
            forest    => $forest,
            metadata_element => undef        # Identity elements have no metadata
        )
    );
    field $_add_id_is_zero :reader = 1;    # Flag to identify add_id

    method init_element_from_rule(
        $rule,
        $start_pos            = 0,
        $end_pos              = 0,
        $parent_derivation_id = undef
      )
    {
        # Infer type from the rule
        my $inferred_type = $self->infer_type_from_rule($rule);

        my $ctx = Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => $start_pos,
            end_pos   => $end_pos,
            env       => $env,
            grammar   => $grammar,
            rule      => $rule,
            forest    => $forest,
            type      => $inferred_type,
            metadata_element => undef        # Will be set during on_complete()
        );

        return Chalk::Semiring::SemanticElement->new(
            value   => 1,     # Success value (not add_id which is 0)
            context => $ctx
        );
    }

    method multiply( $x, $y ) {

        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus( $x, $y ) {

        # For backward compatibility if called directly
        return $x->add($y);
    }

    # Infer the type of an expression from its grammar rule
    # TODO put these into the Rule classes themselves
    method infer_type_from_rule($rule) {
        return Chalk::Grammar::Chalk::Type::Any->new() unless defined($rule);

        my $lhs = $rule->lhs;
        my @rhs = @{ $rule->rhs };

        # Literal types - check RHS for terminal patterns
        if ( @rhs == 1 ) {
            my $terminal = $rhs[0];

            # Integer literal
            return Chalk::Grammar::Chalk::Type::Int->new()
              if $terminal eq '%INTEGER%';

            # Float/Number literal
            return Chalk::Grammar::Chalk::Type::Num->new()
              if $terminal eq '%FLOAT%' || $terminal eq '%VERSION%';

            # String literals
            return Chalk::Grammar::Chalk::Type::Str->new()
              if $terminal eq '%SINGLE_QUOTED_STRING%'
              || $terminal eq '%DOUBLE_QUOTED_STRING%';
        }

        # Variable types - infer from sigil in RHS
        if ( $lhs =~ qr/Variable$/ ) {

            # Scalar variable: $ identifier
            if ( @rhs >= 1 && $rhs[0] eq '$' ) {
                return Chalk::Grammar::Chalk::Type::Scalar->new();
            }

            # Array variable: @ identifier
            if ( @rhs >= 1 && $rhs[0] eq '@' ) {
                return Chalk::Grammar::Chalk::Type::Array->new(
                    element_type => Chalk::Grammar::Chalk::Type::Any->new() );
            }

            # Hash variable: % identifier
            if ( @rhs >= 1 && $rhs[0] eq '%' ) {
                return Chalk::Grammar::Chalk::Type::Hash->new(
                    value_type => Chalk::Grammar::Chalk::Type::Any->new() );
            }
        }

        # Operation types - check for operators in RHS
        for my $i ( 0 .. $#rhs ) {
            my $symbol = $rhs[$i];

            # Numeric operations
            if ( $symbol =~ qr/^[+\-*\/]$/ || $symbol eq '**' ) {
                return Chalk::Grammar::Chalk::Type::Num->new();
            }

            # String concatenation
            if ( $symbol eq '.' ) {
                return Chalk::Grammar::Chalk::Type::Str->new();
            }

            # Range operator
            if ( $symbol eq '..' ) {
                return Chalk::Grammar::Chalk::Type::List->new();
            }
        }

        # Type inference by LHS name
        return Chalk::Grammar::Chalk::Type::Int->new()
          if $lhs eq 'Integer' || $lhs eq 'IntegerLiteral';
        return Chalk::Grammar::Chalk::Type::Num->new()
          if $lhs eq 'Number' || $lhs eq 'NumberLiteral';
        return Chalk::Grammar::Chalk::Type::Str->new()
          if $lhs eq 'String'
          || $lhs eq 'StringLiteral'
          || $lhs =~ qr/Quoted/;
        return Chalk::Grammar::Chalk::Type::Array->new(
            element_type => Chalk::Grammar::Chalk::Type::Any->new() )
          if $lhs eq 'ArrayLiteral' || $lhs eq 'List';
        return Chalk::Grammar::Chalk::Type::List->new() if $lhs eq 'Range';

        # Default to Any for unknown constructs
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    # Override base on_complete() to call semantic actions (evaluate())
    # This maintains polymorphism - Parser calls this uniformly on all semirings
    method on_complete( $completed_item, $completed_element, $metadata_element = undef ) {
        my $ctx = $completed_element->context;

        # Set metadata_element on context so rule.evaluate() can access precedence metadata
        if ($metadata_element && !$ctx->metadata_element) {
            $ctx = Chalk::EvalContext->new(
                focus     => $ctx->focus,
                children  => $ctx->children,
                start_pos => $ctx->start_pos,
                end_pos   => $ctx->end_pos,
                env       => $ctx->env,
                grammar   => $ctx->grammar,
                rule      => $ctx->rule,
                forest    => $ctx->forest,
                type      => $ctx->type,
                metadata_element => $metadata_element
            );
        }

        # Evaluate the rule's semantic action if it has one
        my $rule = $ctx->rule;
        if ( $rule && $rule->can('evaluate') ) {
            my $result = $rule->evaluate($ctx);

            # Set the focus to the evaluated result
            $ctx = Chalk::EvalContext->new(
                focus     => $result,
                children  => $ctx->children,
                start_pos => $ctx->start_pos,
                end_pos   => $ctx->end_pos,
                env       => $ctx->env,
                grammar   => $ctx->grammar,
                rule      => $ctx->rule,
                forest    => $ctx->forest,
                metadata_element => $metadata_element  # Pass metadata from SPPF/Precedence
            );

            # Update the completed element with evaluated context
            $completed_element = Chalk::Semiring::SemanticElement->new(
                value   => 1,
                context => $ctx
            );
        }

        return $completed_element;
    }

    # Override base on_scan() to accumulate terminal values
    # This maintains polymorphism - Parser calls this uniformly on all semirings
    method on_scan( $item, $element, $pos, $matched_value, $pattern_name = undef ) {
        my $match_length = length($matched_value);

        # Create a terminal element with the matched value as focus
        my $terminal_ctx = Chalk::EvalContext->new(
            focus     => $matched_value,
            children  => [],
            start_pos => $pos,
            end_pos   => $pos + $match_length,
            env       => $element->context->env,
            grammar   => $element->context->grammar,
            rule      => $item->rule,
            forest    => $element->context->forest,
            type      => $element->context->type,
            metadata_element => $element->context->metadata_element  # Propagate metadata
        );

        my $terminal_element = Chalk::Semiring::SemanticElement->new(
            value   => 1,
            context => $terminal_ctx
        );

        # Multiply to accumulate terminal into children
        return $element->multiply($terminal_element);
    }
}

