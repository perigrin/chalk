# ABOUTME: Semantic action semiring for building IR nodes from parse results.
# ABOUTME: Values are Contexts, operations combine contexts for sequences and alternatives.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

my sub _describe_focus($focus) {
    return '<undef>' unless defined $focus;
    if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
        my $val = $focus->value() // '<undef>';
        return "Constant('$val')";
    }
    if ($focus isa Chalk::Bootstrap::IR::Node::Constructor) {
        return "Constructor:" . $focus->class();
    }
    if ($focus isa Chalk::Bootstrap::IR::Node) {
        return ref($focus);
    }
    if (ref($focus) eq 'ARRAY') {
        return "ARRAY[" . scalar($focus->@*) . "]";
    }
    return ref($focus) || "'$focus'";
}

class Chalk::Bootstrap::Semiring::SemanticAction {
    field $actions :param = undef;

    # Hash-cons cache: maps stringified key to Context object.
    # Ensures identical derivations share the same refaddr, so Composite add()
    # can detect identity collapse via refaddr equality.
    my %_ctx_cache;

    # Singleton for one(): a Context with undef focus and no children.
    my $_one_singleton;

    # Return a singleton one() Context, creating it on first call.
    my sub _one_ctx() {
        return ($_one_singleton //= Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    # Return a hash-consed scan leaf Context for the given text and position.
    # Two calls with the same text+pos return the same object (same refaddr).
    my sub _scan_ctx($text, $pos) {
        my $key = "scan:$pos:" . ($text // '');
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $text,
            children => [],
            position => $pos,
            rule     => undef,
        ));
    }

    # Return a hash-consed multiply Context for the given left+right children.
    # Two calls with the same children (same refaddrs) return the same object.
    my sub _mul_ctx($left, $right) {
        my $key = "mul:" . refaddr($left) . ":" . refaddr($right);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$left, $right],
            position => $right->position(),
            rule     => undef,
        ));
    }

    # zero returns undef (parse failure)
    method zero() {
        return undef;
    }

    # one returns the singleton empty context with undef focus
    method one() {
        return _one_ctx();
    }

    # Check if value is zero (undef)
    method is_zero($value) {
        return !defined $value;
    }

    # Multiply combines two contexts in sequence.
    # Creates a parent context with both as children, hash-consed by child identity.
    method multiply($left, $right) {
        # Propagate zero
        return undef if !defined $left;
        return undef if !defined $right;

        return _mul_ctx($left, $right);
    }

    # on_scan: create a hash-consed Context for the matched text and multiply
    # with existing value
    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $scan_ctx = _scan_ctx($matched_text, $pos);
        return $self->multiply($item->{value}, $scan_ctx);
    }

    # on_complete: apply semantic action for a completed rule.
    # Looks up action by rule_name via can(), applies via extend, sets rule field.
    # Not hash-consed: semantic actions may have side effects and the result
    # focus depends on the actions object, so caching by input refaddr is unsafe.
    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return undef if !defined $value;

        my $rule_name = $item->{rule}->name();
        my $method = $actions ? $actions->can($rule_name) : undef;
        my $result;
        if ($method) {
            # Call the method via the actions object instance
            $result = $value->extend(sub { $actions->$method(@_) });
        } else {
            # No action registered - preserve value as-is
            $result = $value;
        }

        # Set the rule name on the result context
        return Chalk::Bootstrap::Context->new(
            focus    => $result->extract(),
            children => $result->children(),
            position => $result->position(),
            rule     => $rule_name,
        );
    }

    # Add combines alternative derivations, returning an arrayref of survivors.
    # This follows the FilterComposite convention: [$winner] for one survivor,
    # [$left, $right] when both survive (genuine ambiguity for Phase 3 to handle).
    # The Composite shim _unwrap_add_result() accepts single-element arrayrefs
    # and dies on multi-element arrayrefs (Phase 3 not yet implemented).
    method add($left, $right) {
        return [$right] if !defined $left;
        return [$left]  if !defined $right;

        # Identity collapse: same refaddr means same derivation (Composite
        # preference-detection protocol passes the winner to both sides)
        return [$left] if refaddr($left) == refaddr($right);

        # Both non-zero and different: return both as survivors.
        # In practice, upstream semirings (Precedence, TypeInference, Structural)
        # should disambiguate before reaching here. If this fires, Composite's
        # _unwrap_add_result() will die with a clear error message.
        return [$left, $right];
    }
}
