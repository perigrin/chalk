# ABOUTME: Scoped-elaboration placement pass for the Chalk LLVM back-half scheduler.
# ABOUTME: Walks the dominator tree in preorder; places values where first needed;
# ABOUTME: emits phi nodes at Region merge points where values diverge between branches.
#
# This is the aegraph "elaborate" step (Cranelift framing): given a dominator tree
# built from the IR control nodes, walk each block in dominator-tree preorder. For
# each side-effectful node in the block, demand its pure inputs (recursively
# placing them into the earliest block that dominates all uses). At Region merge
# points, emit a phi for any variable whose SSA value differs between predecessors.
#
# Defs-dominate-uses holds BY CONSTRUCTION: a value placed in block B is visible
# in B and every block B dominates (the dominated subtree). Values needed in two
# sibling branches (neither dominates the other) are rematerialized per branch
# or, if they are mutable variables ($x was assigned in one branch only), get a
# phi at the common dominator (the merge block).
#
# This module does NOT perform front-half optimization (no GVN/LICM/rewrite).
# Placement only.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::NodeFactory;   # %STATEMENT_EFFECT_OPS (the shared statement-effect table)

class Chalk::IR::Schedule::Elaborate {
    # blocks: arrayref of elaborated blocks in dominator-preorder.
    # Each block is { id, ctrl_nodes, phi_nodes => [...] }
    field $blocks :param :reader;

    # dominators: the Dominators object used for this elaboration.
    field $dominators :param;

    # emitted_phis: arrayref of { block_id, vd_id, incoming => [...], repr }
    # records for each phi emitted at a merge block.
    field $emitted_phis :param :reader = [];

    # emit_phi($block_id, $vd_id, $incoming, $repr) -> records a phi.
    # Called by the elaboration pass at merge points.
    method emit_phi($block_id, $vd_id, $incoming, $repr) {
        push $emitted_phis->@*, {
            block_id => $block_id,
            vd_id    => $vd_id,
            incoming => $incoming,
            repr     => $repr,
        };
    }

    # ---------------------------------------------------------------------------
    # Class method: build an Elaborate object from a Return node + Dominators.
    # Runs the scoped elaboration: walks the control chain, tracks SSA values
    # per variable through branches, and emits phi nodes at Region merges.
    # ---------------------------------------------------------------------------
    sub from_return_node($class, $ret_node, $dominators) {
        # Walk the control_in chain from Return to build an ordered list of
        # control nodes and detect branch/merge structure.
        my @ctrl_chain = _collect_control_chain($ret_node);

        my @elaborated_blocks;
        my @emitted_phis;

        # val_map: VarDecl-id -> current SSA value (an IR node).
        # We thread this map through the control chain, forking at If/Loop
        # and merging (with phi emission) at Region nodes.
        my %val_map;

        _elaborate_chain(
            \@ctrl_chain,
            \%val_map,
            \@elaborated_blocks,
            \@emitted_phis,
            $dominators,
        );

        return $class->new(
            blocks       => \@elaborated_blocks,
            dominators   => $dominators,
            emitted_phis => \@emitted_phis,
        );
    }

    # ---------------------------------------------------------------------------
    # Private helpers
    # ---------------------------------------------------------------------------

    # _collect_control_chain($ret_node) -> ordered list of control nodes (forward).
    # Walks control_in backward from Return, collecting the chain in reverse,
    # then reverses it. Stops when control_in is undef or circular.
    sub _collect_control_chain($ret_node) {
        my @chain;
        my $cur = $ret_node;
        my %seen;
        while (defined $cur) {
            last if $seen{$cur->id}++;
            push @chain, $cur;
            my $op = $cur->can('operation') ? $cur->operation : '';
            last if $op eq 'Start';
            # Region: stop linear traversal; the region's incoming branches
            # are handled by the If/Loop that preceded the Region.
            # For Region, use its head (the If/Loop that owns it) to continue.
            if ($op eq 'Region') {
                my $head = $cur->can('head') ? $cur->head : undef;
                if (defined $head) {
                    $cur = $head->can('control_in') ? $head->control_in : undef;
                } else {
                    $cur = undef;
                }
                next;
            }
            $cur = $cur->can('control_in') ? $cur->control_in : undef;
        }
        return reverse @chain;
    }

    # _elaborate_chain(\@chain, \%val_map, \@elab_blocks, \@phis, $dom):
    # The core scoped-elaboration loop. Processes each node in the chain:
    # - VarDecl: add variable to val_map with init value.
    # - Assign/CompoundAssign: update val_map for the lhs variable.
    # - If: fork val_map for then/else branches; recurse; merge at Region.
    # - Loop: handle header phi + body + exit merge.
    # - Region: merge point (handled via the If/Loop that precedes it).
    # - Other (Return, Phi): record.
    sub _elaborate_chain($chain, $val_map, $elab_blocks, $phis, $dom) {
        for my $node (@$chain) {
            my $op = $node->can('operation') ? $node->operation : '';

            if ($op eq 'VarDecl') {
                # Find the init value (inputs[1] if present).
                my $init = $node->inputs->[1];
                $val_map->{$node->id} = $init;   # may be undef for uninit
                my $blk = $dom->block_for($node->id);
                push @$elab_blocks, { id => (defined $blk ? $blk->{id} : 'entry'),
                                      ctrl_nodes => [$node], phi_nodes => [] };
            }
            elsif ($op eq 'Assign' || $op eq 'CompoundAssign') {
                # Update the val_map for the target VarDecl.
                my $lhs = $node->inputs->[0];
                my $rhs = $node->inputs->[1];
                my $vd  = _resolve_vd($lhs);
                if (defined $vd) {
                    $val_map->{$vd->id} = $rhs;
                }
                my $blk = $dom->block_for($node->id);
                push @$elab_blocks, { id => (defined $blk ? $blk->{id} : 'entry'),
                                      ctrl_nodes => [$node], phi_nodes => [] };
            }
            elsif ($op eq 'If') {
                _elaborate_if($node, $val_map, $elab_blocks, $phis, $dom);
            }
            elsif ($op eq 'Loop') {
                _elaborate_loop($node, $val_map, $elab_blocks, $phis, $dom);
            }
            elsif ($op eq 'Region') {
                # A Region appearing in the chain indicates that Return.control_in
                # was wired to the Region directly (instead of to the If/Loop that
                # precedes it). The Region's head back-pointer gives us the owning
                # If/Loop, which we elaborate now. This is the M2 path.
                my $head = $node->can('head') ? $node->head : undef;
                if (defined $head) {
                    my $head_op = $head->can('operation') ? $head->operation : '';
                    if ($head_op eq 'If') {
                        _elaborate_if($head, $val_map, $elab_blocks, $phis, $dom);
                    }
                    elsif ($head_op eq 'Loop') {
                        _elaborate_loop($head, $val_map, $elab_blocks, $phis, $dom);
                    }
                }
                # Also record the Region as an elaborated block.
                my $blk = $dom->block_for($node->id);
                my $bid = defined $blk ? $blk->{id} : 'entry';
                push @$elab_blocks, { id => $bid, ctrl_nodes => [$node], phi_nodes => [] };
            }
            # Return, Start, Phi — just record; no val_map update.
            else {
                my $blk = $dom->block_for($node->id);
                my $bid = defined $blk ? $blk->{id} : 'entry';
                push @$elab_blocks, { id => $bid, ctrl_nodes => [$node], phi_nodes => [] };
            }
        }
    }

    # _elaborate_if($if_node, $val_map, ...): fork val_map for then/else,
    # collect branch body nodes, merge at Region with phi emission.
    sub _elaborate_if($if_node, $val_map, $elab_blocks, $phis, $dom) {
        # Snapshot the val_map before branches.
        my %pre = %$val_map;

        # Find Proj consumers for then (0) and else (1).
        my $proj0 = _find_proj($if_node, 0);
        my $proj1 = _find_proj($if_node, 1);

        # Collect body nodes for each branch.
        my @then_chain = defined $proj0 ? _collect_branch_chain($proj0) : ();
        my @else_chain = defined $proj1 ? _collect_branch_chain($proj1) : ();

        # Process then-branch with a copy of pre-branch val_map.
        my %then_map = %pre;
        _elaborate_chain(\@then_chain, \%then_map, $elab_blocks, $phis, $dom);

        # Process else-branch with a copy of pre-branch val_map.
        my %else_map = %pre;
        _elaborate_chain(\@else_chain, \%else_map, $elab_blocks, $phis, $dom);

        # Merge at the Region: for each VarDecl whose value differs between
        # the two branch maps (or differs from the pre-branch value on the
        # not-taken edge), emit a phi at the merge block.
        my $region = $if_node->region;
        # Use 'if.merge.<region_id>' as the canonical merge block key. This must
        # agree with the LLVM backend's phi lookup key (ElaboratedContext uses
        # 'if.merge.' . $region->id). Using the Dominators block_for() can return
        # the wrong block id when the Region is not reachable via the backward
        # control_in chain (e.g. the M2 case: Return.control_in = Region directly).
        my $merge_bid = defined $region ? 'if.merge.' . $region->id : undef;

        # Collect all VarDecl ids visible in either branch.
        my %all_vd_ids;
        $all_vd_ids{$_} = 1 for keys %then_map;
        $all_vd_ids{$_} = 1 for keys %else_map;
        $all_vd_ids{$_} = 1 for keys %pre;

        for my $vd_id (sort keys %all_vd_ids) {
            # then-branch value (fall back to pre-branch if no assignment in then)
            my $then_val = exists $then_map{$vd_id} ? $then_map{$vd_id} : $pre{$vd_id};
            # else-branch value (fall back to pre-branch if no assignment in else)
            my $else_val = exists $else_map{$vd_id} ? $else_map{$vd_id} : $pre{$vd_id};

            # Determine if the two values are the same IR node (by id).
            my $then_id_str = defined $then_val ? $then_val->id : '__undef__';
            my $else_id_str = defined $else_val ? $else_val->id : '__undef__';

            if ($then_id_str ne $else_id_str) {
                # Values differ — emit a phi at the merge block.
                if (defined $merge_bid) {
                    push @$phis, {
                        block_id => $merge_bid,
                        vd_id    => $vd_id,
                        incoming => [
                            { value => $then_val, from_branch => 'then' },
                            { value => $else_val, from_branch => 'else' },
                        ],
                    };
                }
                # After the merge, the variable holds the phi result.
                # Represent the phi result as a sentinel "Phi@merge_bid/vd_id".
                # (The actual LLVM phi instruction is emitted by the backend.)
                # For val_map tracking, store the then_val node with a phi marker.
                $val_map->{$vd_id} = $then_val;  # placeholder; phi replaces at emit time
            }
            else {
                # Same value in both branches — no phi needed.
                $val_map->{$vd_id} = $then_val;
            }
        }
    }

    # _elaborate_loop($loop_node, $val_map, ...): handle loop header phi +
    # body elaboration + exit merge.
    #
    # Loop bodies in the SoN IR represent variable modifications through Phi
    # nodes (backedge pattern), not Assign nodes — so walking the body chain for
    # Assign nodes misses all loop-carried variable updates. Instead, we look at
    # the explicit Phi nodes whose region is this Loop node: each such Phi tracks
    # one variable that changes across loop iterations. The variables tracked by
    # loop Phis are the ones we must mark as modified by the loop.
    #
    # After a loop, any variable tracked by a loop Phi holds the loop-exit value
    # (the header phi ref when the condition was last false). We signal this by
    # storing the loop_node itself as a sentinel in val_map for that variable.
    # The LLVM backend uses var_table snapshots (not lower_value on the sentinel)
    # so the sentinel is never lowered directly; it only serves to make the
    # post-loop value DISTINCT from the pre-loop value so that any outer phi
    # (e.g. the merge of an if whose then-branch contained this loop) detects
    # the divergence and emits the outer merge phi.
    sub _elaborate_loop($loop_node, $val_map, $elab_blocks, $phis, $dom) {
        my $header_blk = $dom->block_for($loop_node->id);
        my $header_bid = defined $header_blk ? $header_blk->{id} : 'loop.header.' . $loop_node->id;

        # Find the VarDecl ids tracked by the loop Phis.
        my %loop_modified_vd_ids;

        # Strategy 1: loop Phi nodes (primary path for D2/D3/D5-style loops).
        my $consumers = $loop_node->consumers // [];
        for my $c (@$consumers) {
            next unless defined $c && $c->can('operation');
            next unless $c->operation eq 'Phi';
            my $r = $c->can('region') ? $c->region : undef;
            next unless defined $r && $r->id eq $loop_node->id;

            my $init_node = $c->inputs->[0];
            next unless defined $init_node;
            my $vd = _resolve_vd_from_node($init_node);
            if (defined $vd) {
                next if $loop_modified_vd_ids{ $vd->id }++;
                push @$phis, {
                    block_id => $header_bid,
                    vd_id    => $vd->id,
                    incoming => [
                        { value => $init_node, from_branch => 'preheader' },
                        { value => $loop_node, from_branch => 'backedge'  },
                    ],
                    is_loop_phi => 1,
                };
            }
        }

        # Strategy 2: body Assign nodes (for assign-within-loop authored graphs).
        my $body_proj = _find_proj($loop_node, 0);
        if (defined $body_proj) {
            my @body_chain = _collect_branch_chain($body_proj);
            my %pre = %$val_map;
            my %body_map = %pre;
            _elaborate_chain(\@body_chain, \%body_map, $elab_blocks, $phis, $dom);

            for my $vd_id (sort keys %pre) {
                next if $loop_modified_vd_ids{$vd_id};
                my $init_val = $pre{$vd_id};
                my $body_val = $body_map{$vd_id} // $init_val;
                my $init_id  = defined $init_val ? $init_val->id : '__undef__';
                my $body_id  = defined $body_val ? $body_val->id : '__undef__';
                if ($init_id ne $body_id) {
                    $loop_modified_vd_ids{$vd_id} = 1;
                    push @$phis, {
                        block_id => $header_bid,
                        vd_id    => $vd_id,
                        incoming => [
                            { value => $init_val, from_branch => 'preheader' },
                            { value => $body_val, from_branch => 'backedge'  },
                        ],
                        is_loop_phi => 1,
                    };
                }
            }
        }

        # For every loop-modified variable, update val_map to the loop_node sentinel.
        # Its id differs from any init_val->id, so an outer phi comparison detects
        # divergence and emits the outer merge phi.
        for my $vd_id (sort keys %loop_modified_vd_ids) {
            $val_map->{$vd_id} = $loop_node;
        }

        # After the loop, val_map entries for loop-modified variables hold the
        # loop_node sentinel; unchanged variables retain their pre-loop values.
    }

    # _resolve_vd_from_node: trace a loop Phi's init-value node back to its VarDecl.
    sub _resolve_vd_from_node($node) {
        return undef unless defined $node;
        return $node if $node->can('operation') && $node->operation eq 'VarDecl';
        if ($node->can('operation') && $node->operation eq 'PadAccess') {
            return $node->inputs->[0];
        }
        return undef;
    }

    # _collect_branch_chain($proj_node) -> ordered list of body nodes for a branch.
    # Walks consumers of the Proj that have control_in == proj, recursively.
    sub _collect_branch_chain($proj_node) {
        return () unless defined $proj_node;
        my @chain;
        my %seen;
        _collect_chain_recursive($proj_node, \@chain, \%seen);
        return @chain;
    }

    sub _collect_chain_recursive($node, $chain, $seen) {
        return unless defined $node;
        return if $seen->{$node->id}++;

        my $op = $node->can('operation') ? $node->operation : '';
        # Stop at Region (merge point) — handled by the enclosing If/Loop.
        return if $op eq 'Region';

        # Statement nodes (is_statement_node: VarDecl + the shared
        # statement-effect table) and nested control (If/Loop).
        if ($op eq 'If' || $op eq 'Loop'
            || Chalk::IR::NodeFactory::is_statement_node($op)) {
            push @$chain, $node;
            return if $op eq 'If' || $op eq 'Loop';  # their branches expanded separately
        }

        # Recurse into consumers with control_in == this node.
        my $consumers = $node->consumers // [];
        for my $c (@$consumers) {
            next unless defined $c && $c->can('control_in');
            my $ci = $c->control_in;
            next unless defined $ci && $ci->id eq $node->id;
            _collect_chain_recursive($c, $chain, $seen);
        }
    }

    # _find_proj($node, $idx): find the Proj consumer with the given index.
    sub _find_proj($node, $idx) {
        my $consumers = $node->consumers // [];
        for my $c (@$consumers) {
            next unless defined $c && $c->can('operation');
            next unless $c->operation eq 'Proj';
            return $c if $c->index == $idx;
        }
        return undef;
    }

    # _resolve_vd($node): resolve a PadAccess or VarDecl to the VarDecl node.
    sub _resolve_vd($node) {
        return undef unless defined $node;
        return $node if $node->can('operation') && $node->operation eq 'VarDecl';
        if ($node->can('operation') && $node->operation eq 'PadAccess') {
            return $node->inputs->[0];
        }
        return undef;
    }
}
