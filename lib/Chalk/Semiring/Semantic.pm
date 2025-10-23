# ABOUTME: Semantic semiring for building values during parsing with evaluation contexts
# ABOUTME: Tracks contexts and enables semantic actions via EvalContext comonad

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;

class Chalk::Semiring::SemanticElement :isa(Chalk::Element) {
    field $value :param :reader;         # Computed semantic value
    field $context :param :reader;       # Evaluation context
    field $sppf_node :param = undef;     # Optional SPPF node

    method add( $other, $swap = undef ) {
        # For alternatives (choice), prefer non-zero value
        # If self has value 0 (is add_id), return other
        if ($value == 0) {
            return $other;
        }

        # Prefer elements with evaluated focus (defined) over unevaluated (undef)
        # This handles the case where we update the chart after evaluation
        my $self_focus = $self->context->focus;
        my $other_focus = $other->context->focus;

        if (!defined($self_focus) && defined($other_focus)) {
            return $other;
        }
        if (defined($self_focus) && !defined($other_focus)) {
            return $self;
        }

        # For semantic values, prefer the alternative with more children
        # (this handles ambiguous parses - we want the one that consumed more input)
        my $self_children = scalar(@{$self->context->children});
        my $other_children = scalar(@{$other->context->children});

        if ($other_children > $self_children) {
            return $other;
        }

        # Otherwise prefer self (first alternative)
        return $self;
    }

    method multiply( $other, $swap = undef ) {
        # For sequences, append other's context to self's children
        # This builds up the children list as we advance the dot through the rule
        my @new_children = (@{$self->context->children}, $other->context);

        my $combined_ctx = Chalk::EvalContext->new(
            focus => undef,  # Not yet evaluated
            children => \@new_children,
            start_pos => $self->context->start_pos,
            end_pos => $other->context->end_pos,
            env => $self->context->env,
            grammar => $self->context->grammar,
            rule => $self->context->rule
        );

        return Chalk::Semiring::SemanticElement->new(
            value => 1,  # Success value
            context => $combined_ctx,
            sppf_node => $sppf_node
        );
    }

    method equals( $other, $swap = undef ) {
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
    field $env :param = {};
    field $grammar :param :reader;
    field $mul_id :reader;
    field $add_id :reader;
    field $_add_id_is_zero :reader = 1;  # Flag to identify add_id

    ADJUST {
        # Create identity elements with empty contexts
        my $empty_ctx_mul = Chalk::EvalContext->new(
            focus => undef,
            children => [],
            start_pos => 0,
            end_pos => 0,
            env => $env,
            grammar => $grammar,
            rule => undef
        );

        my $empty_ctx_add = Chalk::EvalContext->new(
            focus => undef,
            children => [],
            start_pos => 0,
            end_pos => 0,
            env => $env,
            grammar => $grammar,
            rule => undef
        );

        $mul_id = Chalk::Semiring::SemanticElement->new(
            value => 1,  # mul_id has value 1
            context => $empty_ctx_mul
        );

        $add_id = Chalk::Semiring::SemanticElement->new(
            value => 0,  # add_id has value 0 (failure/no parse)
            context => $empty_ctx_add
        );
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0) {
        my $ctx = Chalk::EvalContext->new(
            focus => undef,
            children => [],
            start_pos => $start_pos,
            end_pos => $end_pos,
            env => $env,
            grammar => $grammar,
            rule => $rule
        );

        return Chalk::Semiring::SemanticElement->new(
            value => 1,  # Success value (not add_id which is 0)
            context => $ctx
        );
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }
}

