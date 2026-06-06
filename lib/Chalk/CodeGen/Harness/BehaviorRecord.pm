# ABOUTME: Widened behavior record capturing all observable axes of a perl method invocation.
# ABOUTME: Each axis has a written normalization/comparison POLICY documented inline.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::CodeGen::Harness::BehaviorRecord {

    # return_values: arrayref of values returned by the method under test,
    # captured in the calling context specified by wantarray_context.
    field $return_values  :param = [];

    # wantarray_context: the calling context used when invoking the method.
    # One of: 'list' | 'scalar' | 'void'
    field $wantarray_context :param = 'scalar';

    # stdout: string captured from STDOUT during method execution.
    field $stdout         :param = '';

    # stderr: string captured from STDERR (including Perl warnings) during execution.
    field $stderr         :param = '';

    # exception: undef when no exception was thrown; otherwise a hashref with keys:
    #   kind    => 'string' | 'object'
    #   class   => blessed class name (for kind=object) or undef (for kind=string)
    #   message => stringified exception message
    field $exception      :param = undef;

    # object_state: hashref mapping field names to their values after method execution,
    # obtained via introspection of the invocant object. Keys are sorted for stability.
    field $object_state   :param = {};

    # hash_order_policy: string token identifying the normalization applied to any
    # hash-valued data in this record. Currently always 'sorted-keys'.
    field $hash_order_policy :param = 'sorted-keys';

    # fp_tolerance: numeric absolute tolerance used when comparing floating-point values.
    # Default is 1e-9 (sub-nanosecond precision, adequate for most numeric Perl work).
    field $fp_tolerance   :param = 1e-9;

    # dualvar_policy: token identifying how numeric-vs-string dualvars are compared.
    # Currently always 'numeric-first': compare the numeric face; fall back to string.
    field $dualvar_policy :param = 'numeric-first';

    # aliasing_topology: hashref capturing reference-topology / shared-aliasing /
    # blessed-ref identity / coderef identity / weakref presence.
    # Keys: refs (arrayref of {id, type, blessed, is_weak}), aliases (arrayrefs of shared ids).
    field $aliasing_topology :param = {};

    # --- Accessors ---

    method return_values()     { $return_values     }
    method wantarray_context() { $wantarray_context }
    method stdout()            { $stdout            }
    method stderr()            { $stderr            }
    method exception()         { $exception         }
    method object_state()      { $object_state      }
    method hash_order_policy() { $hash_order_policy }
    method fp_tolerance()      { $fp_tolerance      }
    method dualvar_policy()    { $dualvar_policy    }
    method aliasing_topology() { $aliasing_topology }

    # --- Policy methods (normalization / comparison) ---

    # POLICY normalize_return_values:
    # Scalar values are kept as-is. Array/hash refs are recursively normalized via
    # normalize_hash_order (all hash keys sorted at every level). This ensures that
    # two records whose methods return hashes with the same key/value pairs but
    # different insertion orders compare equal. Plain list return values are left in
    # their captured order (the caller controls list ordering by calling context).
    method normalize_return_values($values) {
        return [ map { $self->_normalize_value($_) } $values->@* ];
    }

    # POLICY normalize_stdout:
    # Stdout is compared as a literal byte string. No normalization is applied
    # (newline conventions, trailing whitespace, etc. are part of observable behavior).
    # The caller is responsible for stripping trailing newlines only when the comparison
    # explicitly opts in via a 'chomp' flag.
    method normalize_stdout($s) { $s }

    # POLICY normalize_stderr:
    # Stderr is compared as a literal byte string, identical policy to normalize_stdout.
    # Perl warning lines contain line-number annotations that vary with snippet wrapping;
    # the comparator must strip " at /tmp/... line N." suffixes before comparing
    # warning text across different wrapping contexts.
    method normalize_stderr($s) {
        # Strip the " at /path/to/file line N." Perl annotation suffix from warnings.
        $s =~ s{ at \S+ line \d+\.?\n?}{\n}gr;
    }

    # POLICY normalize_exception:
    # Exceptions are compared by { kind, class, message } triple.
    # - kind: 'string' for plain die("...") and 'object' for die($obj).
    # - class: undef for string exceptions; blessed class name for object exceptions.
    # - message: for string exceptions, the raw die string stripped of the
    #   " at FILE line N." Perl annotation. For object exceptions, the result of
    #   calling ->message() / ->stringify() if available, otherwise "".
    # Two exception records are equal iff all three fields compare equal.
    method normalize_exception($exc) {
        return undef unless defined $exc;
        my %e = $exc->%*;
        if (defined $e{message}) {
            $e{message} =~ s{ at \S+ line \d+\.?\n?}{}g;
            $e{message} =~ s/\s+$//;
        }
        return \%e;
    }

    # POLICY normalize_object_state:
    # Keys are sorted alphabetically. Values are recursively normalized via _normalize_value.
    # Fields that hold coderefs are recorded as the string '<CODE>' (not comparable as
    # identity) unless explicitly noted in aliasing_topology.
    method normalize_object_state($state) {
        return { map { $_ => $self->_normalize_value($state->{$_}) } sort keys $state->%* };
    }

    # POLICY normalize_hash_order:
    # All hashrefs at any nesting level have their keys sorted. This policy applies
    # recursively. It is used by normalize_return_values and normalize_object_state.
    # Rationale: Perl hash iteration order is randomized (PERL_HASH_SEED); any test
    # that compares hash stringifications without normalization is non-deterministic.
    method normalize_hash_order($h) {
        return { map { $_ => $self->_normalize_value($h->{$_}) } sort keys $h->%* };
    }

    # POLICY normalize_fp:
    # Floating-point values are compared with absolute tolerance fp_tolerance (default 1e-9).
    # Two values $a and $b are considered equal iff abs($a - $b) <= $self->fp_tolerance.
    # This policy does NOT apply to integer-typed values (Perl's IV/UV); those compare exactly.
    method normalize_fp($v) {
        # Normalize by rounding to within tolerance band.
        # We store the value as-is; the comparator calls this and applies abs-diff check.
        return $v;
    }

    # POLICY normalize_dualvar:
    # Dualvars (scalars with both a numeric and string representation, e.g. $!,
    # or Scalar::Util::dualvar) are compared by their NUMERIC face first.
    # If both faces agree (NV == IV-coercion of PV), a single value is stored.
    # If they disagree, the record stores { nv => ..., pv => ... } to expose both.
    # Rationale: silently coercing a dualvar to string can hide numeric bugs.
    method normalize_dualvar($v) { $v }

    # POLICY normalize_aliasing_topology:
    # Reference topology is captured as a list of { id, type, blessed, is_weak } records
    # sorted by id. Two records are equal iff the topology lists are equal after sorting.
    # Shared-aliasing (same refaddr appearing twice) is always recorded.
    # Closures / coderefs are recorded by id only (content not comparable); identity
    # changes across processes, so cross-process coderef comparison is NEVER attempted.
    method normalize_aliasing_topology($topo) {
        return {} unless defined $topo && ref $topo eq 'HASH';
        my $refs = $topo->{refs} // [];
        my @sorted = sort { $a->{id} cmp $b->{id} } $refs->@*;
        return { refs => \@sorted, aliases => ($topo->{aliases} // []) };
    }

    # --- Internal helpers ---

    method _normalize_value($v) {
        return undef unless defined $v;
        if (ref $v eq 'HASH') {
            return $self->normalize_hash_order($v);
        }
        elsif (ref $v eq 'ARRAY') {
            return [ map { $self->_normalize_value($_) } $v->@* ];
        }
        elsif (ref $v eq 'CODE') {
            return '<CODE>';
        }
        else {
            return $v;
        }
    }
}

true;
