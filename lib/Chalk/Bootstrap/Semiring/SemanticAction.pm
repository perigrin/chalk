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

    # Pending scope update from action methods. Action methods call
    # update_scope() to request a scope change; _complete_sa applies it to
    # the result context after the action returns.
    my $_pending_scope_update;

    # Pending graph update from action methods. Used by side-effect
    # actions (VarDecl, Assign, Call) that need to publish an IR graph
    # so MethodDefinition / Block can attach it to the MOP metaobject.
    my $_pending_graph_update;

    # Pending annotations update from action methods. Action methods call
    # update_annotations() to request annotation additions to the result
    # context; _complete_sa merges them into the result context annotations.
    my $_pending_annotations_update;

    # The active SemanticAction instance during a complete event. Action methods
    # access this via current_instance() to call update_scope/update_annotations.
    my $_current_instance;

    # TypeInference Context for the current complete event. Set by
    # FilterComposite before SA runs, so action methods can read
    # type annotations (e.g., return_type) from TI.
    my $_type_context;

    # Singleton for one(): a Context with undef focus and no children.
    my $_one_singleton;

    # Singleton for zero(): a Context with is_zero=true. Identity-stable so
    # callers that hash-cons on semiring results (FilterComposite) get
    # ref-eq behavior on parse failure.
    my $_zero_singleton;

    # MOP instance to thread through parse contexts. Set via set_mop() before
    # parsing; invalidates the singleton so _one_ctx() recreates it with the MOP.
    my $_mop;

    # Return a singleton one() Context, creating it on first call.
    # Initializes the scope field with a fresh Start node as control.
    # Implemented as a method (not my sub) so the XS codegen can compile it
    # natively — my sub cannot access class-scope lexicals in XS.
    method _one_ctx() {
        if (!defined $_one_singleton) {
            my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
            my $start   = $factory->make('Start');
            my $scope   = Chalk::Bootstrap::Scope->new()->with_control($start);
            $_one_singleton = Chalk::Bootstrap::Context->new(
                focus    => undef,
                children => [],
                position => 0,
                rule     => undef,
                mop      => $_mop,
                scope    => $scope,
            );
        }
        return $_one_singleton;
    }

    # Merge two scope values from multiply children, using the same
    # control-preference logic that cfg_state propagation used:
    # prefer non-Start over Start (structural change wins).
    # Merges variable bindings from both sides (right takes precedence for dups).
    my sub _merge_scope($left_scope, $right_scope) {
        return $right_scope // $left_scope unless defined $left_scope && defined $right_scope;

        my $l_ctrl = $left_scope->control;
        my $r_ctrl = $right_scope->control;

        # Both have a control input — pick the more advanced one
        if (defined $l_ctrl && defined $r_ctrl) {
            my $l_op = $l_ctrl->operation();
            my $r_op = $r_ctrl->operation();
            my $base;
            if ($l_op ne 'Start' && $r_op eq 'Start') {
                $base = $left_scope;
            } else {
                $base = $right_scope;
            }
            # Merge bindings: left accumulated, right may add new vars
            return $base->merge($left_scope);
        }

        # Fallback: use whichever has a control, or right if neither does
        return (defined $r_ctrl ? $right_scope : $left_scope);
    }

    # Return a hash-consed multiply Context for the given left+right children.
    # Two calls with the same children (same refaddrs) return the same object.
    # Scope propagates right-to-left; if right has no scope, inherit from left.
    my sub _mul_ctx($left, $right) {
        my $key = "mul:" . refaddr($left) . ":" . refaddr($right);
        return ($_ctx_cache{$key} //= do {
            # Propagate scope: prefer scope with more-advanced control.
            # Right is later in the sequence; if right has a non-Start control
            # and left has a Start (or no scope), prefer right. Otherwise prefer left.
            my $scope = _merge_scope($left->scope, $right->scope);
            # Propagate graph: prefer right (later in the sequence). If right
            # has no graph, fall back to left's graph - side-effect actions
            # publish a graph via update_graph; the same instance should
            # bubble up so Block/MethodDefinition see the populated graph.
            my $graph = $right->graph() // $left->graph();
            Chalk::Bootstrap::Context->new(
                focus    => undef,
                children => [$left, $right],
                position => $right->position(),
                rule     => undef,
                mop      => $_mop,
                scope    => $scope,
                graph    => $graph,
            );
        });
    }

    # zero returns a Context with is_zero=true (parse failure).
    # Honors the (Context, Context) -> Context contract per Decision 4 in
    # docs/plans/2026-04-24-semiring-contract-drift.md.
    method zero() {
        $_zero_singleton //= Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            rule     => undef,
            is_zero  => true,
        );
        return $_zero_singleton;
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
        $_zero_singleton = undef;
    }

    # Request a scope update from within an action method.
    # Called by Actions.pm during extend(); _complete_sa applies the update
    # to the result context's scope field after the action returns.
    method update_scope($scope) {
        $_pending_scope_update = $scope;
        return;
    }

    # Request annotation additions from within an action method.
    # Called by Actions.pm to store structural cfg data (if_node, loop,
    # try_node, then_stmts, etc.) on the result context's annotations.
    # _complete_sa merges the provided hashref into the result annotations.
    method update_annotations($data) {
        $_pending_annotations_update = $data;
        return;
    }

    # Request a graph update from within an action method.
    # Side-effect actions call this to publish a Chalk::IR::Graph; the
    # result context propagates it upward so MethodDefinition can attach
    # the graph to the MOP metaobject.
    method update_graph($graph) {
        $_pending_graph_update = $graph;
        return;
    }

    # Class method: return the SemanticAction instance currently executing
    # a complete event. Allows action methods in Actions.pm to access
    # update_scope/update_annotations without needing a reference to the semiring.
    sub current_instance { return $_current_instance }

    # Class method: set the MOP instance to thread through parse Contexts.
    # Invalidates the one() singleton so the next call recreates it with the MOP.
    sub set_mop($mop) { $_mop = $mop; $_one_singleton = undef; }

    # Class method: return the currently set MOP instance (may be undef).
    sub current_mop() { return $_mop }

    # Set the TypeInference Context for the current complete event.
    # Called by FilterComposite after TI (index 2) completes, before SA runs.
    method set_type_context($ctx) {
        $_type_context = $ctx;
    }

    # Class method: return the TypeInference Context for the current complete event.
    # Called by action methods (e.g. MethodDefinition in Actions.pm) to read
    # type annotations computed by TypeInference.
    sub current_type_context { return $_type_context }

    # Check if value is zero by reading the Context's is_zero flag.
    method is_zero($value) {
        return $value->is_zero();
    }

    # Multiply combines two contexts in sequence.
    # Creates a parent context with both as children, hash-consed by child identity.
    # Propagates scope from children via _merge_scope.
    # When $right is a complete-annotated Context, applies rule-completion (semantic action)
    # logic: looks up action by rule_name, extends the value via the action, propagates scope.
    method multiply($left, $right) {
        # Propagate zero
        return $self->zero() if $left->is_zero();
        return $self->zero() if $right->is_zero();

        # Complete event: right Context has annotations->{complete} = true.
        # Apply semantic action for the completed rule.
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{complete}) {
            my $rule_name = $right->annotations()->{rule_name};
            return $self->_complete_sa($left, $rule_name);
        }

        return _mul_ctx($left, $right);
    }

    # _complete_sa: apply semantic action for a completed rule.
    # Looks up action by rule_name via can(), applies via extend, sets rule field.
    # Not hash-consed: semantic actions may have side effects and the result
    # focus depends on the actions object, so caching by input refaddr is unsafe.
    # Called from multiply() when the right argument is a complete-annotated Context.
    method _complete_sa($value, $rule_name) {
        return $self->zero() if $value->is_zero();

        my $has_method = false;
        if ($actions) {
            $has_method = defined $actions->can($rule_name);
        }
        my $result_ctx;
        $_pending_scope_update       = undef;  # Clear before action call
        $_pending_annotations_update = undef;  # Clear before action call
        $_pending_graph_update       = undef;  # Clear before action call
        $_current_instance = $self;             # Make accessible to action methods
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

        # Apply pending scope update from action method, if any.
        # Scope update overrides what extend inherited from $value.
        if (defined $_pending_scope_update) {
            $result_ctx = Chalk::Bootstrap::Context->new(
                focus       => $result_ctx->focus(),
                children    => $result_ctx->children(),
                position    => $result_ctx->position(),
                rule        => $result_ctx->rule(),
                annotations => $result_ctx->annotations(),
                token       => $result_ctx->token(),
                is_zero     => $result_ctx->is_zero(),
                error       => $result_ctx->error(),
                mop         => $result_ctx->mop(),
                graph       => $result_ctx->graph(),
                scope       => $_pending_scope_update,
            );
            $_pending_scope_update = undef;
        }

        # Apply pending annotations update from action method, if any.
        # Merges the provided keys into the result context annotations.
        if (defined $_pending_annotations_update) {
            my $ann = $result_ctx->annotations();
            for my $key (keys $_pending_annotations_update->%*) {
                $ann->{$key} = $_pending_annotations_update->{$key};
            }
            $_pending_annotations_update = undef;
        }

        # Apply pending graph update from action method, if any.
        # Graph update overrides what extend inherited from $value.
        if (defined $_pending_graph_update) {
            $result_ctx = Chalk::Bootstrap::Context->new(
                focus       => $result_ctx->focus(),
                children    => $result_ctx->children(),
                position    => $result_ctx->position(),
                rule        => $result_ctx->rule(),
                annotations => $result_ctx->annotations(),
                token       => $result_ctx->token(),
                is_zero     => $result_ctx->is_zero(),
                error       => $result_ctx->error(),
                mop         => $result_ctx->mop(),
                scope       => $result_ctx->scope(),
                graph       => $_pending_graph_update,
            );
            $_pending_graph_update = undef;
        }

        # Propagate scope: inherit from $value if result has no scope.
        if (!defined $result_ctx->scope()) {
            my $inherited_scope = $value->scope();
            if (defined $inherited_scope) {
                $result_ctx = Chalk::Bootstrap::Context->new(
                    focus       => $result_ctx->focus(),
                    children    => $result_ctx->children(),
                    position    => $result_ctx->position(),
                    rule        => $result_ctx->rule(),
                    annotations => $result_ctx->annotations(),
                    token       => $result_ctx->token(),
                    is_zero     => $result_ctx->is_zero(),
                    error       => $result_ctx->error(),
                    mop         => $result_ctx->mop(),
                    graph       => $result_ctx->graph(),
                    scope       => $inherited_scope,
                );
            }
        }

        # Propagate graph: inherit from $value if result has no graph.
        if (!defined $result_ctx->graph()) {
            my $inherited_graph = $value->graph();
            if (defined $inherited_graph) {
                $result_ctx = Chalk::Bootstrap::Context->new(
                    focus       => $result_ctx->focus(),
                    children    => $result_ctx->children(),
                    position    => $result_ctx->position(),
                    rule        => $result_ctx->rule(),
                    annotations => $result_ctx->annotations(),
                    token       => $result_ctx->token(),
                    is_zero     => $result_ctx->is_zero(),
                    error       => $result_ctx->error(),
                    mop         => $result_ctx->mop(),
                    scope       => $result_ctx->scope(),
                    graph       => $inherited_graph,
                );
            }
        }

        # Clear current_instance and type_context after action to prevent stale access
        $_current_instance = undef;
        $_type_context = undef;

        return $result_ctx;
    }

    # Add combines alternative derivations, returning an arrayref of survivors.
    # This follows the FilterComposite convention: [$correct] for one survivor,
    # [$left, $right] when both survive (genuine ambiguity that FilterComposite
    # resolves by picking left as a deterministic tie-break).
    method add($left, $right) {
        return [$right] if $left->is_zero();
        return [$left]  if $right->is_zero();

        # Identity collapse: same refaddr means same derivation (FilterComposite
        # preference-detection protocol passes the same value to both sides)
        return [$left] if refaddr($left) == refaddr($right);

        # Both non-zero and different: return both as survivors.
        # In practice, upstream semirings (Precedence, TypeInference, Structural)
        # should disambiguate before reaching here. When all four admit both
        # derivations, FilterComposite currently picks one via a deterministic
        # tie-break — that is a separate bug (composition should have no opinion;
        # genuine ambiguity that survives all filtering should surface as such,
        # not be silently resolved). Tracked separately from the filter-gap
        # work; see docs/plans/2026-05-09-fixup-audit-baseline.md.
        return [$left, $right];
    }

    # Post-merge hook: when the filter stack admitted both derivations of a
    # span (no semiring expressed a preference), Earley's add() returned both
    # as survivors and FilterComposite then picked one via a deterministic
    # tie-break (a separate bug — composition shouldn't have an opinion).
    # The picked side may lack scope information that the other survivor
    # carries, because both were built independently before the chart-level
    # merge. This hook transfers scope from the other survivor when the
    # picked one lacks it. See _fix_postfix_chain in Perl/Actions.pm for the
    # canonical filter-gap-merge explanation; tracked by the fixup audit at
    # docs/plans/2026-05-09-fixup-audit-baseline.md.
    method on_merge($correct, $rejected) {
        return if $correct->is_zero() || $rejected->is_zero();
        my $correct_scope  = $correct->scope();
        my $rejected_scope = $rejected->scope();

        return unless defined $rejected_scope;

        # If the rejected side has scope but the correct side doesn't, transfer it
        if (!defined $correct_scope) {
            # Rebuild the correct context with the rejected scope
            my $updated = Chalk::Bootstrap::Context->new(
                focus       => $correct->focus(),
                children    => $correct->children(),
                position    => $correct->position(),
                rule        => $correct->rule(),
                annotations => $correct->annotations(),
                token       => $correct->token(),
                is_zero     => $correct->is_zero(),
                error       => $correct->error(),
                mop         => $correct->mop(),
                graph       => $correct->graph(),
                scope       => $rejected_scope,
            );
            # Transfer the rebuilt context's scope to the original via annotations hack:
            # We can't replace $correct's identity (caller holds a reference), so
            # transfer scope data via annotations for on_merge compatibility.
            $correct->annotations()->{_transferred_scope} = $rejected_scope;
            return;
        }

        # Both have scope: merge them using the same logic as _merge_scope.
        my $merged = _merge_scope($correct_scope, $rejected_scope);
        if (defined $merged && refaddr($merged) != refaddr($correct_scope)) {
            $correct->annotations()->{_transferred_scope} = $merged;
        }
        return;
    }

    # slot_name: SemanticAction owns the focus field + scope field, not a named slot.
    method slot_name() {
        return undef;
    }

}
