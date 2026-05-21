# ABOUTME: N-ary FilterComposite semiring running multiple semirings together as staged filters.
# ABOUTME: Values are shared Context objects; each annotation-layer semiring writes to a named slot.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::FilterComposite {
    field $semirings :param :reader;  # arrayref of semirings

    # Tie instrumentation: records unresolved ties when CHALK_COUNT_FILTER_TIES is set.
    # Each entry is a hashref: { semiring => $sr, slot => $slot_name }.
    # Enabled only when the env var is non-empty; zero production impact otherwise.
    field $_tie_log = [];

    # Audit instrumentation: records per-merge verdict comparison when CHALK_AUDIT_FILTER is set.
    # Each entry is a hashref with verdict_first_wins, verdict_product, and per_component.
    # No Context refs are stored — only slot names and verdict strings (avoids memory bloat).
    field $_audit_log = [];

    # Cached one() return value. Computed lazily on first call. Safe to cache
    # because component semirings' one() values are stable across calls and
    # Context objects are immutable. Cleared by reset_cache() if state changes.
    field $_one_cache;

    # Cached annotation-semiring list. Recomputed only when reset_cache() fires.
    # Avoids repeated grep+blessed+can on every one()/multiply call.
    field $_annotation_semirings_cache;

    # Cached SA semiring reference + the SA's set_type_context method
    # availability flag. Both are stable across the parser's lifetime —
    # multiply() reads them on every call, so caching them avoids one
    # method dispatch per multiply.
    field $_sa_cache;
    field $_sa_has_set_type_context;

    # SA is always the last semiring by convention.
    # All semirings before SA are annotation-layer semirings that write to
    # named slots in the Context's annotations hash.
    method _sa() {
        return $_sa_cache //= $semirings->[-1];
    }
    method _annotation_semirings() {
        # All semirings except the last (SA) that have a defined slot_name.
        # Non-object semirings (legacy test stubs without slot_name) are skipped.
        # Cached: $semirings doesn't change after construction.
        $_annotation_semirings_cache //= [
            grep {
                blessed($_) && $_->can('slot_name') && defined $_->slot_name()
            } $semirings->@[0 .. $#{ $semirings } - 1]
        ];
        return $_annotation_semirings_cache->@*;
    }

    # tie_log() returns the current tie log (arrayref of tie entries).
    # Each entry: { semiring => $sr, slot => $slot_name }.
    # Only populated when CHALK_COUNT_FILTER_TIES env var is set.
    method tie_log() { return $_tie_log }

    # flush_tie_log() resets the tie log to empty.
    # Call before each parse to attribute ties to the correct file.
    method flush_tie_log() { $_tie_log = [] }

    # audit_log() returns the current audit log (arrayref of merge records).
    # Each entry: { verdict_first_wins, verdict_product, per_component }.
    # Only populated when CHALK_AUDIT_FILTER env var is set.
    method audit_log() { return $_audit_log }

    # flush_audit_log() empties the audit log.
    # Call before each parse to attribute records to the correct file.
    method flush_audit_log() { $_audit_log = [] }

    # Clear hash-cons caches in all component semirings that support it.
    # Called between file parses to prevent unbounded memory growth.
    method reset_cache() {
        for my $sr ($semirings->@*) {
            $sr->reset_cache() if $sr->can('reset_cache');
        }
        # Component semirings' one() values may now point at freed Contexts;
        # invalidate the cached composite one() so the next call rebuilds it.
        $_one_cache = undef;
    }

    # zero() returns a Context with is_zero=true.
    # Any method that receives this value will short-circuit.
    method zero() {
        return Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            is_zero  => true,
        );
    }

    # one() returns a fresh Context with annotation slots initialized from
    # each component semiring's one() value.
    # SA's one() already carries the cfg annotation; we build a new Context
    # copying it plus all annotation-layer slots.
    method one() {
        return $_one_cache //= do {
            my $sa_one = $self->_sa()->one();
            # SA must return a Context; non-Context last semirings get a plain wrapper.
            my $is_ctx = blessed($sa_one) && $sa_one->can('annotations');
            my $annotations = $is_ctx ? { $sa_one->annotations()->%* } : {};
            for my $sr ($self->_annotation_semirings()) {
                my $slot = $sr->slot_name();
                # TI (#707): annotations->{type} holds a tag hash, not a TI Context.
                # Extract the focus from TI's one() to get the { valid => true } hash.
                if ($slot eq 'type') {
                    my $ti_one = $sr->one();
                    $annotations->{$slot} = (blessed($ti_one) && $ti_one->can('extract'))
                        ? $ti_one->extract()
                        : $ti_one;
                } else {
                    $annotations->{$slot} = $sr->one();
                }
            }
            my $focus = $is_ctx ? $sa_one->extract() : $sa_one;
            Chalk::Bootstrap::Context->new(
                focus    => $focus,
                children => [],
                position => 0,
                is_zero  => false,
                annotations => $annotations,
                mop      => ($is_ctx ? $sa_one->mop() : undef),
                scope    => ($is_ctx ? $sa_one->scope() : undef),
                graph    => ($is_ctx ? $sa_one->graph() : undef),
                factory  => ($is_ctx ? $sa_one->factory() : undef),
            );
        };
    }

    # is_zero() checks the Context's is_zero flag directly.
    # Handles non-Context values from legacy semiring configurations.
    method is_zero($ctx) {
        return true if !defined $ctx;
        return $ctx->is_zero() if blessed($ctx) && $ctx->can('is_zero');
        return false;
    }

    # _wrap_sa_result: Build a new Context from SA's result merged with slot annotations.
    # Does NOT mutate $sa_result — it may be hash-consed or shared.
    # Handles non-Context SA results (e.g., when last semiring is Structural).
    # Propagates SA's scope and graph fields to the outer Context so that
    # cfg_state() can read control/scope information from the parse result.
    method _wrap_sa_result($sa_result, %slot_results) {
        my $is_ctx = blessed($sa_result) && $sa_result->can('extract');
        return Chalk::Bootstrap::Context->new(
            focus       => $is_ctx ? $sa_result->extract() : $sa_result,
            children    => $is_ctx ? [$sa_result->children()->@*] : [],
            position    => $is_ctx ? $sa_result->position() : 0,
            rule        => $is_ctx ? $sa_result->rule() : undef,
            is_zero     => false,
            scope       => ($is_ctx ? $sa_result->scope() : undef),
            graph       => ($is_ctx ? $sa_result->graph() : undef),
            factory     => ($is_ctx ? $sa_result->factory() : undef),
            annotations => {
                ($is_ctx ? $sa_result->annotations()->%* : ()),
                %slot_results,
            },
        );
    }

    # _is_packed: returns true when a Context is a packed-ambiguous carrier.
    # Packed Contexts are created by add() when all components abstain; they
    # carry multiple alternative Contexts in their children list.
    my sub _is_packed($ctx) {
        return blessed($ctx) && $ctx->can('is_ambiguous') && $ctx->is_ambiguous();
    }

    # _pack_survivors: given a list of non-zero Contexts, return:
    #   zero Context  — if the list is empty
    #   the single ctx — if exactly one survivor
    #   packed Context — if more than one survivor
    method _pack_survivors(@survivors) {
        return $self->zero()  if @survivors == 0;
        return $survivors[0]  if @survivors == 1;
        return Chalk::Bootstrap::Context->new(
            focus        => undef,
            children     => \@survivors,
            position     => 0,
            is_zero      => false,
            is_ambiguous => true,
            annotations  => {},
        );
    }

    # _same_value: identity comparison suitable for both refs and scalars.
    my sub _same_value($a, $b) {
        return true  if !defined($a) && !defined($b);
        return false if !defined($a) || !defined($b);
        if (ref($a) && ref($b)) {
            return refaddr($a) == refaddr($b);
        }
        if (!ref($a) && !ref($b)) {
            return $a == $b;
        }
        return false;
    }

    # multiply() computes the product of two Context values.
    # Short-circuits to zero if either input is_zero or any annotation-layer
    # semiring's multiply returns zero. SA builds the tree structure.
    #
    # Each annotation semiring receives the full Context objects ($left, $right)
    # and is responsible for extracting its own slot value from
    # $left->annotations()->{slot} and $right->annotations()->{slot}.
    # When $right carries annotations->{scan} = true, semirings interpret
    # it as a scan event and apply their scan-time logic (e.g., Precedence
    # validates operators; TypeInference attaches type tags; Structural
    # performs a transparent passthrough).
    # When $right carries annotations->{complete} = true, semirings apply
    # their rule-completion logic inline in multiply.
    #
    # Packed-ambiguous Contexts (is_ambiguous=true) distribute over multiply:
    #   multiply(packed(A,B), C)    → pack(multiply(A,C), multiply(B,C))
    #   multiply(A, packed(C,D))    → pack(multiply(A,C), multiply(A,D))
    #   multiply(packed(A,B), packed(C,D)) → pack of all 4 sub-products
    # Each sub-product goes through the normal multiply path so component
    # semirings always see unpacked operands.
    method multiply($left, $right) {
        return $self->zero() if $left->is_zero();
        return $self->zero() if $right->is_zero();

        # Distribute multiply over packed Contexts.
        if (_is_packed($left) || _is_packed($right)) {
            my @lefts  = _is_packed($left)  ? $left->children()->@*  : ($left);
            my @rights = _is_packed($right) ? $right->children()->@* : ($right);
            my @survivors;
            for my $l (@lefts) {
                for my $r (@rights) {
                    my $sub = $self->multiply($l, $r);
                    push @survivors, $sub unless $sub->is_zero();
                }
            }
            return $self->_pack_survivors(@survivors);
        }

        my $is_complete = blessed($right) && $right->can('annotations')
            && $right->annotations()->{complete};

        # Run each annotation-layer semiring and collect results.
        # Pass full Context objects so each semiring can read event metadata
        # (annotations->{scan}, annotations->{complete}, etc.) and its own
        # slot value from the shared Context's annotations hash.
        my %slot_results;
        my $ti_result_tag_hash;
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            my $result = $sr->multiply($left, $right);
            return $self->zero() if $sr->is_zero($result);
            $slot_results{$slot} = $result;
            # Capture TI's tag hash result so we can thread it to SA below.
            # TI.multiply returns a tag hash directly for complete events
            # (and for scan events). For regular multiply it returns a Context.
            if ($slot eq 'type' && $is_complete) {
                $ti_result_tag_hash = $result;
            }
        }

        # Thread TI result to SA before SA runs so action methods can read type info.
        # SA actions fire during SA.multiply for complete events.
        my $sa = $self->_sa();
        $_sa_has_set_type_context //= ($sa->can('set_type_context') ? 1 : 0);
        if ($is_complete && defined $ti_result_tag_hash
                && $_sa_has_set_type_context) {
            my $ti_ctx_wrapper = Chalk::Bootstrap::Context->new(
                focus    => $ti_result_tag_hash,
                children => [],
                position => 0,
                rule     => undef,
            );
            $sa->set_type_context($ti_ctx_wrapper);
        }

        # SA builds the tree structure (the shared Context) for regular multiply,
        # or applies semantic action (via _complete_sa) for complete events.
        my $sa_result = $sa->multiply($left, $right);
        return $self->zero() if $sa->is_zero($sa_result);

        return $self->_wrap_sa_result($sa_result, %slot_results);
    }

    # _filter_compare: determine which of left or right is the preferred derivation.
    #
    # Uses product semantics: ALL annotation-layer semirings are consulted in
    # priority order. Each semiring's add() verdict is collected. When components
    # disagree (one says left, another says right), the FIRST opinionated
    # component in priority order wins — this preserves the documented ordering
    # of _annotation_semirings() as a true priority ordering, not just short-circuit
    # optimization.
    #
    # Per-component add() results are normalized to arrayrefs:
    #   [] (empty)        → skip (zero-product; component has no viable parse)
    #   [$x] (single)     → classify: left if $x eq $li, right if $x eq $ri, abstain otherwise
    #   [$x,$y,...] (>1)  → abstain (component explicitly has no preference)
    #
    # The 'type' slot is skipped (TI contract: TI updates type annotations in multiply,
    # not in add; calling add() on type slots is undefined behavior).
    # Identity-equal slot values are skipped (both alternatives identical for this slot).
    #
    # Verdict string names ('left_loses', 'right_loses') are kept as-is for
    # compatibility with XS codegen in EmitHelpers.pm, which pattern-matches
    # them in generated C code.
    #
    # Returns: 'right_loses' | 'left_loses' | 'neither'
    method _filter_compare($left, $right) {
        # _slot_verdict: classify one semiring's add() result against ($li, $ri).
        # Returns: 'identity_skip' | 'left' | 'right' | 'abstain' | 'zero'
        my $slot_verdict = sub($sr, $li, $ri) {
            my $slot = $sr->slot_name();
            return 'identity_skip' if _same_value($li, $ri);
            return 'identity_skip' if $slot eq 'type';
            # Boolean is a recognizer (yes/no). Any two non-zero values are
            # equivalent at the recognizer level — they only differ in refaddr
            # because Boolean.add returns a fresh Context to signal abstention
            # (per Phase 2 of survivor-list plan). Without this skip, every
            # chart-merge of two non-zero parses creates an unresolved tie
            # even when all OTHER slots are identical.
            if ($slot eq 'boolean'
                && defined $li && defined $ri
                && !$sr->is_zero($li) && !$sr->is_zero($ri)) {
                return 'identity_skip';
            }

            my $result = $sr->add($li, $ri);
            $result = [$result] unless ref($result) eq 'ARRAY';

            return 'zero' if $result->@* == 0;
            return 'abstain' if $result->@* > 1;

            my $r = $result->[0];
            my $r_eq_left  = ref($r) && ref($li)  ? refaddr($r) == refaddr($li)
                           : !ref($r) && !ref($li) ? $r == $li
                           :                         false;
            my $r_eq_right = ref($r) && ref($ri)  ? refaddr($r) == refaddr($ri)
                           : !ref($r) && !ref($ri) ? $r == $ri
                           :                         false;

            return 'abstain' if $r_eq_left && $r_eq_right;
            return 'abstain' if !$r_eq_left && !$r_eq_right;
            return $r_eq_left ? 'left' : 'right';
        };

        # Collect per-component verdicts from all annotation semirings.
        my @per_component;
        my $first_opinion;   # first 'left' or 'right' seen in priority order

        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            my $li   = $left->annotations()->{$slot};
            my $ri   = $right->annotations()->{$slot};

            my $v = $slot_verdict->($sr, $li, $ri);
            push @per_component, { slot => $slot, verdict => $v };

            if (!defined $first_opinion && ($v eq 'left' || $v eq 'right')) {
                $first_opinion = $v;
            }
        }

        # Translate first opinion to verdict string.
        my $verdict = 'neither';
        if (defined $first_opinion) {
            $verdict = $first_opinion eq 'left' ? 'right_loses' : 'left_loses';
        }

        # Distinguish "all identity_skip" (the two derivations are semantically
        # identical for every slot — not a tie, just a redundant merge) from
        # "all abstain" (the two ARE different but no component has an opinion
        # — a real unresolved tie that needs investigation).
        my $all_identity = !grep { $_->{verdict} ne 'identity_skip' } @per_component;

        if ($verdict eq 'neither' && !$all_identity && $ENV{CHALK_COUNT_FILTER_TIES}) {
            my $entry = {
                semiring => 'all',
                slot     => 'unresolved',
            };
            if ($ENV{CHALK_TIE_CONTEXT}) {
                # Capture (rule, position, scanned-text-fragment) for tie investigation.
                # Helps categorize ties by source pattern.
                $entry->{left_rule}  = $left->can('rule')  ? $left->rule()  : undef;
                $entry->{right_rule} = $right->can('rule') ? $right->rule() : undef;
                $entry->{left_pos}   = $left->can('position')  ? $left->position()  : undef;
                $entry->{right_pos}  = $right->can('position') ? $right->position() : undef;
                my $lt = eval { $left->scanned_text() // '' };
                my $rt = eval { $right->scanned_text() // '' };
                $entry->{left_text}  = (length($lt) > 40) ? substr($lt, 0, 37) . '...' : $lt;
                $entry->{right_text} = (length($rt) > 40) ? substr($rt, 0, 37) . '...' : $rt;
                $entry->{per_component} = [map { { slot => $_->{slot}, verdict => $_->{verdict} } } @per_component];
            }
            push $_tie_log->@*, $entry;
        }

        # Audit log: record actual verdict + per-component analysis.
        if ($ENV{CHALK_AUDIT_FILTER}) {
            my @opinions = map { $_->{verdict} }
                           grep { $_->{verdict} eq 'left' || $_->{verdict} eq 'right' }
                           @per_component;
            my %seen = map { $_ => 1 } @opinions;

            my $verdict_product;
            if ($seen{left} && $seen{right}) {
                $verdict_product = 'conflict';
            } elsif ($seen{left}) {
                $verdict_product = 'left_wins';
            } elsif ($seen{right}) {
                $verdict_product = 'right_wins';
            } else {
                $verdict_product = 'all_abstain';
            }

            push $_audit_log->@*, {
                verdict_actual  => $verdict,
                verdict_product => $verdict_product,
                per_component   => \@per_component,
            };
        }

        return $verdict;
    }

    # _has_real_annotation_difference: returns true when at least one annotation
    # slot has a semantically meaningful distinct value between $left and $right.
    # When all semantically-comparable slots are identity-equal, the two Contexts
    # are indistinguishable and packing is not warranted.
    #
    # Slots excluded from the check:
    #   'type'    — TI updates types in multiply, not add; add never compares type slots.
    #   'boolean' — Boolean.add always creates a new Context object for two non-zero
    #               inputs (so refaddrs always differ even when semantically identical).
    #               The meaningful boolean distinction (zero vs non-zero) is handled by
    #               the is_zero guard before _add_unpacked is called.
    method _has_real_annotation_difference($left, $right) {
        for my $sr ($self->_annotation_semirings()) {
            my $slot = $sr->slot_name();
            next if $slot eq 'type';
            next if $slot eq 'boolean';
            my $li = $left->annotations()->{$slot};
            my $ri = $right->annotations()->{$slot};
            return true unless _same_value($li, $ri);
        }
        return false;
    }

    # _add_unpacked: core add logic for two non-packed Contexts.
    # Returns a single Context (left, right, or packed-ambiguous).
    # Called by add() after packed distribution is handled.
    method _add_unpacked($left, $right) {
        # Ask the filter semirings which derivation is the correct parse.
        my $verdict = $self->_filter_compare($left, $right);

        my ($correct, $rejected);
        if ($verdict eq 'right_loses') {
            ($correct, $rejected) = ($left, $right);
        } elsif ($verdict eq 'left_loses') {
            ($correct, $rejected) = ($right, $left);
        } else {
            # 'neither': no component expressed a preference.
            #
            # Only pack as ambiguous when the alternatives actually differ in at
            # least one annotation slot — that is when genuine component-level
            # abstention is occurring. When all slots are identity-equal the two
            # Contexts are indistinguishable and returning $left preserves the
            # existing deterministic tie-break without inflating the chart.
            if ($self->_has_real_annotation_difference($left, $right)) {
                # Genuine abstention: both alternatives survive as a packed Context.
                # Downstream multiply will distribute over the packed set; Phase 5
                # will raise a structured error if ambiguity reaches Program rule
                # completion. See docs/plans/2026-05-17-survivor-list-architecture.md.
                if ($self->_sa()->can('on_merge')) {
                    $self->_sa()->on_merge($left, $right);
                }
                return Chalk::Bootstrap::Context->new(
                    focus        => undef,
                    children     => [$left, $right],
                    position     => 0,
                    is_zero      => false,
                    is_ambiguous => true,
                    annotations  => {},
                );
            }
            # All slots identical: deterministic tie-break picks left.
            ($correct, $rejected) = ($left, $right);
        }

        # Post-merge hook: allow SA to transfer side-table state between the
        # two survivors when filter-gap merge admits both derivations and
        # composition picks one. The picked side may lack cfg_state info that
        # the other survivor carries; on_merge transfers it. See
        # _fix_postfix_chain in Perl/Actions.pm for the canonical
        # filter-gap-merge explanation.
        if ($self->_sa()->can('on_merge')) {
            $self->_sa()->on_merge($correct, $rejected);
        }

        return $correct;
    }

    # add() merges two alternative Contexts, returning the survivor.
    #
    # When all annotation-layer semirings abstain (no component expresses a
    # preference), both alternatives survive as a packed-ambiguous Context.
    # Downstream multiply distributes over the packed set; Phase 5 will raise
    # a structured error if ambiguity reaches Program rule completion.
    #
    # Packed Contexts on either side are distributed:
    #   add(packed(A,B), C)    → merge each of A,B against C; collect unique survivors
    #   add(A, packed(C,D))    → merge A against each of C,D; collect unique survivors
    #   add(packed(A,B), packed(C,D)) → all pairwise merges; collect unique survivors
    method add($left, $right) {
        # Zero handling: is_zero flag on Context
        return $right if $left->is_zero();
        return $left  if $right->is_zero();

        # Distribute add over packed Contexts.
        if (_is_packed($left) || _is_packed($right)) {
            my @lefts  = _is_packed($left)  ? $left->children()->@*  : ($left);
            my @rights = _is_packed($right) ? $right->children()->@* : ($right);

            # Collect unique survivors: merge each left alt against each right alt.
            # Dedup by refaddr to avoid storing the same derivation twice.
            my %seen;
            my @survivors;
            for my $l (@lefts) {
                for my $r (@rights) {
                    my $sub = $self->_add_unpacked($l, $r);
                    if ($sub->is_ambiguous()) {
                        # _add_unpacked returned a packed — absorb its children
                        for my $child ($sub->children()->@*) {
                            my $addr = refaddr($child);
                            unless ($seen{$addr}++) {
                                push @survivors, $child;
                            }
                        }
                    } elsif (!$sub->is_zero()) {
                        my $addr = refaddr($sub);
                        unless ($seen{$addr}++) {
                            push @survivors, $sub;
                        }
                    }
                }
            }
            return $self->_pack_survivors(@survivors);
        }

        return $self->_add_unpacked($left, $right);
    }

}
