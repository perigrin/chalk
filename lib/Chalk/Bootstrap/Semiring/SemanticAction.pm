# ABOUTME: Semantic action semiring for building IR nodes from parse results.
# ABOUTME: Values are Contexts, operations combine contexts for sequences and alternatives.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::NodeFactory;

class Chalk::Bootstrap::Semiring::SemanticAction {
    field $actions :param = undef;

    # Hash-cons cache: maps stringified key to Context object.
    # Ensures identical derivations share the same refaddr, so FilterComposite add()
    # can detect identity collapse via refaddr equality.
    my %_ctx_cache;

    # Side-table mapping Context refaddr to {control, scope} state.
    # Keeps the Context tree clean (focus remains bare IR node or undef)
    # while threading CFG state for Sea of Nodes construction.
    my %_cfg_state;

    # Pending CFG state update from action methods. Action methods call
    # update_cfg() to request a state change; on_complete applies it to the
    # result context after the action returns.
    my $_pending_cfg_update;

    # The active SemanticAction instance during on_complete. Action methods
    # access this via current_instance() to call cfg_state/update_cfg.
    my $_current_instance;

    # Singleton for one(): a Context with undef focus and no children.
    my $_one_singleton;

    # Return a singleton one() Context, creating it on first call.
    # Also initializes the cfg_state side-table entry for this context.
    my sub _one_ctx() {
        if (!defined $_one_singleton) {
            $_one_singleton = Chalk::Bootstrap::Context->new(
                focus    => undef,
                children => [],
                position => 0,
                rule     => undef,
            );
            my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
            $_cfg_state{refaddr($_one_singleton)} = {
                control => $factory->make('Start'),
                scope   => Chalk::Bootstrap::Scope->new(),
            };
        }
        return $_one_singleton;
    }

    # Return a hash-consed scan leaf Context for the given text and position.
    # Two calls with the same text+pos return the same object (same refaddr).
    my sub _scan_ctx($text, $pos) {
        my $key = defined($text) ? "scan:$pos:t:$text" : "scan:$pos:u";
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

    # Clear hash-cons cache between parses to prevent unbounded growth.
    # Cache entries from one file are not useful for subsequent files
    # because they reference different Context refaddrs.
    method reset_cache() {
        %_ctx_cache = ();
        %_cfg_state = ();
        $_one_singleton = undef;
    }

    # Retrieve CFG state (control token + scope) for a Context.
    # Returns hashref {control => $node, scope => $scope} or undef if no state.
    method cfg_state($ctx) {
        return $_cfg_state{refaddr($ctx)};
    }

    # Set CFG state for a Context. Used by action methods to update
    # control flow and scope as they build Sea of Nodes IR.
    method set_cfg_state($ctx, $state) {
        $_cfg_state{refaddr($ctx)} = $state;
        return;
    }

    # Request a CFG state update from within an action method.
    # Called by Actions.pm during extend(); on_complete applies the update
    # to the result context after the action returns.
    method update_cfg($state) {
        $_pending_cfg_update = $state;
        return;
    }

    # Class method: return the SemanticAction instance currently executing
    # an on_complete action. Allows action methods in Actions.pm to access
    # cfg_state/update_cfg without needing a reference to the semiring.
    sub current_instance { return $_current_instance }

    # Get the inherited CFG state for a context.
    # Returns the direct cfg_state if available, falls back to one() defaults.
    method inherited_cfg_state($ctx) {
        return $_cfg_state{refaddr($ctx)} // $_cfg_state{refaddr(_one_ctx())};
    }

    # Build scope by walking the Context tree post-parse.
    # Finds all VarDecl IR nodes in tree order and accumulates them into a Scope.
    # This avoids the Earley chart merge problem where side-table state is lost
    # during add() operations that pick older values without scope updates.
    method build_scope($ctx) {
        my $scope = Chalk::Bootstrap::Scope->new();
        my @stack = ($ctx);
        while (@stack) {
            my $node = pop @stack;
            my $focus = $node->extract();
            # Check if focus is a VarDecl Constructor IR node
            if (defined $focus && ref($focus) && $focus isa Chalk::Bootstrap::IR::Node
                && $focus->operation() eq 'Constructor' && $focus->class() eq 'VarDecl') {
                my $var_node = $focus->inputs()->[0];  # variable input
                if (defined $var_node && $var_node isa Chalk::Bootstrap::IR::Node
                    && $var_node->operation() eq 'Constant') {
                    my $var_name = $var_node->value();
                    $scope = $scope->define($var_name, $focus);
                }
            }
            # Walk children in reverse so leftmost is processed first
            push @stack, reverse $node->children()->@*;
        }
        return $scope;
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
        $_pending_cfg_update = undef;  # Clear before action call
        $_current_instance = $self;     # Make accessible to action methods
        if ($method) {
            # Call the method via the actions object instance
            $result = $value->extend(sub { $actions->$method(@_) });
        } else {
            # No action registered - preserve value as-is
            $result = $value;
        }

        # Set the rule name on the result context
        my $result_ctx = Chalk::Bootstrap::Context->new(
            focus    => $result->extract(),
            children => $result->children(),
            position => $result->position(),
            rule     => $rule_name,
        );

        # Apply pending CFG state update from action method, if any
        if (defined $_pending_cfg_update) {
            $_cfg_state{refaddr($result_ctx)} = $_pending_cfg_update;
            $_pending_cfg_update = undef;
        }

        # Propagate CFG state: inherit from the value context,
        # unless an action explicitly set state via update_cfg.
        if (!exists $_cfg_state{refaddr($result_ctx)}) {
            my $inherited = $self->inherited_cfg_state($value);
            $_cfg_state{refaddr($result_ctx)} = $inherited if defined $inherited;
        }

        return $result_ctx;
    }

    # Add combines alternative derivations, returning an arrayref of survivors.
    # This follows the FilterComposite convention: [$winner] for one survivor,
    # [$left, $right] when both survive (genuine ambiguity that FilterComposite
    # resolves by picking left as a deterministic tie-break).
    method add($left, $right) {
        return [$right] if !defined $left;
        return [$left]  if !defined $right;

        # Identity collapse: same refaddr means same derivation (FilterComposite
        # preference-detection protocol passes the winner to both sides)
        return [$left] if refaddr($left) == refaddr($right);

        # Both non-zero and different: return both as survivors.
        # In practice, upstream semirings (Precedence, TypeInference, Structural)
        # should disambiguate before reaching here. FilterComposite picks left
        # as a deterministic tie-break when no semiring expresses a preference.
        return [$left, $right];
    }

    # should_scan: gate for scan operation, called after regex match succeeds
    # Returns true to proceed with scan, false to skip it.
    # Default: always return true (no filtering).
    method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
        return true;
    }
}
