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
    method merge($node) {
        return unless defined $node && blessed($node);
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
        my $hash = $node->content_hash();
        delete $cache{$hash};
        # Also delete by id in case the node was added via _seed().
        my $id = $node->id();
        delete $cache{$id} if defined $id && $id ne $hash;
        return;
    }

    # Allocate a unique CFG node id. CFG nodes (If, Proj, Region, Loop, Start,
    # Return, Unwind) are never hash-consed; each call returns a new id.
    method next_cfg_id() {
        return ++$cfg_counter;
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
            return true if exists $cache{$n->id()};
            return true if $n->can('content_hash')
                && exists $cache{$n->content_hash()};
            return false;
        };

        my @order;
        my %visited;
        my %temp;
        my $visit;
        $visit = sub ($n) {
            return unless blessed($n);
            return if $visited{$n->id()};
            return if $temp{$n->id()};
            $temp{$n->id()} = 1;
            for my $input ($n->inputs()->@*) {
                if (ref($input) eq 'ARRAY') {
                    for my $el ($input->@*) {
                        $visit->($el) if defined $el && blessed($el);
                    }
                    next;
                }
                next unless defined $input && blessed($input);
                $visit->($input);
            }
            if ($n->can('consumers')) {
                for my $c ($n->consumers()->@*) {
                    next unless $in_cache->($c);
                    $visit->($c);
                }
            }
            delete $temp{$n->id()};
            $visited{$n->id()} = 1;
            push @order, $n;
        };

        for my $node (values %cache) {
            $visit->($node);
        }

        return \@order;
    }
}
