# ABOUTME: CFG skeleton + dominator tree for Chalk SoN IR control nodes.
# ABOUTME: Implements Cooper-Harvey-Kennedy iterative dominator algorithm (2001) over the CFG.
#
# Algorithm reference: Keith D. Cooper, Timothy J. Harvey, Ken Kennedy,
# "A Simple, Fast Dominance Algorithm", Rice University TR-06-33870, 2001.
# The iterative reverse-postorder algorithm: O(N^2) worst case but fast in
# practice on reducible CFGs (all Chalk control-flow graphs are reducible).
#
# CFG skeleton derived from the IR control nodes:
#   Start/entry  -> a single entry block (synthetic; holds straight-line prefix)
#   VarDecl/Assign/CompoundAssign nodes in the pre-if chain  -> entry block
#   If node      -> the block that performs the conditional branch; its successors
#                   are Proj0 (then) and Proj1 (else)
#   Proj(index)  -> defines its own block (body of one If/Loop branch)
#   Region       -> defines the merge/join block; its predecessors are Proj blocks
#   Loop         -> defines the loop-header block; its successors are Proj0 (body)
#                   and Proj1 (exit); its back-edge predecessor is the body block
#
# Dominator semantics: block A dominates block B iff every path from entry to B
# passes through A. By definition every block dominates itself.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::IR::Schedule::Dominators {
    # blocks: arrayref of { id => str, preds => [str, ...], succs => [str, ...],
    #                        ctrl_nodes => [IR node, ...] }
    # Ordered in reverse-postorder for the Cooper-Harvey-Kennedy algorithm.
    field $blocks :param :reader;

    # idoms: hashref of block_id -> immediate_dominator_block_id.
    # The entry block has idom('entry') = 'entry' (self-dom sentinel).
    field $idoms :param;

    # block_map: hashref of block_id -> block struct (derived from $blocks).
    field $block_map = {};

    ADJUST {
        $block_map = { map { $_->{id} => $_ } @$blocks };
    }

    # idom($block_id) -> immediate dominator block id (or undef for entry)
    method idom($bid) {
        return $idoms->{$bid};
    }

    # dominates($a_id, $b_id) -> true iff block A dominates block B.
    # Walks the idom chain from B upward; if we reach A, A dominates B.
    # Every block dominates itself.
    method dominates($a_id, $b_id) {
        # Walk up the idom chain from B toward entry.
        # If we encounter A, it dominates B.
        my $cur = $b_id;
        my $seen = {};
        while (defined $cur) {
            return true if $cur eq $a_id;
            # Safety: stop at entry (which idoms to itself)
            last if $cur eq 'entry' && $cur ne $b_id;
            my $next = $idoms->{$cur};
            last unless defined $next;
            last if $seen->{$next}++;   # cycle guard
            $cur = $next;
        }
        # Check if we stopped AT entry and $a_id is entry
        return true if defined $cur && $cur eq $a_id;
        return false;
    }

    # block_for($ctrl_node_id) -> block struct that contains this control node,
    # or undef if not found.
    method block_for($node_id) {
        for my $b (@$blocks) {
            for my $n ($b->{ctrl_nodes}->@*) {
                return $b if $n->id eq $node_id;
            }
        }
        return undef;
    }

    # blocks() -> arrayref of all blocks (already a :reader field; re-expose
    # as method for clarity in tests)

    # ---------------------------------------------------------------------------
    # Class method: build a Dominators object from the Return node of a graph.
    # Walks the control_in chain from Return backward to discover the CFG skeleton,
    # then runs the Cooper-Harvey-Kennedy iterative algorithm.
    # ---------------------------------------------------------------------------
    sub from_return_node($class, $ret_node) {
        # --- Phase 1: Build the CFG skeleton ---
        # Walk the control_in / region / proj chain to discover all blocks and edges.
        my @blocks;
        my %block_map;   # id -> block
        my %node_to_block; # IR-node-id -> block id (which block "owns" this node)

        # _make_block: allocate a fresh block struct.
        my $block_seq = 0;
        my $make_block = sub($id, @ctrl_nodes) {
            my $b = { id => $id, preds => [], succs => [], ctrl_nodes => [@ctrl_nodes] };
            push @blocks, $b;
            $block_map{$id} = $b;
            $node_to_block{$_->id} = $id for @ctrl_nodes;
            return $b;
        };

        # _link: add a directed CFG edge A -> B (A is pred of B).
        my $link = sub($from_id, $to_id) {
            push $block_map{$from_id}{succs}->@*, $to_id
                unless grep { $_ eq $to_id } $block_map{$from_id}{succs}->@*;
            push $block_map{$to_id}{preds}->@*, $from_id
                unless grep { $_ eq $from_id } $block_map{$to_id}{preds}->@*;
        };

        # The entry block is always block 0. Its ctrl_nodes are collected below.
        my $entry_block = $make_block->('entry');

        # Walk the control_in chain from the Return node backward.
        # We collect a stack of the control chain in forward order.
        # Control-flow nodes (If, Loop, Region) mark where the entry block ends
        # and new sub-blocks begin.
        {
            my @chain;
            my $cur = $ret_node;
            while (defined $cur) {
                push @chain, $cur;
                my $op = $cur->can('operation') ? $cur->operation : '';
                # Stop at node types that break the linear chain
                last if $op eq 'Region' || $op eq 'Start';
                # For If and Loop, control_in gives the predecessor in the chain
                # (handled recursively below via the chain walk)
                my $pred = $cur->can('control_in') ? $cur->control_in : undef;
                last unless defined $pred;
                $cur = $pred;
            }
            @chain = reverse @chain;  # now in forward order

            # Walk the chain; assign each node to the current "active" block.
            # When we encounter an If or Loop, it closes the current block and
            # branches into sub-blocks (Proj nodes and their consumers).
            my $current_block = $entry_block;
            my @pending_ifs;   # (if_node, then_block, else_block) tuples to process

            for my $node (@chain) {
                my $op = $node->can('operation') ? $node->operation : '';

                if ($op eq 'If') {
                    # This If node lives in the current block (it IS the branch).
                    push $current_block->{ctrl_nodes}->@*, $node;
                    $node_to_block{$node->id} = $current_block->{id};

                    # Discover the two Proj successors.
                    my $proj0 = _find_proj($node, 0);
                    my $proj1 = _find_proj($node, 1);

                    # Build then/else blocks (one per Proj).
                    my $then_id  = 'if.then.' . $node->id;
                    my $else_id  = 'if.else.' . $node->id;
                    my $then_blk = $make_block->($then_id, $proj0 ? ($proj0) : ());
                    my $else_blk = $make_block->($else_id, $proj1 ? ($proj1) : ());

                    $link->($current_block->{id}, $then_id);
                    $link->($current_block->{id}, $else_id);

                    # Recursively collect branch body nodes for each Proj.
                    _collect_branch_into($proj0, $then_blk, $make_block, $link, \%block_map, \%node_to_block)
                        if defined $proj0;
                    _collect_branch_into($proj1, $else_blk, $make_block, $link, \%block_map, \%node_to_block)
                        if defined $proj1;

                    # The Region merge point — build or find it.
                    my $region = $node->region;
                    if (defined $region) {
                        my $merge_id  = 'if.merge.' . $region->id;
                        unless (exists $block_map{$merge_id}) {
                            my $merge_blk = $make_block->($merge_id, $region);
                            $node_to_block{$region->id} = $merge_id;
                            # The merge block's predecessors are the tail blocks of
                            # each branch. For simplicity in the skeleton, wire
                            # then/else block labels as preds of merge.
                            $link->($then_id, $merge_id);
                            $link->($else_id, $merge_id);
                        }
                        $current_block = $block_map{$merge_id};
                    }
                }
                elsif ($op eq 'Loop') {
                    # The Loop node itself is the header block.
                    my $header_id  = 'loop.header.' . $node->id;
                    my $header_blk = $make_block->($header_id, $node);
                    $node_to_block{$node->id} = $header_id;

                    # Edge from current block (preheader) into the loop header.
                    $link->($current_block->{id}, $header_id);

                    # Body Proj (index 0) -> body block; exit Proj (index 1) -> exit block.
                    my $body_proj = _find_proj($node, 0);
                    my $exit_proj = _find_proj($node, 1);

                    my $body_id  = 'loop.body.' . $node->id;
                    my $exit_id  = 'loop.exit.' . $node->id;
                    my $body_blk = $make_block->($body_id, $body_proj ? ($body_proj) : ());
                    my $exit_blk = $make_block->($exit_id, $exit_proj ? ($exit_proj) : ());

                    $link->($header_id, $body_id);
                    $link->($header_id, $exit_id);

                    # Body iterates back to header (back-edge).
                    $link->($body_id, $header_id);

                    # Collect body nodes (side-effects under body_proj).
                    _collect_branch_into($body_proj, $body_blk, $make_block, $link, \%block_map, \%node_to_block)
                        if defined $body_proj;

                    # Exit Region (if present).
                    my $exit_region = $node->region;
                    if (defined $exit_region) {
                        my $exit_merge_id = 'loop.exit_merge.' . $exit_region->id;
                        unless (exists $block_map{$exit_merge_id}) {
                            my $exit_merge_blk = $make_block->($exit_merge_id, $exit_region);
                            $node_to_block{$exit_region->id} = $exit_merge_id;
                            $link->($exit_id, $exit_merge_id);
                        }
                        $current_block = $block_map{$exit_merge_id};
                    }
                    else {
                        $current_block = $exit_blk;
                    }
                }
                elsif ($op eq 'Region') {
                    # A Region node we encounter inline (e.g. the chain passes
                    # through a Region if it appears as control_in of Return).
                    # It has already been handled above by the If/Loop processing,
                    # so just look it up and continue.
                    my $mid = 'if.merge.' . $node->id;
                    $mid = 'loop.exit_merge.' . $node->id unless exists $block_map{$mid};
                    if (exists $block_map{$mid}) {
                        $current_block = $block_map{$mid};
                    }
                    # else: plain region we haven't indexed yet — assign to current
                    else {
                        push $current_block->{ctrl_nodes}->@*, $node;
                        $node_to_block{$node->id} = $current_block->{id};
                    }
                }
                elsif ($op eq 'Return') {
                    # Return lives in the current block.
                    push $current_block->{ctrl_nodes}->@*, $node;
                    $node_to_block{$node->id} = $current_block->{id};
                }
                else {
                    # VarDecl, Assign, CompoundAssign, Phi, Start, etc.
                    push $current_block->{ctrl_nodes}->@*, $node;
                    $node_to_block{$node->id} = $current_block->{id};
                }
            }
        }

        # --- Phase 2: Reverse-postorder numbering ---
        # Cooper-Harvey-Kennedy requires blocks in reverse-postorder (RPO).
        # Compute via a DFS from entry, numbering in postorder, then reverse.
        my %rpo;   # block_id -> RPO index (0 = entry)
        {
            my $post_num = 0;
            my %visited;
            my @po;
            my $dfs;
            $dfs = sub($bid) {
                return if $visited{$bid}++;
                my $b = $block_map{$bid};
                return unless defined $b;
                for my $s ($b->{succs}->@*) {
                    # Avoid following back-edges in DFS order; they form cycles.
                    # Simple heuristic: only follow successors not yet visited.
                    $dfs->($s) unless $visited{$s};
                }
                push @po, $bid;
            };
            $dfs->('entry');
            # Any unreachable blocks get appended at the end.
            for my $b (@blocks) {
                $dfs->($b->{id}) unless $visited{$b->{id}};
            }
            my @rpo_order = reverse @po;
            for my $i (0 .. $#rpo_order) {
                $rpo{$rpo_order[$i]} = $i;
            }
        }

        # Sort blocks in RPO order for the algorithm.
        my @rpo_blocks = sort { $rpo{$a->{id}} <=> $rpo{$b->{id}} } @blocks;

        # --- Phase 3: Cooper-Harvey-Kennedy iterative dominator computation ---
        # idoms{b} = immediate dominator of b.
        # Entry's idom is itself (sentinel).
        my %idoms;
        $idoms{'entry'} = 'entry';

        # intersect(b1, b2): find the common dominator of b1 and b2 by
        # walking up the idom chain from each until they meet.
        my $intersect = sub($b1, $b2) {
            my $f1 = $b1;
            my $f2 = $b2;
            while ($f1 ne $f2) {
                while ($rpo{$f1} > $rpo{$f2}) {
                    $f1 = $idoms{$f1};
                    return undef unless defined $f1;
                }
                while ($rpo{$f2} > $rpo{$f1}) {
                    $f2 = $idoms{$f2};
                    return undef unless defined $f2;
                }
            }
            return $f1;
        };

        my $changed = true;
        while ($changed) {
            $changed = false;
            for my $b (@rpo_blocks) {
                next if $b->{id} eq 'entry';
                my @preds = grep { exists $idoms{$_} } $b->{preds}->@*;
                next unless @preds;

                my $new_idom = $preds[0];
                for my $p (@preds[1..$#preds]) {
                    my $merged = $intersect->($new_idom, $p);
                    $new_idom = $merged if defined $merged;
                }

                unless (defined $idoms{$b->{id}} && $idoms{$b->{id}} eq $new_idom) {
                    $idoms{$b->{id}} = $new_idom;
                    $changed = true;
                }
            }
        }

        return $class->new(blocks => \@rpo_blocks, idoms => \%idoms);
    }

    # block_for is now available as an instance method above.

    # ---------------------------------------------------------------------------
    # Private helpers (plain subs — not methods; called by from_return_node)
    # ---------------------------------------------------------------------------

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

    # _collect_branch_into($proj, $block, $make_block, $link, $block_map_ref, $n2b_ref):
    # Walk consumers of $proj (side-effect nodes) and assign them to $block.
    # If a nested If or Loop is found, recursively build sub-blocks for it.
    sub _collect_branch_into($proj, $block, $make_block, $link, $block_map_ref, $n2b_ref) {
        return unless defined $proj;
        my %seen;
        _collect_ctrl_recursive($proj, $block, $make_block, $link, $block_map_ref, $n2b_ref, \%seen);
    }

    sub _collect_ctrl_recursive($node, $current_block, $make_block, $link, $block_map_ref, $n2b_ref, $seen) {
        return unless defined $node;
        return if $seen->{$node->id}++;

        my $op = $node->can('operation') ? $node->operation : '';

        if ($op eq 'If') {
            # Nested If: lives in current_block; build sub-blocks.
            push $current_block->{ctrl_nodes}->@*, $node;
            $n2b_ref->{$node->id} = $current_block->{id};

            my $proj0 = _find_proj($node, 0);
            my $proj1 = _find_proj($node, 1);
            my $then_id  = 'if.then.' . $node->id;
            my $else_id  = 'if.else.' . $node->id;
            unless (exists $block_map_ref->{$then_id}) {
                $make_block->($then_id, $proj0 ? ($proj0) : ());
                $make_block->($else_id, $proj1 ? ($proj1) : ());
                $link->($current_block->{id}, $then_id);
                $link->($current_block->{id}, $else_id);
            }
            $n2b_ref->{$proj0->id} = $then_id if defined $proj0;
            $n2b_ref->{$proj1->id} = $else_id if defined $proj1;

            _collect_branch_into($proj0, $block_map_ref->{$then_id}, $make_block, $link, $block_map_ref, $n2b_ref)
                if defined $proj0;
            _collect_branch_into($proj1, $block_map_ref->{$else_id}, $make_block, $link, $block_map_ref, $n2b_ref)
                if defined $proj1;

            my $region = $node->region;
            if (defined $region) {
                my $merge_id = 'if.merge.' . $region->id;
                unless (exists $block_map_ref->{$merge_id}) {
                    $make_block->($merge_id, $region);
                    $n2b_ref->{$region->id} = $merge_id;
                    $link->($then_id, $merge_id);
                    $link->($else_id, $merge_id);
                }
            }
            return;
        }
        elsif ($op eq 'Loop') {
            # Nested Loop: same structure as above.
            push $current_block->{ctrl_nodes}->@*, $node;
            $n2b_ref->{$node->id} = $current_block->{id};

            my $header_id = 'loop.header.' . $node->id;
            unless (exists $block_map_ref->{$header_id}) {
                my $header_blk = $make_block->($header_id, $node);
                $link->($current_block->{id}, $header_id);

                my $body_proj = _find_proj($node, 0);
                my $exit_proj = _find_proj($node, 1);
                my $body_id   = 'loop.body.' . $node->id;
                my $exit_id   = 'loop.exit.' . $node->id;
                $make_block->($body_id, $body_proj ? ($body_proj) : ());
                $make_block->($exit_id, $exit_proj ? ($exit_proj) : ());
                $link->($header_id, $body_id);
                $link->($header_id, $exit_id);
                $link->($body_id, $header_id);
                _collect_branch_into($body_proj, $block_map_ref->{$body_id}, $make_block, $link, $block_map_ref, $n2b_ref)
                    if defined $body_proj;

                my $exit_region = $node->region;
                if (defined $exit_region) {
                    my $exit_merge_id = 'loop.exit_merge.' . $exit_region->id;
                    unless (exists $block_map_ref->{$exit_merge_id}) {
                        $make_block->($exit_merge_id, $exit_region);
                        $n2b_ref->{$exit_region->id} = $exit_merge_id;
                        $link->($exit_id, $exit_merge_id);
                    }
                }
            }
            return;
        }
        elsif ($op eq 'Proj') {
            # Proj nodes are entry points to branch blocks; their id was already
            # added to ctrl_nodes when the block was created via $make_block. Just
            # ensure the node_to_block mapping is current, then recurse into
            # consumers that use this Proj as control_in — they are the body nodes
            # (including nested If/Loop) that live in this block.
            $n2b_ref->{$node->id} = $current_block->{id}
                unless exists $n2b_ref->{$node->id};

            my $consumers = $node->consumers // [];
            for my $c (@$consumers) {
                next unless defined $c && $c->can('control_in');
                my $ci = $c->control_in;
                next unless defined $ci && $ci->id eq $node->id;
                _collect_ctrl_recursive($c, $current_block, $make_block, $link, $block_map_ref, $n2b_ref, $seen);
            }
            return;
        }
        elsif ($op eq 'Region') {
            # Region nodes are join points; already handled structurally by their
            # If/Loop parent. Just register the id mapping.
            unless (exists $n2b_ref->{$node->id}) {
                push $current_block->{ctrl_nodes}->@*, $node;
                $n2b_ref->{$node->id} = $current_block->{id};
            }
            return;
        }
        else {
            # VarDecl, Assign, CompoundAssign, Phi, and other effectful nodes:
            # assign to the current block.
            push $current_block->{ctrl_nodes}->@*, $node;
            $n2b_ref->{$node->id} = $current_block->{id};
        }

        # Recurse into consumers that have this node as a control predecessor.
        my $consumers = $node->consumers // [];
        for my $c (@$consumers) {
            next unless defined $c && $c->can('control_in');
            my $ci = $c->control_in;
            next unless defined $ci && $ci->id eq $node->id;
            _collect_ctrl_recursive($c, $current_block, $make_block, $link, $block_map_ref, $n2b_ref, $seen);
        }
    }
}
