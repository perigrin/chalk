# ABOUTME: Behavioral comparator for the CodeGen harness — classifies S-vs-P divergence.
# ABOUTME: Emits PASS | GAP | MISCOMPILE per the gap-vs-miscompile discrimination rule (C7).
use 5.42.0;
use utf8;
no warnings 'experimental::class';
use feature 'class';

class Chalk::CodeGen::Harness::Comparator {

    # ------------------------------------------------------------------
    # verdict($S, $P, \%emission_meta) -> { verdict => ..., ... }
    #
    # THE LOAD-BEARING DISCRIMINATION RULE (architecture C7 / round-2 HIGH):
    #
    #   GAP      — CodeGen could not emit / emitted obviously-incomplete code /
    #              marked-unsupported.  emitted_for_every_construct is false
    #              OR marked_unsupported is true.  This is backlog, not a
    #              correctness alarm.
    #
    #   MISCOMPILE — CodeGen emitted COMPLETE-looking code (emitted_for_every_construct
    #              true AND marked_unsupported false) that diverged on any observed
    #              axis.  This is a CORRECTNESS ALARM, never backlog.  The directional
    #              framing must NOT be allowed to launder a miscompile as a gap.
    #
    #   PASS     — All axes match under their normalization policies AND emission
    #              was complete AND at least one axis carries observable behavior
    #              (guards against empty-record collusion).
    #
    # $S, $P      — BehaviorRecord objects (duck-typed; must respond to all
    #               canonical axis accessors):
    #               return_values, wantarray_context, stdout, stderr, exception,
    #               object_state, hash_order_policy, fp_tolerance, dualvar_policy,
    #               aliasing_topology.
    # $emission_meta — hashref: { emitted_for_every_construct => bool,
    #                             marked_unsupported => bool,
    #                             graph_source => str (optional) }
    # ------------------------------------------------------------------
    sub verdict ($class_or_self, $S, $P, $emission_meta) {
        my $graph_source = $emission_meta->{graph_source} // 'unknown';

        # ---- GAP check: emission_meta decides before any axis comparison ----
        # A GAP is signalled when CodeGen could not or did not fully emit.
        # Checked FIRST so an incomplete emission can never be laundered as PASS.
        if ( $emission_meta->{marked_unsupported} || !$emission_meta->{emitted_for_every_construct} ) {
            return {
                verdict          => 'GAP',
                graph_source     => $graph_source,
                implicated_layer => 'codegen',
            };
        }

        # ---- Empty-record collusion guard ------------------------------------
        # If neither record carries any observable behavior, we cannot claim PASS.
        # An empty oracle and an empty generated record agree vacuously; that is
        # not evidence of correct behaviour — it is a silent false-green risk.
        if ( _is_degenerate($S) && _is_degenerate($P) ) {
            return {
                verdict          => 'MISCOMPILE',
                graph_source     => $graph_source,
                implicated_layer => 'oracle',
                diverged_axes    => ['empty_record_collusion'],
            };
        }

        # ---- Per-axis comparison under normalization policies ----------------
        my @diverged;

        # Axis: wantarray_context (exact match required)
        if ( ( $S->wantarray_context // '' ) ne ( $P->wantarray_context // '' ) ) {
            push @diverged, 'wantarray_context';
        }

        # Axis: stdout (exact string match)
        if ( ( $S->stdout // '' ) ne ( $P->stdout // '' ) ) {
            push @diverged, 'stdout';
        }

        # Axis: stderr (normalized string match; source-location footers from
        # warn/die are stripped because oracle and generated code run from
        # different temp files, making the " at FILE line N." suffix always
        # differ even when the message content is identical).
        if ( _normalize_stderr( $S->stderr // '' ) ne _normalize_stderr( $P->stderr // '' ) ) {
            push @diverged, 'stderr';
        }

        # Axis: exception (structural comparison — kind + class + message)
        if ( !_exceptions_equal( $S->exception, $P->exception ) ) {
            push @diverged, 'exception';
        }

        # Axis: return_values (list comparison under FP tolerance + dualvar policy)
        #   fp_tolerance and dualvar_policy are read from $S (the oracle record).
        if ( !_return_values_equal( $S->return_values, $P->return_values,
                                    $S->fp_tolerance,  $S->dualvar_policy ) )
        {
            push @diverged, 'return_values';
        }

        # Axis: object_state (hash comparison under hash_order_policy from $S)
        if ( !_object_states_equal( $S->object_state, $P->object_state,
                                    $S->hash_order_policy ) )
        {
            push @diverged, 'object_state';
        }

        # ---- Verdict --------------------------------------------------------
        if (@diverged) {
            # Emission was complete-looking but diverged on one or more axes.
            # This is a MISCOMPILE — a correctness alarm, never backlog.
            return {
                verdict          => 'MISCOMPILE',
                graph_source     => $graph_source,
                implicated_layer => 'codegen',
                diverged_axes    => \@diverged,
            };
        }

        return {
            verdict      => 'PASS',
            graph_source => $graph_source,
        };
    }

    # ------------------------------------------------------------------
    # Private helpers — defined as plain subs inside the class block so
    # they are visible to verdict() without fully-qualified names.
    # ------------------------------------------------------------------

    # _is_degenerate($record) — true when a BehaviorRecord carries no observable
    # behavior on any axis.  Used by the empty-record collusion guard.
    sub _is_degenerate ($record) {
        return false unless defined $record;

        my $rv  = $record->return_values  // [];
        my $so  = $record->stdout         // '';
        my $se  = $record->stderr         // '';
        my $exc = $record->exception;
        my $os  = $record->object_state   // {};

        return ( scalar(@$rv) == 0 && $so eq '' && $se eq '' && !defined($exc) && !%$os );
    }

    # _exceptions_equal($a, $b) — structural comparison of exception hashrefs.
    # Both undef => equal.  One undef, one defined => not equal.
    # Both defined => compare kind + class + message.
    sub _exceptions_equal ($a, $b) {
        return true  if !defined($a) && !defined($b);
        return false if !defined($a) || !defined($b);
        return false if ( $a->{kind}    // '' ) ne ( $b->{kind}    // '' );
        return false if ( $a->{class}   // '' ) ne ( $b->{class}   // '' );
        return false if ( $a->{message} // '' ) ne ( $b->{message} // '' );
        return true;
    }

    # _return_values_equal($a, $b, $fp_tolerance, $dualvar_policy) — compare
    # two arrayrefs element-by-element applying FP tolerance and dualvar policy.
    #
    # dualvar_policy:
    #   'string'  — compare the string face (Perl's "stringification") exactly.
    #               No FP tolerance is applied: "3.0" ne "3" => not equal.
    #               This is the right policy for string-typed outputs where
    #               string identity matters.
    #   'numeric' — coerce both to numbers and compare with abs(a-b) <= fp_tolerance.
    #               This is the right policy for computed floating-point outputs.
    #   (other)   — exact string (eq) comparison, no FP tolerance.
    sub _return_values_equal ($a, $b, $fp_tolerance, $dualvar_policy) {
        $a //= [];
        $b //= [];
        return false if scalar(@$a) != scalar(@$b);

        for my $i ( 0 .. $#$a ) {
            my $va = $a->[$i];
            my $vb = $b->[$i];

            # Both undef => equal element; skip.
            if ( !defined($va) && !defined($vb) ) { next }
            # One undef => not equal.
            if ( !defined($va) || !defined($vb) ) { return false }

            if ( ( $dualvar_policy // 'string' ) eq 'numeric' ) {
                # Numeric comparison with FP tolerance.
                my $na = $va + 0;
                my $nb = $vb + 0;
                return false if abs($na - $nb) > ( $fp_tolerance // 1e-9 );
            }
            elsif ( ( $dualvar_policy // 'string' ) eq 'string' ) {
                # Exact string-face comparison; no FP blurring.
                return false if "$va" ne "$vb";
            }
            else {
                # Default: exact eq comparison.
                return false if "$va" ne "$vb";
            }
        }
        return true;
    }

    # _normalize_stderr($stderr_text) — strip Perl source-location footers from
    # warn/die output so oracle and generated stderr can be compared by message
    # content only.  Lines ending in " at FILE line N." or " at FILE line N.\n"
    # (where FILE is an absolute path to a temp file) are normalized by removing
    # the " at ..." suffix.  This preserves message content while ignoring the
    # ephemeral filename/line that differs between oracle and generated runs.
    sub _normalize_stderr ($text) {
        $text =~ s{ at \S+ line \d+\.?\n?}{\n}g;
        return $text;
    }

    # _object_states_equal($a, $b, $policy) — compare two object_state hashrefs.
    # hash_order_policy 'sorted' (default): sort keys before comparing.
    # Unknown policies also fall through to sorted comparison.
    sub _object_states_equal ($a, $b, $policy) {
        $a //= {};
        $b //= {};
        my @ka = sort keys %$a;
        my @kb = sort keys %$b;
        return false if scalar(@ka) != scalar(@kb);
        for my $i ( 0 .. $#ka ) {
            return false if $ka[$i] ne $kb[$i];
            return false if ( $a->{ $ka[$i] } // '' ) ne ( $b->{ $kb[$i] } // '' );
        }
        return true;
    }

}

1;
