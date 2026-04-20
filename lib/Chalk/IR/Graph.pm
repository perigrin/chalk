# ABOUTME: Container for a complete Chalk computation graph.
# ABOUTME: Holds Start/Return/Unwind nodes and provides topological iteration.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::IR::Graph {
    field $start      :param :reader;
    field $returns    :param :reader = [];
    field $schedule   :param :reader = {};

    # Body statements for the method/sub this graph covers.
    # These are included as BFS seeds so that side-effect nodes
    # (VarDecl, Assign, Call) that lack explicit control inputs
    # are still reachable via graph->nodes().  This is a prototype
    # approach: the statements themselves become roots alongside
    # Start and Return, making their transitive inputs visible.
    field $body_stmts :param :reader = [];

    method nodes() {
        my @order;
        my %visited;

        # BFS to find all nodes reachable via inputs() from start, returns,
        # and body_stmts.  body_stmts seeds ensure side-effect statements
        # (VarDecl, Assign, Call) are reachable even though they have no
        # explicit control edge to Start or Return yet.
        #
        # Following consumers() is intentionally excluded: shared hash-consed
        # nodes (e.g., a Start constant used as a control token by multiple
        # methods) accumulate consumers from every method graph that references
        # them. Traversing consumers() would pull foreign Return/Unwind nodes
        # from other method graphs into this one.
        my @worklist = ($start, $returns->@*, $body_stmts->@*);
        my @all;
        my %seen;
        while (my $node = shift @worklist) {
            next unless defined $node;
            next unless blessed($node);
            next if $seen{$node->id()}++;
            push @all, $node;
            push @worklist, $node->inputs()->@*;
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
