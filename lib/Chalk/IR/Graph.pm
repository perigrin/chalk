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
    field $body_stmts    :param :reader     = [];

    # Per-graph hash-cons cache (content-hash → node).
    # Scoped to this graph so consumer lists cannot leak across graphs.
    field %cache;

    # Unique ID allocator for CFG nodes (If, Proj, Region, Loop, Start, Return, Unwind).
    # CFG nodes are never hash-consed; each call site gets a distinct node.
    field $cfg_counter = 0;

    ADJUST {
        # Seed the cache with any nodes provided at construction time.
        # This preserves semantics for legacy callers that pass start/returns/body_stmts.
        if (defined $start_param) {
            $self->_seed($start_param);
        }
        for my $r ($returns_param->@*) {
            $self->_seed($r) if defined $r;
        }
        for my $b ($body_stmts->@*) {
            $self->_seed($b) if defined $b;
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
        my @order;
        my %visited;

        # If the cache has been populated via merge() or _seed(), iterate it directly.
        # Otherwise fall back to the legacy BFS from start/returns/body_stmts seeds.
        my @all = values %cache;

        if (!@all) {
            # Legacy BFS path — kept for backward compat with callers that
            # construct Graph->new(start=>, returns=>) without merging.
            my $s = $self->start();
            my $r = $self->returns();
            my @worklist = ($s // (), $r->@*, $body_stmts->@*);
            my %seen;
            while (my $node = shift @worklist) {
                next unless defined $node;
                next unless blessed($node);
                next if $seen{$node->id()}++;
                push @all, $node;
                push @worklist, $node->inputs()->@*;
            }
        }

        # Topological sort via DFS post-order
        my %temp;
        my $visit;
        $visit = sub ($n) {
            return unless blessed($n);
            return if $visited{$n->id()};
            return if $temp{$n->id()};
            $temp{$n->id()} = 1;
            for my $input ($n->inputs()->@*) {
                next unless defined $input && blessed($input);
                $visit->($input);
            }
            delete $temp{$n->id()};
            $visited{$n->id()} = 1;
            push @order, $n;
        };

        for my $node (@all) {
            $visit->($node);
        }

        return \@order;
    }
}
