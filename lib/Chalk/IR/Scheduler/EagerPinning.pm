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
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::TryCatch;
use Chalk::Scheduler::EagerPinning::If;
use Chalk::Scheduler::EagerPinning::Loop;
use Chalk::Scheduler::EagerPinning::TryCatch;

class Chalk::IR::Scheduler::EagerPinning {

    # Schedule a single MOP::Method or MOP::Sub. Returns a
    # Chalk::IR::Schedule populated with stmt items plus matched
    # block_open / block_close (and interior else / elsif / catch)
    # markers for structured control flow.
    method schedule($method) {
        my $graph = $method->graph;
        my @returns = $graph->returns->@*;
        return Chalk::IR::Schedule->new(items => []) unless @returns;

        # A method with multiple `return` statements has multiple Return
        # nodes in the graph (one per source-level `return`). The outer
        # chain ends at exactly one of them — the chain-final Return,
        # whose inputs[0] is on the outer chain rather than at a Start
        # (which would mean this Return is inside an inner branch). We
        # pick the one with the deepest chain by traversing from each
        # candidate; the chain whose walk visits the most distinct
        # nodes is the outer chain.
        my $exit = $self->_pick_outer_return(\@returns);

        # Walk backward from the Return's control input. The chain
        # predecessor reading varies by node type:
        #
        #   Region: no single chain predecessor (its inputs are Projs
        #     from divergent branches). Read $region->head to find the
        #     controlling If/Loop and continue from head.control_in.
        #   If, Loop: override control_in to read inputs[0] (rewired
        #     by Block fixup).
        #   VarDecl: control predecessor lives in control_in (set by
        #     Block fixup); inputs hold only the name and init.
        #   Return, Unwind: control predecessor lives in control_in;
        #     inputs hold only the value.
        #   Call, Assign, CompoundAssign, RegexSubst, TryCatch: base
        #     control_in field set by Block fixup; that's the
        #     predecessor.
        #
        # Unified reader: $cur->control_in if defined, else inputs[0].
        my @reverse;
        my $cur = $exit->control_in;
        while (defined $cur && blessed($cur)) {
            last if $cur->operation eq 'Start';

            if ($cur isa Chalk::IR::Node::Region) {
                my $head = $cur->head;
                last unless defined $head;
                push @reverse, $head;
                $cur = $head->control_in;
                next;
            }

            push @reverse, $cur;
            my $next = $cur->control_in;
            if (!defined $next) {
                my $ins = $cur->inputs;
                last unless defined $ins && ref($ins) eq 'ARRAY';
                $next = $ins->[0];
            }
            $cur = $next;
        }

        my @body = reverse @reverse;
        push @body, $exit;

        my @items;
        for my $node (@body) {
            push @items, $self->_expand_node($node);
        }

        return Chalk::IR::Schedule->new(items => \@items);
    }

    # Pick the outer-chain Return from a list of candidates. The outer
    # Return is the one whose inputs[0]-via-control_in chain walks back
    # to a Start without going through another Return's inner branch.
    # Heuristic: count the chain depth (number of distinct nodes
    # reachable backward) for each candidate; the deepest one wins.
    # Ties broken by the candidate that comes last in the input list
    # (parser order typically puts the chain-final return last).
    method _pick_outer_return($returns) {
        return $returns->[0] if scalar $returns->@* == 1;

        my $best     = $returns->[0];
        my $best_len = 0;
        for my $r ($returns->@*) {
            my $len = 0;
            my $cur = $r->control_in;
            my %seen;
            while (defined $cur && blessed($cur)) {
                last if $cur->operation eq 'Start';
                last if $seen{$cur->id}++;
                $len++;
                my $next = $cur->can('control_in') ? $cur->control_in : undef;
                if (!defined $next) {
                    my $ins = $cur->inputs;
                    last unless defined $ins && ref($ins) eq 'ARRAY';
                    $next = $ins->[0];
                }
                # Region jumps: read its head.
                if (blessed($next) && $next->can('operation')
                        && $next->operation eq 'Region'
                        && $next->can('head'))
                {
                    my $head = $next->head;
                    $next = defined $head ? $head->control_in : undef;
                }
                $cur = $next;
                last if ref($cur) eq 'ARRAY';
            }
            if ($len > $best_len) {
                $best = $r;
                $best_len = $len;
            } elsif ($len == $best_len) {
                # Prefer Return over Unwind on ties: an Unwind (die/throw)
                # is a terminal abort node; the synthetic Return is the
                # true method exit. Picking Unwind here causes the method
                # body to be emitted as `die $e` instead of the structured
                # try/catch block.
                if (!($best isa Chalk::IR::Node::Return)
                        && $r isa Chalk::IR::Node::Return) {
                    $best = $r;
                    $best_len = $len;
                }
            }
        }
        return $best;
    }

    # Convert a single body-position node into one or more Schedule
    # items. Control nodes (If) expand into structured block markers;
    # everything else becomes a single stmt item. Loop and TryCatch
    # expansion lands in Phase 4c/4d.
    method _expand_node($node) {
        if ($node isa Chalk::IR::Node::If) {
            return $self->_expand_if($node);
        }
        if ($node isa Chalk::IR::Node::Loop) {
            return $self->_expand_loop($node);
        }
        if ($node isa Chalk::IR::Node::TryCatch) {
            return $self->_expand_try($node);
        }
        return Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $node);
    }

    # Structured expansion for a TryCatch node. Reads
    # try_stmts/catch_stmts/catch_var from EagerPinning::TryCatch
    # schedule_data (mig 4). Emits:
    #
    #   block_open(try, node=$try)
    #   ...try-body items...
    #   catch
    #   ...catch-body items...
    #   block_close(try)
    #
    # The catch variable name is carried on the catch marker's node
    # field as a Constant — codegen looks it up off the TryCatch's
    # schedule_data when emitting the `catch ($e)` clause.
    method _expand_try($try) {
        my $sd = $try->schedule_data;

        unless (defined $sd && $sd isa Chalk::Scheduler::EagerPinning::TryCatch) {
            return Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $try);
        }

        my @items;
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'block_open',
            form => 'try',
            node => $try,
        );
        for my $t ($sd->try_stmts->@*) {
            push @items, $self->_expand_node($t);
        }
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'catch',
            node => $try,
        );
        for my $c ($sd->catch_stmts->@*) {
            push @items, $self->_expand_node($c);
        }
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'block_close',
            form => 'try',
        );
        return @items;
    }

    # Structured expansion for a Loop node. Reads body_stmts and form-
    # determining fields from EagerPinning::Loop schedule_data (migs 1,
    # 3, 6). Surface-form choice:
    #
    #   iterator defined    → form 'foreach'
    #   is_for_style true   → form 'for'      (C-style)
    #   otherwise           → form 'while'
    #
    # `until` is already normalized to `while !cond` in the IR (the
    # PostfixModifier / WhileStatement actions wrap the condition);
    # the scheduler emits `while` in both cases.
    method _expand_loop($loop) {
        my $sd = $loop->schedule_data;

        unless (defined $sd && $sd isa Chalk::Scheduler::EagerPinning::Loop) {
            return Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $loop);
        }

        my $form = defined $sd->iterator    ? 'foreach'
                 : $sd->is_for_style        ? 'for'
                 :                            'while';

        my @items;
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'block_open',
            form => $form,
            node => $loop,
        );
        for my $b ($sd->body_stmts->@*) {
            push @items, $self->_expand_node($b);
        }
        push @items, Chalk::IR::Schedule::Item->new(
            kind => 'block_close',
            form => $form,
        );
        return @items;
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
