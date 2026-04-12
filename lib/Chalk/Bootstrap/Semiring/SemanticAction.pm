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

    # Pending CFG state update from action methods. Action methods call
    # update_cfg() to request a state change; on_complete applies it to the
    # result context after the action returns.
    my $_pending_cfg_update;

    # The active SemanticAction instance during on_complete. Action methods
    # access this via current_instance() to call cfg_state/update_cfg.
    my $_current_instance;

    # TypeInference Context for the current on_complete. Set by
    # FilterComposite before SA runs, so action methods can read
    # type annotations (e.g., return_type) from TI.
    my $_type_context;

    # Singleton for one(): a Context with undef focus and no children.
    my $_one_singleton;

    # Return a singleton one() Context, creating it on first call.
    # Also initializes the cfg annotation for this context.
    # Implemented as a method (not my sub) so the XS codegen can compile it
    # natively — my sub cannot access class-scope lexicals in XS.
    method _one_ctx() {
        if (!defined $_one_singleton) {
            $_one_singleton = Chalk::Bootstrap::Context->new(
                focus    => undef,
                children => [],
                position => 0,
                rule     => undef,
            );
            my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
            my $state = {
                control => $factory->make('Start'),
                scope   => Chalk::Bootstrap::Scope->new(),
            };
            # Store cfg state in the Context annotation (canonical location)
            $_one_singleton->annotations()->{cfg} = $state;
        }
        return $_one_singleton;
    }

    # Check if two cfg_state hashrefs can be merged (both defined with control).
    # Avoids complex && chains that the XS codegen mis-compiles.
    my sub _can_merge_cfg($state_a, $state_b) {
        return false if !defined $state_a;
        return false if !defined $state_b;
        return false if !defined $state_a->{control};
        return false if !defined $state_b->{control};
        return true;
    }

    # Copy a cfg_state hashref, replacing the scope field.
    # Uses explicit key copying instead of $base->%* hash spread
    # which the XS codegen can't handle.
    my sub _copy_cfg_with_scope($base, $new_scope) {
        my $copy = {
            control => $base->{control},
            scope   => $new_scope,
        };
        # Preserve extra fields (then_stmts, if_node, etc.)
        for my $key (keys %{$base}) {
            if ($key ne 'control' && $key ne 'scope') {
                $copy->{$key} = $base->{$key};
            }
        }
        return $copy;
    }

    # Return a hash-consed scan leaf Context for the given text.
    # Position-independent: two calls with the same text return the same object
    # regardless of position, since position is bookkeeping not semantics.
    # The tree structure preserves source ordering; leaf identity does not.
    my sub _scan_ctx($text) {
        my $key = defined($text) ? "scan:t:$text" : "scan:u";
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $text,
            children => [],
            position => 0,
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
        return $self->_one_ctx();
    }

    # Clear hash-cons cache between parses to prevent unbounded growth.
    # Cache entries from one file are not useful for subsequent files
    # because they reference different Context refaddrs.
    method reset_cache() {
        %_ctx_cache = ();
        $_one_singleton = undef;
    }

    # Retrieve CFG state (control token + scope) for a Context.
    # Reads from annotations->{cfg} — the canonical location for cfg state.
    # Returns hashref {control => $node, scope => $scope} or undef if no state.
    method cfg_state($ctx) {
        return $ctx->annotations()->{cfg};
    }

    # Set CFG state for a Context. Used by action methods to update
    # control flow and scope as they build Sea of Nodes IR.
    method set_cfg_state($ctx, $state) {
        $ctx->annotations()->{cfg} = $state;
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

    # Set the TypeInference Context for the current on_complete.
    # Called by FilterComposite after TI (index 2) completes, before SA runs.
    method set_type_context($ctx) {
        $_type_context = $ctx;
    }

    # Class method: return the TypeInference Context for the current on_complete.
    # Called by action methods (e.g. MethodDefinition in Actions.pm) to read
    # type annotations computed by TypeInference.
    sub current_type_context { return $_type_context }

    # Get the inherited CFG state for a context.
    # Returns annotations->{cfg} if present, falls back to one() defaults.
    method inherited_cfg_state($ctx) {
        my $state = $ctx->annotations()->{cfg};
        return $state if defined $state;
        return $self->_one_ctx()->annotations()->{cfg};
    }

    # Check if value is zero (undef)
    method is_zero($value) {
        return !defined $value;
    }

    # Multiply combines two contexts in sequence.
    # Creates a parent context with both as children, hash-consed by child identity.
    # Propagates cfg_state from children: prefer right (later in sequence), fall back to left.
    method multiply($left, $right) {
        # Propagate zero
        return undef if !defined $left;
        return undef if !defined $right;

        my $result = _mul_ctx($left, $right);

        # Propagate cfg_state through multiply chains so that parent rules
        # see the most recent control/scope state from their children.
        # Only propagate when the result does not already have an annotation
        # (hash-consed results reuse the same object; avoid overwriting).
        if (!defined $result->annotations()->{cfg}) {
            my $right_state = $right->annotations()->{cfg};
            my $left_state  = $left->annotations()->{cfg};
            # Combine CFG state from both sides of the multiply:
            # 1. Control: prefer non-Start over Start (structural change wins)
            # 2. Scope: merge both sides (left accumulated, right may add new vars)
            # Right is later in sequence, but whitespace/punctuation rules
            # carry Start state which should not overwrite a Region/If from left.
            my $inherited;
            my $can_merge = _can_merge_cfg($left_state, $right_state);
            if ($can_merge) {
                my $l_ctrl = $left_state->{control}->operation();
                my $r_ctrl = $right_state->{control}->operation();
                # Pick the more advanced control token and preserve
                # all extra fields (then_stmts, if_node, etc.) from
                # the side with the more advanced control.
                my $base;
                if ($l_ctrl ne 'Start' && $r_ctrl eq 'Start') {
                    $base = $left_state;
                } else {
                    $base = $right_state;
                }
                # Merge scopes: left's bindings + right's bindings
                my $merged_scope = $left_state->{scope}->merge($right_state->{scope});
                $inherited = _copy_cfg_with_scope($base, $merged_scope);
            } else {
                $inherited = $right_state // $left_state;
            }
            # Store cfg state in the Context annotation (canonical location)
            $result->annotations()->{cfg} = $inherited if defined $inherited;
        }

        return $result;
    }

    # on_complete: apply semantic action for a completed rule.
    # Looks up action by rule_name via can(), applies via extend, sets rule field.
    # Not hash-consed: semantic actions may have side effects and the result
    # focus depends on the actions object, so caching by input refaddr is unsafe.
    method on_complete($value, $rule_name, $alt_idx, $pos, $origin, $on_epoch_commit = undef) {
        return undef if !defined $value;

        my $has_method = false;
        if ($actions) {
            $has_method = defined $actions->can($rule_name);
        }
        my $result_ctx;
        $_pending_cfg_update = undef;  # Clear before action call
        $_current_instance = $self;     # Make accessible to action methods
        if ($has_method) {
            # Dispatch action and wrap value in one extend call.
            # The action receives $value (the multiply tree) and returns an IR node.
            # extend wraps $value as a child and stamps the rule name.
            $result_ctx = $value->extend(
                sub ($ctx) { $actions->$rule_name($ctx) },
                rule => $rule_name,
            );
        } else {
            # No action registered — wrap value with rule name stamp only
            $result_ctx = $value->extend(
                sub ($ctx) { $ctx->extract() },
                rule => $rule_name,
            );
        }

        # Apply pending CFG state update from action method, if any
        if (defined $_pending_cfg_update) {
            # Store cfg state in the Context annotation (canonical location)
            $result_ctx->annotations()->{cfg} = $_pending_cfg_update;
            $_pending_cfg_update = undef;
        }

        # Propagate CFG state: inherit from the value context,
        # unless an action explicitly set state via update_cfg.
        if (!defined $result_ctx->annotations()->{cfg}) {
            my $inherited = $self->inherited_cfg_state($value);
            # Store cfg state in the Context annotation (canonical location)
            $result_ctx->annotations()->{cfg} = $inherited if defined $inherited;
        }

        # Signal epoch boundary for statement-level completions.
        # StatementItem wraps individual statements — its completion means
        # the statement's internal parse positions can be swept.
        if (defined $on_epoch_commit && $rule_name eq 'StatementItem') {
            $on_epoch_commit->($origin, $pos);
        }

        # Clear current_instance and type_context after on_complete to prevent stale access
        $_current_instance = undef;
        $_type_context = undef;

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

    # Post-merge hook: transfer cfg_state from loser to winner when the winner
    # lacks state that the loser has. This fixes the Earley stale-value merge
    # problem where add() picks an older value that predates a cfg_state update.
    method on_merge($winner, $loser) {
        return unless defined $winner && defined $loser;
        my $winner_state = $winner->annotations()->{cfg};
        my $loser_state  = $loser->annotations()->{cfg};

        # If the loser has cfg_state but the winner doesn't, transfer it
        if (defined $loser_state && !defined $winner_state) {
            # Store cfg state in the Context annotation (canonical location)
            $winner->annotations()->{cfg} = $loser_state;
            return;
        }

        # If both have cfg_state, merge them:
        # Control: prefer non-Start over Start
        # Scope: merge both sides (loser may have bindings winner lacks)
        my $can_merge = _can_merge_cfg($winner_state, $loser_state);
        if ($can_merge) {
            my $w_ctrl = $winner_state->{control}->operation();
            my $l_ctrl = $loser_state->{control}->operation();
            # Pick the side with the more advanced control and preserve
            # all extra fields (then_stmts, if_node, etc.)
            my $base;
            if ($w_ctrl eq 'Start' && $l_ctrl ne 'Start') {
                $base = $loser_state;
            } else {
                $base = $winner_state;
            }
            my $merged_scope = $winner_state->{scope}->merge($loser_state->{scope});
            # Store cfg state in the Context annotation (canonical location)
            $winner->annotations()->{cfg} = _copy_cfg_with_scope($base, $merged_scope);
        }
        return;
    }

    # on_skip_optional: create a placeholder Context for a skipped X? symbol.
    # Preserves positional child indexing for actions that access children by position.
    method on_skip_optional($value, $rule_name, $alt_idx, $pos, $symbol_name) {
        return undef if !defined $value;
        # Create a placeholder Context representing "X was absent"
        my $placeholder = Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => $pos,
            rule     => "${symbol_name}_opt",
        );
        # Propagate cfg_state from parent to placeholder
        my $parent_state = $self->inherited_cfg_state($value);
        # Store cfg state in the Context annotation (canonical location)
        $placeholder->annotations()->{cfg} = $parent_state if defined $parent_state;
        return $self->multiply($value, $placeholder);
    }

    # slot_name: SemanticAction owns the focus field + cfg annotation, not a named slot.
    method slot_name() {
        return undef;
    }
}
