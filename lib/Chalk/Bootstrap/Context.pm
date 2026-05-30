# ABOUTME: Comonad for threading context through parser and semantic actions.
# ABOUTME: Implements extract, extend, and duplicate operations for functional composition.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Context {
    field $focus       :param :reader;
    field $children    :param :reader = [];
    field $position    :param :reader = 0;
    field $rule        :param :reader = undef;
    field $annotations :param :reader = {};
    field $token       :param :reader = undef;
    field $is_zero      :param :reader = false;
    field $is_ambiguous :param :reader = false;
    field $error        :param :reader = undef;
    field $mop         :param :reader = undef;
    field $graph       :param :reader = undef;
    field $scope       :param :reader = undef;
    field $factory      :param :reader = undef;
    field $control_head :param :reader = undef;

    # Extract the current focus value from the context
    method extract() {
        return $focus;
    }

    # Apply a function to this context, creating a new context with the result as focus
    # This is the comonad 'extend' operation: (Context -> a) -> Context -> Context
    # Optional %opts may include rule, annotations, graph, scope, and other field overrides.
    method extend($f, %opts) {
        my $new_focus = $f->($self);
        return Chalk::Bootstrap::Context->new(
            focus       => $new_focus,
            children    => [$self],
            position    => $position,
            rule        => (exists $opts{rule} ? $opts{rule} : $rule),
            annotations => (exists $opts{annotations} ? $opts{annotations} : { $annotations->%* }),
            token       => (exists $opts{token} ? $opts{token} : $token),
            is_zero     => (exists $opts{is_zero} ? $opts{is_zero} : $is_zero),
            error       => (exists $opts{error} ? $opts{error} : $error),
            mop         => (exists $opts{mop} ? $opts{mop} : $mop),
            graph       => (exists $opts{graph} ? $opts{graph} : $graph),
            scope       => (exists $opts{scope} ? $opts{scope} : $scope),
            factory      => (exists $opts{factory}      ? $opts{factory}      : $factory),
            control_head => (exists $opts{control_head} ? $opts{control_head} : $control_head),
        );
    }

    # Create a context of contexts
    # duplicate() = extend(id) where id is the identity function
    method duplicate() {
        return $self->extend(sub ($ctx) { return $ctx });
    }

    # Collect leaf contexts with defined focuses from this Context tree.
    # A "leaf" is a context that has a defined focus (set by multiply with a complete-annotated Context).
    # Optional $node_class filters to only contexts whose focus isa $node_class.
    method leaves($node_class = undef) {
        return $self->walk_all(sub ($node) {
            my $f = $node->extract();
            if (!$node_class || $f isa $node_class) {
                return $node;
            }
            return undef;
        });
    }

    # Extract concatenated scanned text from this Context tree.
    # Walks the tree and collects all string focuses (set by multiply with a scan-annotated Context),
    # concatenating them in order. Non-string (ref) focuses do not contribute
    # text, but their children are still walked (same as undef focus nodes).
    # Iterative (explicit stack) to avoid deep-recursion on tall parse trees.
    method scanned_text() {
        my $text = '';
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f && !ref($f)) {
                # String focus from a scan event — accumulate text, no child recursion
                $text .= $f;
                next;
            }

            # Undef focus (intermediate node) or ref focus (IR node from a complete event):
            # either way, recurse into children to collect scanned text.
            # Push children in reverse order so leftmost child is processed first.
            push @stack, reverse $node->children()->@*;
        }

        return $text;
    }

    # Walk the tree and return the first defined result from $callback.
    # Descends through unfocused multiply nodes, stops at focused leaves.
    # Optional reverse => true for right-to-left traversal.
    method walk($callback, %opts) {
        my $reverse = $opts{reverse};
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                my $result = $callback->($node);
                return $result if defined $result;
                next;
            }
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, @kids;
        }

        return undef;
    }

    # Walk the tree and collect all defined results from $callback.
    # Descends through unfocused multiply nodes, stops at focused leaves.
    # Optional reverse => true for right-to-left traversal.
    method walk_all($callback, %opts) {
        my $reverse = $opts{reverse};
        my @results;
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                my $result = $callback->($node);
                push @results, $result if defined $result;
                next;
            }
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, @kids;
        }

        return @results;
    }

    # Walk the tree threading an accumulator through focused leaves.
    # $callback->($acc, $node) returns the new accumulator value.
    # Optional reverse => true for right-to-left traversal.
    method walk_acc($init, $callback, %opts) {
        my $reverse = $opts{reverse};
        my $acc = $init;
        my @stack = ($self);

        while (@stack) {
            my $node = pop @stack;
            my $f = $node->extract();
            if (defined $f) {
                $acc = $callback->($acc, $node);
                next;
            }
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, @kids;
        }

        return $acc;
    }

    # Assemble a CFG-state hashref from the tree's $scope field and any
    # structural annotations (if_node, loop, try_node, then_stmts, etc.)
    # set on _complete_sa result nodes.
    #
    # Walks the whole subtree, collecting:
    #   - the outermost scope (the one whose control is most-advanced — non-Start
    #     wins over Start, BFS-first wins among equally-advanced)
    #   - the first occurrence of each known structural-annotation key
    #
    # Returns undef when no scope is found anywhere in the tree. Otherwise
    # returns { control => $scope->control(), scope => $scope, %structural }.
    #
    # Replaces the read-side of the deleted cfg_state side channel — see
    # docs/plans/2026-05-20-mop-migration-3a-infra-status.md. The structural
    # keys are kept as-is to avoid forcing every reader to walk the tree
    # themselves; future work may push readers to fish out the specific keys
    # they need directly via $ctx->annotations()->{$key}.
    my @_cfg_struct_keys = qw(
        if_node loop try_node
        then_stmts else_stmts body_stmts statements
        loop_if body_proj exit_proj
        true_proj false_proj
        loop_jump iterator list
        catch_var try_stmts catch_stmts
    );

    # Returns { control, scope, ...structural } summarizing this Context.
    # Walks all child Contexts to find the most-advanced control_head; the
    # accompanying scope and structural annotations come from the same node.
    #
    # Post-Commit-2 of scope/control divorce: sources `control` from the
    # new control_head Context field, not from scope.control. The returned
    # hash's `control` and `scope` keys preserve the public contract.
    method cfg_state() {
        my @stack = ($self);
        my $found_ch;
        my $found_scope;
        my %structural;

        while (@stack) {
            my $node = pop @stack;

            my $nc = $node->control_head;
            if (defined $nc) {
                # Co-existence invariant: every site that sets control_head
                # also has scope populated. If $found_scope is missing here,
                # it's a code bug, not a cfg_state defect.
                if (!defined $found_ch) {
                    $found_ch = $nc;
                    $found_scope = $node->scope;
                } else {
                    # Prefer non-Start over Start (structural change wins).
                    if ($found_ch->operation eq 'Start'
                            && $nc->operation ne 'Start') {
                        $found_ch = $nc;
                        $found_scope = $node->scope;
                    }
                }
            }

            my $ann = $node->annotations();
            for my $key (@_cfg_struct_keys) {
                $structural{$key} //= $ann->{$key} if exists $ann->{$key};
            }

            push @stack, $node->children()->@*;
        }

        return undef unless defined $found_ch;

        return {
            control => $found_ch,
            scope   => $found_scope,
            %structural,
        };
    }
}
