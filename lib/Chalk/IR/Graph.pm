# ABOUTME: Container for a complete Chalk computation graph with hash-cons scope.
# ABOUTME: Owns %cache and $cfg_counter; merge() hash-conses nodes into this graph.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::IR::Graph {
    # Legacy constructor params (optional, used by existing callers pre-Phase 2).
    # New code constructs empty graphs and accumulates via merge().
    field $start_param   :param(start)      = undef;
    field $returns_param :param(returns)    = [];
    field $schedule      :param :reader     = {};

    # Per-graph hash-cons cache (content-hash → node).
    # Scoped to this graph so consumer lists cannot leak across graphs.
    # Bidirectional traversal in nodes() relies on per-graph scope: consumer
    # lists never reach nodes from a different graph because each graph hash-
    # conses its own nodes.
    field %cache;

    # Unique ID allocator for CFG nodes (If, Proj, Region, Loop, Start, Return, Unwind).
    # CFG nodes are never hash-consed; each call site gets a distinct node.
    field $cfg_counter = 0;

    ADJUST {
        # Seed the cache with any nodes provided at construction time.
        # This preserves semantics for legacy callers that pass start/returns.
        if (defined $start_param) {
            $self->_seed($start_param);
        }
        for my $r ($returns_param->@*) {
            $self->_seed($r) if defined $r;
        }
    }

    # Seed the cache with an already-constructed node. Used by legacy callers
    # and by the BFS traversal in nodes() to include transitively-reachable nodes.
    method _seed($node) {
        return unless defined $node && blessed($node);
        my $id = $node->id();
        return if exists $cache{$id};
        $cache{$id} = $node;
    }

    # Hash-cons a freshly-constructed data node into this graph.
    # If an identical node (same content_hash) already exists, returns the existing one.
    # Otherwise adds the node to the cache and returns it.
    #
    # Per-call nodes (counter-suffixed ids: VarDecl#3, Assign#7, If#2, ...)
    # are keyed by id, never by content: two content-identical statement
    # effects are distinct members, and merge must return the node it was
    # handed — substituting a content-equal earlier member would silently
    # re-point a statement at the wrong side effect.
    method merge($node) {
        return unless defined $node && blessed($node);
        # Per-call ids are bare "Op#N" tokens; content-hash ids are
        # pipe-joined ("Op|...") and can END in an embedded per-call input
        # id ("PadAccess|...|VarDecl#3"), so the suffix alone is not enough.
        my $id = $node->id();
        if (defined $id && $id !~ /\|/ && $id =~ /#\d+$/) {
            $cache{$id} = $node;
            return $node;
        }
        my $hash = $node->content_hash();
        if (exists $cache{$hash}) {
            return $cache{$hash};
        }
        $cache{$hash} = $node;
        return $node;
    }

    # Remove a node from the graph's cache. Used when a side-effect action
    # (e.g., AssignmentExpression refining a bare VarDecl) replaces an
    # earlier node with a refined version that should be the sole reachable
    # representative in the graph.
    method unmerge($node) {
        return unless defined $node && blessed($node);
        my $id = $node->id();
        # Per-call nodes (bare "Op#N" ids, no pipe) are keyed by id only;
        # deleting by content_hash here could evict a content-identical
        # sibling that is a distinct effect.
        if (defined $id && $id !~ /\|/ && $id =~ /#\d+$/) {
            delete $cache{$id};
            return;
        }
        my $hash = $node->content_hash();
        delete $cache{$hash};
        # Also delete by id in case the node was added via _seed().
        delete $cache{$id} if defined $id && $id ne $hash;
        return;
    }

    # Allocate a unique CFG node id. CFG nodes (If, Proj, Region, Loop, Start,
    # Return, Unwind) are never hash-consed; each call returns a new id.
    method next_cfg_id() {
        return ++$cfg_counter;
    }

    # Returns the nodes that were explicitly merged/seeded into this graph —
    # the membership set ONLY, without the transitive input closure that
    # nodes() walks. Use when "belongs to this graph" matters (e.g. which
    # nodes are an ADJUST body's statements) rather than reachability.
    method members() {
        return [ values %cache ];
    }

    # Returns the Start node for this graph, derived from the cache.
    # Preserves legacy param when provided; otherwise scans the cache.
    method start() {
        return $start_param if defined $start_param;
        for my $node (values %cache) {
            return $node if ref($node) && $node->isa('Chalk::IR::Node::Start');
        }
        return undef;
    }

    # Returns Return/Unwind nodes for this graph, derived from the cache.
    # Preserves legacy param when provided; otherwise scans the cache.
    method returns() {
        return $returns_param if $returns_param->@*;
        my @r;
        for my $node (values %cache) {
            next unless ref($node);
            if ($node->isa('Chalk::IR::Node::Return')
                    || $node->isa('Chalk::IR::Node::Unwind')) {
                push @r, $node;
            }
        }
        return \@r;
    }

    method nodes() {
        # Returns a topologically-sorted list of nodes in this graph.
        #
        # Walks both inputs() and consumers() from every cached node.
        # Inputs are followed unconditionally (the legacy input-closure
        # behavior — transitive inputs of cached nodes appear in the
        # result even if they were not separately merged in).
        #
        # Consumers are followed only when they are themselves in
        # %cache. This is the membership filter that keeps the walk
        # graph-local: consumer pointers can reach foreign nodes
        # (the Bootstrap singleton's hash-cons cache is process-wide)
        # or orphan nodes (built by losing Earley alternatives and
        # never merged into any graph), and those must not appear in
        # the result.
        my $in_cache = sub ($n) {
            return false unless blessed($n);
            my $id = $n->id();
            return true if exists $cache{$id};
            # Per-call nodes (bare "Op#N" ids, no pipe) are keyed by id only
            # — a content-hash fallback would admit content-identical
            # orphans (e.g., losing Earley alternatives that were never
            # merged into any graph).
            return false if defined $id && $id !~ /\|/ && $id =~ /#\d+$/;
            return true if $n->can('content_hash')
                && exists $cache{$n->content_hash()};
            return false;
        };

        # Iterative post-order DFS. Each stack frame is
        # [$node, $emit_phase]:
        #   $emit_phase = 0 — first visit; push children, then re-push
        #                     self with phase=1 so we finalize after
        #                     descendants complete (post-order).
        #   $emit_phase = 1 — finalize: move from temp to visited,
        #                     append to @order.
        # The earlier recursive implementation hit Perl's deep-recursion
        # warning at 100 frames on graphs produced by ~20KB+ source
        # files; this iterative form has no recursion depth bound (only
        # heap-bounded stack growth).
        my @order;
        my %visited;
        my %temp;
        my @stack;
        for my $root (values %cache) {
            push @stack, [$root, 0];
        }

        # Helper: collect the child nodes of $n in the order the
        # recursive version would have visited them — inputs first
        # (with array-of-arrayrefs flattening), then cache-filtered
        # consumers. The returned list is what we push on the stack
        # in REVERSE so pop()-LIFO yields the original left-to-right
        # visit order.
        my $children_of = sub ($n) {
            my @children;
            for my $input ($n->inputs()->@*) {
                if (ref($input) eq 'ARRAY') {
                    for my $el ($input->@*) {
                        push @children, $el
                            if defined $el && blessed($el);
                    }
                    next;
                }
                push @children, $input
                    if defined $input && blessed($input);
            }
            if ($n->can('consumers')) {
                for my $c ($n->consumers()->@*) {
                    push @children, $c if $in_cache->($c);
                }
            }
            return @children;
        };

        while (@stack) {
            my $frame = pop @stack;
            my ($n, $phase) = $frame->@*;
            next unless blessed($n);

            if ($phase == 1) {
                # Finalize: post-order emit.
                delete $temp{$n->id()};
                $visited{$n->id()} = 1;
                push @order, $n;
                next;
            }

            # phase == 0: pre-visit.
            next if $visited{$n->id()};
            next if $temp{$n->id()};
            $temp{$n->id()} = 1;

            # Push our finalize-frame first so it's processed AFTER
            # all children — LIFO stack means children pop first.
            push @stack, [$n, 1];

            # Push children in reverse so leftmost pops first,
            # matching the recursive visitor's left-to-right order.
            my @children = $children_of->($n);
            for my $c (reverse @children) {
                push @stack, [$c, 0];
            }
        }

        return \@order;
    }
}
