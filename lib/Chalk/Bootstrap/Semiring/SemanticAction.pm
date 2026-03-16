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

    # TypeInference Context for the current on_complete. Set by
    # FilterComposite before SA runs, so action methods can read
    # type annotations (e.g., return_type) from TI.
    my $_type_context;

    # Singleton for one(): a Context with undef focus and no children.
    my $_one_singleton;

    # Return a singleton one() Context, creating it on first call.
    # Also initializes the cfg_state side-table entry for this context.
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
            $_cfg_state{refaddr($_one_singleton)} = {
                control => $factory->make('Start'),
                scope   => Chalk::Bootstrap::Scope->new(),
            };
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
        return $self->_one_ctx();
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
    # Returns the direct cfg_state if available, falls back to one() defaults.
    method inherited_cfg_state($ctx) {
        my $state = $_cfg_state{refaddr($ctx)};
        return $state if defined $state;
        return $_cfg_state{refaddr($self->_one_ctx())};
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
        if (!exists $_cfg_state{refaddr($result)}) {
            my $right_state = $_cfg_state{refaddr($right)};
            my $left_state = $_cfg_state{refaddr($left)};
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
            $_cfg_state{refaddr($result)} = $inherited if defined $inherited;
        }

        return $result;
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
    method on_complete($item, $alt_idx, $pos, $on_epoch_commit = undef) {
        my $value = $item->{value};
        return undef if !defined $value;

        my $rule_name = $item->{rule}->name();
        my $has_method = false;
        if ($actions) {
            $has_method = defined $actions->can($rule_name);
        }
        my $result;
        $_pending_cfg_update = undef;  # Clear before action call
        $_current_instance = $self;     # Make accessible to action methods
        if ($has_method) {
            # Dispatch the action via string method name. Using $rule_name
            # as a string method call compiles to call_method in XS, avoiding
            # coderef calls which the XS codegen drops arguments from.
            my $new_focus = $actions->$rule_name($value);
            $result = Chalk::Bootstrap::Context->new(
                focus    => $new_focus,
                children => $value->children(),
                position => $value->position(),
                rule     => $value->rule(),
            );
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

        # Signal epoch boundary for statement-level completions.
        # StatementItem wraps individual statements — its completion means
        # the statement's internal parse positions can be swept.
        if (defined $on_epoch_commit && $rule_name eq 'StatementItem') {
            $on_epoch_commit->($item->{origin}, $pos);
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
        my $winner_state = $_cfg_state{refaddr($winner)};
        my $loser_state = $_cfg_state{refaddr($loser)};

        # If the loser has cfg_state but the winner doesn't, transfer it
        if (defined $loser_state && !defined $winner_state) {
            $_cfg_state{refaddr($winner)} = $loser_state;
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
            $_cfg_state{refaddr($winner)} = _copy_cfg_with_scope($base, $merged_scope);
        }
        return;
    }

    # on_skip_optional: create a placeholder Context for a skipped X? symbol.
    # Preserves positional child indexing for actions that access children by position.
    method on_skip_optional($item, $alt_idx, $pos, $symbol_name) {
        my $value = $item->{value};
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
        $_cfg_state{refaddr($placeholder)} = $parent_state if defined $parent_state;
        return $self->multiply($value, $placeholder);
    }

    # should_scan: gate for scan operation, called after regex match succeeds
    # Returns true to proceed with scan, false to skip it.
    # Default: always return true (no filtering).
    method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
        return true;
    }
}
