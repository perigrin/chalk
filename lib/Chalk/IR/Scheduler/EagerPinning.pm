# ABOUTME: Eager-pinning scheduler — walks the Return->Start chain via inputs[0] and emits Items.
# ABOUTME: Phase 3 covers straight-line bodies only; if/loop/try structured expansion is Phase 4.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Scalar::Util qw(blessed);
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;

class Chalk::IR::Scheduler::EagerPinning {

    # Schedule a single MOP::Method or MOP::Sub. Returns a
    # Chalk::IR::Schedule containing the side-effect chain in source
    # order, terminating in the Return / Unwind.
    #
    # Algorithm: walk inputs[0] backward from the graph's Return (or
    # Unwind) until we hit Start, accumulating nodes. Reverse to get
    # source order. Emit one { kind => stmt, node => $n } per node,
    # then the Return itself.
    method schedule($method) {
        my $graph = $method->graph;
        my @returns = $graph->returns->@*;
        return Chalk::IR::Schedule->new(items => []) unless @returns;

        my $exit = $returns[0];

        # Walk backward via inputs[0] from the Return's control input.
        # Stop at Start (which has no further predecessor).
        my @reverse;
        my $cur = $exit->inputs->[0];
        while (defined $cur && blessed($cur)) {
            last if $cur->operation eq 'Start';
            push @reverse, $cur;
            my $ins = $cur->inputs;
            last unless defined $ins && ref($ins) eq 'ARRAY';
            $cur = $ins->[0];
        }

        my @body = reverse @reverse;
        push @body, $exit;

        my @items = map {
            Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $_)
        } @body;

        return Chalk::IR::Schedule->new(items => \@items);
    }
}
