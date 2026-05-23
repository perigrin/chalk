# ABOUTME: Eager-pinning scheduler — walks the Return->Start chain via inputs[0] and emits Items.
# ABOUTME: Phase 4a covers if/else structured expansion via schedule_data; loop/try are Phase 4c/4d.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Scalar::Util qw(blessed refaddr);
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Region;
use Chalk::Scheduler::EagerPinning::If;

class Chalk::IR::Scheduler::EagerPinning {

    # Schedule a single MOP::Method or MOP::Sub. Returns a
    # Chalk::IR::Schedule populated with stmt items plus matched
    # block_open / block_close (and interior else / elsif / catch)
    # markers for structured control flow.
    method schedule($method) {
        my $graph = $method->graph;
        my @returns = $graph->returns->@*;
        return Chalk::IR::Schedule->new(items => []) unless @returns;

        my $exit = $returns[0];

        # Walk backward from the Return's control input via inputs[0],
        # collecting body-position nodes. When the walk hits a Region,
        # the Region has no single chain predecessor (its inputs are
        # Projs from divergent branches); we read Region.head to find
        # the controlling If/Loop/TryCatch, treat THAT as the body
        # node, and continue from head.control_in.
        my @reverse;
        my $cur = $exit->inputs->[0];
        while (defined $cur && blessed($cur)) {
            last if $cur->operation eq 'Start';

            if ($cur isa Chalk::IR::Node::Region) {
                my $head = $cur->head;
                # Bail if Region has no head — shouldn't happen for
                # parser-built IR, but degrade gracefully.
                last unless defined $head;
                push @reverse, $head;
                $cur = $head->control_in;
                next;
            }

            push @reverse, $cur;
            my $ins = $cur->inputs;
            last unless defined $ins && ref($ins) eq 'ARRAY';
            $cur = $ins->[0];
        }

        my @body = reverse @reverse;
        push @body, $exit;

        my @items;
        for my $node (@body) {
            push @items, $self->_expand_node($node);
        }

        return Chalk::IR::Schedule->new(items => \@items);
    }

    # Convert a single body-position node into one or more Schedule
    # items. Control nodes (If) expand into structured block markers;
    # everything else becomes a single stmt item. Loop and TryCatch
    # expansion lands in Phase 4c/4d.
    method _expand_node($node) {
        if ($node isa Chalk::IR::Node::If) {
            return $self->_expand_if($node);
        }
        return Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $node);
    }

    # Structured expansion for an If node. Reads then_stmts/else_stmts
    # from the EagerPinning::If schedule_data populated by the parser
    # actions (mig 5). Emits:
    #
    #   block_open(if, node=$if)
    #   ...then-branch items...
    #   [else]                       — only if else_stmts is defined
    #   ...else-branch items...
    #   block_close(if)
    method _expand_if($if) {
        my $sd = $if->schedule_data;

        # An If without schedule_data is unexpected today (every parser
        # site populates it), but degrade gracefully to a one-item stmt.
        unless (defined $sd && $sd isa Chalk::Scheduler::EagerPinning::If) {
            return Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $if);
        }

        my @items;
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'block_open',
            form => 'if',
            node => $if,
        );
        for my $t ($sd->then_stmts->@*) {
            push @items, $self->_expand_node($t);
        }
        if (defined $sd->else_stmts) {
            # Elsif recognition: the else branch is *exactly one* If
            # node. The two source forms `if(A){} elsif(B){}` and
            # `if(A){} else { if(B){} }` produce identical IR (a
            # single-If else_stmts arrayref), and both emit as
            # `} elsif (B) {` in byte-compat round-trip — they're
            # semantically equivalent. We do NOT compare $if->region
            # against the nested If's region because the parser
            # creates separate Regions for nested Ifs that are never
            # merged into the outer chain anyway.
            my @else = $sd->else_stmts->@*;
            if (@else == 1
                && blessed($else[0])
                && $else[0] isa Chalk::IR::Node::If)
            {
                $self->_expand_elsif_chain($else[0], \@items);
            } else {
                push @items, Chalk::IR::Schedule::Item->new(kind => 'else');
                for my $e (@else) {
                    push @items, $self->_expand_node($e);
                }
            }
        }
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'block_close',
            form => 'if',
        );
        return @items;
    }

    # Helper for _expand_if: walk an elsif chain, pushing markers and
    # branch items in source order without opening new blocks. The
    # incoming $if is the chain's next-clause If; we emit its
    # elsif marker then its then/(else | recurse-elsif) body. The
    # block_close belongs to the outer block_open, so we don't emit
    # one here.
    method _expand_elsif_chain($if, $items) {
        my $sd = $if->schedule_data;
        unless (defined $sd && $sd isa Chalk::Scheduler::EagerPinning::If) {
            push $items->@*, Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $if);
            return;
        }

        push $items->@*, Chalk::IR::Schedule::Item->new(
            kind => 'elsif',
            node => $if,
        );
        for my $t ($sd->then_stmts->@*) {
            push $items->@*, $self->_expand_node($t);
        }

        if (defined $sd->else_stmts) {
            my @else = $sd->else_stmts->@*;
            if (@else == 1
                && blessed($else[0])
                && $else[0] isa Chalk::IR::Node::If)
            {
                $self->_expand_elsif_chain($else[0], $items);
            } else {
                push $items->@*, Chalk::IR::Schedule::Item->new(kind => 'else');
                for my $e (@else) {
                    push $items->@*, $self->_expand_node($e);
                }
            }
        }
    }
}
