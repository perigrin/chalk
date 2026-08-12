# ABOUTME: LLVM lowering context variant that places phis from the Elaborate pass output (dominator-tree driven).
# ABOUTME: Subclass of Chalk::Target::LLVM::Context; overrides Region-merge handling to consume precomputed phi records.
# ---------------------------------------------------------------------------
# ElaboratedContext: a Context subclass that uses the Elaborate pass output
# for phi placement at Region merges. Placement is driven by the dominator tree
# and scoped value map computed by Chalk::IR::Schedule::Elaborate.
# ---------------------------------------------------------------------------
package Chalk::Target::LLVM::ElaboratedContext;
use 5.42.0;
use utf8;

use parent -norequire, 'Chalk::Target::LLVM::Context';

sub new {
    my ($class, %args) = @_;
    my $elab           = delete $args{elab};
    my $class_registry = delete $args{class_registry};
    my $self  = $class->SUPER::new(%args);
    $self->{elab} = $elab;
    # Class registry: maps class_name -> { methods => [...], fields => [...], parent => str }
    # Built by _build_registry_from_mop() from the sealed MOP (019eb42a).
    $self->{class_registry} = $class_registry // {};
    # Index emitted_phis by Region id -> list of phi records.
    # The Elaborate pass emits phis with block_id = the merge block id.
    # We need to look them up by the Region node's block id at emit time.
    $self->{elab_phi_by_block} = {};
    if (defined $elab) {
        for my $phi_rec ($elab->emitted_phis->@*) {
            push $self->{elab_phi_by_block}{ $phi_rec->{block_id} }->@*, $phi_rec;
        }
    }
    return $self;
}

# _process_if_node: elaboration-driven version.
# Reads phi records from the Elaborate pass for this Region's merge block.
sub _process_if_node {
    my ($self, $if_node) = @_;

    my $cond_input = $if_node->inputs->[1];
    die "LLVM backend (elaboration): If node has no condition (inputs[1] is undef)"
        unless defined $cond_input;

    my $cond_ref = $self->lower_value($cond_input);

    my $cond_repr = $cond_input->representation // 'Bool';
    if ($cond_repr eq 'Int') {
        my $bool_ref = $self->_fresh;
        $self->_emit("  $bool_ref = icmp ne i64 $cond_ref, 0  ; If (elab): coerce Int to i1");
        $cond_ref = $bool_ref;
    }

    my $then_label  = $self->_fresh_label('if.then.');
    my $else_label  = $self->_fresh_label('if.else.');
    my $merge_label = $self->_fresh_label('if.merge.');

    # Memory-SSA 2b: a branch-guarded element store and the post-merge read share
    # the store's container and index (hash-consed). Lazy lowering would emit them
    # inside the guarded THEN block, so the post-merge read's use would not be
    # dominated. Pre-lower each guarded element store's container + index HERE, in
    # the pre-branch block (which dominates both the store and the merge), so the
    # shared refs are cached and dominance-correct.
    $self->_prelower_branch_store_operands($if_node);

    $self->_set_terminator("  br i1 $cond_ref, label %$then_label, label %$else_label  ; If (elab): branch");

    my $region = $if_node->region;

    # Snapshot var_table before any branch so each branch starts from the same
    # pre-branch state. This is required for correctness with nested control:
    # the then-branch may contain a nested If that updates var_table with an
    # inner-merge phi ref; the else-branch must see the pre-branch state, not the
    # post-then state. After both branches run, phi arms are taken from branch
    # snapshots (not from raw assignment nodes in the elab record), so a nested
    # If's merge phi ref is correctly propagated as the outer phi arm value.
    my %pre_var = %{ $self->{var_table} };

    # Process then-branch. var_table is mutated in place; snapshot after.
    $self->_new_block($then_label);
    $self->_process_branch_from_if($if_node, 0, $merge_label);
    my $then_end_label = $self->_current_block_label;
    my %then_var = %{ $self->{var_table} };

    # Restore to pre-branch state before processing else-branch.
    %{ $self->{var_table} } = %pre_var;

    # Process else-branch. var_table starts from pre-branch state.
    $self->_new_block($else_label);
    $self->_process_branch_from_if($if_node, 1, $merge_label);
    my $else_end_label = $self->_current_block_label;
    my %else_var = %{ $self->{var_table} };

    # Restore to pre-branch state before emitting merge phis. The merge block
    # will update var_table with phi results.
    %{ $self->{var_table} } = %pre_var;

    # Merge block.
    $self->_new_block($merge_label);

    # Emit phis from the elaboration plan for this merge block.
    # The Elaborate pass determines which variables diverge between branches and
    # records the merge block id (keyed as 'if.merge.<region_id>'). We look up
    # the exact key by region id (M1 fix: exact match, not substring regex, to
    # prevent Region#5 matching Region#59).
    if (defined $region) {
        # Wire explicit Phi nodes on the Region FIRST: lowering their arm
        # values may extend the then/else tails with continuation blocks
        # (multi-block values), which changes the labels that actually
        # branch into the merge. The elab phis below must name those
        # updated labels, so take them from the wiring's return value.
        # Arm values are lowered with each branch's var_table snapshot so
        # variable reads are branch-correct.
        ($then_end_label, $else_end_label) = $self->_wire_region_phis_with_preblock(
            $region, $then_end_label, $else_end_label, \%then_var, \%else_var);

        my $phi_key = 'if.merge.' . $region->id;
        my $phi_recs = $self->{elab_phi_by_block}{$phi_key} // [];

        for my $phi_rec (@$phi_recs) {
            my $vd_id = $phi_rec->{vd_id};

            # Use var_table snapshots from each branch — NOT lower_value(arm->{value}).
            # lower_value on a raw assignment node emits a fresh instruction that does
            # not reflect nested merge phis. The snapshot holds the SSA ref LIVE AT
            # THE END of each branch: for a nested-if branch, that is the inner merge
            # phi ref; for a simple-assign branch, it is the assign's SSA ref.
            my $then_ref = $then_var{$vd_id};
            my $else_ref = $else_var{$vd_id};

            # Fall back to '0' only for truly uninit variables.
            $then_ref //= '0';
            $else_ref //= '0';

            # Look up the VarDecl repr for this phi.
            my $var_repr  = $self->{_vd_repr}{$vd_id} // 'Int';
            my $llvm_type = Chalk::Target::LLVM::Context::_repr_to_llvm_type($var_repr);

            my $phi_ref  = $self->_fresh;
            my $phi_line = "  $phi_ref = phi $llvm_type "
                         . "[ $then_ref, %$then_end_label ], "
                         . "[ $else_ref, %$else_end_label ]"
                         . "  ; elab phi (vd=$vd_id)";
            $self->_emit($phi_line);
            $self->{var_table}{$vd_id} = $phi_ref;
        }

    }
}

# _wire_region_phis_with_preblock: emit explicit Phi nodes on a Region,
# ensuring each incoming value is lowered in its PREDECESSOR block (not the
# current/merge block). For each Phi consumer of the Region, we temporarily
# switch to the then/else tail block to emit the incoming-value instructions
# (if they are not already in cache), then switch back to the merge block to
# emit the phi instruction itself.
#
# This is required when a Phi's incoming value has not been pre-lowered during
# branch processing (e.g. a pure data node like Add that has no control_in
# and is not in the body chain). Emitting it from the merge block would place
# the instruction after the phi that references it — invalid in LLVM IR.
#
# A multi-block arm value (bounds-checked Subscript, And/Or, ternary)
# consumes the tail block's branch-to-merge and opens continuation blocks;
# _lower_arm_in_tail re-attaches the branch to the new tail and returns the
# label that actually enters the merge. Arms are lowered with that branch's
# var_table snapshot so variable reads see branch-final state, not merge
# state. Returns the updated (then_label, else_label) — the caller must use
# these for any further phi lines it emits into the same merge block.
sub _wire_region_phis_with_preblock {
    my ($self, $region, $then_label, $else_label, $then_vars, $else_vars) = @_;

    my $consumers = $region->consumers // [];
    my @all_phis = grep {
        defined $_ && ref($_)
            && $_->can('operation') && $_->operation eq 'Phi'
            && !exists $self->{cache}{ $_->id }
    } @$consumers;

    # A memory-Phi (inputs include MemStart or an element-store Assign) merges
    # MEMORY versions, not a value: its element-store arm mutates the heap under
    # the branch, and the post-merge read re-loads from the aggregate at its own
    # program point, so it needs no value phi line (lowering its arms as values
    # would hit MemStart/Assign, which are not values). Wire only the value phis.
    my (@mem_phis, @phis);
    for my $p (@all_phis) {
        if (Chalk::Target::LLVM::Context::_is_memory_phi($p)) { push @mem_phis, $p }
        else                                                  { push @phis,     $p }
    }

    # 2b-3 mixed effect: an arm that BOTH rebinds a scalar (a value-Phi) AND
    # stores an element (a memory-Phi) merges on the same Region. The value-Phi's
    # arm order for this shape is not yet reconciled with the element store, and
    # wiring it produces a wrong value (the scalar reads the wrong arm). This was
    # a loud GAP before memory-Phis were skipped; keep it loud rather than
    # silently miscompiling.
    if (@mem_phis && @phis) {
        die "GAP: a branch arm that both rebinds a scalar and stores an element "
          . "(2b-3 mixed effect) is not yet lowered — refusing to mislower.";
    }

    return ($then_label, $else_label) unless @phis;

    my $merge_idx = $self->_find_block_idx($self->_current_block_label);

    # Pass 1: lower ALL arms for ALL phis. Emitting phi lines one at a time
    # is wrong: a later phi's multi-block arm extends the same tail and
    # re-points the branch-to-merge, leaving any already-emitted phi naming
    # a block that no longer branches to the merge ("PHI node entries do
    # not match predecessors"). Every phi line must name the FINAL tail
    # labels, known only after all arms have lowered. (An earlier-lowered
    # arm value defined in the pre-extension tail still dominates the final
    # tail's branch, so the value/label pairing stays valid.)
    my @wired;
    for my $phi_node (@phis) {
        my $inputs = $phi_node->inputs;
        unless (defined $inputs && scalar @$inputs >= 2) {
            die "LLVM backend: Phi node (id=" . $phi_node->id . ") attached to Region "
              . "has fewer than 2 incoming values — missing predecessor edge";
        }
        for my $slot (0, 1) {
            next if defined $inputs->[$slot];
            # Bindings builds Phi([val, undef]) when a variable is bound in
            # one branch only. Die with a diagnostic (mirrors _lower_phi's
            # undef-arm guard) instead of crashing inside lower_value.
            die "GAP: Region Phi (id=" . $phi_node->id . ") incoming slot $slot "
              . "is undef (variable bound in one branch only) — cannot lower "
              . "a one-sided merge value runtime-free.";
        }
        # A merge yields one of its ARMS, so the arms can differ in machine
        # type: an early-return `return 99` (Int) merging with a fall-through
        # whose value is a print's Bool produces
        #   phi i64 [ %int, ... ], [ %i1, ... ]
        # which lli rejects outright. The arms are bridged to the Phi's own
        # repr — the operator rule (Part J) applied to a merge, the same fix
        # _lower_ternary and _lower_and/_lower_or use.
        #
        # The coercion must land in the ARM's block, where its value is live,
        # which is exactly where _lower_arm_in_tail leaves the emitter. Doing
        # it in pass 2 (next to the phi) would reference each arm from the
        # merge block, which is invalid IR rather than a wrong answer.
        my $phi_repr = $phi_node->representation;
        my ($then_val, $else_val);
        ($then_val, $then_label) =
            $self->_lower_arm_in_tail($inputs->[0], $then_label, $then_vars);
        $then_val = $self->_coerce_arm($inputs->[0], $then_val, $phi_repr,
                                       $then_label, 'Region.Phi.then');
        ($else_val, $else_label) =
            $self->_lower_arm_in_tail($inputs->[1], $else_label, $else_vars);
        $else_val = $self->_coerce_arm($inputs->[1], $else_val, $phi_repr,
                                       $else_label, 'Region.Phi.else');
        push @wired, [$phi_node, $then_val, $else_val];
    }

    # Pass 2: emit all phi lines into the merge block with the final labels.
    $self->{current_idx} = $merge_idx;
    for my $w (@wired) {
        my ($phi_node, $then_val, $else_val) = @$w;
        my $repr      = Chalk::Target::LLVM::Context::_require_repr($phi_node, 'ElaboratedContext.Region.Phi');
        my $llvm_type = Chalk::Target::LLVM::Context::_repr_to_llvm_type($repr);
        my $result    = $self->_fresh;
        $self->_emit("  $result = phi $llvm_type [ $then_val, %$then_label ], [ $else_val, %$else_label ]  ; Region phi");
        $self->{cache}{ $phi_node->id } = $result;
    }
    return ($then_label, $else_label);
}

# _coerce_arm($arm_node, $arm_val, $phi_repr, $arm_label, $what) -> $val
#
# Bridge one merge arm to the Phi's repr, emitting into the ARM's block. A
# no-op when the arm already conforms, when the Phi has no repr (that stays
# _require_repr's loud GAP in pass 2), or when the arm's own repr is unknown.
sub _coerce_arm {
    my ($self, $arm_node, $arm_val, $phi_repr, $arm_label, $what) = @_;

    return $arm_val unless defined $phi_repr && defined $arm_val;
    return $arm_val unless ref($arm_node) && $arm_node->can('representation');
    my $arm_repr = $arm_node->representation;
    return $arm_val unless defined $arm_repr && $arm_repr ne $phi_repr;

    my $idx = $self->_find_block_idx($arm_label);
    return $arm_val unless defined $idx;
    my $saved = $self->{current_idx};
    $self->{current_idx} = $idx;
    my $ref = Chalk::Target::LLVM::Context::_emit_coercion(
        $self, $arm_val, $arm_repr, $phi_repr, $what);
    $self->{current_idx} = $saved;
    return $ref;
}

# _lower_arm_in_tail($arm_node, $tail_label, $var_snapshot) -> ($val, $end_label)
# Lower a phi arm value inside the named predecessor tail block, with the
# branch's var_table snapshot swapped in (when provided) so variable reads
# are branch-correct. If the arm expands into continuation blocks, its
# control flow consumed the tail's terminator: re-attach the saved
# branch-to-merge to the new tail and report the new tail's label as the
# phi's incoming label.
sub _lower_arm_in_tail {
    my ($self, $arm_node, $tail_label, $var_snapshot) = @_;

    my $idx = $self->_find_block_idx($tail_label);
    $self->{current_idx} = $idx;
    my $saved_term = $self->{blocks}[$idx]{terminator};

    my %merge_vars;
    if (defined $var_snapshot) {
        %merge_vars = %{ $self->{var_table} };
        %{ $self->{var_table} } = %$var_snapshot;
    }
    my $val = $self->lower_value($arm_node);
    if (defined $var_snapshot) {
        %{ $self->{var_table} } = %merge_vars;
    }

    my $end_label = $self->_current_block_label;
    if ($end_label ne $tail_label) {
        $self->_set_terminator($saved_term);
    }
    return ($val, $end_label);
}
