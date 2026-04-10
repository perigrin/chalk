# ABOUTME: Container for a complete Chalk computation graph.
# ABOUTME: Holds Start/Return/Unwind nodes and provides topological iteration.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::IR::Graph {
    field $start    :param :reader;
    field $returns  :param :reader = [];
    field $schedule :param :reader = {};

    method nodes() {
        my @order;
        my %visited;

        # BFS to find all reachable nodes
        my @worklist = ($start, $returns->@*);
        my @all;
        my %seen;
        while (my $node = shift @worklist) {
            next unless defined $node;
            next unless blessed($node);
            next if $seen{$node->id()}++;
            push @all, $node;
            push @worklist, $node->inputs()->@*;
            # consumers() may contain stale weak refs (unblessed); filter them
            push @worklist, grep { defined $_ && blessed($_) } $node->consumers()->@*;
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
