# ABOUTME: Internal LLVM lowering context — accumulates basic blocks and SSA state during SoN->LLVM emission.
# ABOUTME: Provides lower_value dispatch and the per-node emitters that build LLVM IR text for one method/function body.
package Chalk::Target::LLVM::Context;
use 5.42.0;
use utf8;

# DIAGNOSTIC CONVENTION -- `GAP:` means ONE thing.
#
#   GAP:  perl does this and Chalk does not YET. A hole in coverage, destined
#         for the worklist, closed by building the feature. The worklists
#         (tbase-worklist.t, ring-worklist.t, son-corpus-wide.t) all match on
#         the literal `GAP:`, so this prefix is what puts a construct on the
#         list of things to work on.
#
#   Everything else dies WITHOUT the prefix:
#
#   - An INVARIANT VIOLATION -- a node reaching here with no representation, a
#     Str whose length was never tracked, a repr=Scalar that inference should
#     have narrowed. There is no future Chalk where these are correct: they are
#     bugs in an EARLIER pass, and if one fires it gets fixed, not filed.
#     Labelling them GAP put live bugs into the backlog reading as unbuilt
#     features, where nobody triaged them because they were already categorised
#     as future work.
#
#   - A GUARD -- a refusal whose alternative is a silent miscompile (a regex
#     flag that would otherwise be ignored, a capture index with no group).
#     These are asserted by their own tests; they are not work, and closing one
#     means implementing it CORRECTLY, not removing the check.
#
# Keep `GAP:` honest: if the message would not make sense as an entry on a
# list of features to implement, it is not a GAP.

use Chalk::IR::NodeFactory;   # is_statement_node() classifier used by the value/effect collectors
use Chalk::IR::Analysis;      # return_reading_for_want: which of a callee reading a callsite takes
use Chalk::IR::Value;   # for `isa Chalk::IR::Value`
use Chalk::IR::Node;   # stamp reads gate on isa Chalk::IR::Node

# Re-export helpers from the main package so unqualified calls in this
# package resolve correctly (both packages share the same implementation).
*_require_repr              = \&Chalk::Target::LLVM::_require_repr;
*_encode_c_string            = \&Chalk::Target::LLVM::_encode_c_string;
*_emit_str_to_num_helper      = \&Chalk::Target::LLVM::_emit_str_to_num_helper;

# _method_fn_type($result_repr) -> LLVM fn type string for method signatures.
# Duplicate of the module-level sub; both packages need it to avoid cross-package calls.
sub _method_fn_type {
    my ($result_repr, $param_reprs) = @_;
    # DERIVED, not a parallel table. A method's function-pointer type is its
    # return type applied to (i8*), so there is exactly one authority for both
    # and they cannot drift. They HAD drifted: this chain grew a `Scalar` arm
    # that _method_fn_llvm_ret_type never got, so a Scalar-returning method
    # could be pointed at but not called -- invisible because the ABI equality
    # check upstream rejected the Scalar/Int pair before either was reached.
    # THE ARGUMENT TYPES ARE PART OF THE FN-POINTER TYPE. A vtable slot is
    # bitcast to this before the call, so a signature that omits the arguments
    # makes the cast and the definition disagree -- exactly the drift the
    # comment above records for the return type, reached through the operand
    # list instead.
    my @args = ('i8*');
    push @args, map { Chalk::Target::LLVM::_method_fn_llvm_ret_type($_) }
                @{ $param_reprs // [] };
    return Chalk::Target::LLVM::_method_fn_llvm_ret_type($result_repr)
         . ' (' . join(', ', @args) . ')';
}

sub new {
    my ($class, %args) = @_;

    # Elaboration inputs, optional. A Context built without them lowers
    # straight-line code (the ADJUST-body context at LLVM.pm:880 and several
    # unit tests do exactly that); one built with them also lowers if/else,
    # placing phis from the Elaborate pass's records.
    #
    # These used to live on a Chalk::Target::LLVM::ElaboratedContext subclass
    # whose only job was if/else lowering, with the base class's
    # _process_if_node a `die "use ElaboratedContext"`. That was not a design:
    # commit 3a103d21 DELETED the base implementation ("Remove the old
    # Context::_process_if_node ... The base class method is replaced with a
    # guard") and the empty shell outlived the migration. zhi issue F10 records
    # the same reading -- "_process_if_node/_wire_region_phis are duplicated
    # between Context and ElaboratedContext (copy-paste-with-divergence)" --
    # and its stated prerequisite, the 019eb316 cache/identity family
    # (4e0d7ba8, 381229b5, 5c7e49ce, d4823444), is landed.
    #
    # NOTE the subclass's `new` accepted %args and passed them to
    # SUPER::new(%args), which took no arguments and silently discarded them.
    # Merging removes that trapdoor: the arguments now reach the only
    # constructor there is.
    my $elab           = delete $args{elab};
    my $class_registry = delete $args{class_registry};
    # Each block is: { label => 'name', insts => [...], terminator => str|undef }
    # The entry block is always first and is never terminated by this emitter
    # during straight-line code — the lower() epilogue adds the final ret.
    my $entry_block = { label => 'entry', insts => [], terminator => undef };
    return bless {
        blocks         => [$entry_block],   # ordered list of basic blocks
        current_idx    => 0,                # index into blocks of current block
        counter        => 0,
        block_counter  => 0,
        cache     => {},     # node id -> llvm_ref (%tmp_N)
        var_table => {},     # VarDecl node id -> current SSA value ref
                             # Used for SSA-value threading of lexical scalars:
                             # VarDecl stores its init SSA ref here; Assign updates
                             # it; PadAccess reads it. Models straight-line SSA
                             # without needing alloca/store/load for simple cases.
        # Str representation tracking (G3):
        #   _str_globals    => [ [$global_name, $content, $byte_len], ... ]
        #     String constant globals to emit in the module prologue.
        #   (_str_len_table is GONE: a Str VALUE is `%Str = { ptr, len, enc }`,
        #    so the length is a field of the value rather than a side channel
        #    keyed by pointer. Ask _str_parts for both halves.)
        #   _need_malloc_memcpy => bool
        #     Set when a Concat node is lowered; triggers malloc/memcpy declarations.
        _str_globals          => [],
        # Package scalars: one %Slot global per qualified name (_pkg_slot_name).
        #   _pkg_slots => { "main::g" => "\@pkg_main_g", ... }
        _pkg_slots            => {},
        _need_malloc_memcpy   => 0,
        _need_str_to_num_helper => 0,
        _need_argv              => 0,
        _need_slot_inc          => 0,
        _need_case_helper       => 0,
        _need_substr_helper     => 0,
        _need_lex_agg           => 0,
        _need_array_append      => 0,
        _need_tr                => 0,
        _need_time              => 0,
        _need_pow               => 0,
        _need_bless             => 0,
        _need_memchr            => 0,
        _need_select            => 0,
        _need_hash_delete       => 0,
        # G4 Array/Hash aggregate tracking:
        #   _need_aggregate_types => bool
        #     Set when any Array/Hash node is lowered; triggers type struct declarations.
        #   _need_memcmp => bool
        #     Set when Subscript(Hash) is lowered; triggers memcmp declaration.
        _need_aggregate_types => 0,
        _need_memcmp          => 0,
        # G5 MOP: class registry (class_name -> { methods, fields, ... }).
        # Passed to new() by the pre-scan in lower_with_elaboration. (Callers
        # spell the constructor ElaboratedContext->new, but that package defines
        # no new of its own -- it is an alias and inherits this one.)
        # Also set on method-body sub-contexts via direct hash assignment.
        class_registry => $class_registry // {},
        # G5 MOP: method body context flags
        _in_method_body      => 0,
        _method_self_name    => undef,
        _method_class_name   => undef,

        # Elaboration state. `elab` is the Chalk::IR::Schedule::Elaborate
        # result; elab_phi_by_block indexes its emitted_phis by merge-block id
        # so _process_if_node can look them up when it reaches that Region.
        elab              => $elab,
        elab_phi_by_block => _index_elab_phis($elab),
    }, $class;
}

# @NEED_FLAGS: the "does the prologue need to declare/emit X" flags that a
# body-lowering Context (a method body or ADJUST block, each lowered in its
# own fresh Context) can set independently of the main Context that renders
# the module prologue. The prologue is assembled before bodies are lowered,
# so a flag set only on a body Context is invisible to it unless copied up --
# a flag left behind produces .ll that references an undeclared global/helper
# (the F6 bug class).
my @NEED_FLAGS = qw(
    _need_malloc_memcpy
    _need_bool_str_globals
    _need_str_to_num_helper
    _need_argv
    _need_slot_inc
    _need_case_helper
    _need_substr_helper
    _need_lex_agg
    _need_num_fmt
    _need_snprintf
    _need_array_append
    _need_tr
    _need_time
    _need_pow
    _need_bless
    _need_memchr
    _need_select
    _need_hash_delete
    _need_memcmp
    _need_aggregate_types
    _need_getenv
    _need_print_str_fmt
    _need_print_int_fmt
    _need_exit
    _need_str_type
);

# absorb_need_flags_from($src_ctx) -> copy ALL NEED_FLAGS set on $src_ctx up
# onto $self. Called on the main/parent context with a body/adjust context as
# the source, after that body has been lowered.
sub absorb_need_flags_from {
    my ($self, $src_ctx) = @_;
    for my $flag (@NEED_FLAGS) {
        $self->{$flag} = 1 if $src_ctx->{$flag};
    }
    # A body that touches a shared lexical names its global; the module
    # declares it once.
    $self->{_lex_globals}{$_} = $src_ctx->{_lex_globals}{$_}
        for keys %{ $src_ctx->{_lex_globals} // {} };
    $self->{_pkg_slots}{$_} = $src_ctx->{_pkg_slots}{$_}
        for keys %{ $src_ctx->{_pkg_slots} // {} };
    $self->{_lex_agg_globals}{$_} = $src_ctx->{_lex_agg_globals}{$_}
        for keys %{ $src_ctx->{_lex_agg_globals} // {} };
    return $self;
}

# inherit_need_flags_from($parent_ctx) -> copy NEED_FLAGS DOWN from a parent
# context onto $self. Used when constructing a fresh body/adjust Context that
# must start with whatever the parent already knows it needs (e.g.
# _need_str_type, set by an earlier :param binding on the main graph) so a
# post-class re-emit isn't needed for state the parent already had.
sub inherit_need_flags_from {
    my ($self, $parent_ctx) = @_;
    for my $flag (@NEED_FLAGS) {
        $self->{$flag} = 1 if $parent_ctx->{$flag};
    }
    return $self;
}

# configure_as_method_body(class_name => $cname, method_name => $mname,
#                           class_registry => $registry, parent_ctx => $ctx,
#                           has_self => bool (default true)) -> $self
#
# Set up a freshly-constructed Context as the lowering target for one class
# member's body: a method (has_self => 1, the default) or a plain class
# `sub` (has_self => 0 -- there is no $self to resolve a FieldAccess
# against; a sub touching a field is a compile error in perl, so a
# FieldAccess reaching here would be a producer bug and should fail loudly
# rather than silently bind to a nonexistent invocant). An ADJUST block is a
# method body in this sense too (has_self => 1, method_name => '__ADJUST').
#
# Replaces the hand-rolled field-by-field setup that used to live at each of
# the three call sites in Target/LLVM.pm (method body, sub body, ADJUST),
# which is also where the boxed-Str need-flag was copied down by hand;
# that copy is now inherit_need_flags_from, covering all NEED_FLAGS (every
# NEED_FLAGS site in this file only ever SETS a flag during lowering, never
# reads one to change what gets emitted, so seeding the full set from the
# parent up front cannot change body output -- only what the eventual
# prologue renders, which absorb_need_flags_from already covers regardless
# of when the seed happened).
sub configure_as_method_body {
    my ($self, %args) = @_;
    my $has_self = $args{has_self} // 1;
    if ($has_self) {
        $self->{_in_method_body}   = 1;
        $self->{_method_self_name} = '%self';
    }
    # TWO DIFFERENT FACTS, and they were one flag until real sub defines
    # needed them apart. `_in_method_body` means "there is an invocant",
    # which is what a FieldAccess and a `$self` PadAccess need.
    # `_in_function_body` means "this is an emitted function whose parameters
    # arrive as LLVM arguments", which is what a Parameter needs -- and that is
    # true of a `sub twice($n)` define, which has arguments and no invocant.
    #
    # Conflating them made a sub's Parameter refuse ("op=Parameter outside a
    # method body") the moment sub defines were emitted, even though the
    # argument was right there in the signature.
    $self->{_in_function_body} = 1;
    $self->{_method_class_name} = $args{class_name};
    $self->{_method_name}       = $args{method_name};
    # varname -> positional index, for a parameter READ AS A PAD SLOT rather
    # than through a Parameter node (`method outer($k) { $self->inner($k) }`).
    # Empty for a method with no declared signature, which is why the lookup
    # site tests `defined` on the result rather than on the map.
    $self->{_method_param_index} = $args{param_index} // {};
    $self->{class_registry}     = $args{class_registry} if defined $args{class_registry};
    $self->inherit_need_flags_from($args{parent_ctx}) if defined $args{parent_ctx};
    return $self;
}

# Index a phi record list by the merge block it belongs to. Returns an empty
# index when there is no elaboration result, which is what a straight-line
# context gets.
sub _index_elab_phis {
    my ($elab) = @_;
    my %by_block;
    return \%by_block unless defined $elab;
    for my $phi_rec ($elab->emitted_phis->@*) {
        push $by_block{ $phi_rec->{block_id} }->@*, $phi_rec;
    }
    return \%by_block;
}

# ---------------------------------------------------------------------------
# %Str SHOULD NOT STILL EXIST (perigrin, 2026-08-29). It was to be fully
# replaced by %Str, and was not — an INCOMPLETE MIGRATION, 47 uses live at this
# writing. The consolidation this comment goes on to describe (four literal
# definitions reduced to one) is a different job from the replacement, and
# doing the first can read as having done the second.
#
# Measured split: %Str is the SSA VALUE type; %Str survives on the PAYLOAD
# paths — Str-returning methods, ArrayRead and HashRead, where a Str is stored
# as an i64 payload and `inttoptr`'d back. Both carry { ptr, len }; only %Str
# carries `enc`.
#
# So %Str IS a %Str with the encoding field dropped — a REPRESENTATION
# CHOICE that got frozen into a second type. Under the T2 framing recorded at
# _repr_to_llvm_type, dropping `enc` where no use observes the encoding is a
# legitimate thing for T2 to CHOOSE per site; what is wrong is that the choice
# is currently made by which code path you are on. Retiring %Str is
# therefore not just cleanup: it is removing a T2 decision that was hardcoded
# before T2 existed.
#
# The %Str layout: ONE definition, everything else derived from it.
#
# This was written as a literal `%Str = type { i8*, i64 }` at LLVM.pm:640
# and again at :1313, with its byte size hardcoded a THIRD time as
# `malloc(i64 16)` at two sites here — four places that had to agree, with
# nothing enforcing it.
#
# That is a live trap for the `{ptr, len, enc}` widening this file already
# specifies at :897. Adding an i32 makes the struct 24 bytes with padding, so
# both hardcoded 16s would UNDER-ALLOCATE and corrupt the heap — and no corpus
# case would catch it, because every corpus string is ASCII, so `enc` is always
# 0 and a short write need not visibly break anything. A silent heap bug whose
# failure mode the test set cannot see is the worst outcome this project has a
# name for.
#
# The size is DERIVED from the field list rather than restated, so widening the
# struct moves the declaration and every allocation together.
my @_STRPAIR_FIELDS = (
    { name => 'ptr', llvm => 'i8*', bytes => 8 },
    { name => 'len', llvm => 'i64', bytes => 8 },
    # WIDENED TO MATCH %Str (step 1 of the collapse; see
    # docs/plans/2026-09-02-finish-the-str-strpair-migration.md).
    #
    # This was "deliberately still two fields" while %Str was the value type
    # and %Str the boxed heap cell. They are the SAME LAYOUT now, which is
    # what makes the remaining steps a substitution rather than a redesign:
    # every site reads indices 0 and 1 (measured -- 18 hardcoded GEPs, all 0/1),
    # so widening is invisible to readers and the third field simply rides
    # along.
    #
    # The size is DERIVED (_sizeof_llvm_type over this list), so the allocation
    # sites follow automatically -- which is exactly the property
    # strpair-layout-single-source.t was written to guarantee before this
    # widening could be attempted. The hardcoded `malloc(i64 16)` sites it
    # warned about are already gone.
    #
    # `enc` is WRITE-ONLY today: one writer (_str_aggregate), zero readers,
    # zero callers passing a non-default. Giving it a reader or deleting it is
    # step 4 and a separate decision.
    { name => q(enc), llvm => q(i32), bytes => 4 },   # charset id; see %_STR_ENC, default utf8
);

# ---------------------------------------------------------------------------
# %Str: the Str VALUE type — a first-class aggregate { ptr, len, enc }.
#
# A Str SSA value was a bare `i8*` with its byte length in the `_str_len_table`
# side channel. That was never a design. It is C's `char*` habit, where a
# "string" is a pointer plus an out-of-band agreement about where it ends —
# and Perl's strings are COUNTED, not terminated, so the convention does not
# survive contact with the language.
#
# This codebase knew from the first commit that introduced it. e602f231's own
# message: "a Str via printf(\"%.*s\", len, ptr) from the tracked
# _str_len_table ... embedded-NUL safe". The table was born in the SAME BREATH
# as the pointer, precisely because the pointer alone is not a string.
#
# The tell is that NOT ONE consumer uses the pointer alone — printf("%.*s"),
# memcmp, memcpy and chalk_str_to_num all take (ptr, len). When every use site
# needs two things, those two things are ONE VALUE.
#
# LLVM supports this directly: structs are FIRST-CLASS AGGREGATES, so a %Str
# can be an SSA value, returned from a function, phi'd across blocks, and read
# with extractvalue. Verified against lli 15. The side table was standing in
# for a struct the target supported all along.
#
# What this buys beyond tidiness: the length CANNOT DESYNCHRONIZE from the
# pointer, because they are one value. `_emit_shortcircuit_phi` dies today with
# "an arm's length is not tracked" exactly when a merge phi'd the pointer but
# lost the length. With `phi %Str` that failure class is deleted BY
# CONSTRUCTION rather than by discipline.
#
# The encoding field is here from the start rather than added later: it is what
# `%HashEntry` already stores for a hash key (key_ptr, key_len, key_enc) and
# what Context.pm:897 already specifies, and leaving it out would mean touching
# every one of these sites twice.
# _sizeof_llvm_type($ty) -> a constant expression giving sizeof($ty) in bytes.
#
# The standard LLVM idiom: index one element past a null pointer and convert
# the resulting address to an integer. LLVM computes it from the type
# declaration it is already emitting, so the size CANNOT DRIFT from the struct
# -- which a hand-written byte count silently does the day a field is added.
#
# This replaced four literals: `$n * 16` for a %Slot array, `$npairs * 48` for
# %HashEntry, and `malloc(i64 24)` twice for the %Array and %Hash headers. The
# %Slot one became wrong-in-waiting the moment the cell gained a tag field, and
# %HashEntry embeds a slot's worth of fields, so it was next.
#
# It is a constant EXPRESSION, not an SSA value, so it can appear inline in a
# malloc argument but must be multiplied with _sizeof_times below when a count
# is involved. Precedent: the Call(new) object allocation already does exactly
# this.
sub _sizeof_llvm_type {
    my $ty = $_[-1];
    return "ptrtoint ($ty* getelementptr ($ty, $ty* null, i64 1) to i64)";
}

# _sizeof_times($ty, $n) -> a constant expression for $n * sizeof($ty).
#
# $n is a compile-time integer here; a RUNTIME count needs a `mul i64` against
# _sizeof_llvm_type instead, which is why this takes a literal rather than
# pretending to handle both.
sub _sizeof_times {
    my ($ty, $n) = @_[-2, -1];
    $n =~ /^\d+$/ or die "_sizeof_times: count must be a compile-time integer, got '$n'";
    return "mul (i64 $n, i64 " . _sizeof_llvm_type($ty) . ")";
}

# %Str.enc -- WHICH CHARACTER SET the bytes behind `ptr` are written in.
#
# AN OPEN SET, NOT A FLAG (perigrin, 2026-09-02). This is a character-set
# IDENTIFIER: UTF-8, UTF-16, Shift-JIS, EUC-JP, the ISO-8859 family, EBCDIC.
# perl's own Encode knows 124 of them. An earlier version of this comment
# described it as distinguishing "bytes vs characters", which is a CONSEQUENCE
# of the encoding rather than the question the field asks -- and a two-way flag
# would have been the wrong shape to grow.
#
# So the values below are a REGISTRY, not an enum: names are assigned numbers
# as the backend learns to handle them, and an unknown name is an error rather
# than a default. Nothing here caps how many there can be.
#
# CHALK'S DEFAULT IS UTF-8, AND THAT IS A DELIBERATE BREAK WITH PERL. perl has
# no single default: a literal without `use utf8` is bytes-as-Latin-1, and with
# `use utf8` it is decoded characters, so the same source text means different
# things depending on a pragma. Measured on 5.42.0:
#
#     length("a\x{2014}b")            3    characters
#     length(encode('UTF-8', $same))   5    bytes
#
# Chalk declines to carry that split: a Str IS UTF-8 unless its enc says
# otherwise, so `len` is a byte count and `enc` says how to walk them.
#
# THIS IS NOT SPECULATIVE. Chalk is itself non-ASCII -- 56 files under
# lib/Chalk carry non-ASCII bytes, 174 declare `use utf8`, and MOP.pm:81 has an
# em-dash INSIDE A `die` STRING. Self-hosting means compiling that source.
#
# The numbers are Chalk's own and deliberately NOT the IANA MIBenum values:
# borrowing an external registry's numbering would imply we implement its whole
# set. utf8 is 0 so that a zeroed cell is the default rather than an unassigned
# encoding.
my %_STR_ENC = (
    utf8   => 0,   # THE DEFAULT. len counts bytes; enc says how to walk them.
    latin1 => 1,   # ISO-8859-1: one byte, one character (perl without utf8)
    binary => 2,   # opaque octets: no character interpretation at all
    # Add here as the backend learns each one. A name absent from this table is
    # an ERROR at emit time (see _str_enc), never a silent 0 -- an encoding we
    # cannot name is one we cannot correctly index, slice or measure.
);

# _str_enc($name) -> the i32 value for a named encoding.
#
# Dies on an unknown name. That is the point: the alternative is emitting a
# default for a string whose encoding we did not recognise, which produces a
# module that runs and is wrong.
sub _str_enc {
    my $n = $_[-1];
    return $_STR_ENC{$n}
        // die "no %Str encoding named '$n' -- add it to %_STR_ENC with a "
             . "number once the backend can index and measure it";
}

# _str_encodings() -> the registry, for tests and for a future emitter that
# needs to name what it supports.
sub _str_encodings { return %_STR_ENC }

my @_STR_FIELDS = (
    { name => 'ptr', llvm => 'i8*', bytes => 8 },
    { name => 'len', llvm => 'i64', bytes => 8 },
    { name => q(enc), llvm => q(i32), bytes => 4 },   # charset id; see %_STR_ENC, default utf8
);

# Field INDEX by name, so emitters say _str_idx('len') rather than a bare 1.
# extractvalue/getelementptr take positional indices, and a literal index is
# how a field reordering becomes a silent miscompile.
my %_STR_IDX = do { my $i = 0; map { $_->{name} => $i++ } @_STR_FIELDS };
sub _str_idx { return $_STR_IDX{ $_[0] } // die "no %Str field named '$_[0]'" }

sub _str_fields { return @_STR_FIELDS }

sub _str_type_decl {
    return '%Str = type { ' . join(', ', map { $_->{llvm} } @_STR_FIELDS) . ' }';
}


# ---------------------------------------------------------------------------
# %Slot -- the uniform scalar cell, and the ONE place its layout is written.
#
# A Slot is what a value gets when nothing narrower was proven: an array
# element, a hash value, an object field, or any `Scalar`. Two axes meet in
# this struct -- `Scalar` is the TYPE (top of the spine) and `%Slot` is its
# ENCODING.
#
# THE TAG IS WHY THIS EXISTS. `_lower_coerce` dies on Coerce[Scalar -> X] with
# "a %Slot payload is i64 bits whose interpretation is not recorded in the
# cell ... which needs either a tag or a runtime" -- measured at 33 corpus
# sites. The payload alone cannot say whether its bits are an integer, a
# double, or a pointer to a string, so a consumer either guesses or refuses.
# `tag` records the answer the producer already knew, making the read a
# dispatch on data rather than a guess.
#
# Derived from a field list rather than written as a literal for the same
# reason %Str is: `$n * 16` at the ArrayRef site hardcoded the two-field size,
# and a field added without updating it would silently UNDER-ALLOCATE -- a
# wrong answer, not a compile error. _slot_size_bytes computes it.
#
# Measured: with the tag the cell is still 16 bytes. `i8` lands in padding the
# two-field layout already had, so no allocation anywhere changed.
my @_SLOT_FIELDS = (
    { name => 'defined', llvm => 'i1',  bytes => 1 },
    { name => 'tag',     llvm => 'i8',  bytes => 1 },
    { name => 'payload', llvm => 'i64', bytes => 8 },
);

# The tag values. Undef is 0 so a ZEROED cell reads as undef rather than as a
# valid Int -- a memset'd buffer must not look like a defined zero.
#
# The vocabulary must be TOTAL over what _box_payload boxes. It boxes eight
# representations; a four-value table mapped five of them onto Undef, which
# makes a live heap pointer indistinguishable from an undefined cell -- not a
# type error LLVM would catch, but a wrong value read at runtime.
#
# Opaque is NOT a representation. It records that the reading was never
# ESTABLISHED, which is a different fact from a cell that IS undef: the first
# says nothing was determined, the second asserts a determination. Collapsing
# them onto 0 would let a consumer treat an un-narrowed cell as known-undef and
# skip the coercion it still needs.
my %_SLOT_TAG = (
    Undef    => 0,
    Int      => 1,
    Num      => 2,
    Str      => 3,
    Boolean  => 4,
    ArrayRef => 5,
    HashRef  => 6,
    CodeRef  => 7,
    Object   => 8,
    Opaque   => 9,
    ScalarRef => 10,
);

# _slot_fields() -> the field list (for size computation and tests).
sub _slot_fields { return @_SLOT_FIELDS }

# Field INDEX by name. insertvalue/extractvalue take positional indices, and a
# literal index is how a field reordering becomes a silent miscompile -- the
# defined-bit read where a payload belonged.
my %_SLOT_IDX = do { my $i = 0; map { $_->{name} => $i++ } @_SLOT_FIELDS };
sub _slot_idx { my $n = $_[-1]; return $_SLOT_IDX{$n} // die "no %Slot field named '$n'" }

# _slot_tag_value($repr) -> the i8 tag constant for a representation name.
sub _slot_tag_value {
    my $r = $_[-1];
    return $_SLOT_TAG{$r} // die "no %Slot tag for representation '$r'";
}

# _slot_tag_names() -> the tagged representations, for tests and diagnostics.
sub _slot_tag_names { return sort keys %_SLOT_TAG }

# _slot_tag_for_repr($repr) -> a tag NAME safe to build a Slot with.
#
# Maps a representation onto the reading its payload carries. A repr with no
# concrete reading -- `Scalar` (the un-narrowed top), `Unknown`, or none at all
# -- yields 'Opaque': the cell records that the reading is NOT ESTABLISHED
# rather than asserting one. That is the honest answer until T2 narrows it, and
# it is what keeps this from becoming the guess the tag exists to remove.
#
# 'Opaque', not 'Undef': an un-narrowed Scalar is not a cell that IS undef, and
# a consumer must be able to tell "no reading yet" from "the reading is undef".
sub _slot_tag_for_repr {
    my $r = $_[-1];
    return 'Opaque' unless defined $r;
    return exists $_SLOT_TAG{$r} ? $r : 'Opaque';
}

# _slot_type_decl() -> the LLVM type declaration line.
# %HashEntry's fields, BY NAME, as %Slot's are: a literal index is how a
# reordering becomes a silent miscompile. val_tag is the value's reading --
# a hash value has one of its own, as an array element does, so a read
# need not take it from the reader's stamp. Appended, it shifts no index.
my @_HASHENTRY_FIELDS = (
    { name => 'key_ptr', llvm => 'i8*' },
    { name => 'key_len', llvm => 'i64' },
    { name => 'key_enc', llvm => 'i32' },
    { name => 'val_def', llvm => 'i1'  },
    { name => 'val_pay', llvm => 'i64' },
    { name => 'val_tag', llvm => 'i8'  },
);
my %_HE_IDX = do { my $i = 0; map { $_->{name} => $i++ } @_HASHENTRY_FIELDS };
sub _he_idx { my $n = $_[-1]; return $_HE_IDX{$n} // die "no %HashEntry field named '$n'" }
sub _hashentry_type_decl {
    return '%HashEntry  = type { ' . join(', ', map { $_->{llvm} } @_HASHENTRY_FIELDS) . ' }';
}

sub _slot_type_decl {
    return '%Slot = type { ' . join(', ', map { $_->{llvm} } @_SLOT_FIELDS) . ' }';
}


# _strpair_fields() -> the field list (for size computation and tests).
sub _strpair_fields { return @_STRPAIR_FIELDS }

# _strpair_type_decl() -> the LLVM type declaration line.
sub _strpair_type_decl {
    # Returns the %Str declaration: @_STRPAIR_FIELDS and @_STR_FIELDS are the
    # same layout since step 1, and the emitted name collapsed in step 2. This
    # exists so strpair-layout-single-source.t keeps its single accessor while
    # the remaining call sites are unwound in step 3.
    return '%Str = type { '
         . join(', ', map { $_->{llvm} } @_STRPAIR_FIELDS)
         . ' }';
}


# Struct SIZES are not computed here. LLVM computes them from the type
# declaration via _sizeof_llvm_type, so the emitted size cannot drift from the
# emitted struct. This function used to re-implement LLVM's alignment rules in
# perl -- two sources of truth for one layout, and the `bytes` fields below
# survive only as documentation of intended widths.

# render_str_type_once() -> @llvm_lines (possibly empty)
#
# %Str, the first-class Str VALUE type, declared at most once per Context.
# Three call sites in Target/LLVM.pm each need "declare %Str unless it's
# already been declared" -- the main prologue (which runs before body
# lowering, so it may not know yet that %Str is needed), the class-registry
# prologue (which runs before METHOD BODIES lower, so it may not know
# either), and neither may have run at all if the other already emitted it.
# Centralizing the guard here means all three share one flag and one
# decision instead of each hand-checking $ctx->{_str_type_emitted}.
sub render_str_type_once {
    my ($self) = @_;
    return () if $self->{_str_type_emitted};
    $self->{_str_type_emitted} = 1;
    return ('; Str VALUE type (layout: Context::_str_fields)', _str_type_decl());
}

# render_strpair_type_once() -> @llvm_lines (possibly empty)
#
# %Str's type-decl line, declared at most once per Context, guarded by
# _strpair_emitted (I3: the flag that stops the post-class re-emit from
# double-declaring when a Str :param bind already forced %Str before any
# Str-returning method was found). Returns just the decl line, not a leading
# comment -- callers push their own comment first (the wording differs by
# call site: "for Str method return values" at the class-registry prologue
# vs. "post-class re-emit, I3" at the F6 re-emit site).
#
# Sets NOTHING -- it is an alias for render_str_type_once, which owns the
# makes %Str needed from here on (a method body lowered afterwards must
# inherit the flag via configure_as_method_body's inherit_need_flags_from).
# The class-registry call site used to set this by hand as a second line
# right after calling this method; the post-class re-emit call site already
# has it true as its own calling condition, so setting it again there is a
# no-op.
sub render_strpair_type_once {
    my ($self) = @_;
    # A PURE ALIAS for render_str_type_once, kept only so the class-registry
    # prologue reads as "declare the boxed-Str type" at its own call site.
    #
    # There is ONE type and ONE need-flag now. This sets neither, because
    # render_str_type_once is the authority for both -- two flags guarding one
    # declaration is the "several places that must agree" shape this migration
    # exists to remove, and it was not merely untidy: the I3 post-class re-emit
    # existed precisely because the two could disagree about whether the type
    # had been declared yet.
    return $self->render_str_type_once;
}

# require_class_support() -> $self
#
# Classes always require %Slot (for fields) and malloc (for New). Called
# right after construction, before any control-chain processing, so the
# prologue emits %Slot/%Array/%Hash and declares malloc/memcpy even if the
# main graph itself never lowers an Array/Hash/Concat node -- a class with
# only Int fields still needs %Slot for its object struct.
sub require_class_support {
    my ($self) = @_;
    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;
    return $self;
}

# require_strlen_once() -> @llvm_lines (possibly empty)
#
# `declare i64 @strlen(...)`, declared at most once per Context, guarded by
# _strlen_declared. Three sites need this guard: here (before any class body
# lowers, for Str field reads), and the two F6 post-class re-emit sites
# (_need_getenv, which also needs strlen for the runtime value length).
# _argv_helper_lines() -> @chalk_argv_array and the strlen it calls, once.
sub _argv_helper_lines {
    my ($self) = @_;
    return () unless $self->{_need_argv} && !$self->{_argv_helper_emitted}++;
    return ('', $self->require_strlen_once, _emit_argv_helper());
}

sub require_strlen_once {
    my ($self) = @_;
    return () if $self->{_strlen_declared};
    $self->{_strlen_declared} = 1;
    return 'declare i64 @strlen(i8* nocapture readonly)';
}

# render_need_flag_prologue($result_repr) -> @llvm_lines
#
# The pre-class-lowering half of the module prologue: declares/emits every
# global and helper this context's NEED_FLAGS (plus the always-collected
# _str_globals/_pkg_*_globals tables) say the module will use. Runs BEFORE
# any class method body lowers, so a flag that method-body lowering sets
# later is invisible here -- render_need_flag_postclass_reemit is the F6 fix
# for that half.
#
# $result_repr distinguishes _need_bool_str_globals's one special case: a
# Str-repr'd return already gets these globals from the return-epilogue
# path (elsewhere), so this block only emits them here when the result is
# NOT Str.
sub render_need_flag_prologue {
    my ($self, $result_repr) = @_;
    my @lines;

    # When body lowering set _need_bool_str_globals (Coerce(Boolean->Str) used
    # internally in a non-Str-return graph), emit those globals now. They are
    # always emitted for a Str result repr (by the caller's return-epilogue
    # path); this branch handles the case where the return is not Str but the
    # body contains a Coerce(Boolean->Str) in the MAIN graph (not a method
    # body — method bodies are handled post-class).
    if ($self->{_need_bool_str_globals} && $result_repr ne 'Str') {
        push @lines, '@coerce_bool_str_true  = private unnamed_addr constant [2 x i8] c"1\00", align 1';
        push @lines, '@coerce_bool_str_false = private unnamed_addr constant [1 x i8] c"\00",   align 1';
        $self->{_bool_str_globals_emitted} = 1;
    }

    # Print emits its list args with a raw (untagged) printf format per arg type.
    # These are distinct from the return-value epilogue formats (which prepend a
    # type tag): a printed value is the raw content, not a tagged result.
    if ($self->{_need_print_str_fmt}) {
        # "%.*s\0" = 5 bytes = [5 x i8]
        push @lines, '@fmt_print_str = private unnamed_addr constant [5 x i8] c"%.*s\00", align 1';
        # Records that the DEFINITION exists, so the post-class re-emit below
        # does not add a second one for a program that prints both in the main
        # graph and in a method body.
        $self->{_print_str_fmt_emitted} = 1;
    }
    if ($self->{_need_print_int_fmt}) {
        # "%lld\0" = %,l,l,d,\0 = 5 bytes = [5 x i8]
        # %lld so printf reads the full i64 arg -- a bare %d truncates the
        # varargs read to 32 bits on LP64 targets.
        push @lines, '@fmt_print_int = private unnamed_addr constant [5 x i8] c"%lld\00", align 1';
    }

    if ($self->{_need_num_fmt} && !$self->{_num_fmt_emitted}++) {
        # "%.15g\0" = 6 bytes = [6 x i8]. This is perl's own float
        # stringification rule, verified against perl 5.42 on the corpus floats
        # and on t/base/num.t's cases (0.1, 1e+34, 1.000001, 0.0005).
        push @lines, '@fmt_num_g = private unnamed_addr constant [6 x i8] c"%.15g\00", align 1';
    }

    push @lines, '';
    push @lines, 'declare i32 @printf(i8* nocapture readonly, ...)';
    # snprintf renders a Num to Str: measure with a null buffer, then render.
    # Same host-interface class as printf -- a plain C function, not libperl.
    push @lines, 'declare i32 @snprintf(i8* nocapture, i64, i8* nocapture readonly, ...)'
        if $self->{_need_snprintf} && !$self->{_snprintf_emitted}++;
    push @lines, 'declare i8* @memchr(i8*, i32, i64)'
        if $self->{_need_memchr} && !$self->{_memchr_emitted}++;

    # Emit string-constant globals collected during body lowering.
    # Each Constant(:Str) node emits a private global; the names are stashed in
    # _str_globals as [ $global_name, $content, $byte_len ] triples. We emit
    # them here (before the function body) so they appear in the module before @main.
    if (defined $self->{_str_globals}) {
        push @lines, '';
        for my $g ($self->{_str_globals}->@*) {
            my ($gname, $content, $blen) = @$g;
            my $total = $blen + 1;  # +1 for NUL terminator
            # Encode the bytes as a c"..." literal (NUL is \00).
            my $enc = _encode_c_string($content);
            push @lines, "$gname = private unnamed_addr constant [$total x i8] c\"$enc\\00\", align 1";
        }
    }

    # Shared file lexicals: one %Slot each, zero-init -- an undefined Slot,
    # as an unassigned `my` is.
    if (my $lex = $self->{_lex_globals}) {
        push @lines, '';
        push @lines, "$lex->{$_} = internal global %Slot zeroinitializer, align 8  ; shared lexical \$$_"
            for sort keys %$lex;
    }

    # An ALIASED package scalar is read through a pointer, which starts at its
    # own %Slot; a LocalAlias points it at an element (_lower_local_alias).
    my @alias_lines = map {
        my ($s, $v) = /\A(.*)::(.*)\z/;
        my $g = $self->_pkg_slot_name($s, $v);
        "${g}_at = internal global %Slot* $g  ; where \$$v points";
    } sort keys %Chalk::Target::LLVM::Context::ALIASED;
    push @lines, '', @alias_lines if @alias_lines;

    # Package scalars: one %Slot each, zero-init -- an undefined Slot, as an
    # unwritten package scalar is. See _pkg_slot_name.
    if (my $pkg = $self->{_pkg_slots}) {
        push @lines, '';
        push @lines, "$pkg->{$_} = internal global %Slot zeroinitializer, align 8  ; package scalar \$$_"
            for sort keys %$pkg;
    }

    # Declare malloc/memcpy when Str concat or aggregate operations were emitted.
    # These are plain C host-interface functions — NOT libperl.
    if ($self->{_need_malloc_memcpy}) {
        push @lines, 'declare i8* @malloc(i64)';
        push @lines, 'declare i8* @memcpy(i8*, i8*, i64)';
    }

    # Declare exit when a `die` arm was lowered (Unwind -> exit(255) + unreachable).
    # A plain C host-interface function — NOT libperl.
    if ($self->{_need_exit} && !$self->{_exit_emitted}++) {
        push @lines, 'declare void @exit(i32)';
    }
    push @lines, 'declare i64 @time(i64*)' if $self->{_need_time};
    push @lines, do { my $d = _repr_to_llvm_type('Num'); "declare $d \@pow($d, $d)" } if $self->{_need_pow};

    # Declare getenv (+ strlen for the runtime value length) when EnvRead was
    # emitted. Plain C host-interface functions — NOT libperl.
    if ($self->{_need_getenv}) {
        push @lines, 'declare i8* @getenv(i8* nocapture readonly)';
        push @lines, 'declare i64 @strlen(i8* nocapture readonly)';
        $self->{_strlen_declared} = 1;
        $self->{_getenv_emitted}  = 1;
    }

    # Declare memcmp when hash key comparison operations were emitted.
    if ($self->{_need_memcmp}) {
        push @lines, 'declare i32 @memcmp(i8* nocapture readonly, i8* nocapture readonly, i64)';
        $self->{_memcmp_emitted} = 1;
    }

    # Emit LLVM type declarations for Array/Hash aggregate structures when needed.
    # %Slot = { i1 defined, i8 tag, i64 payload } (16 bytes with padding --
    #   the tag rides in padding the two-field cell already had, so adding
    #   it changed no allocation). Rendered from @_SLOT_FIELDS, not a literal.
    # %Array = { i64 len, i64 cap, %Slot* elems }
    # %HashEntry = { i8* key_ptr, i64 key_len, i32 key_enc, i1 val_def, i64 val_pay }
    # %Hash = { i64 count, i64 cap, %HashEntry* entries }
    #
    # %HashEntry INLINES a slot's value fields rather than embedding a %Slot,
    # so the tag added to %Slot did not shift any %HashEntry index. It carries
    # NO tag of its own yet, and that is a deliberate scope line, not an
    # oversight: a hash value's reading is currently established by the READING
    # node's repr (HashRead stamps the Slot it builds from `$repr`), so nothing
    # yet consults a stored tag. It needs one exactly when a hash value's
    # reading must survive independently of the reader's stamp -- a Scalar-typed
    # hash whose values have mixed readings, which is the same case that makes
    # the %Slot tag load-bearing. Widening it is a layout change to a hardcoded
    # literal with five index sites (HashRef, HashRead, Assign(Hash-lvalue)),
    # and those indices are literals today: they must move to a named field list
    # of their own FIRST, exactly as @_SLOT_FIELDS did, or the widening repeats
    # the off-by-one that the %Slot tag attempt was reverted for.
    if ($self->{_need_aggregate_types}) {
        push @lines, _slot_type_decl();
        push @lines, '%Array      = type { i64, i64, %Slot* }';
        push @lines, _hashentry_type_decl();
        push @lines, '%Hash       = type { i64, i64, %HashEntry* }';
    }

    # %Str, the first-class Str VALUE type. Emitted here rather than in the
    # class-registry prologue because _need_str_type is set DURING lowering (by
    # _str_value), and this block runs after it — the same ordering the
    # _need_aggregate_types flag above relies on. Declaring it in the earlier
    # prologue would need a pre-scan, which is the trap the old "I3" re-emit
    # existed to patch around (deleted with the %StrPair collapse).
    if ($self->{_need_str_type}) {
        push @lines, $self->render_str_type_once;
    }

    # Emit @chalk_str_to_num helper + strtod declaration when Coerce(Str->Num) is used.
    #
    # The helper implements perl's leading-numeric rule: skip whitespace, then parse
    # a decimal number (no hex). The one divergence from libc strtod: strtod parses
    # "0x10" as 16.0, but perl returns 0. We pre-check for "0x"/"0X" and return 0.0.
    #
    # strtod is a plain C library function (host interface, NOT libperl). The
    # chalk_str_to_num function is a module-local helper; no external linkage needed.
    if ($self->{_need_str_to_num_helper}) {
        push @lines, '';
        push @lines, 'declare double @strtod(i8* nocapture readonly, i8** nocapture)';
        push @lines, '';
        # @chalk_str_to_num(i8* %ptr, i64 %len) -> double
        # Implements perl's leading-numeric rule (decimal only; "0x..." -> 0.0).
        push @lines, _emit_str_to_num_helper();
        $self->{_str_to_num_helper_emitted} = 1;
    }
    push @lines, $self->_argv_helper_lines;
    push @lines, $self->_slot_inc_helper_lines;
    push @lines, $self->_case_helper_lines;
    push @lines, $self->_substr_helper_lines;

    return @lines;
}

# render_need_flag_postclass_reemit($result_repr) -> @llvm_lines
#
# The post-class-lowering half of the module prologue (the F6 fix): a method
# body or ADJUST block lowers in its OWN Context and is only absorbed into
# this one (via absorb_need_flags_from) AFTER _emit_class_registry_ir runs --
# so a flag set only by a method body is invisible to
# render_need_flag_prologue, which ran before any body lowered. Each check
# here is guarded by "was it already emitted?" so a non-method use of the
# same helper (already emitted by the pre-class prologue) is not duplicated.
sub render_need_flag_postclass_reemit {
    my ($self, $result_repr) = @_;
    my @lines;

    if ($self->{_need_bool_str_globals} && $result_repr ne 'Str') {
        # Only emit if the Str-prologue path (which always includes these globals)
        # did NOT already emit them. The Str-prologue emits them unconditionally
        # when result_repr eq 'Str'; for all other reprs, we must emit here if needed.
        # To avoid duplicate definitions, we track whether they were already emitted.
        # The prologue emits them only when result_repr eq 'Str' (the return-epilogue
        # path, elsewhere) or when _need_bool_str_globals was already set on $self
        # before class-lowering (render_need_flag_prologue, above). Since we only
        # reach here when result_repr ne 'Str', the prologue cannot have emitted them
        # (it checks `$result_repr ne 'Str'` too), so we need to emit now IF the flag
        # was newly set by method-body propagation (not by the main graph). Guard:
        # _bool_str_globals_emitted tracks whether the prologue already emitted them.
        unless ($self->{_bool_str_globals_emitted}) {
            push @lines, '';
            push @lines, '@coerce_bool_str_true  = private unnamed_addr constant [2 x i8] c"1\00", align 1';
            push @lines, '@coerce_bool_str_false = private unnamed_addr constant [1 x i8] c"\00",   align 1';
            $self->{_bool_str_globals_emitted} = 1;
        }
    }
    if ($self->{_need_str_to_num_helper} && !$self->{_str_to_num_helper_emitted}) {
        push @lines, '';
        push @lines, 'declare double @strtod(i8* nocapture readonly, i8** nocapture)';
        push @lines, '';
        push @lines, _emit_str_to_num_helper();
        $self->{_str_to_num_helper_emitted} = 1;
    }
    push @lines, $self->_argv_helper_lines;
    push @lines, $self->_slot_inc_helper_lines;
    push @lines, $self->_case_helper_lines;
    push @lines, $self->_substr_helper_lines;
    # Shared aggregates: emitted once, here, after every body has named its own.
    push @lines, $self->_lex_aggregate_lines;
    push @lines, $self->_array_append_lines;
    push @lines, $self->_tr_lines;
    push @lines, $self->_bless_lines;
    push @lines, $self->_hash_delete_lines;
    push @lines, '@chalk_selected = internal global i8* null  ; the handle a bare print writes to (null: STDOUT)'
        if $self->{_need_select} && !$self->{_select_emitted}++;
    # A method body that stringifies a Num needs these too; the prologue ran
    # before any body lowered.
    push @lines, '@fmt_num_g = private unnamed_addr constant [6 x i8] c"%.15g\00", align 1'
        if $self->{_need_num_fmt} && !$self->{_num_fmt_emitted}++;
    push @lines, 'declare i32 @snprintf(i8* nocapture, i64, i8* nocapture readonly, ...)'
        if $self->{_need_snprintf} && !$self->{_snprintf_emitted}++;
    push @lines, 'declare i8* @memchr(i8*, i32, i64)'
        if $self->{_need_memchr} && !$self->{_memchr_emitted}++;
    # ...and exit, which a method body's helper (++ on a Scalar) calls.
    push @lines, 'declare void @exit(i32)'
        if $self->{_need_exit} && !$self->{_exit_emitted}++;
    # Post-class re-emit for _need_memcmp: a method body doing Subscript(Hash)
    # sets _need_memcmp on $body_ctx (propagated to $self by G.5), but the prologue
    # memcmp declare runs BEFORE method bodies lower. If the flag was set only by a
    # method body, the prologue missed it. Emit here, guarded by _memcmp_emitted so
    # a non-method hash op + a method hash op cannot double-declare.
    if ($self->{_need_memcmp} && !$self->{_memcmp_emitted}) {
        push @lines, 'declare i32 @memcmp(i8* nocapture readonly, i8* nocapture readonly, i64)';
        $self->{_memcmp_emitted} = 1;
    }

    # Post-class re-emit for _need_print_str_fmt (the same F6 pattern as memcmp
    # above): a `print` inside a METHOD BODY sets the flag on $body_ctx, which
    # reaches $self only through absorb_need_flags_from -- and that runs after
    # _emit_class_registry_ir, by which time the prologue has already chosen
    # what to declare. The module then REFERENCED @fmt_print_str without
    # defining it, and lli refused to load it ("use of undefined value").
    #
    # Worse than a GAP: the compiler reported success and produced a module
    # that cannot run.
    #
    # Guarded by _print_str_fmt_emitted so a program that prints in BOTH the
    # main graph and a method body defines it once, not twice -- a redefinition
    # is the mirror-image lli rejection.
    if ($self->{_need_print_str_fmt} && !$self->{_print_str_fmt_emitted}) {
        push @lines, '@fmt_print_str = private unnamed_addr constant [5 x i8] c"%.*s\00", align 1';
        $self->{_print_str_fmt_emitted} = 1;
    }

    # Post-class re-emit for _need_getenv (same F6 pattern as memcmp): a
    # method-body EnvRead sets the flag after the prologue ran.
    if ($self->{_need_getenv} && !$self->{_getenv_emitted}) {
        push @lines, 'declare i8* @getenv(i8* nocapture readonly)';
        push @lines, $self->require_strlen_once;
        $self->{_getenv_emitted}  = 1;
    }

    # THE I3 POST-CLASS RE-EMIT IS GONE, with the condition that made it
    # necessary.
    #
    # It existed because %StrPair was declared from a PRE-SCAN (which methods
    # return Str?) while _need_strpair could be set LATER, during lowering --
    # so a Str :param bind in a class whose methods all return Int emitted
    # references against an undeclared type and lli rejected the module. The
    # re-emit patched that up after the fact.
    #
    # Since the collapse there is one type, one need-flag and one render-once
    # guard, and render_str_type_once is idempotent -- so a late need is served
    # by the declaration the prologue already emitted. Nothing is left to patch.
    #
    # This is the bug class the whole migration was for: the DROPPED Str arm of
    # the method-body field read -- which made `field $s :param = "hi"` print an
    # empty line -- was a workaround for exactly this ordering hazard.

    return @lines;
}

# ---------------------------------------------------------------------------
# The Str seam.
#
# A Str VALUE is `{ ptr: i8*, len: i64, enc: i32 }` — this file has said so at
# :897 and `%HashEntry` already stores all three fields for a hash key. But a
# Str SSA VALUE is still a bare `i8*`, with the length in the `_str_len_table`
# side channel and the encoding NOWHERE. The type is three fields in one place
# and one field in another.
#
# That side channel is not merely untidy, it is a live correctness hazard:
#   - `_emit_shortcircuit_phi` DIES with "an arm's length is not tracked"
#     when a merge loses it, and merges are exactly where it goes missing;
#   - `_box_payload` falls back to `strlen`, which is WRONG for any string
#     containing an embedded NUL (its own comment says so);
#   - the encoding field cannot be carried at all, which is why non-ASCII is
#     a tracked GAP rather than a supported case.
#
# EVERY read and write of the length now goes through this pair, so the table
# has exactly two access points. That is what makes the migration to a real
# `%Str` struct incremental: producers and consumers move independently, the
# table becomes an implementation detail of these two subs, and when the last
# producer emits a struct these two are deleted together with it.
#
# DO NOT add a third access point. Reaching into `_str_len_table` directly is
# what made this a 46-site change instead of a 2-site one.
# ---------------------------------------------------------------------------

# _str_len_for is DELETED, along with the _str_len_table it read.
#
# It answered "what is this pointer's length?" — a question that only existed
# because a Str SSA value was a bare i8* with its length in a side channel. A
# Str value is now `%Str = { ptr, len, enc }`, so the length is a FIELD: ask
# _str_parts, which returns the pointer and the length together and cannot
# return one without the other.
#
# The table's disappearance is the migration's honesty check. It was introduced
# in the same commit as the pointer it compensated for (e602f231, "a Str via
# printf(\"%.*s\", len, ptr) from the tracked _str_len_table ... embedded-NUL
# safe") — born because the pointer alone is not a string. With the pair made
# into one value there is nothing left for it to hold.

# _set_str_len($ptr_ref, $len) -> $ptr_ref
# Record the byte length for a Str SSA ref. Returns the ref so a producer can
# tail-call it: `return $self->_set_str_len($ptr, $len);`
#
# $len may be a literal integer or an SSA ref — both are legal, and callers
# already branch on which they have (see _lower_concat's literal-sum fast path).
#
# THIS IS THE STRING CONSTRUCTOR, in all but name. Measured, every one of the 17
# producer sites reaches it with the same shape — a pointer already in hand and
# a length already computed — which is why the migration to a real `%Str` value
# does not need 17 separate rewrites: they all mint their Str HERE.
#
# It records into a side table today rather than building an aggregate. Making
# it emit `insertvalue` is what turns the side channel into a value, and this
# comment marks the seam so that change lands in one place.
#
# NOT YET a constructor in the ownership sense: it takes a pointer its caller
# already allocated, so it cannot enforce WHERE the bytes live. That is the open
# question filed in docs/architecture/typed-ir-representation.md — producers use
# globals, malloc and alloca inconsistently, and only a constructor that does
# the allocation can make "Str bytes are never alloca" true by construction.
sub _set_str_len {
    my ($self, $ptr_ref, $len, %opt) = @_;

    # THE PRODUCER SEAM. Every producer reaches here with a pointer in hand and
    # a length computed, then caches and returns the result — so building the
    # aggregate HERE converted all seventeen at once rather than editing each.
    #
    # The side table is GONE. It existed to carry the length beside a bare i8*;
    # the length now rides IN the value, so there is nothing to carry and
    # nothing that can fall out of sync with the pointer.
    return $self->_str_value($ptr_ref, len => $len, %opt);
}

# _str_value($ptr_ref) -> an SSA ref holding a `%Str` aggregate.
#
# Builds the first-class aggregate from a pointer whose length this context has
# tracked, so a consumer can take ONE value instead of asking two sources that
# can disagree. Emits:
#
#   %s0 = insertvalue %Str undef, i8* PTR, 0
#   %s1 = insertvalue %Str %s0,   i64 LEN, 1
#   %s2 = insertvalue %Str %s1,   i32 ENC, 2
#
# Dies when the length is untracked rather than falling back to `strlen`: the
# fallback is wrong for any string containing an embedded NUL (perl strings are
# counted, not terminated), and a loud refusal here names the producer that
# failed to record a length instead of silently truncating at the first NUL.
sub _str_value {
    my ($self, $ptr_ref, %opt) = @_;

    my $len = $opt{len};
    defined $len or die
        "LLVM backend: cannot build a %Str from '$ptr_ref' — its byte length is "
      . "not tracked. A Str is (ptr, len, enc); strlen is NOT a valid fallback "
      . "because a perl string may contain an embedded NUL. Fix the producer to "
      . "record the length when it mints the pointer.";

    my $enc = $opt{enc} // _str_enc('utf8');

    # A Str CONSTANT's GEP is hoisted to the entry block so it dominates every
    # use — two if/else arms may share one hash-consed Str constant, and a
    # branch-local definition would not dominate the sibling arm ("Instruction
    # does not dominate all uses"). The aggregate built from it must be hoisted
    # for exactly the same reason: it is a pure value over a module global, so
    # the entry block is always a legal place for it.
    my $emit = $opt{entry} ? sub { $self->_emit_entry($_[0]) }
                           : sub { $self->_emit($_[0]) };

    my $s0 = $self->_fresh;
    my $s1 = $self->_fresh;
    my $s2 = $self->_fresh;
    $emit->("  $s0 = insertvalue %Str undef, i8* $ptr_ref, "  . _str_idx('ptr') . "  ; %Str.ptr");
    $emit->("  $s1 = insertvalue %Str $s0, i64 $len, "        . _str_idx('len') . "  ; %Str.len");
    $emit->("  $s2 = insertvalue %Str $s1, i32 $enc, "        . _str_idx('enc') . "  ; %Str.enc");
    $self->{_need_str_type} = 1;
    # Mark this ref as an aggregate so _str_parts destructures it rather than
    # passing it through. During the flip both forms are live, and the
    # difference must be a recorded FACT about the value, not inferred from how
    # the ref is spelled.
    return $s2;
}

# _str_parts($str_ref) -> ($ptr_ref, $len_ref_or_undef)
#
# THE CONSUMER SEAM. Every site that needs a Str's bytes asks HERE, and gets the
# pointer and length TOGETHER — which is what consumers actually want, since
# printf("%.*s"), memcmp, memcpy and chalk_str_to_num all take the pair.
#
# TRANSITIONAL. A Str SSA value is still a bare `i8*` today, so this returns the
# ref unchanged plus its side-table length. When `lower_value` starts returning
# a real `%Str` aggregate, ONLY THIS FUNCTION changes — to the extractvalue pair
# below — and all 15 consumer call sites are already correct.
#
# That is the whole point of routing them through here first: the pointer half
# of the migration is otherwise a 15-site atomic flip verified by a single
# green/red corpus signal, which is the shape that has produced silent
# regressions in this work twice. Converting the call sites while the
# representation is UNCHANGED is a no-op refactor that can be verified on its
# own; only then does the representation flip, and it touches one function.
#
# The post-flip body is:
#
#     my $p = $self->_fresh;
#     my $l = $self->_fresh;
#     $self->_emit("  $p = extractvalue %Str $str_ref, " . _str_idx('ptr'));
#     $self->_emit("  $l = extractvalue %Str $str_ref, " . _str_idx('len'));
#     return ($p, $l);
#
# $len may be undef when the producer never recorded one. Callers MUST handle
# that — an untracked length is the failure the seam exists to expose, and
# `strlen` is NOT a valid substitute because a perl string may contain an
# embedded NUL.
sub _str_parts {
    my ($self, $str_ref) = @_;

    # EVERY Str value is the %Str aggregate, so destructure unconditionally.
    #
    # An earlier version consulted a `_str_aggregates` registry to decide, which
    # was needed only while some producers had been converted and others had
    # not. That registry is now both obsolete and WRONG: it records refs minted
    # by _str_value, and a PHI is never minted there — the merge code emits
    # `phi %Str [...]` directly. So a merged Str is an aggregate the registry
    # has never heard of, and keying on it sent phi results down the bare-pointer
    # path, where the length lookup missed and Print died with "length is not
    # tracked".
    #
    # Asking a side registry what a value IS, when the type already says so, is
    # the exact mistake this migration exists to remove. The repr is the answer.
    my $p = $self->_fresh;
    my $l = $self->_fresh;
    $self->_emit("  $p = extractvalue %Str $str_ref, " . _str_idx('ptr') . "  ; %Str.ptr");
    $self->_emit("  $l = extractvalue %Str $str_ref, " . _str_idx('len') . "  ; %Str.len");
    return ($p, $l);
}

# render_blocks($skip_first_label) -> @llvm_lines
#
# Render this context's basic blocks, with the block that was CURRENT at end
# of lowering rendered LAST: epilogue lines (printf/ret) attach textually to
# the final rendered block and must close the block holding the result
# value. Multi-block phi arms append continuation blocks after the merge
# block, so creation order does not guarantee the current block is last.
# Block order is otherwise semantically irrelevant in LLVM IR, except that
# the entry block must stay first — the current block at end of lowering is
# never the entry block when later blocks exist (fallback preserves creation
# order if it ever were). $skip_first_label suppresses block 0's label for
# callers that emit their own 'entry:' line.
sub render_blocks {
    my ($self, $skip_first_label) = @_;
    my @lines;
    my $blocks = $self->{blocks};
    my $final_idx = $self->{current_idx} // $#$blocks;
    $final_idx = $#$blocks if $final_idx == 0 && $#$blocks > 0;
    for my $i ((grep { $_ != $final_idx } 0 .. $#$blocks), $final_idx) {
        my $block = $blocks->[$i];
        unless ($skip_first_label && $i == 0) {
            push @lines, $block->{label} . ':';
        }
        push @lines, $block->{insts}->@*;
        if (defined $block->{terminator}) {
            push @lines, $block->{terminator};
        }
    }
    return @lines;
}

# render_str_globals() -> @llvm_lines
#
# str_globals() -> arrayref of [ $global_name, $content, $byte_len ] triples
#
# The string-constant globals accumulated so far by THIS context. A reader
# for tests that assert on the registered-global table directly (e.g. that a
# failed _module_global_name call registered nothing); production code goes
# through render_str_globals/render_need_flag_prologue instead.
sub str_globals { $_[0]->{_str_globals} }

# A SLOT VALUE IS ONE AGGREGATE, NOT TWO HALVES.
#
# %Slot is { i1 defined, i8 tag, i64 payload }. It used to be carried as its DEFINED
# BIT ALONE -- the node's cached SSA ref was the i1, and the payload lived in a
# side table keyed by that ref, "because there is no single SSA ref that
# carries both halves". There is: the aggregate itself, exactly as %Str already
# carries its own (ptr, len) pair so that a merge cannot desynchronize them.
#
# The side table had two failure modes, and the second is why it is gone:
#
#   - A consumer holding the cached ref and forgetting the lookup used a
#     defined-bit where a value belonged. Three `// die` guards existed to
#     catch that, which is evidence it happened rather than reassurance.
#   - It was keyed by an SSA REF STRING while SSA numbering is PER-GRAPH, so
#     `%1` in one graph is not `%1` in another -- the string-keyed-cache shape
#     that has caused silent cross-graph miscompiles in this codebase before.
#
# And it could not survive a phi: merging the def-bit leaves the payload
# behind, so both producer sites emitted two parallel phis by hand and relinked
# them. One `phi %Slot` replaces that.

# _build_slot($defined, $payload, $tag_name, $what) -> $slot_ref
#
# $defined is an i1 operand ('i1 true', or a bare SSA ref), $payload an i64.
#
# $tag_name is REQUIRED and has no default. A default would be a guess wearing
# the syntax of a fact, and the tag exists precisely to stop consumers guessing.
# A caller that does not know the reading says so by passing 'Opaque' -- see
# _slot_tag_for_repr, which maps an un-narrowed repr onto exactly that.
sub _build_slot {
    my ($self, $defined, $payload, $tag_name, $what) = @_;
    # Naming %Slot as a value is what makes its type declaration necessary;
    # setting the flag HERE rather than at each caller means a new Slot
    # producer cannot forget it and emit a module that references an
    # undeclared type.
    $self->{_need_aggregate_types} = 1;
    die "_build_slot($what): tag is required -- pass 'Opaque' if the reading "
      . "is not established" unless defined $tag_name && length $tag_name;
    my $tag = _slot_tag_value($tag_name);
    my $s0   = $self->_fresh;
    my $s1   = $self->_fresh;
    my $slot = $self->_fresh;
    # `undef` is LLVM's poison aggregate, not perl's undef -- the starting
    # value into which the fields are inserted.
    my $d = $defined =~ /^i1 / ? $defined : "i1 $defined";
    my ($i_def, $i_tag, $i_pay) =
        (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
    $self->_emit("  $s0 = insertvalue %Slot undef, $d, $i_def  ; $what: defined");
    $self->_emit("  $s1 = insertvalue %Slot $s0, i8 $tag, $i_tag  ; $what: tag=$tag_name");
    $self->_emit("  $slot = insertvalue %Slot $s1, i64 $payload, $i_pay  ; $what: payload");
    return $slot;
}

# _slot_tag_of($slot_ref) -> $i8_ref
sub _slot_tag_of {
    my ($self, $slot_ref) = @_;
    $self->{_need_aggregate_types} = 1;   # naming %Slot requires its declaration
    my $ref = $self->_fresh;
    my $i_tag = _slot_idx('tag');
    $self->_emit("  $ref = extractvalue %Slot $slot_ref, $i_tag  ; Slot.tag");
    return $ref;
}

# _slot_defined_bit($slot_ref) -> $i1_ref
sub _slot_defined_bit {
    my ($self, $slot_ref) = @_;
    $self->{_need_aggregate_types} = 1;   # naming %Slot requires its declaration
    my $ref = $self->_fresh;
    my $i_def = _slot_idx('defined');
    $self->_emit("  $ref = extractvalue %Slot $slot_ref, $i_def  ; Slot.defined");
    return $ref;
}

# _slot_payload_of($slot_ref) -> $i64_ref
sub _slot_payload_of {
    my ($self, $slot_ref) = @_;
    $self->{_need_aggregate_types} = 1;   # naming %Slot requires its declaration
    my $ref = $self->_fresh;
    my $i_pay = _slot_idx('payload');
    $self->_emit("  $ref = extractvalue %Slot $slot_ref, $i_pay  ; Slot.payload");
    return $ref;
}

# Emit string-constant globals accumulated by THIS context during body
# lowering (a method body or ADJUST block, each lowered in its own fresh
# Context). They cannot go in the main module prologue -- that has already
# been emitted by the time a body lowers -- so the caller places these lines
# in the class section, near the function that references them.
sub render_str_globals {
    my ($self) = @_;
    my @lines;
    if (defined $self->{_str_globals} && @{ $self->{_str_globals} }) {
        for my $g (@{ $self->{_str_globals} }) {
            my ($gname, $content, $blen) = @$g;
            my $total = $blen + 1;
            my $enc = _encode_c_string($content);
            push @lines, "$gname = private unnamed_addr constant [$total x i8] c\"$enc\\00\", align 1";
        }
    }
    return @lines;
}

# blocks() -> arrayref of { label, insts, terminator }
sub blocks { $_[0]->{blocks} }

# instructions() -> the insts arrayref of the current block.
# Maintained for backward compatibility with callers that read this directly.
sub instructions { $_[0]->{blocks}[ $_[0]->{current_idx} ]{insts} }

# _emit($inst) -> push $inst into the current block's instruction list.
sub _emit {
    my ($self, $inst) = @_;
    push $self->{blocks}[ $self->{current_idx} ]{insts}->@*, $inst;
}

# _emit_entry($inst) -> push $inst into the ENTRY block (block 0). A pure,
# rematerializable value (a Constant) emitted here dominates ALL blocks, so it is
# valid at any use site -- avoids an "instruction does not dominate all uses"
# error when a shared node (e.g. a hash-consed index constant) is first lowered
# inside a branch block but used after the merge (memory-SSA phase 2b). The entry
# block's terminator is appended after its instruction list, so unshifting/pushing
# an instruction before the terminator is safe.
sub _emit_entry {
    my ($self, $inst) = @_;
    push $self->{blocks}[0]{insts}->@*, $inst;
}

# _set_terminator($term) -> set the current block's terminator instruction.
# A block must have exactly one terminator. Call this before _new_block().
sub _set_terminator {
    my ($self, $term) = @_;
    $self->{blocks}[ $self->{current_idx} ]{terminator} = $term;
}

# _new_block($label) -> $label
# Start a new basic block with the given label. All subsequent _emit() calls
# go into this block. Returns the label string for use in phi/branch args.
sub _new_block {
    my ($self, $label) = @_;
    my $block = { label => $label, insts => [], terminator => undef };
    push $self->{blocks}->@*, $block;
    $self->{current_idx} = $#{ $self->{blocks} };
    return $label;
}

# _current_block_label() -> the label of the current block.
sub _current_block_label {
    my ($self) = @_;
    return $self->{blocks}[ $self->{current_idx} ]{label};
}

# _fresh_label($hint) -> unique block label string
sub _fresh_label {
    my ($self, $hint) = @_;
    $self->{block_counter}++;
    return $hint . $self->{block_counter};
}

sub _fresh {
    my ($self) = @_;
    $self->{counter}++;
    return '%tmp_' . $self->{counter};
}

# _module_global_name($tag, $content) -> ($gname, $byte_len, $total)
#
# Allocate one module-scope string-constant global and register it in
# _str_globals. This is the single owner of the symbol-prefix + byte-length
# computation shared by @str_const_N, @rxs_lit_N, and @env_key_N (previously
# triplicated, and micro-diverged: some sites used CHAR length instead of BYTE
# length, producing wrong [N x i8] sizes for any non-ASCII content).
#
#   $tag     — global-name stem (e.g. 'str_const', 'rxs_lit', 'env_key').
#   $content — the string bytes the global will hold.
#
# I1 symbol-prefix rule: method bodies lower in fresh Contexts whose counters
# restart at 0, but every global lands at module scope. Prefix by class/method
# so two bodies do not both emit e.g. @str_const_0 (a duplicate symbol).
#
# G6 S4: the sanitized name (everything after the leading '@') must be a legal
# unquoted LLVM identifier (\w+). A class name containing '::' would produce an
# illegal identifier that silently corrupts the module — die loudly instead.
#
# Returns the LLVM global name (with leading '@'), the byte length, and the
# array size ($byte_len + 1, for the NUL terminator). The global is pushed onto
# _str_globals as [ $gname, $content, $byte_len ]; the caller only emits the
# getelementptr that references it.
sub _module_global_name {
    my ($self, $tag, $content) = @_;

    my $byte_len = do { use bytes; length($content) };

    my $prefix = '';
    if ($self->{_in_method_body}
        && defined $self->{_method_class_name}
        && defined $self->{_method_name}) {
        $prefix = "$self->{_method_class_name}__$self->{_method_name}__";
    }

    my $gidx  = scalar @{ $self->{_str_globals} };
    my $ident = "${prefix}${tag}_${gidx}";
    die "GAP: LLVM global name '\@$ident' is not a legal unquoted identifier "
      . "(\\w+) — a class or method name likely contains '::' or other "
      . "non-identifier characters"
        unless $ident =~ /\A\w+\z/;

    my $gname = "\@$ident";
    push $self->{_str_globals}->@*, [ $gname, $content, $byte_len ];
    return ($gname, $byte_len, $byte_len + 1);
}

# _pkg_slot_name($stash, $var) -> the %Slot global a package scalar lives in.
#
# ONE GLOBAL HOLDING A VALUE, not a typed family per representation (Part
# H5): a store boxes, a read unboxes to its own reading, and an unwritten
# one is an undefined Slot. The three families (i64, (ptr, len), double)
# were perl's SV union rebuilt by hand, and a store in one was invisible to
# a read of another. The name must be a legal unquoted LLVM identifier.
# %ALIASED: the package scalars a LocalAlias in this module points at an
# element (`$_` for a foreach that calls subs reading it). Set for one
# module's lowering by lower_with_elaboration, before any graph lowers: a
# read of an aliased scalar goes through its pointer from the first one on.
our %ALIASED;

# %POS_VARS: the variables a scalar m//g matches, by name -- each has a pos()
# cell (_pos_cell), which a store to the variable clears.
our %POS_VARS;

# _pkg_slot_ptr($stash, $var) -> a %Slot* to read or store a package scalar
# through: its global, or -- aliased -- wherever its pointer points now.
sub _pkg_slot_ptr {
    my ($self, $stash, $var) = @_;
    my $g = $self->_pkg_slot_name($stash, $var);
    return $g unless $ALIASED{"${stash}::${var}"};
    my $p = $self->_fresh;
    $self->_emit("  $p = load %Slot*, %Slot** ${g}_at  ; where \$${var} points now");
    return $p;
}

sub _pkg_slot_name {
    my ($self, $stash, $var) = @_;
    # $@ IS THE ONE PUNCTUATION VARIABLE chalk keeps (block evals set it),
    # spelled by its bytes' hex under its own prefix so no word-named variable
    # can spell the same global. Any other ($^W, $^O) is perl's to set, and
    # an empty global would read wrong: it stays refused below.
    my $ident = "${stash}::${var}" eq 'main::@' ? "pkgp_main_" . unpack('H*', $var)
              : "pkg_${stash}_${var}";
    die "GAP: package-scalar global '\@$ident' (from ${stash}::${var}) is not a "
      . "legal unquoted LLVM identifier (\\w+)\n"
        unless $ident =~ /\A\w+\z/;
    return $self->{_pkg_slots}{"${stash}::${var}"} = "\@$ident";
}

# _lex_global_name($symbol) -> the module global for a shared file lexical.
#
# A FILE LEXICAL A NAMED SUB SHARES (PadAccess shared) is one variable read
# and written from several graphs, so it lives in memory, not in an SSA
# value: one `%Slot` module global, boxed on store and unboxed at each read
# to the reading's repr -- a Slot because its reads disagree (a counter is
# Num in the sub and Str where it is printed). The producer spells a second
# lexical of one name apart, so the symbol is the identity.
sub _lex_global_name {
    my ($self, $symbol) = @_;
    my $ident = "lex_$symbol";
    die "GAP: shared lexical global '\@$ident' is not a legal unquoted LLVM "
      . "identifier (\\w+)\n"
        unless $ident =~ /\A\w+\z/;
    return $self->{_lex_globals}{$symbol} = "\@$ident";
}

# _refuse_an_in_place_write_to_a_location($node, $op): die by name when
# $node writes a location's value in place -- `$s =~ s///`, `tr///`,
# `chop $s`, an lvalue `substr` -- rather than through an Assign (s/// on
# its own subject stores back; see _lower_regex_subst). The next
# read of the location is versioned at that write, but nothing stores its
# result back to the %Slot, so the read would see the value before it
# (`s/a/$n+1/e` left "abc" for perl's "2bc").
my %_IN_PLACE_WRITER   = map { $_ => 1 } qw(RegexSubst Transliterate Chomp ChompValue);
# (pos() is not one: setting it moves where the next m//g starts, not the string.)
my %_IN_PLACE_BUILTIN  = map { $_ => 1 } qw(chop chomp substr undef read sysread recv vec);
sub _refuse_an_in_place_write_to_a_location {
    my ($node, $op) = @_;
    my $writes = $_IN_PLACE_WRITER{$op}
        || ( $op eq 'Call' && ( $node->dispatch_kind // '' ) eq 'builtin'
             && $_IN_PLACE_BUILTIN{ $node->name // '' } );
    return unless $writes;
    # A 3-ARGUMENT substr READS: only the 4-argument form (an lvalue substr
    # arrives as it) writes (pvm 154).
    return if $op eq 'Call' && ( $node->name // '' ) eq 'substr'
        && ( grep { blessed($_) } $node->inputs->@* ) < 4;
    my @in = $node->inputs->@*;
    shift @in if $op eq 'RegexSubst' || $op eq 'Transliterate';   # its subject is stored back
    for my $in (grep { blessed($_) && $_->operation eq 'PadAccess' } @in) {
        die "GAP: " . ( $op eq 'Call' ? 'builtin ' . $node->name : $op )
          . " writing the location " . $in->name . " in place is not lowered\n"
            if $in->is_location;
    }
}

# _as_phi_reading($ref, $value_node, $phi, $what) -> $ref as the phi's repr
#
# A LOOP PHI'S TWO VALUES ARE READ AS THE PHI IS. `my $s = 0` carried
# through `$s + $x / 2` was a double phi over an i64 0, and `my $s; ...
# $s = $i` a %Slot phi over an undef's bare defined bit and an i64 counter:
# lli rejected both (backlog 22f3248c; pvm case 106). A Scalar phi boxes its
# values; any other widens along an arrow that keeps the value. Both ends may
# open blocks (a stringify does): each is lowered before its edge's label is
# taken.
sub _as_phi_reading {
    my ($self, $ref, $value_node, $phi, $what) = @_;
    return $ref unless blessed($value_node);
    my ($from, $to) = ( $value_node->stamp // '', $phi->stamp // '' );
    return $self->_build_slot($ref, '0', 'Undef', $what)
        if $to eq 'Scalar' && $from eq 'Undef';
    # An untyped side is left to the machine-type refusal that names it TOP.
    return $ref if $from eq $to || grep { $_ eq '' || $_ eq 'Unknown' } $from, $to;
    # An integer stringified is exact, and numified back is the same integer.
    return $self->_emit_coercion($ref, $from, $to, $what)
        if $from =~ /\A(?:Int|Num|Str|Boolean)\z/
        && ( $to eq 'Scalar' || ( $from eq 'Int' && $to eq 'Str' )
             || ( $to =~ /\A(?:Int|Num|Str)\z/ && _keeps_value($from, $to) ) );
    die "GAP: a loop phi read as a $to carries a $from ($what) -- no coercion "
      . "between them keeps the value\n"
        if ( eval { _repr_to_llvm_type($from) } // '' ) ne ( eval { _repr_to_llvm_type($to) } // '' );
    return $ref;
}

# _is_memory_version($node) -> true when $node is a state of memory (what a
# memory input names), not a value.
sub _is_memory_version {
    my ($node) = @_;
    my $op = $node->operation;
    return 1 if $op =~ /\A(?:MemStart|Assign|Call|RegexSubst|Transliterate|EntryWrite|CellWrite|Delete|ElemRestore)\z/;
    # an m//g writes pos(), so B::SoN versions memory at it
    return 1 if $op eq 'RegexMatch' && ( $node->flags // '' ) =~ /g/;
    return $op eq 'Phi' && _is_memory_phi($node) ? 1 : 0;
}

# _location_ptr($pad) -> the %Slot* a location PadAccess (is_location) is
# stored to and read from. A shared file lexical is its module global. A
# `my $x` kept in memory is one alloca per variable per graph INSTANCE --
# an inlined sub's `my $x` is not its caller's, nor its own last call's --
# allocated in the function's entry block (outside any loop) and set undef
# where its graph's lowering began, so each call, each pass of a loop the
# call sits in, starts it fresh as perl's `my` does.
sub _location_ptr {
    my ($self, $pad) = @_;
    return $self->_lex_global_name($pad->symbol) if $pad->shared;
    my $sym = $pad->symbol;
    return $self->{_local_slots}{$sym} if $self->{_local_slots}{$sym};
    my $slot = $self->_fresh;
    $self->_emit_entry("  $slot = alloca %Slot, align 8  ; my \$$sym, a location");
    push $self->{blocks}[ $self->{_graph_entry_idx} // 0 ]{insts}->@*,
        "  store %Slot zeroinitializer, %Slot* $slot  ; my \$$sym starts undef";
    return $self->{_local_slots}{$sym} = $slot;
}



# Ops that LOAD from a mutable memory location when lowered: a pad slot
# (PadAccess reads var_table), an aggregate element (Subscript), or an object
# field (FieldAccess). Their lowered value is program-point-dependent — a
# later store changes what an identical load returns — so they must re-lower
# at every consumption point, never serve from the value cache.
my %MUTABLE_READ_OPS = map { $_ => 1 } qw(PadAccess Subscript FieldAccess EntryDef);

# Pure value ops the staleness predicate descends THROUGH: a pure node over a
# mutable-location read is itself program-point-dependent (Add(PadAccess, 10)
# after a reassign must re-read). The walk stops at everything else — side
# effects (Assign/Call/RegexMatch/...) execute once at their control position
# and their result SSA ref is fixed; Phi/Constant/VarDecl/ArrayRef/HashRef
# likewise produce a fixed SSA value at a single program point.
my %PURE_DESCEND_OPS = map { $_ => 1 } qw(
    Add Subtract Multiply Divide Modulo Power Concat
    NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
    StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
    And Or DefinedOr Xor Not Negate Complement Defined UnaryPlus
    BitAnd BitOr BitXor LeftShift RightShift
    Coerce Interpolate Length Count PostfixDeref Ref RefType TernaryExpr
    Repeat Range IsaOp Slice
);

# The two tables above are being replaced by Chalk::IR::Node::staleness_kind,
# following the pattern step 1 used for is_fixed: the property lands on the
# type, the registry stays until a test pins that the two AGREE on every op the
# registry names, and only then is the registry deleted. These accessors exist
# so t/bootstrap/ir/node-staleness-kind.t can read the registries (which are
# my-scoped) to assert that agreement. They have no production consumer and go
# with the tables.
sub _mutable_read_ops { return sort keys %MUTABLE_READ_OPS }
sub _pure_descend_ops { return sort keys %PURE_DESCEND_OPS }

# _reads_mutable_location($node) -> bool
# True when lowering $node (or any pure node it transitively feeds on)
# performs a mutable-location load — i.e. when a cached SSA ref for it can
# go stale across a store (whole-branch review C1/C2). Structural property
# of the graph, so memoized per node id for the lifetime of this lowering.
sub _reads_mutable_location {
    my ($self, $node) = @_;
    my $id = $node->id();
    return $self->{_mut_read_memo}{$id}
        if exists $self->{_mut_read_memo}{$id};

    my $op = $node->operation();
    my $result = 0;
    if (exists $MUTABLE_READ_OPS{$op}) {
        $result = 1;
    }
    elsif (exists $PURE_DESCEND_OPS{$op}) {
        # Seed the memo before descending so an unexpected cycle terminates
        # (pure-op cycles do not occur; Phi backedges stop above).
        $self->{_mut_read_memo}{$id} = 0;
        INPUT: for my $input ($node->inputs()->@*) {
            my @flat = (ref($input) eq 'ARRAY') ? $input->@* : ($input);
            for my $el (@flat) {
                next unless defined $el && blessed($el);
                if ($self->_reads_mutable_location($el)) {
                    $result = 1;
                    last INPUT;
                }
            }
        }
    }
    return $self->{_mut_read_memo}{$id} = $result;
}

# lower_value($node) -> $llvm_ref (a string like "%tmp_1" or "1" for constants)
# Recursively lowers the data sub-graph rooted at $node, accumulating
# LLVM IR instructions into the current basic block. Returns the LLVM value
# reference (SSA name or immediate) for the node's result.
sub lower_value {
    my ($self, $node) = @_;

    # Argument binding for an inlined direct call (F5): while a callee is being
    # inlined at a call site, its positional argument reads (a `shift @_`) are
    # bound to the caller's already-lowered argument SSA refs. The binding is
    # keyed by the callee node's refaddr (its string id can collide with a
    # caller node's id — both graphs number `Call#N` from their own factory),
    # and consulted BEFORE the cache so the arg-read never reaches
    # _lower_builtin_shift_pop (which has no @_ array to drain). See
    # _lower_call_direct for how the frame is built and torn down.
    if ($self->{_arg_bind}) {
        my $bound = $self->{_arg_bind}{ refaddr($node) };
        if (defined $bound) {
            die "GAP: a code reference used other than by a call is not lowered\n"
                unless defined $bound->{ref};
            # THE CALLER'S VALUE IS COERCED TO THE CALLEE'S READING, never the
            # callee node restamped to the caller's. Analysis typed the
            # callee's consumers from that node's own stamp: restamping `$a`
            # from Num to Int left an Add and a NumGt built for doubles
            # reading an i64, and lli rejected the module. The callee graph
            # is shared by every call site, so it is not ours to rewrite.
            # UNKNOWN SAYS NOTHING of the value, so the caller's value stands
            # as it is: a `my ($h, $k) = @_` target nothing typed was refused
            # as "a coercion between them would not keep the value". Its
            # consumers read the caller's repr (_repr_of).
            return $bound->{ref} if ( $node->stamp // 'Unknown' ) eq 'Unknown';
            if (defined $bound->{repr} && defined $node->stamp
                    && $node->stamp ne $bound->{repr}) {
                die "GAP: an inlined argument is a $bound->{repr} where the "
                  . "callee reads a " . $node->stamp . " -- a coercion between "
                  . "them would not keep the value.\n"
                    unless _keeps_value($bound->{repr}, $node->stamp);
                return $self->_emit_coercion($bound->{ref}, $bound->{repr},
                    $node->stamp, 'inlined argument');
            }
            return $bound->{ref};
        }
    }

    # Cache: if we already lowered this node (hash-cons sharing), reuse the
    # previously computed SSA ref — except for nodes that read mutable
    # locations (directly or through pure ops).
    #
    # Such nodes are EXCLUDED from the cache-hit path: they must read the
    # current state at the moment they are lowered. var_table is updated by
    # Assign (and by phi emission at merge points), and aggregate elements /
    # object fields are updated by element/field stores, so a load for a
    # mutated location must see the post-store value, not a cached pre-store
    # SSA ref. Bypassing the cache ensures every such node re-lowers and is
    # always program-point-correct. See t/bootstrap/ir/llvm-reassign-soundness.t
    # for the adversarial proof of the PadAccess/var_table model across
    # straight-line, branch, and loop shapes, and
    # t/bootstrap/ir/llvm-stale-value-cache.t for the pure-over-read and
    # element/field store cases. Side-effecting ops STAY cached: they execute
    # once at their control position; re-lowering would double the effect.
    my $id = $node->id();
    my $op = $node->operation();
    _refuse_an_in_place_write_to_a_location($node, $op);
    # Memory-SSA: a Subscript with a memory input (inputs[2]) that has already
    # been frozen (_freeze_memory_reads emitted it at its memory version's
    # control position) is served from the cache -- its memory input fixes its
    # program point, so it is NOT program-point-ambiguous and must NOT re-read
    # (re-reading at the consumer would observe a LATER memory state). This is the
    # opposite of a bare mutable read (no memory input), which still re-reads.
    die "GAP: a value a block eval's body made, read after the eval -- where a die "
      . "leaves what it stored as it was, and nothing merges the two -- is not lowered" . ($ENV{DBG} ? " [$id]" : "") . "\n"
        if $self->{_past_a_died_eval}{$id} && exists $self->{cache}{$id};
    if ($op eq 'Subscript' && exists $self->{cache}{$id}
            && defined $node->inputs->[2]) {
        return $self->{cache}{$id};
    }
    # So is a FieldAccess _freeze_memory_reads froze. Only that one: a field
    # read at any other version (a call's, a Phi's) is cached where it was
    # first lowered, and served to a block that one does not dominate, lli
    # rejected the module.
    if (($op eq 'FieldAccess' || $op eq 'PadAccess' || $op eq 'EntryDef' || $op eq 'PostfixDeref') && $self->{_frozen_reads}{$id}
            && exists $self->{cache}{$id}) {
        return $self->{cache}{$id};
    }
    if (exists $self->{cache}{$id} && !$self->_reads_mutable_location($node)) {
        return $self->{cache}{$id};
    }

    if ($op eq 'Constant') {
        return $self->_lower_constant($node);
    }
    elsif ($op eq 'Add') {
        return $self->_lower_binop_int($node, 'add');
    }
    elsif ($op eq 'Subtract') {
        return $self->_lower_binop_int($node, 'sub');
    }
    elsif ($op eq 'Multiply') {
        return $self->_lower_binop_int($node, 'mul');
    }
    elsif ($op eq 'Divide') {
        return $self->_lower_divide($node);
    }
    elsif ($op eq 'Modulo') {
        return $self->_lower_modulo($node);
    }
    elsif ($op =~ /\ABit(And|Or|Xor)\z/) {
        return $self->_lower_bitop($node, lc $1);
    }
    elsif ($op eq 'ElemRestore') {
        return $self->_lower_elem_restore($node);
    }
    elsif ($op eq 'Power') {
        return $self->_lower_power($node);
    }
    elsif ($op eq 'Negate') {
        return $self->_lower_negate($node);
    }
    elsif ($op eq 'Repeat') {
        return $self->_lower_repeat($node);
    }
    elsif ($op =~ /\A(Left|Right)Shift\z/) {
        return $self->_lower_shift($node, $1 eq 'Left' ? 'shl' : 'lshr');
    }
    # ~ IS DONE ON BYTES when its operand is a string, and whether it is one
    # (or was once read as a number) is not on the wire.
    elsif ($op eq 'Complement') {
        die "GAP: a bitwise ~ is not lowered -- perl does it on bytes when its operand is a string\n";
    }
    elsif ($op eq 'Coerce') {
        return $self->_lower_coerce($node);
    }
    elsif ($op eq 'VarDecl') {
        return $self->_lower_vardecl($node);
    }
    elsif ($op eq 'PadAccess') {
        return $self->_lower_padaccess($node);
    }
    elsif ($op eq 'Assign' || $op eq 'CompoundAssign') {
        return $self->_lower_assign($node);
    }
    elsif ($op eq 'TernaryExpr') {
        return $self->_lower_ternary($node);
    }
    elsif ($op eq 'NumGt' || $op eq 'NumLt' || $op eq 'NumGe' || $op eq 'NumLe'
        || $op eq 'NumEq' || $op eq 'NumNe') {
        return $self->_lower_icmp_int($node);
    }
    elsif ($op eq 'StrEq' || $op eq 'StrNe') {
        return $self->_lower_str_compare($node, $op eq 'StrEq');
    }
    elsif ($op eq 'NumCmp') {
        return $self->_lower_num_cmp($node);
    }
    elsif ($op eq 'StrCmp') {
        return $self->_lower_str_cmp($node);
    }
    elsif ($op eq 'Not') {
        return $self->_lower_not($node);
    }
    elsif ($op eq 'And') {
        return $self->_lower_and($node);
    }
    elsif ($op eq 'Or') {
        return $self->_lower_or($node);
    }
    elsif ($op eq 'DefinedOr') {
        return $self->_lower_defined_or($node);
    }
    elsif ($op eq 'Defined') {
        return $self->_lower_defined($node);
    }
    elsif ($op eq 'Concat') {
        return $self->_lower_concat($node);
    }
    elsif ($op eq 'Phi') {
        return $self->_lower_phi($node);
    }
    elsif ($op eq 'If') {
        return $self->_lower_if($node);
    }
    elsif ($op eq 'Region') {
        return $self->_lower_region($node);
    }
    elsif ($op eq 'Proj') {
        return $self->_lower_proj($node);
    }
    elsif ($op eq 'Loop') {
        return $self->_lower_loop($node);
    }
    elsif ($op eq 'ArrayLiteral') {
        return $self->_lower_array_ref($node);
    }
    elsif ($op eq 'HashLiteral') {
        return $self->_lower_hash_ref($node);
    }
    elsif ($op eq 'Length') {
        return $self->_lower_length($node);
    }
    # Count lowers through the SAME path Length used for an aggregate operand.
    # The split was about which QUESTION the node asks (characters in a string
    # vs elements in a container), not about how the count is computed -- so
    # this is one dispatch line, not a new lowering.
    elsif ($op eq 'Count') {
        return $self->_lower_length($node);
    }
    elsif ($op eq 'ListAppend') {
        return $self->_lower_list_append($node);
    }
    elsif ($op eq 'Parameter') {
        return $self->_lower_parameter($node);
    }
    elsif ($op eq 'Subscript') {
        return $self->_lower_subscript($node);
    }
    elsif ($op eq 'PostfixDeref') {
        return $self->_lower_postfix_deref($node);
    }
    # FieldAccess in a method body context: load from $self's struct
    elsif ($op eq 'FieldAccess' && $self->{_in_method_body}) {
        return $self->_lower_field_access_in_method($node);
    }
    # RefType (ref($x)): reads the type/class name of a reference. Over an Object
    # it is the class name (statically the object's class); other reference kinds
    # (ref([...]) -> "ARRAY") are not yet lowered and stay an honest GAP. This is
    # distinct from Ref (the \ operator, a reference constructor): ref() takes a
    # reference and yields a Str, \ takes a value and yields a reference.
    elsif ($op eq 'RefType' && defined $node->inputs->[0]
        && defined $node->inputs->[0]->stamp
        && $node->inputs->[0]->stamp eq 'Object') {
        return $self->_lower_ref_of_object($node);
    }
    # Call(dispatch_kind='method'): vtable-slot dispatch, canonical form of MethodCall.
    # inputs[0] = invocant (obj node); the class rides as the class_name attr.
    # name = method name. return repr from node->stamp.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'method') {
        return $self->_lower_call_method($node);
    }
    # Call(dispatch_kind='direct'): a direct named-sub call. The callee graph
    # was resolved by the loader (target, a MOP::Sub). F1 handles the no-argument
    # form: inline the callee's result subgraph at this call site.
    # ponytail: inline no-arg callee; a real LLVM `define`+`call` and argument
    # binding land when F3 (arg-passing direct calls) is implemented.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'direct') {
        return $self->_lower_call_direct($node);
    }
    # Call(dispatch_kind='builtin'): a Perl builtin. shift/pop remove and return
    # an element from a mutable %Array (the array-drain primitives).
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin'
            && defined $node->name && ($node->name eq 'shift' || $node->name eq 'pop')) {
        return $self->_lower_builtin_shift_pop($node);
    }
    # Call(builtin, push): append to a mutable %Array.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin'
            && defined $node->name && $node->name eq 'push') {
        return $self->_lower_builtin_push($node);
    }
    # Call(builtin, sort): the operand's elements, ordered.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin'
            && defined $node->name && $node->name eq 'sort') {
        return $self->_lower_builtin_sort($node);
    }
    # Call(builtin, keys): the hash's keys as an %Array of %Slot.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin'
            && defined $node->name && $node->name =~ /\A(?:keys|values)\z/) {
        return $self->_lower_builtin_keys($node);
    }
    # Call(builtin, join): the separator plus the list's elements, in order.
    # Lowerable only when the list argument's ARITY IS STATIC -- see
    # _lower_builtin_join, which refuses otherwise rather than guessing a count.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin'
            && defined $node->name && $node->name eq 'join') {
        return $self->_lower_builtin_join($node);
    }
    # Call(builtin, exit): set the process exit status and abort. A program has
    # no return value — its observable contract is stdout plus exit status — so
    # `exit` is not a value-producing call at all; it terminates the block, the
    # same shape `die` uses (see _emit_unwind_terminator, which is this with a
    # hardcoded 255).
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin'
            && defined $node->name && $node->name eq 'exit') {
        return $self->_lower_builtin_exit($node);
    }
    # RegexMatch: lower a literal pattern to a runtime-free matcher (G6).
    # inputs[0] = subject (Str, i8* + tracked len); pattern is a compile-time
    # literal attr. Produces an i1 matched? (Boolean repr).
    elsif ($op eq 'RegexMatch') {
        return $self->_lower_regex_match($node);
    }
    # RegexSubst: s/// = match + splice (prefix + replacement(+$N) + suffix).
    # Produces the result string (i8*, runtime length in _str_len_table).
    elsif ($op eq 'Transliterate') {
        return $self->_lower_transliterate($node);
    }
    elsif ($op eq 'TransliterateCount') {
        my $tr = $node->inputs->[0];
        $self->lower_value($tr);
        return $self->{cache}{$id} = $self->{cache}{ 'trcount:' . $tr->id }
            // die "GAP: a tr/// count whose tr/// was not lowered here\n";
    }
    elsif ($op eq 'RegexSubst') {
        return $self->_lower_regex_subst($node);
    }
    elsif ($op eq 'RegexSubstCount') {
        return $self->_lower_regex_subst_count($node);
    }
    # Print: a control-pinned statement effect. Emit each list arg to stdout
    # (Str via printf("%.*s"), Int via printf("%d")); print yields boolean 1.
    elsif ($op eq 'Print') {
        return $self->_lower_print($node);
    }
    # Match (=~ with a compiled-regex VALUE, i.e. qr//): the rhs is a
    # Constant(const_type='regex') whose pattern is compile-time known; the
    # lowering resolves it statically and inlines the same matcher.
    elsif ($op eq 'Match') {
        return $self->_lower_match_apply($node);
    }
    # RegexCapture ($N magic var): a slot of the match node's result — a
    # zero-copy {ptr,len} view into the subject at the captured offsets.
    elsif ($op eq 'RegexCapture') {
        return $self->_lower_regex_capture($node);
    }
    # EnvRead (%ENV{key}): host process state via the C getenv — not libperl.
    elsif ($op eq 'EnvRead') {
        return $self->_lower_env_read($node);
    }
    # EntryDef (`our $g`): a package/global scalar read — load the module-level
    # i64 slot. A mutable-location read (in %MUTABLE_READ_OPS), so it re-lowers at
    # every use and observes the post-store value.
    elsif ($op eq 'EntryDef') {
        return $self->_lower_stash_access($node);
    }
    elsif ($op eq 'EntryWrite') {
        return $self->_lower_entry_write($node);
    }
    elsif ($op eq 'Ref') {
        return $self->_lower_ref($node);
    }
    elsif ($op eq 'Exists') {
        return $self->_lower_exists($node);
    }
    # time: the C clock, seconds since the epoch.
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'time') {
        $self->{_need_time} = 1;
        my $t = $self->_fresh;
        $self->_emit("  $t = call i64 \@time(i64* null)  ; time");
        return $self->{cache}{$id} = $t;
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin'
            && ($node->name // '') =~ /\A(?:uc|lc|ucfirst|lcfirst)\z/) {
        return $self->_lower_case_map($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin'
            && ($node->name // '') =~ /\A(?:open|close|readline|eof)\z/) {
        return $self->_lower_handle_op($node);
    }
    elsif ($op eq 'CellWrite') {
        my ($cell, $v) = $node->inputs->@[0, 1];
        my $ptr = $self->_cell_storage($cell);
        my $from = $self->_repr_of($v) // $v->stamp // '';
        my $val = $self->lower_value($v);
        $val = $self->_emit_coercion($val, $from, 'Scalar', 'store to a captured variable') if $from ne 'Scalar';
        $self->_emit("  store %Slot $val, %Slot* $ptr  ; store to a captured variable");
        return $self->{cache}{ $node->id } = $val;
    }
    elsif ($op eq 'CellRead' && blessed($node->inputs->[0]) && $node->inputs->[0]->operation eq 'MakeCell') {
        my $slot = $self->_fresh;
        $self->_emit("  $slot = load %Slot, %Slot* " . $self->_cell_storage($node->inputs->[0]) . "  ; read a captured variable");
        return $slot;
    }
    elsif ($op eq 'AnonSub') {
        die "GAP: a code reference used as a value -- not called where it is made -- is not lowered\n";
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'reverse') {
        return $self->_lower_reverse($node);
    }
    # `xor`: true when exactly one side is, by perl's truth for each.
    elsif ($op eq 'Xor') {
        my ($l, $r) = map {
            my $v = $self->lower_value($_);
            $self->_ensure_i1($v, $_->operation eq 'Print' ? 'Boolean' : ( $self->_repr_of($_) // _require_repr($_, 'Xor operand') ));
        } $node->inputs->@[0, 1];
        my $x = $self->_fresh;
        $self->_emit("  $x = xor i1 $l, $r  ; xor");
        return $self->{cache}{ $node->id } = $x;
    }
    elsif ($op eq 'Delete') {
        return $self->_lower_delete($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'sprintf') {
        return $self->_lower_sprintf($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'formline') {
        return $self->_lower_formline($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'pos') {
        return $self->_lower_pos($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'split') {
        return $self->_lower_split($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'indirect') {
        return $self->_lower_call_indirect($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'select') {
        return $self->_lower_select($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'sselect') {
        return $self->_lower_sselect($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'bless') {
        return $self->_lower_bless($node);
    }
    elsif ($op eq 'Call' && ($node->dispatch_kind // '') eq 'builtin' && ($node->name // '') eq 'substr') {
        return $self->_lower_substr($node);
    }
    # AN ARRAY SLICE OR A RANGE WALKED AS A CONTAINER -- `grep { } @a[...]`
    # is Count(Slice) and Subscript(Slice, $i) -- is the list made once, a
    # fresh array (a range's numbers are no one's to alias). perl's $_ there is the array's own element, so one that is
    # stored to, referenced or passed would be a copy: refused.
    elsif (( $op eq 'Slice' || $op eq 'Range' ) && _is_walked_list($node)) {
        for my $el (grep { blessed($_) && $_->operation eq 'Subscript' } ($node->consumers // [])->@*) {
            die "GAP: an element of an array slice walked by grep or map is written, referenced "
              . "or passed -- perl aliases the array's element, and the walk here is of a copy\n"
                if grep { blessed($_) && ( $_->operation eq 'Ref'
                    || ( $_->operation eq 'Assign' && blessed($_->inputs->[0]) && $_->inputs->[0] == $el )
                    || ( $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) ne 'builtin' ) ) }
                    ($el->consumers // [])->@*;
        }
        return $self->{cache}{ $node->id } = $self->_emit_flattened_array_of([$node]);
    }
    elsif ($op eq 'LocalAlias') {
        return $self->_lower_local_alias($node);
    }
    elsif ($op eq 'Increment') {
        return $self->_lower_increment($node);
    }
    elsif ($op eq 'RefType') {
        return $self->_lower_reftype($node);
    }
    # Statement-effect ops that carry per-call identity (they are in
    # %STATEMENT_EFFECT_OPS, so the control collectors route them here) but
    # have no runtime-free lowering yet. An honest GAP names the op so the
    # corpus L-corner records a gap-map entry rather than misdirecting with a
    # generic backend error (whole-branch review I1):
    #   NotMatch     — !~ ; the negated-match runtime-free path is unbuilt
    #                  (RegexMatch/Match exist; NotMatch is their negation).
    #   BacktickExpr — qx`` ; command execution is a host-process effect.
    #   TryCatch     — try/catch ; needs LLVM landingpad + a personality fn.
    elsif ($op eq 'NotMatch') {
        die "GAP: op=NotMatch (!~) is not lowered runtime-free yet — the "
          . "negated-match path is unbuilt (RegexMatch/Match are; NotMatch "
          . "is their negation).";
    }
    elsif ($op eq 'BacktickExpr') {
        die "GAP: op=BacktickExpr (qx``) is not lowered runtime-free — "
          . "command execution is a host-process effect (a future host tier).";
    }
    elsif ($op eq 'TryCatch') {
        die "GAP: op=TryCatch (try/catch) is not lowered runtime-free yet — "
          . "needs an LLVM landingpad + personality function for exception "
          . "unwind.";
    }
    else {
        # A CALL IS NAMED BY WHAT IT CALLS: "op=Call" alone pooled forty
        # different builtins into one refusal, and said nothing of which.
        my $what = $op;
        $what = "Call " . ($node->can('dispatch_kind') ? ($node->dispatch_kind // '?') : '?')
              . " " . $node->name
            if $op eq 'Call' && $node->can('name') && defined $node->name;
        if (defined $node->stamp && $node->stamp eq 'Scalar') {
            die "node op=$what repr=Scalar reached LLVM backend — cannot lower runtime-free. "
              . "This value requires libperl; it is a GAP on the L corner.";
        }
        die "LLVM backend: cannot lower op=$what (not in literal-arithmetic slice)";
    }
}

sub _lower_constant {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    my $val  = $node->value;

    if (!defined $repr) {
        # Undef representation: the TypeInference pass did not annotate this node.
        # Die loudly instead of silently defaulting to Int — this masks upstream
        # TypeInference bugs as plausible integer output (F7 fix / G.6).
        # Consistent with _ensure_i1 which already dies on undef-repr inputs.
        die "Constant node has no representation at lowering time "
          . "(value=${\(defined $val ? $val : 'undef')}). "
          . "Fix TypeInference to annotate this node, or set the representation explicitly.";
    }
    if ($repr eq 'Scalar') {
        die "Constant node with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    if ($repr eq 'Int') {
        # Int constant -> i64 immediate via add i64 0, VALUE. Emit into the ENTRY
        # block: a constant is pure and, when hash-consed across blocks (e.g. an
        # index shared by a branch-guarded store and a post-merge read, memory-SSA
        # 2b), a branch-local emit would not dominate the post-merge use. Entry
        # placement dominates all uses.
        my $ref = $self->_fresh;
        $self->_emit_entry("  $ref = add i64 0, $val          ; Constant($val, repr=Int -> i64)");
        $self->{cache}{$node->id} = $ref;
        return $ref;
    }
    elsif ($repr eq 'Boolean') {
        # Boolean constant -> i1 immediate. A folded comparison (1 < 2) reaches
        # here as a Boolean Constant; Perl's true is 1, false is the empty
        # string, so any truthy value lowers to i1 1 and a falsy one to i1 0.
        my $bit = (defined $val && $val ne '' && $val ne '0') ? 1 : 0;
        my $ref = $self->_fresh;
        $self->_emit("  $ref = add i1 0, $bit            ; Constant(repr=Boolean -> i1)");
        $self->{cache}{$node->id} = $ref;
        return $ref;
    }
    elsif ($repr eq 'Num') {
        # Num constant -> double immediate.
        #
        # A float whose value is INTEGRAL arrives here as a bare integer literal
        # (`1e3` and `2.0` both reach us as "1000" / "2"), and LLVM rejects an
        # integer constant in a double operand: "integer constant must have
        # integer type". Give it a fractional part so it is typed as a double.
        # Measured: `say 1e3` emitted `fadd double 0.0, 1000` and lli refused
        # to run the module at all.
        my $ty   = _repr_to_llvm_type($repr);
        my $zero = _repr_zero($repr);
        my $op   = _repr_opcode('add', $repr);
        # The `.0` suffix is itself a representation decision -- an integral
        # machine type must NOT get one -- so it is gated on the same predicate
        # the opcode and the zero are, not on the repr's name.
        my $dval = (_repr_is_float($repr) && $val =~ /\A-?\d+\z/) ? "$val.0" : $val;
        my $ref = $self->_fresh;
        $self->_emit("  $ref = $op $ty $zero, $dval    ; Constant($val, repr=Num -> $ty)");
        $self->{cache}{$node->id} = $ref;
        return $ref;
    }
    elsif ($repr eq 'Str') {
        # Str constant -> private global + GEP to get i8* ptr.
        # The Str representation is {ptr, len, encoding}; here encoding=0 (ASCII/default).
        # We track the ptr as the SSA value and record the byte-length in _str_len_table.
        # The private global is emitted in the module prologue.
        #
        # For a Constant node whose value is the string content (e.g., "hello"),
        # the byte length = length($val) (UTF-8 byte count; all corpus cases are ASCII).
        # The name-constant Constant("s") :Str for VarDecl names is also Str repr but
        # should not be printed — it is used only as a VarDecl name marker. We lower
        # it to the same ptr-to-global pattern; the len is tracked but unused for names.
        # Allocate a unique global name + byte length for this string constant.
        # The symbol-prefix rule (I1) and byte-length computation live in the
        # shared _module_global_name helper. The name-constant Constant("s") :Str
        # for VarDecl names is also Str repr but should not be printed — it is
        # used only as a VarDecl name marker. We lower it to the same
        # ptr-to-global pattern; the len is tracked but unused for names.
        # A CHARACTER PAST ASCII IS REFUSED. chalk's strings are bytes, and
        # perl's length, substr and case mapping act on characters: `length
        # "\x{e9}"` is 1. The emitted constant's size also disagreed with its
        # bytes, and lli rejected the module. Until strings carry character
        # semantics this is a GAP, not a byte-counted answer.
        die "GAP: a string constant with a character past ASCII is not lowered -- "
          . "chalk's strings are bytes; perl's length, substr and case act on characters\n"
            if $val =~ /[^\x00-\x7F]/;
        my ($gname, $byte_len, $total) = $self->_module_global_name('str_const', $val);

        # GEP to get i8* from the global array. Emit into the ENTRY block: the
        # GEP is a pure pointer to a module global, and a hash-consed Str constant
        # shared across blocks (the SAME literal in both arms of an if/else, e.g.
        # `if(C){print "x"}else{print "x"}`) would, if emitted branch-locally, not
        # dominate the sibling arm's use (lli: "Instruction does not dominate all
        # uses"). Entry placement dominates every use. Same rule as the Int/Boolean
        # constant cases above.
        my $ref = $self->_fresh;
        # Sanitize the comment text: a control byte (e.g. a newline in the
        # string value) would split the IR line and break the module.
        (my $val_cmt = $val) =~ s/[^\x20-\x7e]/./g;
        $self->_emit_entry("  $ref = getelementptr inbounds [$total x i8], [$total x i8]* $gname, i64 0, i64 0  ; Constant(\"$val_cmt\", Str) -> i8* ptr");

        # Record the byte-length as a compile-time literal for the output epilogue.
        # PILOT of the %Str flip: this producer now returns the AGGREGATE rather
        # than the bare pointer. _set_str_len still records the length so the
        # side table stays consistent for producers not yet converted; the value
        # handed to consumers is the struct, and _str_parts destructures it.
        # entry => 1: a Str constant's GEP is hoisted to the entry block so it
        # dominates every use (two if/else arms may share one hash-consed Str
        # constant), and the aggregate built from it must be hoisted for the
        # same reason.
        my $strv = $self->_set_str_len($ref, $byte_len, entry => 1);

        $self->{cache}{$node->id} = $strv;
        return $strv;
    }
    elsif ($repr eq 'Undef') {
        # Undef constant -> an i1 defined-bit of false (0).
        #
        # The Undef representation carries a single i1 "defined" bit. For a
        # Constant(undef), that bit is always false (= not defined). We emit
        # it via alloca+store+load so the value is RUNTIME-opaque: an LLVM
        # optimizer cannot constant-fold or dead-code-eliminate the branch in
        # DefinedOr even with -O3, because the alloca/store/load sequence is
        # a memory-barrier that defeats scalar replacement without mem2reg.
        #
        # The "payload" (what the variable holds when it is defined) is not
        # needed for a Constant(undef): the defined bit is always false, so
        # the payload is never read. We still record a payload of i64 0 in
        # _undef_payload so that DefinedOr can phi-merge the LHS payload
        # when the defined path is taken (the optimizer will eliminate the
        # dead path but the IR must be well-formed).
        my $slot = $self->_fresh;
        $self->_emit("  $slot = alloca i1                            ; Constant(undef): defined-bit slot");
        $self->_emit("  store i1 false, i1* $slot                   ; Constant(undef): store false = not defined");
        my $defined_bit = $self->_fresh;
        $self->_emit("  $defined_bit = load i1, i1* $slot           ; Constant(undef): load defined bit (runtime-opaque)");

        # Record the defined bit so DefinedOr can retrieve it.
        $self->{_undef_defined_bit}{ $node->id } = $defined_bit;
        # Payload for undef LHS: i64 0 (never read on the undef path).
        my $payload = $self->_fresh;
        $self->_emit("  $payload = add i64 0, 0                     ; Constant(undef): payload i64 0 (never used)");
        $self->{_undef_payload}{ $node->id } = $payload;

        # The canonical SSA ref for an Undef-typed node is its defined bit (i1).
        # DefinedOr retrieves the payload via _undef_payload when needed.
        $self->{cache}{ $node->id } = $defined_bit;
        return $defined_bit;
    }
    else {
        die "LLVM backend: cannot lower Constant with repr=$repr";
    }
}

# The loader's repr-join (Serialize::JSON _propagate_computed_reprs) already
# widens an Add/Subtract/Multiply over any Num operand to Num; the backend must
# then emit whatever instruction that representation's machine type calls for,
# and bring each operand to that type first.
#
# The op table that stood here (%_INT_TO_FLOAT_OP: add=>fadd, sub=>fsub,
# mul=>fmul) is now %_FLOAT_OPCODE beside %_REPR_LLVM_TYPE, reached through
# _repr_opcode. Here it was keyed by the mnemonic ALONE, so the representation
# entered only through a `$repr eq 'Num'` branch that hardcoded `double` next
# to it -- the machine type asserted at the site rather than asked for.

sub _lower_binop_int {
    my ($self, $node, $llvm_op) = @_;

    my $repr = $node->stamp;
    my $op   = $node->operation;
    unless (defined $repr) {
        die "$op node has no representation at lowering time. "
          . "Fix TypeInference to annotate this node (G.6/F7).";
    }
    die "$op with repr=Scalar reached LLVM backend" if $repr eq 'Scalar';

    my $inputs  = $node->inputs;

    # The result's representation decides BOTH the machine type and the
    # instruction; neither is named here. A Num-repr arithmetic op (the
    # repr-join widened it because at least one operand is Num — e.g. a Num-init
    # loop accumulator `$s=$s+$x`) currently lands on `fadd double` because
    # %_REPR_LLVM_TYPE maps Num to double, and each operand is brought to that
    # type first. An `add i64` over a double operand is invalid IR (lli verify:
    # "double but expected i64"). 019f63e9.
    #
    # The single branch that used to read `if ($repr eq 'Num')` is gone: were
    # Num to map to an integral type, _repr_opcode would return the integer
    # mnemonic and _lower_as_repr would emit no conversion, with no edit here.
    my $ty     = _repr_to_llvm_type($repr);
    my $opcode = _repr_opcode($llvm_op, $repr);

    my $lhs_ref = $self->_lower_as_repr($inputs->[0], $repr);
    my $rhs_ref = $self->_lower_as_repr($inputs->[1], $repr);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = $opcode $ty $lhs_ref, $rhs_ref  ; $op(repr=$repr) -> $ty $opcode");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# _lower_as_repr($node, $want) -> an SSA ref for $node in representation $want's
# machine type, emitting a conversion only when the two machine types differ.
#
# Replaces _lower_as_double, whose NAME presumed the answer: it could only ever
# bring an operand to a double, so a caller had already decided the destination
# was floating-point before asking. Here the destination is a REPRESENTATION and
# the instruction (if any) comes from _repr_convert_op.
#
# An operand with no representation at all is treated as already being in the
# destination's type -- the pre-existing behaviour on the integer path, where
# a bare untyped operand was passed to `add i64` unconverted.
sub _lower_as_repr {
    my ($self, $node, $want) = @_;
    my $ref  = $self->lower_value($node);
    my $orep = (ref($node) && $node isa Chalk::IR::Value)
        ? $node->stamp : undef;

    # A bare untyped operand feeding a float-typed op still needs promoting:
    # its SSA value is an integer one. This mirrors _lower_as_double, which
    # sitofp'd exactly this case.
    $orep //= _repr_is_float($want) ? 'Int' : $want;

    my $conv_op = _repr_convert_op($orep, $want) or return $ref;
    my $from_ty = _repr_to_llvm_type($orep);
    my $to_ty   = _repr_to_llvm_type($want);
    my $conv    = $self->_fresh;
    $self->_emit("  $conv = $conv_op $from_ty $ref to $to_ty  ; promote $orep operand to $want for $want arithmetic");
    return $conv;
}

sub _lower_divide {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    my $op   = $node->operation;

    # Divide with Int representation is a correctness trap: Perl `/` is always
    # floating-point division (3/4 == 0.75), not truncating integer division.
    # An Int-repr Divide would silently emit sdiv which miscompiles vs perl.
    # The correct path: give the Divide node Num representation and Coerce the
    # Int operands to Num before dividing.
    if (!defined $repr || $repr eq 'Int') {
        die "GAP: op=Divide with repr=" . ($repr // 'undef')
          . " — Perl `/` is float division; lower as Num (fdiv double) not i64 sdiv. "
          . "Set Divide representation to 'Num' and Coerce Int operands to Num.";
    }
    if ($repr eq 'Scalar') {
        die "Divide with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    # Each operand is brought to the result's representation via _lower_as_repr
    # first -- an Int operand (e.g. a Num-init loop divisor, or plain `$a/$b`
    # where both are Int) would otherwise feed a raw i64 to fdiv, which lli
    # rejects ("defined with type 'i64' but expected 'double'"). Mirrors
    # _lower_binop_int.
    #
    # The machine type is asked for; the FLOAT-ness of the division is not, and
    # deliberately so. Perl `/` is float division as a matter of SEMANTICS
    # (3/4 == 0.75), which is why the Int arm above is a GAP rather than an
    # `sdiv`. If Num were ever mapped to an integral type, this site must FAIL
    # rather than quietly pick `sdiv` -- so it asserts the representation it
    # needs instead of dispatching on it. That assertion is the guard the
    # Int-repr GAP above would otherwise lose.
    die "GAP: op=Divide at repr=$repr, whose machine type is "
      . _repr_to_llvm_type($repr) . " — Perl `/` is float division, so this "
      . "representation cannot carry a Divide result. An integral machine type "
      . "here would emit truncating division and miscompile against perl."
        unless _repr_is_float($repr);

    my $ty      = _repr_to_llvm_type($repr);
    my $inputs  = $node->inputs;
    my $lhs_ref = $self->_lower_as_repr($inputs->[0], $repr);
    my $rhs_ref = $self->_lower_as_repr($inputs->[1], $repr);

    $self->_die_on_zero($inputs->[1], $rhs_ref, $ty, 'Illegal division by zero');
    my $ref = $self->_fresh;
    $self->_emit("  $ref = fdiv $ty $lhs_ref, $rhs_ref  ; Divide(repr=$repr) -> fdiv $ty");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# _die_on_zero($divisor, $ref, $ty, $msg) -- perl dies on a zero divisor
# ("Illegal division by zero"): exit 255, as its die does. A literal nonzero
# divisor cannot be zero. Inside an eval perl catches it, with " at FILE line
# N." in $@ -- refused there.
sub _die_on_zero {
    my ($self, $divisor, $ref, $ty, $msg) = @_;
    my $lit = $divisor;
    $lit = $lit->inputs->[0] while blessed($lit) && $lit->operation eq 'Coerce';
    return if blessed($lit) && $lit->operation eq 'Constant'
        && ($lit->const_type // '') =~ /\A(?:integer|number)\z/ && ($lit->value // 0) != 0;
    die "GAP: a divisor that may be zero, inside a block eval, is not lowered -- "
      . "perl's \"$msg\" message there names the file and line\n"
        if ($self->{_eval_frames} // [])->@*;
    my ($z, $die, $ok) = ($self->_fresh, $self->_fresh_label('divzero'), $self->_fresh_label('divok'));
    my $cmp = $ty eq 'i64' ? "icmp eq i64 $ref, 0" : "fcmp oeq $ty $ref, " . _repr_zero('Num');
    $self->_emit("  $z = $cmp  ; a zero divisor?");
    $self->{_need_exit} = 1;
    $self->_set_terminator("  br i1 $z, label %$die, label %$ok");
    $self->_new_block($die);
    $self->_emit("  call void \@exit(i32 255)  ; $msg");
    $self->_set_terminator("  unreachable");
    $self->_new_block($ok);
    return;
}

# _lower_bitop($node, 'and'|'or'|'xor') -> i64: `&` `|` `^` on numbers.
#
# PERL DOES THEM ON NUMBERS when the bitwise feature says so (flavor
# numeric), or when an operand has a number in it -- a literal surely does.
# Otherwise on two strings it combines their bytes, and whether a variable
# holds a number or a string (one a number was once read from counts as a
# number) is not on the wire: refused. Its result is unsigned: one past
# what an i64 holds stops the program, unless another bitwise op takes it.
sub _lower_bitop {
    my ($self, $node, $llop) = @_;
    my @in = $node->inputs->@[0, 1];
    my $is_number = sub ($n) {
        $n = $n->inputs->[0] while blessed($n) && $n->operation eq 'Coerce';
        blessed($n) && $n->operation eq 'Constant' && ( $n->const_type // '' ) =~ /\A(?:integer|number)\z/;
    };
    die "GAP: a bitwise " . $node->op_str . " that perl may do on strings (no number among its "
      . "operands, no bitwise feature) is not lowered\n"
        unless ( $node->flavor // '' ) eq 'numeric' || grep { $is_number->($_) } @in;
    my @v = map {
        my $s = $self->_repr_of($_) // $_->stamp // '';
        my $r = $self->lower_value($_);
        $s eq 'Int' ? $r : $self->_emit_coercion($r, $s, 'Int', 'a bitwise operand');
    } @in;
    my $ref = $self->_fresh;
    $self->_emit("  $ref = $llop i64 $v[0], $v[1]  ; " . $node->op_str);
    unless (grep { blessed($_) && $_->operation =~ /\ABit(?:And|Or|Xor)\z/ } ($node->consumers // [])->@*
            and !grep { blessed($_) && $_->operation !~ /\ABit(?:And|Or|Xor)\z/ } ($node->consumers // [])->@*) {
        $self->_refuse_inside_eval("a bitwise result past what an integer holds");
        my ($big, $stop, $ok) = ($self->_fresh, $self->_fresh_label('bit.big.'), $self->_fresh_label('bit.ok.'));
        $self->_emit("  $big = icmp slt i64 $ref, 0  ; unsigned past an i64?");
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $big, label %$stop, label %$ok");
        $self->_new_block($stop);
        $self->_emit("  call void \@exit(i32 255)  ; an unsigned bitwise result an i64 cannot hold");
        $self->_set_terminator("  unreachable");
        $self->_new_block($ok);
    }
    return $self->{cache}{ $node->id } = $ref;
}

# _operand_as($node, $repr, $what) -> $node lowered and coerced to $repr.
sub _operand_as {
    my ($self, $n, $to, $what) = @_;
    my $s = $self->_repr_of($n) // $n->stamp // '';
    my $r = $self->lower_value($n);
    return $s eq $to ? $r : $self->_emit_coercion($r, $s, $to, $what);
}

# _stop_unless($ok_i1, $what) -- the program stops (exit 255) where $ok is
# false: a value perl has that chalk's representation does not.
sub _stop_unless {
    my ($self, $ok, $what) = @_;
    $self->_refuse_inside_eval($what);
    my ($go, $stop) = ($self->_fresh_label('ok.'), $self->_fresh_label('stop.'));
    $self->{_need_exit} = 1;
    $self->_set_terminator("  br i1 $ok, label %$go, label %$stop");
    $self->_new_block($stop);
    $self->_emit("  call void \@exit(i32 255)  ; $what");
    $self->_set_terminator("  unreachable");
    $self->_new_block($go);
    return;
}

# _local_restore_of($assign) -> the ElemRestore that puts back the element a
# `local` store writes: the same container and key (its memory is whatever
# version the scope ends at, not the store).
sub _local_restore_of {
    my ($a) = @_;
    my $lhs = $a->inputs->[0];
    return () unless blessed($lhs) && $lhs->operation eq 'Subscript';
    my ($c, $k) = $lhs->inputs->@[0, 1];
    return grep { blessed($_) && $_->operation eq 'ElemRestore'
                  && refaddr($_->inputs->[0]) == refaddr($c) && refaddr($_->inputs->[1]) == refaddr($k) }
        ($c->consumers // [])->@*;
}

# _lower_elem_restore($node): where a `local $h{k}` scope ends, the element
# B::SoN read before the local store goes back -- or, absent then, the key
# goes (perl deletes it). inputs: container, key, saved value, existed, memory.
sub _lower_elem_restore {
    my ($self, $node) = @_;
    my ($ctr, $key, $saved, $existed) = $node->inputs->@[0 .. 3];
    die "GAP: putting back a local array element is not lowered\n"
        unless ( $node->kind // '' ) eq 'hash';
    $self->{$_} = 1 for qw(_need_aggregate_types _need_malloc_memcpy _need_memcmp _need_hash_delete);
    my $hash = $self->_container_ptr($ctr, 'Hash');
    my ($kp, $kl) = $self->_str_parts($self->_hash_key_str($key));
    my @v = $self->_slot_fields_of_value($saved, $self->lower_value($saved), 'local restore');
    my $had = $self->lower_value($existed);
    my ($put, $del, $done) = map { $self->_fresh_label("lrest.$_.") } qw(put del done);
    $self->_set_terminator("  br i1 $had, label %$put, label %$del");
    $self->_new_block($put);
    $self->_emit_hash_upsert($hash, $kp, $kl, @v);
    $self->_set_terminator("  br label %$done");
    $self->_new_block($del);
    my $gone = $self->_fresh;
    $self->_emit("  $gone = call %Slot \@chalk_hash_delete(%Hash* $hash, i8* $kp, i64 $kl)  ; local: the key was not there");
    $self->_set_terminator("  br label %$done");
    $self->_new_block($done);
    return $self->{cache}{ $node->id } = '';
}

# _lower_negate($node) -> unary minus on a number: Int `sub 0, x`, Num fneg.
# On a string perl negates the text (-"abc" is "-abc"): a string operand is
# refused, one read by its tag stops the program when its tag is a string.
sub _lower_negate {
    my ($self, $node) = @_;
    my $x = $node->inputs->[0];
    my $o = $x;
    $o = $o->inputs->[0] while blessed($o) && $o->operation eq 'Coerce';
    my $os = $self->_repr_of($o) // $o->stamp // '';
    die "GAP: unary minus on a string is not lowered -- perl negates its text\n" if $os eq 'Str';
    if ($os =~ /\A(?:Scalar|Slot)\z/) {
        my $tag = $self->_slot_tag_of($self->lower_value($o));
        my ($s, $ok) = ($self->_fresh, $self->_fresh);
        $self->_emit("  $s = icmp eq i8 $tag, " . _slot_tag_value('Str') . "  ; -: a string?");
        $self->_emit("  $ok = xor i1 $s, true");
        $self->_stop_unless($ok, "unary minus on a string (perl negates its text)");
    }
    my $repr = ( $node->stamp // '' ) eq 'Int' ? 'Int' : 'Num';
    my $v = $self->_operand_as($x, $repr, '-');
    my $r = $self->_fresh;
    $self->_emit($repr eq 'Int' ? "  $r = sub i64 0, $v  ; -" : "  $r = fneg " . _repr_to_llvm_type('Num') . " $v  ; -");
    return $self->{cache}{ $node->id } = $r;
}

# _lower_power($node) -> double: perl's ** is a number, C's pow (an integer
# result prints as one under %.15g, as perl prints it).
sub _lower_power {
    my ($self, $node) = @_;
    my ($b, $e) = map { $self->_operand_as($_, 'Num', '**') } $node->inputs->@[0, 1];
    $self->{_need_pow} = 1;
    my $r = $self->_fresh;
    my $d = _repr_to_llvm_type('Num');
    $self->_emit("  $r = call $d \@pow($d $b, $d $e)  ; **");
    return $self->{cache}{ $node->id } = $r;
}

# _lower_repeat($node) -> Str: `$s x $n`, the string $n times (none for $n
# below 1). A list repeated -- `(1, 2) x 2` -- is refused.
sub _lower_repeat {
    my ($self, $node) = @_;
    my ($l, $n) = $node->inputs->@[0, 1];
    die "GAP: a list repeated (x on a list) is not lowered\n"
        unless ( $self->_repr_of($l) // $l->stamp // '' ) =~ /\A(?:Str|Int|Num|Scalar|Boolean)\z/;
    my ($p, $len) = $self->_str_parts($self->_operand_as($l, 'Str', 'x'));
    my $cnt = $self->_operand_as($n, 'Int', 'x count');
    $self->{_need_malloc_memcpy} = 1;
    my ($neg, $k, $tot, $sz, $buf, $ip) = map { $self->_fresh } 1 .. 6;
    $self->_emit("  $neg = icmp slt i64 $cnt, 0");
    $self->_emit("  $k = select i1 $neg, i64 0, i64 $cnt  ; x: none below 1");
    $self->_emit("  $tot = mul i64 $len, $k");
    $self->_emit("  $sz = add i64 $tot, 1");
    $self->_emit("  $buf = call i8* \@malloc(i64 $sz)  ; x: the repeated string");
    $self->_emit_entry("  $ip = alloca i64  ; x: copies made");
    $self->_emit("  store i64 0, i64* $ip");
    my ($head, $body, $done) = map { $self->_fresh_label("rep.$_.") } qw(head body done);
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    my ($i, $more) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $i = load i64, i64* $ip");
    $self->_emit("  $more = icmp slt i64 $i, $k");
    $self->_set_terminator("  br i1 $more, label %$body, label %$done");
    $self->_new_block($body);
    my ($off, $dst, $i1) = map { $self->_fresh } 1 .. 3;
    $self->_emit("  $off = mul i64 $i, $len");
    $self->_emit("  $dst = getelementptr inbounds i8, i8* $buf, i64 $off");
    $self->_emit("  call i8* \@memcpy(i8* $dst, i8* $p, i64 $len)");
    $self->_emit("  $i1 = add i64 $i, 1");
    $self->_emit("  store i64 $i1, i64* $ip");
    $self->_set_terminator("  br label %$head");
    $self->_new_block($done);
    return $self->{cache}{ $node->id } = $self->_set_str_len($buf, $tot);
}

# _lower_shift($node, 'shl'|'lshr') -> i64: << >> on numbers, unsigned. A
# count of 64 or more is 0. A negative operand or count, or a result past
# an i64 (perl's is unsigned), stops the program.
sub _lower_shift {
    my ($self, $node, $llop) = @_;
    my ($a, $c) = map { $self->_operand_as($_, 'Int', $node->op_str) } $node->inputs->@[0, 1];
    my ($ok_a, $ok_c, $ok) = map { $self->_fresh } 1 .. 3;
    $self->_emit("  $ok_a = icmp sge i64 $a, 0");
    $self->_emit("  $ok_c = icmp sge i64 $c, 0");
    $self->_emit("  $ok = and i1 $ok_a, $ok_c");
    $self->_stop_unless($ok, "a shift of a negative number or by a negative count");
    my ($big, $sh, $r) = map { $self->_fresh } 1 .. 3;
    $self->_emit("  $big = icmp uge i64 $c, 64");
    $self->_emit("  $sh = $llop i64 $a, $c");
    $self->_emit("  $r = select i1 $big, i64 0, i64 $sh  ; " . $node->op_str);
    if ($llop eq 'shl') {
        my $fits = $self->_fresh;
        $self->_emit("  $fits = icmp sge i64 $r, 0");
        $self->_stop_unless($fits, "a shift past what an i64 holds (perl's is unsigned)");
    }
    return $self->{cache}{ $node->id } = $r;
}

sub _lower_modulo {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    my $op   = $node->operation;

    if (defined $repr && $repr eq 'Scalar') {
        die "Modulo with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }
    if (defined $repr && $repr eq 'Num') {
        die "LLVM backend: Modulo with repr=Num not supported (fmod semantics differ from perl %)";
    }

    # Int representation: perl-semantics sign-corrected modulo.
    #
    # Perl `%` follows the SIGN of the RIGHT operand (the divisor), matching
    # mathematical modulo. LLVM `srem` follows the sign of the LEFT operand
    # (the dividend), like C `%`. For mixed-sign inputs these differ:
    #   perl:  -7 % 3 == 2    (positive, sign of divisor 3)
    #   srem:  -7 srem 3 == -1 (negative, sign of dividend -7)
    #
    # Sign-correction formula (branchless via select):
    #   t = a srem b
    #   needs_fix = (t != 0) AND ((t XOR b) < 0)   ; signs differ and remainder nonzero
    #   if needs_fix: t = t + b
    #
    # In LLVM IR (branchless with icmp + select):
    #   %t     = srem i64 %a, %b
    #   %xorv  = xor  i64 %t, %b
    #   %nonz  = icmp ne  i64 %t, 0
    #   %sneg  = icmp slt i64 %xorv, 0
    #   %fix   = and  i1  %nonz, %sneg
    #   %adj   = add  i64 %t, %b
    #   %res   = select i1 %fix, i64 %adj, i64 %t

    # EACH OPERAND IS READ AS AN INTEGER, as perl's % reads one: a Num is
    # truncated toward zero (7.5 % 2 is 7 % 2). Lowered raw, a double reached
    # `srem i64` and lli rejected the module.
    my $inputs  = $node->inputs;
    my ($lhs_ref, $rhs_ref) = map {
        my ($in, $ref) = ($_, $self->lower_value($_));
        my $st = $in->stamp // '';
        if ($st eq 'Num') {
            my $i = $self->_fresh;
            $self->_emit("  $i = fptosi " . _repr_to_llvm_type('Num')
                . " $ref to i64  ; Modulo: operand truncated to an integer");
            $ref = $i;
        }
        elsif ($st eq 'Boolean') {
            my $i = $self->_fresh;
            $self->_emit("  $i = zext i1 $ref to i64  ; Modulo: Boolean operand as 0/1");
            $ref = $i;
        }
        elsif ($st ne 'Int') {
            die "GAP: a % operand with repr=" . ($st || 'NONE') . " is not lowered\n";
        }
        $ref;
    } @$inputs[0, 1];

    my $t    = $self->_fresh;
    my $xorv = $self->_fresh;
    my $nonz = $self->_fresh;
    my $sneg = $self->_fresh;
    my $fix  = $self->_fresh;
    my $adj  = $self->_fresh;
    my $res  = $self->_fresh;

    $self->_die_on_zero($inputs->[1], $rhs_ref, 'i64', 'Illegal modulus zero');
    $self->_emit("  $t    = srem i64 $lhs_ref, $rhs_ref    ; Modulo step 1: srem (C/LLVM semantics)");
    $self->_emit("  $xorv = xor  i64 $t, $rhs_ref          ; Modulo step 2: signs-differ test");
    $self->_emit("  $nonz = icmp ne  i64 $t, 0              ; Modulo step 3: remainder nonzero?");
    $self->_emit("  $sneg = icmp slt i64 $xorv, 0           ; Modulo step 4: signs differ?");
    $self->_emit("  $fix  = and  i1  $nonz, $sneg           ; Modulo step 5: fix needed?");
    $self->_emit("  $adj  = add  i64 $t, $rhs_ref           ; Modulo step 6: adjusted value");
    $self->_emit("  $res  = select i1 $fix, i64 $adj, i64 $t ; Modulo step 7: perl-semantics result");

    $self->{cache}{$node->id} = $res;
    return $res;
}

# _lower_concat: emit Str concatenation as malloc+memcpy.
#
# Str = { ptr: i8*, len: i64, enc: i32 } where enc=0 (ASCII/default).
# Concat(a, b) allocates a new buffer of len(a)+len(b)+1 bytes (NUL term),
# copies a's bytes then b's bytes, returns the new ptr.
#
# The length of the result is tracked in _str_len_table for the output epilogue.
# The allocation is malloc (not alloca) — SOUND for G4 aggregates where Str values
# escape function frames. alloca would be unsound once a Str escapes its defining frame.
# The malloc leak is acceptable for main()-returns-then-process-exits patterns.
#
# Both operands must have Str representation; lengths must be tracked in
# _str_len_table. If a length is not tracked, the operation cannot be lowered safely.
sub _lower_concat {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    if (defined $repr && $repr ne 'Str') {
        die "GAP: Concat with repr=$repr reached LLVM backend — Concat requires Str operands";
    }

    my $inputs  = $node->inputs;
    my $lhs_val = $self->lower_value($inputs->[0]);
    my $rhs_val = $self->lower_value($inputs->[1]);

    # Through the consumer seam: a Str's pointer and length arrive TOGETHER, so
    # they cannot be sourced from two places that disagree.
    my ($lhs_ref, $len_a) = $self->_str_parts($lhs_val);
    my ($rhs_ref, $len_b) = $self->_str_parts($rhs_val);
    unless (defined $len_a && defined $len_b) {
        die "Concat cannot lower — one or both operand lengths not tracked in _str_len_table. "
          . "Only Str values produced by Constant(:Str) or Concat(:Str) have tracked lengths.";
    }

    # Compute result length = len_a + len_b. Emit as LLVM add i64 if either is
    # an SSA ref (not a literal); use the literal sum if both are literals.
    my $len_sum;
    if ($len_a =~ /^\d+$/ && $len_b =~ /^\d+$/) {
        # Both compile-time literals: compute the sum at codegen time.
        $len_sum = $len_a + $len_b;
    }
    else {
        # At least one is an SSA ref: emit add i64.
        my $la_ref = $len_a =~ /^\d+$/ ? $len_a : $len_a;
        my $lb_ref = $len_b =~ /^\d+$/ ? $len_b : $len_b;
        $len_sum = $self->_fresh;
        $self->_emit("  $len_sum = add i64 $la_ref, $lb_ref  ; Concat: total byte-len");
    }

    # Allocate: malloc(len_a + len_b + 1) — +1 for NUL terminator.
    my $total;
    if ($len_sum =~ /^\d+$/) {
        $total = $len_sum + 1;
    }
    else {
        $total = $self->_fresh;
        $self->_emit("  $total = add i64 $len_sum, 1  ; Concat: +1 for NUL terminator");
    }
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $total)  ; Concat: allocate result buffer");

    # Copy a's bytes (len_a bytes from lhs_ref into buf).
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $lhs_ref, i64 $len_a)  ; Concat: copy lhs");

    # Advance write ptr by len_a.
    my $buf_b = $self->_fresh;
    $self->_emit("  $buf_b = getelementptr inbounds i8, i8* $buf, i64 $len_a  ; Concat: ptr after lhs");

    # Copy b's bytes (exactly len_b), then store the NUL explicitly. Copying
    # len_b+1 "to include the source NUL" is wrong for VIEW-typed inputs (a
    # RegexCapture points into the middle of its subject — the byte past the
    # view is the next subject byte, not NUL).
    $self->_emit("  call i8* \@memcpy(i8* $buf_b, i8* $rhs_ref, i64 $len_b)  ; Concat: copy rhs");
    my $nul_ptr = $self->_fresh;
    $self->_emit("  $nul_ptr = getelementptr inbounds i8, i8* $buf, i64 $len_sum  ; Concat: NUL slot");
    $self->_emit("  store i8 0, i8* $nul_ptr  ; Concat: NUL-terminate");

    # Track the result length and mark that malloc/memcpy declarations are needed.
    $buf = $self->_set_str_len($buf, $len_sum);
    $self->{_need_malloc_memcpy}  = 1;

    $self->{cache}{$node->id} = $buf;
    return $buf;
}

# _str_const_parts($text, $label) -> ($ptr, $byte_len)
#
# A literal string as a (pointer, length) pair, for a site that needs the two
# halves separately -- a select over string constants has to choose the
# pointer and the length on the SAME predicate, and a helper returning a
# packed %Str would have to be taken apart again immediately.
#
# The global is emitted through _module_global_name, so identical text is
# shared and the name stays deterministic. The length is the byte count
# WITHOUT the NUL: _module_global_name's total includes it, and a %Str's
# length never does.
sub _str_const_parts {
    my ($self, $text, $label) = @_;
    my ($glob, undef, $total) = $self->_module_global_name('str_const', $text);
    my $ptr = $self->_fresh;
    # A comment ends at a newline: the text shown in it is escaped.
    (my $shown = $text) =~ s/([^\x20-\x7e])/sprintf('\\%02X', ord $1)/ge;
    $self->_emit_entry("  $ptr = getelementptr inbounds [$total x i8], [$total x i8]* $glob, i64 0, i64 0  ; $label: \"$shown\"");
    return ($ptr, $total - 1);
}

# _emit_str_append($lhs_ref, $rhs_ref, $label) -> $ptr
#
# Concatenate two Str VALUES, independent of any Concat node. _lower_concat
# does this over a node's two inputs; a builtin folding N pieces has no node
# per join, so the same emission is reached here without one.
#
# Copies exactly len_b bytes and stores the NUL explicitly rather than copying
# len_b+1 "to include the source NUL" -- that is wrong for a VIEW-typed input
# (a RegexCapture points into the middle of its subject, so the byte past the
# view is the next subject byte, not NUL). Same reasoning as _lower_concat,
# which is the shape this follows.
sub _emit_str_append {
    my ($self, $lhs_ref, $rhs_ref, $label) = @_;

    my ($a_ptr, $len_a) = $self->_str_parts($lhs_ref);
    my ($b_ptr, $len_b) = $self->_str_parts($rhs_ref);
    die "GAP: $label cannot lower — an operand's byte length is not tracked "
      . "(only Str values with a known length can be appended)."
        unless defined $len_a && defined $len_b;

    my $len_sum;
    if ($len_a =~ /^\d+$/ && $len_b =~ /^\d+$/) {
        $len_sum = $len_a + $len_b;
    }
    else {
        $len_sum = $self->_fresh;
        $self->_emit("  $len_sum = add i64 $len_a, $len_b  ; $label: total byte-len");
    }

    my $total;
    if ($len_sum =~ /^\d+$/) {
        $total = $len_sum + 1;
    }
    else {
        $total = $self->_fresh;
        $self->_emit("  $total = add i64 $len_sum, 1  ; $label: +1 for NUL terminator");
    }

    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $total)  ; $label: allocate result buffer");
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $a_ptr, i64 $len_a)  ; $label: copy lhs");

    my $buf_b = $self->_fresh;
    $self->_emit("  $buf_b = getelementptr inbounds i8, i8* $buf, i64 $len_a  ; $label: ptr after lhs");
    $self->_emit("  call i8* \@memcpy(i8* $buf_b, i8* $b_ptr, i64 $len_b)  ; $label: copy rhs");

    my $nul_ptr = $self->_fresh;
    $self->_emit("  $nul_ptr = getelementptr inbounds i8, i8* $buf, i64 $len_sum  ; $label: NUL slot");
    $self->_emit("  store i8 0, i8* $nul_ptr  ; $label: NUL-terminate");

    $self->{_need_malloc_memcpy} = 1;
    return $self->_set_str_len($buf, $len_sum);
}

# _empty_str_ref($label) -> $ptr to a zero-length Str
#
# The identity for a string fold: joining nothing yields "". Length 0 is
# tracked like any other, so a consumer reading _str_parts gets (ptr, 0)
# rather than an untracked pointer.
sub _empty_str_ref {
    my ($self, $label) = @_;
    my ($glob, undef, $total) = $self->_module_global_name('empty_str', '');
    my $ptr = $self->_fresh;
    $self->_emit_entry("  $ptr = getelementptr inbounds [$total x i8], [$total x i8]* $glob, i64 0, i64 0  ; $label: \"\"");
    return $self->_set_str_len($ptr, 0);
}

# _emit_to_str($from_repr, $input_ref, $label) -> $ptr
#
# The X -> Str conversion, in ONE place. Stringify(X) and Coerce(X -> Str) are
# the same edge -- Stringify is Coerce with a different name tag -- and they used
# to be implemented separately. They had already DIVERGED: Coerce's Boolean arm
# selected the pointer only and recorded no length, while Stringify's selected
# both. A false Boolean is the EMPTY string, so a consumer slicing an unrecorded
# length off that pointer would print a byte of "1". The length-recording
# version below is the survivor.
#
# Every arm must register _str_len_table for the pointer it returns.
sub _emit_to_str {
    my ($self, $from, $input_ref, $label) = @_;

    if ($from eq 'Str') {
        return $input_ref;   # already a Str; the length is already tracked
    }

    if ($from eq 'Boolean') {
        my ($one_g, $one_len, $one_tot) = $self->_module_global_name('bool_str', '1');
        my ($nil_g, undef,    $nil_tot) = $self->_module_global_name('bool_str', '');
        my ($one_p, $nil_p, $ptr, $len) =
            ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);
        $self->_emit_entry("  $one_p = getelementptr inbounds [$one_tot x i8], [$one_tot x i8]* $one_g, i64 0, i64 0  ; $label: \"1\"");
        $self->_emit_entry("  $nil_p = getelementptr inbounds [$nil_tot x i8], [$nil_tot x i8]* $nil_g, i64 0, i64 0  ; $label: \"\"");
        $self->_emit("  $ptr = select i1 $input_ref, i8* $one_p, i8* $nil_p  ; $label -> ptr");
        $self->_emit("  $len = select i1 $input_ref, i64 $one_len, i64 0  ; $label -> len");
        $ptr = $self->_set_str_len($ptr, $len);
        return $ptr;
    }

    if ($from eq 'Num') {
        # perl's float stringification IS %.15g (verified against perl 5.42 on
        # 0.1, 1e+34, 1.000001, 0.0005 and the corpus floats). snprintf is
        # called twice: once with a null buffer to learn the length, then into a
        # buffer of exactly that size -- the length is what the (ptr,len) pair
        # needs, and computing it another way would re-implement %g.
        $self->{_need_malloc_memcpy} = 1;
        $self->{_need_num_fmt}       = 1;
        $self->{_need_snprintf}      = 1;

        my $fmt = $self->_fresh;
        $self->_emit("  $fmt = getelementptr inbounds [6 x i8], [6 x i8]* \@fmt_num_g, i64 0, i64 0  ; $label: %.15g fmt");
        my $need = $self->_fresh;
        $self->_emit("  $need = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* null, i64 0, i8* $fmt, double $input_ref)  ; $label: measure");
        my $need64 = $self->_fresh;
        $self->_emit("  $need64 = sext i32 $need to i64  ; $label: length as i64");
        my $size = $self->_fresh;
        $self->_emit("  $size = add i64 $need64, 1  ; $label: + NUL");
        my $buf = $self->_fresh;
        $self->_emit("  $buf = call i8* \@malloc(i64 $size)  ; $label: buffer");
        my $wrote = $self->_fresh;
        $self->_emit("  $wrote = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* $buf, i64 $size, i8* $fmt, double $input_ref)  ; $label: render");
        $buf = $self->_set_str_len($buf, $need64);

        # PERL AND C DISAGREE ON NON-FINITE DOUBLES. Measured on perl 5.42.0:
        #
        #   9**9**9             "Inf"    C's %g gives "inf"
        #   -9**9**9            "-Inf"   C gives "-inf"
        #   9**9**9 - 9**9**9   "NaN"    C gives "nan"
        #
        # so the snprintf above is right for every finite value and wrong for
        # exactly three. The return-value epilogue carried this fixup and the
        # Coerce did not, which was invisible while every observation of a Num
        # went through the epilogue -- a program that PRINTS a non-finite value
        # reaches the Coerce instead. Moving it here puts it where a real
        # program meets it; the epilogue's copy can then go with the epilogue.
        #
        # NaN is detected as `fcmp uno x, x` (a NaN is unordered with itself,
        # the only value that is) and the infinities by their exact bit
        # patterns. The selects nest so NaN wins over the +/-Inf choice, which
        # matters because the +Inf compare is FALSE for a NaN but the ordering
        # would otherwise depend on that.
        my $is_nan  = $self->_fresh;
        my $is_pinf = $self->_fresh;
        my $is_ninf = $self->_fresh;
        my $is_inf  = $self->_fresh;
        my $is_nf   = $self->_fresh;
        $self->_emit("  $is_nan = fcmp uno double $input_ref, $input_ref  ; $label: NaN iff unordered with itself");
        $self->_emit("  $is_pinf = fcmp oeq double $input_ref, 0x7FF0000000000000  ; $label: +Inf");
        $self->_emit("  $is_ninf = fcmp oeq double $input_ref, 0xFFF0000000000000  ; $label: -Inf");
        $self->_emit("  $is_inf = or i1 $is_pinf, $is_ninf  ; $label: either infinity");
        $self->_emit("  $is_nf = or i1 $is_nan, $is_inf  ; $label: non-finite?");

        # Perl's spellings as ordinary tracked Str values -- NOT the epilogue's
        # @num_*_str globals, which carry a `Num:` tag prefix and a trailing
        # newline and are shaped for a printf rather than for a value.
        my ($inf_ptr,  $inf_len)  = $self->_str_const_parts('Inf',  "$label: +Inf");
        my ($ninf_ptr, $ninf_len) = $self->_str_const_parts('-Inf', "$label: -Inf");
        my ($nan_ptr,  $nan_len)  = $self->_str_const_parts('NaN',  "$label: NaN");

        my ($inf_sel_p, $nf_p, $out_p) = ($self->_fresh, $self->_fresh, $self->_fresh);
        my ($inf_sel_l, $nf_l, $out_l) = ($self->_fresh, $self->_fresh, $self->_fresh);
        $self->_emit("  $inf_sel_p = select i1 $is_pinf, i8* $inf_ptr, i8* $ninf_ptr  ; $label: +Inf or -Inf");
        $self->_emit("  $inf_sel_l = select i1 $is_pinf, i64 $inf_len, i64 $ninf_len  ; $label: matching length");
        $self->_emit("  $nf_p = select i1 $is_nan, i8* $nan_ptr, i8* $inf_sel_p  ; $label: NaN overrides");
        $self->_emit("  $nf_l = select i1 $is_nan, i64 $nan_len, i64 $inf_sel_l  ; $label: matching length");

        # The pointer and the length are selected TOGETHER on the same
        # predicate: a mismatched pair would read the right buffer for the
        # wrong number of bytes, which is a silent wrong answer rather than a
        # crash. Same reasoning that makes %Str a first-class aggregate.
        my ($fin_ptr, $fin_len) = $self->_str_parts($buf);
        $self->_emit("  $out_p = select i1 $is_nf, i8* $nf_p, i8* $fin_ptr  ; $label: non-finite or rendered");
        $self->_emit("  $out_l = select i1 $is_nf, i64 $nf_l, i64 $fin_len  ; $label: matching length");

        # A ZERO WITH ITS SIGN SET is "0" to perl; %.15g printed "-0".
        my ($zp, $zl) = $self->_str_const_parts('0', "$label: zero");
        my ($is_z, $zo_p, $zo_l) = map { $self->_fresh } 1 .. 3;
        $self->_emit("  $is_z = fcmp oeq double $input_ref, 0.0  ; $label: a zero, either sign");
        $self->_emit("  $zo_p = select i1 $is_z, i8* $zp, i8* $out_p");
        $self->_emit("  $zo_l = select i1 $is_z, i64 $zl, i64 $out_l");

        return $self->_set_str_len($zo_p, $zo_l);
    }

    if ($from eq 'Int') {
        return $self->_emit_int_to_str($input_ref);
    }

    # `print undef` prints the empty string. Undef is a UNIT TYPE -- one value,
    # so one answer, and no runtime work: the input ref is not even read.
    #
    # NOT shared with the Unknown arm below, which refuses: undef IS a value
    # whose string is "", while Unknown is a value nothing typed ("Scalar is a
    # legitimate static answer, Unknown is an inference failure").
    if ($from eq 'Undef') {
        return $self->_emit_empty_str($label);
    }

    # AN UNKNOWN OPERAND IS REFUSED, not printed as "". A value nothing typed
    # is not therefore undef: an inlined `my $y = $n; if ($n) { $y = 9 }
    # return $y` folds to a ternary stamped Unknown, and this arm printed ""
    # for perl's 9. The fallback was a guess that a wrong answer could hide
    # behind; the fix is upstream, wherever this should have been typed.
    if ($from eq 'Unknown') {
        die "GAP: $label: 'Unknown' is the lattice TOP -- nothing typed this "
          . "value, so it has no stringification (it is not therefore undef).\n";
    }

    # A Slot is Maybe[word]: its SSA ref is the %Slot aggregate, so both halves
    # are read off it with extractvalue. Perl prints an undefined value
    # as the empty string, so render the payload as an Int and select it against
    # "" on the defined bit -- pointer AND length together, since a Str is a
    # (ptr, len) pair and an undef contributes zero bytes.
    #
    # The payload is rendered UNCONDITIONALLY (both arms of the select are
    # evaluated). That is safe because _emit_int_to_str is pure -- a malloc and
    # a digit loop over an i64 that is 0 when undefined -- so the undefined case
    # renders "0" into a buffer nobody reads.
    if ($from eq 'Slot') {
        # No lookup, and no way for either half to be missing: they are fields
        # 0 and 1 of the value we were handed.
        my $defined = $self->_slot_defined_bit($input_ref);
        my $payload = $self->_slot_payload_of($input_ref);

        my ($rendered, $rlen) = $self->_str_parts($self->_emit_int_to_str($payload));
        my ($nil_g, undef, $nil_tot) = $self->_module_global_name('slot_str', '');
        my ($nil_p, $ptr, $len) = ($self->_fresh, $self->_fresh, $self->_fresh);
        $self->_emit_entry("  $nil_p = getelementptr inbounds [$nil_tot x i8], [$nil_tot x i8]* $nil_g, i64 0, i64 0  ; $label: \"\"");
        $self->_emit("  $ptr = select i1 $defined, i8* $rendered, i8* $nil_p  ; $label -> ptr");
        $self->_emit("  $len = select i1 $defined, i64 $rlen, i64 0  ; $label -> len");
        $ptr = $self->_set_str_len($ptr, $len);
        return $ptr;
    }

    # AN AGGREGATE IN SCALAR CONTEXT IS ITS LENGTH, and that length is an Int
    # with an ordinary stringification. Measured on perl 5.42.0:
    #
    #   my %h=(b=>2,a=>1);  scalar(keys %h)   2
    #   my @k = keys %h;    scalar(@k)        2
    #   "@k"                                  "a b"   <- interpolation, NOT this
    #
    # This is the same rule as a list return's scalar reading (`return @a` in
    # scalar context is the count, not the container), so it belongs here as
    # an arrow rather than at each site that happens to need it.
    #
    # It is NOT string INTERPOLATION: `"@k"` joins the elements with $" and is
    # a different operation reached a different way. The refusal below stays
    # for anything that really has no scalar reading.
    # A REFERENCE IS NOT ITS CONTAINER. `print [1,2,3]` prints ARRAY(0x...),
    # and this arm printed 3 (backlog 336a2f63). A Ref has no runtime-free
    # stringification here, so it falls through to the refusal below.
    if ($from eq 'Array' || $from eq 'Hash') {
        my $kind = $from;
        my $ptr  = $input_ref;
        # Field 0 of both %Array and %Hash is the count: %Array is
        # { i64 len, i64 cap, %Slot* } and %Hash is { i64 count, i64 cap,
        # %HashEntry* }, which is why one read serves both.
        my ($cnt_ptr, $cnt) = ($self->_fresh, $self->_fresh);
        $self->_emit("  $cnt_ptr = getelementptr inbounds %$kind, %$kind* $ptr, i32 0, i32 0  ; $label: count ptr");
        $self->_emit("  $cnt = load i64, i64* $cnt_ptr  ; $label: scalar context = element count");
        # _emit_to_str always yields a Str, so render the count as one.
        return $self->_emit_int_to_str($cnt);
    }

    die "GAP: $label is not lowered runtime-free (Int, Boolean, Num, Slot, "
      . "Undef, Str and an aggregate's count are wired; this repr has no "
      . "stringification).";
}

# _emit_empty_str($label) -> $ptr to "", with its length recorded as 0.
#
# The Undef arm's tail (Unknown refuses instead). The length REGISTRATION is the
# part that matters: a Str is a (ptr, len) pair, and an unrecorded length on a
# shared "" global is how the Boolean arm once printed a stray byte of "1".
# Zero is a length, and it has to be written down like any other.
sub _emit_empty_str {
    my ($self, $label) = @_;
    my ($nil_g, undef, $nil_tot) = $self->_module_global_name('undef_str', '');
    my $ptr = $self->_fresh;
    $self->_emit_entry("  $ptr = getelementptr inbounds [$nil_tot x i8], [$nil_tot x i8]* $nil_g, i64 0, i64 0  ; $label: \"\"");
    return $self->_set_str_len($ptr, 0);
}

# _emit_int_to_str($val_ref) -> $ptr (an i8* to a runtime-rendered decimal string,
# with its byte length recorded in _str_len_table). The int-to-decimal renderer
# shared by Stringify[Int] (interpolation coercion) and StrEq/StrNe over an Int
# operand (`$a eq "1"` where $a is an int -- perl stringifies the number for the
# comparison). No libc: an int-to-decimal loop into a malloc'd buffer.
sub _emit_int_to_str {
    my ($self, $val) = @_;

    $self->{_need_malloc_memcpy} = 1;   # for @malloc

    # buf[0..23]; digits fill from index 22 backward, index 23 holds the NUL.
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 24)  ; Stringify[Int]: digit buffer");
    my $nul_slot = $self->_fresh;
    $self->_emit("  $nul_slot = getelementptr inbounds i8, i8* $buf, i64 23  ; Stringify[Int]: NUL slot");
    $self->_emit("  store i8 0, i8* $nul_slot  ; Stringify[Int]: NUL-terminate");

    # Sign: neg = (val < 0); magnitude = neg ? 0 - val : val.
    # ponytail: 0 - INT64_MIN overflows (UB); the corpus/int range is small. A
    # full-range renderer would extract the last digit from the negative value
    # before negating -- upgrade path if INT64_MIN stringification is ever needed.
    my $neg = $self->_fresh;
    $self->_emit("  $neg = icmp slt i64 $val, 0  ; Stringify[Int]: negative?");
    my $negated = $self->_fresh;
    $self->_emit("  $negated = sub i64 0, $val  ; Stringify[Int]: magnitude if negative");
    my $mag0 = $self->_fresh;
    $self->_emit("  $mag0 = select i1 $neg, i64 $negated, i64 $val  ; Stringify[Int]: magnitude");

    my $lbl_pre  = $self->_current_block_label;
    my $lbl_loop = $self->_fresh_label('s2i.loop.');
    my $lbl_sign = $self->_fresh_label('s2i.sign.');

    my $mag_next = $self->_fresh;
    my $idx_next = $self->_fresh;

    # do-while: always write one digit (so 0 -> "0"), loop while quotient != 0.
    $self->_set_terminator("  br label \%$lbl_loop");
    $self->_new_block($lbl_loop);
    my $mag_phi = $self->_fresh;
    $self->_emit("  $mag_phi = phi i64 [ $mag0, \%$lbl_pre ], [ $mag_next, \%$lbl_loop ]  ; Stringify[Int]: current magnitude");
    my $idx_phi = $self->_fresh;
    $self->_emit("  $idx_phi = phi i64 [ 22, \%$lbl_pre ], [ $idx_next, \%$lbl_loop ]  ; Stringify[Int]: write index");
    my $rem = $self->_fresh;
    $self->_emit("  $rem = urem i64 $mag_phi, 10  ; Stringify[Int]: last digit");
    my $ch = $self->_fresh;
    $self->_emit("  $ch = trunc i64 $rem to i8  ; Stringify[Int]: digit as i8");
    my $ch_ascii = $self->_fresh;
    $self->_emit("  $ch_ascii = add i8 $ch, 48  ; Stringify[Int]: digit + '0'");
    my $slot = $self->_fresh;
    $self->_emit("  $slot = getelementptr inbounds i8, i8* $buf, i64 $idx_phi  ; Stringify[Int]: digit slot");
    $self->_emit("  store i8 $ch_ascii, i8* $slot  ; Stringify[Int]: write digit");
    $self->_emit("  $mag_next = udiv i64 $mag_phi, 10  ; Stringify[Int]: drop last digit");
    $self->_emit("  $idx_next = sub i64 $idx_phi, 1  ; Stringify[Int]: move left");
    my $more = $self->_fresh;
    $self->_emit("  $more = icmp ne i64 $mag_next, 0  ; Stringify[Int]: more digits?");
    $self->_set_terminator("  br i1 $more, label \%$lbl_loop, label \%$lbl_sign");

    # Sign block: the first digit is at $idx_phi (the last-written slot). Prepend
    # '-' one slot to its left when negative, and pick the result start pointer.
    $self->_new_block($lbl_sign);
    my $first_digit = $self->_fresh;   # index of the most-significant digit written
    $self->_emit("  $first_digit = phi i64 [ $idx_phi, \%$lbl_loop ]  ; Stringify[Int]: first-digit index");
    my $sign_idx = $self->_fresh;
    $self->_emit("  $sign_idx = sub i64 $first_digit, 1  ; Stringify[Int]: sign slot");
    my $sign_slot = $self->_fresh;
    $self->_emit("  $sign_slot = getelementptr inbounds i8, i8* $buf, i64 $sign_idx  ; Stringify[Int]: sign slot ptr");
    $self->_emit("  store i8 45, i8* $sign_slot  ; Stringify[Int]: write '-' (harmless when unused)");
    # start = neg ? sign_idx : first_digit
    my $start_idx = $self->_fresh;
    $self->_emit("  $start_idx = select i1 $neg, i64 $sign_idx, i64 $first_digit  ; Stringify[Int]: result start index");
    my $ptr = $self->_fresh;
    $self->_emit("  $ptr = getelementptr inbounds i8, i8* $buf, i64 $start_idx  ; Stringify[Int]: result ptr");
    my $len = $self->_fresh;
    $self->_emit("  $len = sub i64 23, $start_idx  ; Stringify[Int]: result byte length");

    $ptr = $self->_set_str_len($ptr, $len);
    return $ptr;
}

# _emit_box_into_slot($input_ref, $from, $label) -> $slot_ref
#
# Coerce(X -> Scalar): wrap a value in the uniform cell. The tag is NOT a
# guess here -- $from is the reading, by definition, so `_slot_tag_for_repr`
# turns it into the tag directly and the cell leaves this function knowing how
# to be read back.
#
# Undef is the one source with no payload: perl's undef is a single value, so
# the cell is `defined=false, tag=Undef, payload=0` and $input_ref (which for
# an Undef value is its always-false defined bit) is not read at all. That is
# the same reasoning the Coerce(Undef->Int) arm gives for using the constant 0
# rather than zext'ing the bit.
sub _emit_box_into_slot {
    my ($self, $input_ref, $from, $label) = @_;

    return $self->_build_slot('false', '0', 'Undef', "$label: undef cell")
        if $from eq 'Undef';

    # An UNKNOWN operand is an inference failure that got this far. It has no
    # established reading, so it boxes as Opaque -- and a later read of that
    # cell takes the not-established path rather than inventing an Int.
    return $self->_build_slot('true', '0', 'Opaque', "$label: unknown cell")
        if $from eq 'Unknown';

    my $payload = $self->_box_payload($input_ref, $from, $label);
    return $self->_build_slot('true', $payload,
                              _slot_tag_for_repr($from), "$label: box");
}

# _emit_read_slot_as($slot_ref, $to, $label) -> the SSA ref of the reading
#
# Coerce(Scalar -> X): dispatch on the cell's tag. Each reachable tag gets its
# own block emitting the conversion that reading calls for, and a phi at the
# join picks the one that ran.
#
# TWO facts short-circuit the dispatch, and both are about honesty rather than
# speed:
#
#   - An UNDEFINED cell must not consult the tag at all. Perl's undef has ONE
#     coercion per target type regardless of what bits the payload holds: "" for
#     Str, 0 for Int, 0.0 for Num. Reading the tag there would let a stale
#     payload change the answer for a value that has no payload.
#   - The NOT-ESTABLISHED tag (Opaque) takes that same path. This is the whole
#     point of having Opaque distinct from Undef at the vocabulary level: we do
#     not know how to read those bits, so we decline to, and falling through to
#     "read it as an Int" would be exactly the guess the tag exists to remove.
#     It is deliberately NOT a die -- a merge arm can carry an un-narrowed cell
#     down a path that never uses the value.
sub _emit_read_slot_as {
    my ($self, $slot_ref, $to, $label, %opt) = @_;

    my $defined = $self->_slot_defined_bit($slot_ref);
    my $tag     = $self->_slot_tag_of($slot_ref);
    my $payload = $self->_slot_payload_of($slot_ref);

    # The readings worth dispatching on: a tag whose payload this backend can
    # actually convert to $to. Every other tag (a live ArrayRef/HashRef/
    # CodeRef/Object pointer, say) has no numeric or string face to emit, so it
    # joins the undef path rather than being read as an integer address.
    #
    # $to is NOT excluded. `grep { $_ ne $to }` stood here on the reasoning
    # that a reading equal to the target needs no conversion -- true, and
    # irrelevant: it still needs its own TAG TEST, or a Num-tagged cell read as
    # Num matches nothing and falls through to the undef arm. Measured: it
    # returned 0 for 3.5. The conversion is what is skipped when $repr eq $to,
    # not the dispatch.
    # converted to $to. Every other tag (a live ArrayRef/HashRef/CodeRef/Object
    # pointer, say) has no numeric or string face this backend can emit, so it
    # joins the undef path rather than being read as an integer address.
    # A caller may narrow the dispatch when its context cannot accept every
    # reading -- see _lower_field_access_in_method, where the Str arm's
    # %Str GEP would precede that type's declaration. Narrowing DROPS
    # readings onto the undef arm, which is honest; it never reinterprets one
    # reading's bits as another's, which is the defect this dispatch exists to
    # prevent.
    my @readings = $opt{readings} ? $opt{readings}->@* : qw(Int Num Str Boolean);

    my $entry     = $self->_current_block_label;
    my $lbl_join  = $self->_fresh_label('slotrd.join.');
    my $lbl_undef = $self->_fresh_label('slotrd.undef.');

    # known = defined AND tag is one we can read. Anything else -> the undef path.
    my $known = $self->_fresh;
    $self->_emit("  $known = icmp ne i1 $defined, 0  ; $label: defined?");

    # Chain of tag tests. Each candidate reading gets a test block and a body
    # block; the last test falls through to the undef path.
    my @arms;            # ([$value_operand, $block_label], ...)
    my @test_lbls = map { $self->_fresh_label('slotrd.t' . $_ . '.') } 0 .. $#readings;
    my @body_lbls = map { $self->_fresh_label('slotrd.b' . $_ . '.') } 0 .. $#readings;

    # Guard the whole chain on the defined bit: undefined goes straight to the
    # undef arm without touching the tag.
    $self->_set_terminator("  br i1 $known, label \%$test_lbls[0], label \%$lbl_undef")
        if @readings;
    $self->_set_terminator("  br label \%$lbl_undef") unless @readings;

    # A reference is always true in perl; read as Boolean, its tag is the answer.
    # As a string or a number it is what perl reads (_emit_ref_reading): read
    # as undef, two references were one hash key "" and equal as numbers.
    my $lbl_ref = $to eq 'Boolean' || ( $to =~ /\A(?:Str|Int|Num)\z/ )
        ? $self->_fresh_label('slotrd.ref.') : undef;

    for my $i (0 .. $#readings) {
        my $repr = $readings[$i];
        my $next = $i < $#readings ? $test_lbls[$i+1] : ( $lbl_ref // $lbl_undef );

        $self->_new_block($test_lbls[$i]);
        my $hit = $self->_fresh;
        my $tv  = _slot_tag_value($repr);
        $self->_emit("  $hit = icmp eq i8 $tag, $tv  ; $label: tag == $repr?");
        $self->_set_terminator("  br i1 $hit, label \%$body_lbls[$i], label \%$next");

        $self->_new_block($body_lbls[$i]);
        my $val = $self->_unbox_payload_as($payload, $repr, "$label: tag=$repr");
        # The reading is a $repr; bridge it to $to with the ordinary arms.
        $val = $self->_emit_coercion($val, $repr, $to, "$label\[$repr]")
            if $repr ne $to;
        # _emit_coercion may itself have opened blocks (Int->Str renders in a
        # loop), so the incoming edge is whatever block is current NOW, not the
        # body label we opened. Reading it back is the same discipline the
        # Stringify loop uses with _current_block_label.
        push @arms, [$val, $self->_current_block_label];
        $self->_set_terminator("  br label \%$lbl_join");
    }

    if ($lbl_ref && $to ne 'Boolean') {
        $self->_new_block($lbl_ref);
        # shortcut: an Object (a class instance) still reads as undef -- its
        # string names a class no tag carries; give it one when objects need it.
        for my $kind (qw(ArrayRef HashRef CodeRef ScalarRef)) {
            my ($hit, $body, $after) = ($self->_fresh, $self->_fresh_label('slotrd.r.'), $self->_fresh_label('slotrd.rn.'));
            $self->_emit("  $hit = icmp eq i8 $tag, " . _slot_tag_value($kind) . "  ; $label: tag == $kind?");
            $self->_set_terminator("  br i1 $hit, label \%$body, label \%$after");
            $self->_new_block($body);
            push @arms, [$self->_emit_ref_reading($payload, $kind, $to, $label), $self->_current_block_label];
            $self->_set_terminator("  br label \%$lbl_join");
            $self->_new_block($after);
        }
        $self->_set_terminator("  br label \%$lbl_undef");
    }
    elsif ($lbl_ref) {
        $self->_new_block($lbl_ref);
        my @is_ref = map {
            my $hit = $self->_fresh;
            $self->_emit("  $hit = icmp eq i8 $tag, " . _slot_tag_value($_) . "  ; $label: tag == $_?");
            $hit;
        } qw(ArrayRef HashRef CodeRef Object ScalarRef);
        my $any = shift @is_ref;
        for my $hit (@is_ref) {
            my $or = $self->_fresh;
            $self->_emit("  $or = or i1 $any, $hit");
            $any = $or;
        }
        my $lbl_true = $self->_fresh_label('slotrd.reftrue.');
        $self->_set_terminator("  br i1 $any, label \%$lbl_true, label \%$lbl_undef");
        $self->_new_block($lbl_true);
        push @arms, ['true', $lbl_true];
        $self->_set_terminator("  br label \%$lbl_join");
    }

    # The undef / not-established arm: one answer per target type, no payload read.
    $self->_new_block($lbl_undef);
    my $undef_val = $self->_emit_coercion('i1 false', 'Undef', $to,
                                          "$label: undefined or not-established");
    push @arms, [$undef_val, $self->_current_block_label];
    $self->_set_terminator("  br label \%$lbl_join");

    $self->_new_block($lbl_join);
    my $ty = _repr_to_llvm_type($to);
    my $out = $self->_fresh;
    $self->_emit("  $out = phi $ty "
        . join(', ', map { "[ $_->[0], \%$_->[1] ]" } @arms)
        . "  ; $label: reading selected by tag");
    return $out;
}

# _emit_ref_reading($payload, $kind, $to, $label) -> a reference (its payload
# the address) read as perl reads it: as a number its address, as a string
# "KIND(0x<hex>)", "Class=KIND(0x<hex>)" when bless recorded a class.
sub _emit_ref_reading {
    my ($self, $payload, $kind, $to, $label) = @_;
    return $payload if $to eq 'Int';
    return $self->_emit_coercion($payload, 'Int', 'Num', "$label: address") if $to eq 'Num';
    my %name = (ArrayRef => 'ARRAY', HashRef => 'HASH', CodeRef => 'CODE', ScalarRef => 'SCALAR');
    my ($cp, $cl, $eq) = ($self->_str_const_parts('', "$label: no class"), undef);
    ($cl, $eq) = (0, $cp);
    if ($kind ne 'CodeRef') {   # bless records arrays, hashes and scalars
        my $ptr = $self->_fresh;
        $self->_emit("  $ptr = inttoptr i64 $payload to i8*");
        my ($is, $bp, $bl) = $self->_bless_class($ptr);
        my ($eqp) = $self->_str_const_parts('=', "$label: Class=");
        my ($p, $l, $e) = map { $self->_fresh } 1 .. 3;
        $self->_emit("  $p = select i1 $is, i8* $bp, i8* $cp  ; $label: blessed into?");
        $self->_emit("  $l = select i1 $is, i64 $bl, i64 0");
        $self->_emit("  $e = select i1 $is, i8* $eqp, i8* $cp");
        ($cp, $cl, $eq) = ($p, $l, $e);
    }
    my ($fmt) = $self->_str_const_parts('%.*s%s%s(0x%lx)', "$label: ref fmt");
    my ($kp)  = $self->_str_const_parts($name{$kind}, "$label: $kind");
    $self->{$_} = 1 for qw(_need_snprintf _need_malloc_memcpy);
    my ($cl32, $need, $need64, $size, $buf, $wrote) = map { $self->_fresh } 1 .. 6;
    my $args = "i8* $fmt, i32 $cl32, i8* $cp, i8* $eq, i8* $kp, i64 $payload";
    $self->_emit("  $cl32 = trunc i64 $cl to i32");
    $self->_emit("  $need = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* null, i64 0, $args)  ; $label: measure");
    $self->_emit("  $need64 = sext i32 $need to i64");
    $self->_emit("  $size = add i64 $need64, 1");
    $self->_emit("  $buf = call i8* \@malloc(i64 $size)");
    $self->_emit("  $wrote = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* $buf, i64 $size, $args)  ; $label: KIND(0x...)");
    return $self->_set_str_len($buf, $need64);
}

# _unbox_payload_as($payload_ref, $repr, $label) -> the SSA ref of the i64
# payload read AS $repr. The exact inverse of _box_payload, and it must stay
# that way: the two are one encoding written from both ends, and a divergence
# between them is a silent misread rather than a type error.
sub _unbox_payload_as {
    my ($self, $payload, $repr, $label) = @_;

    return $payload if $repr eq 'Int';   # an Int IS the payload word

    my $ref = $self->_fresh;
    if ($repr eq 'Num') {
        # REINTERPRET, not convert: the payload word holds this value's bits.
        # Only the KIND of move is fixed here; the type it lands in is
        # %_REPR_LLVM_TYPE's decision, exactly as at _store_field_payload's
        # already-correct sibling. Were Num to map to i64 the bitcast becomes a
        # no-op the verifier accepts, not a wrong type.
        my $num_ty = _repr_to_llvm_type($repr);
        $self->_emit("  $ref = bitcast i64 $payload to $num_ty  ; $label: payload -> Num");
        return $ref;
    }
    if ($repr eq 'Boolean') {
        $self->_emit("  $ref = icmp ne i64 $payload, 0  ; $label: payload -> Boolean");
        return $ref;
    }
    if ($repr eq 'Str') {
        # _box_payload stores a %Str* via ptrtoint; read the pair back and
        # rebuild the (ptr, len) VALUE so the length travels with the pointer.
        $self->{_need_str_type} = 1;
        my $pair = $self->_fresh;
        $self->_emit("  $pair = inttoptr i64 $payload to %Str*  ; $label: payload -> StrPair*");
        my $pp = $self->_fresh;
        $self->_emit("  $pp = getelementptr inbounds %Str, %Str* $pair, i64 0, i32 0  ; $label: StrPair.ptr");
        my $sp = $self->_fresh;
        $self->_emit("  $sp = load i8*, i8** $pp  ; $label: str ptr");
        my $lp = $self->_fresh;
        $self->_emit("  $lp = getelementptr inbounds %Str, %Str* $pair, i64 0, i32 1  ; $label: StrPair.len");
        my $sl = $self->_fresh;
        $self->_emit("  $sl = load i64, i64* $lp  ; $label: str len");
        return $self->_str_value($sp, len => $sl);
    }

    die "GAP: $label cannot read a %Slot payload as $repr -- _box_payload has "
      . "no inverse for it. The two are one encoding written from both ends; "
      . "add the read here when the write is added there.";
}

sub _lower_coerce {
    my ($self, $node) = @_;

    my $to = $node->to_repr;

    # A qr// AS A STRING is perl's stringification of it, (?^FLAGS:pattern)
    # (pvm 389).
    my ($in0) = $node->inputs->@*;
    if ($to eq 'Str' && blessed($in0) && $in0->operation eq 'Constant'
            && ( $in0->const_type // '' ) eq 'regex') {
        my $text = '(?^' . ( $in0->flags // '' ) . ':' . ( $in0->value // '' ) . ')';
        return $self->{cache}{ $node->id } = $self->_set_str_len($self->_str_const_parts($text, 'qr// as a string'));
    }

    # Lower the operand FIRST, then ask what it actually is. `from_repr` is a
    # static field stamped when the graph was loaded; it describes the operand
    # the analysis saw, which is not always the value the backend ends up
    # holding. Inlining is the case that matters: `_arg_bind` substitutes the
    # caller's already-lowered argument for a callee's `$_[0]` read, so a node
    # the analysis stamped `Scalar` (an @_ element, honestly un-narrowed in the
    # callee) now holds the caller's `i64`. Emitting from the stale `Scalar`
    # produced a %Slot tag dispatch against a bare integer -- "'%tmp_1' defined
    # with type 'i64' but expected '%Slot'". The operand's own representation
    # is the truth at emission time; from_repr is the fallback for operands
    # that carry none.
    my $input_ref = $self->lower_value($node->inputs->[0]);
    my $operand   = $node->inputs->[0];
    # `_is_narrowed`, NOT `defined`. Under the every-Value-node-is-stamped
    # invariant a stamp is ALWAYS defined, so `defined` stopped discriminating
    # and this branch began firing for operands whose stamp is `Unknown` --
    # emitting an i1 where a %Slot was expected. Measured on
    # `my $ok = print "x\n"`: lli refused with "'%tmp_10' defined with type
    # 'i1' but expected '%Slot'".
    #
    # The question this guard MEANT is "has the operand COMMITTED to a
    # representation?", which is what `_is_narrowed` answers. Node.pm's
    # deprecation notice predicted exactly this: "once this holds, `defined
    # $node->representation` STOPS DISCRIMINATING for value nodes -- it is
    # always true."
    # NO CLASS TEST. `stamp` is declared on Chalk::IR::Node (Node.pm:64), the
    # BASE -- every node carries one. But Chalk::IR::Value is a SIBLING of the
    # value-producing control nodes, not their parent: Print, Proj, VarDecl and
    # ListAssign are all `:isa(Chalk::IR::Node)` directly. An `isa
    # Chalk::IR::Value` test therefore asks about the CLASS HIERARCHY when the
    # question is about the STAMP, and silently skips the 4 node kinds that
    # produce a value without descending from Value.
    #
    # Measured on `my $ok = print "x\n"`: T1 stamps the Print `Boolean`, the
    # wire's `from_repr` says `Scalar`, the class test fails, the stale
    # `Scalar` wins, and the %Slot tag dispatch runs against a bare i1 --
    # "'%tmp_10' defined with type 'i1' but expected '%Slot'". The trace named
    # the caller outright: `Coerce[Scalar -> Str]` from _lower_coerce.
    #
    # `_is_narrowed` alone is the whole question: has this operand COMMITTED to
    # a representation? A node that has answers for itself; one that has not
    # falls back to the wire's static claim.
    # An inlined argument the callee left Unknown is the caller's value as
    # it is (see lower_value's binding), so its reading is the caller's.
    my $bound_repr = ( $operand->stamp // 'Unknown' ) eq 'Unknown' && $self->_bound_ref($operand)
                   ? $self->_repr_of($operand) : undef;
    my $from      = defined $bound_repr ? $bound_repr
                  : Chalk::IR::Analysis::_is_narrowed($operand->stamp)
                  ? $operand->stamp
                  # A Scalar operand IS its Slot, which says more than an
                  # Unknown the coercion was built with: a shared lexical, and
                  # a call returning one.
                  : ( ( $operand->stamp // '' ) eq 'Scalar'
                      && ( $node->from_repr // '' ) eq 'Unknown' ) ? 'Scalar'
                  : $node->from_repr;

    my $ref = $self->_emit_coercion($input_ref, $from, $to, 'Coerce');
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# _emit_coercion($input_ref, $from, $to, $what) -> the converted SSA ref
#
# The conversion itself, independent of any Coerce NODE. A merge
# (TernaryExpr, &&/||, a Region Phi) needs to bridge an ARM whose repr differs
# from the merge's own — perl's merges yield one of their OPERANDS, so
# `$c ? 42 : "hi"` really is an Int on one path and a Str on the other — and
# there is no Coerce node on that edge to lower. Same rule, same conversions,
# reached without a node.
sub _emit_coercion {
    my ($self, $input_ref, $from, $to, $what) = @_;

    return $input_ref if $from eq $to;   # nothing to bridge

    my $ref = $self->_fresh;

    # The numeric arrows. Which instruction bridges Int and Num is a fact about
    # their REPRESENTATIONS, not their names: _repr_convert_op reads both ends
    # out of %_REPR_LLVM_TYPE and answers `sitofp`/`fptosi` only while one side
    # is integral and the other is not. Map Num to an integral type and it
    # returns undef -- the arrow is the identity and nothing is emitted, which
    # is the correct answer, reached without editing this arm.
    if (($from eq 'Int' && $to eq 'Num') || ($from eq 'Num' && $to eq 'Int')) {
        my $conv = _repr_convert_op($from, $to);
        return $input_ref unless $conv;   # same machine type: nothing to bridge
        my $ft = _repr_to_llvm_type($from);
        my $tt = _repr_to_llvm_type($to);
        $self->_emit("  $ref = $conv $ft $input_ref to $tt  ; Coerce[$from->$to]");
    }
    # Coerce(*->Boolean) = truthiness: produce i1 from the input's machine type.
    # One arm for both numeric sources. Int truthiness: nonzero -> true (1),
    # zero -> false (0). Num truthiness: nonzero -> true, zero (INCLUDING -0.0)
    # -> false, which `une` against 0.0 gives for free.
    #
    # Which compare instruction and which not-equal predicate apply is decided
    # by $from's machine type: integral gets `icmp ne`, floating gets `fcmp une`
    # (unordered, so a NaN is true -- perl's behaviour, and the reason the
    # predicates differ by more than a leading `f`). The zero it compares
    # against comes from the same authority, so -0.0 stays covered whatever
    # that zero becomes.
    elsif ($to eq 'Boolean' && ($from eq 'Int' || $from eq 'Num')) {
        my $cmp   = _repr_opcode('icmp', $from);
        my $pred  = _repr_is_float($from) ? 'une' : 'ne';
        my $ty    = _repr_to_llvm_type($from);
        my $zero  = _repr_zero($from);
        $self->_emit("  $ref = $cmp $pred $ty $input_ref, $zero  ; Coerce[$from->Boolean] truthiness");
    }
    elsif ($to eq 'Boolean' && $from eq 'Boolean') {
        # Identity coercion — just pass through. (Also caught by the
        # $from eq $to guard above; kept so the arm list stays exhaustive.)
        return $input_ref;
    }
    # Coerce(Boolean->Num) = 0.0 (false) or 1.0 (true). Num IS `double`
    # (%_REPR_LLVM_TYPE), so the result must BE a double: `zext ... to i64`
    # stood here and produced an i64, which typechecks only until something
    # merges it with a real Num. The %Slot tag dispatch is the first such
    # consumer -- a Boolean-tagged cell read as Num lands in a `phi double`
    # beside a genuine double -- and lli rejected it there.
    elsif ($from eq 'Boolean' && $to eq 'Num') {
        # `uitofp` vs `zext` is exactly the choice _repr_convert_op makes, from
        # Num's machine type rather than from its name -- and it knows i1 is
        # UNsigned, which is the bug the comment above records.
        my $conv = _repr_convert_op($from, $to) // 'zext';
        my $ft   = _repr_to_llvm_type($from);
        my $tt   = _repr_to_llvm_type($to);
        my $one  = _repr_is_float($to) ? '0.0/1.0' : '0/1';
        $self->_emit("  $ref = $conv $ft $input_ref to $tt  ; Coerce[Boolean->Num] $one");
    }
    # Coerce(Boolean->Int) = 0/1: zero-extend i1 to i64 (same as Boolean->Num for integers).
    elsif ($from eq 'Boolean' && $to eq 'Int') {
        $self->_emit("  $ref = zext i1 $input_ref to i64  ; Coerce[Boolean->Int] 0/1");
    }
    # Coerce(Undef->Int/Num) = 0. Perl is unambiguous: undef in numeric context
    # is 0 (`my $u; $u + 0` is 0). An Undef value's SSA ref is its defined bit
    # (always i1 false), so the numeric face is the constant, not a conversion
    # of that bit -- zext'ing the bit would also give 0 here, but only by
    # coincidence, and would be wrong the moment Undef is represented otherwise.
    elsif ($from eq 'Undef' && ($to eq 'Int' || $to eq 'Num')) {
        # These three ternaries were the functor written inline in miniature:
        # one branch on the Chalk type picking a zero literal, one picking a
        # machine type, one picking an opcode -- three chances to disagree.
        # All three now come from the same authority keyed by the same repr.
        my $zero = _repr_zero($to);
        my $ty   = _repr_to_llvm_type($to);
        my $op   = _repr_opcode('add', $to);
        $self->_emit("  $ref = $op $ty $zero, $zero  ; $what\[Undef->$to] = 0");
    }
    # Coerce(Undef->Boolean) = false. Perl is unambiguous: undef is FALSE in
    # boolean context. Like the Int/Num arm above, the answer is the constant
    # rather than a conversion of the input ref -- an Undef value carries no
    # information that could change it.
    #
    # This edge had no arm until 2026-08-31 while Undef->Int and Undef->Num did.
    # The %Slot tag dispatch is the first caller to reach it: an undefined cell
    # read as Boolean takes the undef path, and that path needs an answer for
    # every target type it can be asked for.
    elsif ($from eq 'Undef' && $to eq 'Boolean') {
        # `icmp ne i1 false, true` computes (false != true) = TRUE, which is
        # the OPPOSITE of what the trailing comment claimed and of what perl
        # does: undef is false. Caught by the composition characterization --
        # Undef->Int->Boolean, Undef->Num->Boolean and Undef->Str->Boolean all
        # independently produced false, three agreeing witnesses against this
        # one outlier. `add i1 0, 0` is the constant false, matching how
        # Constant(Boolean) is emitted elsewhere in this file.
        $self->_emit("  $ref = add i1 0, 0  ; $what\[Undef->Boolean] = false (perl: undef is false)");
    }
    # ---- %Slot: the uniform scalar cell, read and written by its TAG ----
    #
    # A `die` stood here from 2026-07-15 to 2026-08-31 saying Scalar "needs a
    # T2 decision about how to read a %Slot payload (tagged? runtime?
    # per-context choice?)". That question is now answered, and the answer is
    # the first option: %Slot carries an `i8 tag` naming how its payload is to
    # be read. The two arms below are the decision made concrete -- a write
    # that records the reading, and a read that dispatches on it.
    #
    # Why it took a field rather than a cleverer emitter: the die was never
    # about missing machinery. Scalar always HAD a machine encoding and
    # insertvalue/extractvalue always worked. What was missing was
    # INFORMATION -- the payload is 64 bits whose interpretation lived nowhere,
    # so any reading emitted here would have been a guess hardcoding a
    # representation choice at the wrong layer. The tag moves that fact into
    # the cell, where the producer can write down what it already knew.
    #
    # $what NAMES THE CALLER, and both arms pass it down. _emit_coercion is
    # reached from seven sites, five of them merge points (And/Or/Ternary arm
    # joins) that pass reprs directly with no Coerce NODE on the edge. When one
    # of these dies, the label is what says whether a node or an arm join
    # produced the conversion.
    elsif ($to eq 'Scalar' || $to eq 'Slot') {
        # BOXING. No dispatch is needed and none would be honest: the source's
        # own representation IS the reading, so it becomes the tag. This is the
        # only point in the pipeline where the interpretation of those 64 bits
        # is known for free, which is exactly why the tag is written here.
        return $self->_emit_box_into_slot($input_ref, $from, "$what\[$from -> $to]");
    }
    # A VALUE READ BY ITS TAG, READ AS A REFERENCE: the pointer it holds when
    # its tag says that kind; anything else stops the program, as a read
    # through it does (_container_ptr). Through the number readings it had no
    # reference to give: `$r->{f} // []` was refused.
    elsif (( $from eq 'Scalar' || $from eq 'Slot' ) && $to =~ /\A(?:Array|Hash|Scalar|Code)Ref\z/) {
        my ($tag, $ok) = ($self->_slot_tag_of($input_ref), $self->_fresh);
        $self->_emit("  $ok = icmp eq i8 $tag, " . _slot_tag_value($to) . "  ; $what: a $to?");
        my ($yes, $no) = ($self->_fresh_label('sref.as.'), $self->_fresh_label('sref.not.'));
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $ok, label %$yes, label %$no");
        $self->_new_block($no);
        $self->_refuse_inside_eval("a value used as a $to that may not be one");
        $self->_emit("  call void \@exit(i32 255)  ; $what: not a $to");
        $self->_set_terminator("  unreachable");
        $self->_new_block($yes);
        $self->_emit("  $ref = inttoptr i64 " . $self->_slot_payload_of($input_ref) . " to i8*  ; $what: the $to");
    }
    elsif ($from eq 'Scalar' || $from eq 'Slot') {
        # READING. The 2026-07-15 die that stood here said this needed "a T2
        # decision about how to read a %Slot payload ... either a tag or a
        # runtime". It is a tag: %Slot carries an i8 naming the reading its
        # producer already knew, so the read is a dispatch on data rather than
        # the guess the die refused to make. The comment was right about what
        # was missing; the missing thing now exists.
        return $self->_emit_read_slot_as($input_ref, $to, "$what\[$from -> $to]");
    }
    # Coerce(Boolean->Str) = select between "" and "1" string-face constants.
    # The Str representation is not fully modelled yet (G3), but the Boolean string-face
    # is only two constant strings and can be lowered as a select i1 between them.
    # Returns an i8* that points to the selected string constant.
    # Coerce(X -> Str) — the edges Stringify used to own. A Str value is a
    # (ptr, len) PAIR, so each of these records a length in _str_len_table
    # alongside the pointer it returns; a consumer that slices `len` bytes off
    # an unrecorded pointer would emit garbage.
    elsif ($to eq 'Str') {
        return $self->_emit_to_str($from, $input_ref, "$what\[$from->Str]");
    }
    # Coerce(Str->Num): perl leading-numeric rule.
    # "3abc"->3, "abc"->0, " 42"->42, "3.14x"->3.14, ""->0, ".5"->0.5,
    # "0x10"->0 (perl does NOT parse hex).
    #
    # Implementation: call a module-level helper @chalk_str_to_num(i8* ptr, i64 len)
    # -> double. The helper uses libc strtod (host-C, NOT libperl) with a pre-check
    # that returns 0.0 for any string starting with "0x" or "0X" (the one known
    # divergence between strtod and perl's rule). strtod matches perl for all other
    # leading-numeric forms. See G3 implementation notes.
    # AN ARRAY OR HASH AS A CONDITION is true when it holds anything: its
    # count (field 0 of both) is not zero.
    elsif (($from eq 'Array' || $from eq 'Hash') && $to eq 'Boolean') {
        my $cp = $self->_fresh;
        my $cnt = $self->_fresh;
        $self->_emit("  $cp = getelementptr inbounds %$from, %$from* $input_ref, i32 0, i32 0  ; $what: count ptr");
        $self->_emit("  $cnt = load i64, i64* $cp");
        $self->_emit("  $ref = icmp ne i64 $cnt, 0  ; $what: holds anything?");
    }
    # AN ARRAY OR HASH AS A NUMBER is its count (`$i < @_`, `@ARGV + 3`).
    elsif (($from eq 'Array' || $from eq 'Hash') && ($to eq 'Int' || $to eq 'Num')) {
        my ($cp, $cnt) = ($self->_fresh, $self->_fresh);
        $self->_emit("  $cp = getelementptr inbounds %$from, %$from* $input_ref, i32 0, i32 0  ; $what: count ptr");
        $self->_emit("  " . ( $to eq 'Int' ? $ref : $cnt ) . " = load i64, i64* $cp  ; $what: scalar context = element count");
        $self->_emit("  $ref = sitofp i64 $cnt to " . _repr_to_llvm_type('Num') . "  ; $what: the count as a Num") if $to eq 'Num';
    }
    elsif ($from eq 'Str' && $to eq 'Num') {
        my ($ptr_ref, $tracked_len) = $self->_str_parts($input_ref);
        my $len_ref = $tracked_len // 0;
        # Flag that the str-to-num helper + strtod declaration are needed.
        $self->{_need_str_to_num_helper} = 1;
        $self->{_need_malloc_memcpy}     = 1;   # it parses a terminated copy
        $self->_emit("  $ref = call double \@chalk_str_to_num(i8* $ptr_ref, i64 $len_ref)  ; Coerce[Str->Num] leading-numeric");
    }
    # Coerce(Str->Int): perl reads the string as a NUMBER and then truncates
    # toward zero -- `int("3.9abc")` is 3, not 0 and not 4. So this composes the
    # two arms that already implement those halves rather than re-deriving the
    # leading-numeric rule a second time; a second copy of that rule is how the
    # "0x10" divergence would come back on one path only.
    #
    # This edge had NO arm until 2026-08-31 (Str->Num and Str->Boolean did),
    # which was latent while nothing routed a Str into an Int. The %Slot tag
    # dispatch is the first caller that reaches it: reading a cell as Int must
    # enumerate the Str tag, because the cell may hold one.
    elsif ($from eq 'Str' && $to eq 'Int') {
        my $as_num = $self->_emit_coercion($input_ref, 'Str', 'Num', $what);
        return $self->_emit_coercion($as_num, 'Num', 'Int', $what);
    }
    # Coerce(Str->Boolean): perl's string truthiness rule.
    # false iff the string is "" (empty) or exactly "0".
    # "0.0","00","0 " etc. are all TRUE (only exact "0" and "" are false).
    #
    # Implementation: branchless LLVM IR:
    #   is_empty = (len == 0)
    #   first_byte = load i8 from ptr (safe since we gep+load conditionally)
    #   is_zero_char = (first_byte == '0')
    #   is_single_char = (len == 1)
    #   is_single_zero = (is_single_char AND is_zero_char)
    #   is_false = (is_empty OR is_single_zero)
    #   result = NOT is_false  (true iff not false)
    elsif ($from eq 'Str' && $to eq 'Boolean') {
        my ($ptr_ref, $tracked_len) = $self->_str_parts($input_ref);
        my $len_ref = $tracked_len // 0;
        # is_empty = (len == 0)
        my $is_empty = $self->_fresh;
        $self->_emit("  $is_empty = icmp eq i64 $len_ref, 0  ; Coerce[Str->Boolean]: len==0 check");
        # Load the first byte conditionally: use select to get '0' when empty
        # (the byte doesn't matter when empty; we AND with is_single_zero anyway).
        # Safe approach: GEP ptr (valid even at length 0 for constant globals),
        # load the byte, then mask out the result with is_single_zero.
        my $first_byte_ptr = $self->_fresh;
        $self->_emit("  $first_byte_ptr = getelementptr inbounds i8, i8* $ptr_ref, i64 0  ; Coerce[Str->Boolean]: ptr to first byte");
        my $first_byte = $self->_fresh;
        $self->_emit("  $first_byte = load i8, i8* $first_byte_ptr  ; Coerce[Str->Boolean]: load first byte");
        # is_zero_char = (first_byte == '0' = 48)
        my $is_zero_char = $self->_fresh;
        $self->_emit("  $is_zero_char = icmp eq i8 $first_byte, 48  ; Coerce[Str->Boolean]: first byte == '0'");
        # is_single_char = (len == 1)
        my $is_single = $self->_fresh;
        $self->_emit("  $is_single = icmp eq i64 $len_ref, 1  ; Coerce[Str->Boolean]: len==1 check");
        # is_single_zero = is_single AND is_zero_char
        my $is_single_zero = $self->_fresh;
        $self->_emit("  $is_single_zero = and i1 $is_single, $is_zero_char  ; Coerce[Str->Boolean]: single-zero check");
        # is_false = is_empty OR is_single_zero
        my $is_false = $self->_fresh;
        $self->_emit("  $is_false = or i1 $is_empty, $is_single_zero  ; Coerce[Str->Boolean]: is false?");
        # result = NOT is_false -> true iff non-empty and not "0"
        $self->_emit("  $ref = xor i1 $is_false, true  ; Coerce[Str->Boolean]: invert -> Boolean");
    }
    # A REFERENCE AS A NUMBER IS ITS ADDRESS: `$r == $s` asks whether two
    # references name one thing.
    elsif ($from =~ /\A(?:Array|Hash|Scalar|Code)Ref\z/ && $to =~ /\A(?:Int|Num)\z/) {
        $self->_emit("  $ref = ptrtoint i8* $input_ref to i64  ; $what\[$from->$to]: the address");
        $ref = $self->_emit_coercion($ref, 'Int', 'Num', $what) if $to eq 'Num';
    }
    else {
        die "LLVM backend: cannot lower $what\[$from->$to]";
    }

    return $ref;
}

# _lower_not: emit UnaryNot(Boolean)->Boolean.
#
# Perl `!` takes the TRUTHINESS of its operand (regardless of the operand's
# representation) and returns a genuine Boolean (is_bool=1).
#
# Implementation:
#   1. Lower the operand. Produce an i1 via _ensure_i1 (coerces Int to Boolean
#      if needed: icmp ne i64 %x, 0).
#   2. Emit: %result = xor i1 %cond, true   ; logical negation
#
# The result is i1 (Boolean representation), which is then returned or used as
# a condition in the enclosing expression.
sub _lower_not {
    my ($self, $node) = @_;

    my $repr = $node->stamp;

    my $inputs   = $node->inputs;
    my $operand  = $inputs->[0];
    my $op_ref   = $self->lower_value($operand);
    # AS IT IS HELD: an inlined argument is the caller's value (_repr_of).
    my $op_repr  = $operand->operation eq 'Print' ? 'Boolean' : ( $self->_repr_of($operand) // $operand->stamp );
    die "LLVM backend: Not operand has no representation set — cannot determine i1 vs i64"
        unless defined $op_repr;

    # Convert operand to i1 (truthiness) if it is not already Boolean.
    my $cond_ref = $self->_ensure_i1($op_ref, $op_repr);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = xor i1 $cond_ref, true  ; Not: logical negation -> Boolean(i1)");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# _ensure_i1($ref, $repr) -> $i1_ref
#
# If $repr is 'Boolean', the value is already i1 — return $ref unchanged.
# If $repr is 'Int', emit an icmp ne i64 %ref, 0 to produce a truthiness i1.
# If $repr is 'Num', emit an fcmp une double %ref, 0.0.
# This is Coerce(*->Boolean) = truthiness, used inline by _lower_not.
sub _ensure_i1 {
    my ($self, $ref, $repr) = @_;
    die "LLVM backend: _ensure_i1 called with undef repr — operand must have a representation set"
        unless defined $repr;

    return $ref if $repr eq 'Boolean';
    # A string, or a value read by its tag, is true by perl's rule: the
    # coercion's truthiness arms ("" and "0" false; undef false).
    return $self->_emit_coercion($ref, $repr, 'Boolean', '_ensure_i1')
        if $repr =~ /\A(?:Str|Scalar|Array|Hash)\z/;

    die "LLVM backend: _ensure_i1 cannot convert repr=$repr to i1"
        unless $repr eq 'Int' || $repr eq 'Num';

    # Same shape as _emit_coercion's truthiness arm, and the same semantics:
    # Int nonzero -> true (1) / zero -> false (0); Num nonzero -> true / zero
    # (including -0.0) -> false.
    #
    # The compare instruction, its not-equal predicate, the operand type and
    # the zero are four answers to one question -- what does this
    # representation look like on the machine -- so all four come from the one
    # place that answers it.
    my $cond = $self->_fresh;
    my $cmp  = _repr_opcode('icmp', $repr);
    my $pred = _repr_is_float($repr) ? 'une' : 'ne';
    my $ty   = _repr_to_llvm_type($repr);
    my $zero = _repr_zero($repr);
    $self->_emit("  $cond = $cmp $pred $ty $ref, $zero  ; _ensure_i1: $repr truthiness -> i1");
    return $cond;
}

# ---------------------------------------------------------------------------
# SSA-value threading for lexical scalar variables (Phase 3c)
#
# Model: straight-line code only (no branches, no loops). VarDecl stores its
# initialized SSA value in var_table[vd_id]. PadAccess reads it. Assign and
# CompoundAssign update it. This covers A1, A4, C1, C2, K1, K2 from the
# gap-map without needing alloca+store+load (LLVM mem2reg would do the same
# optimization anyway; we do it directly at the IR level).
#
# The var_table is keyed by VarDecl node id. PadAccess locates its VarDecl
# via inputs->[0]. Assign locates the VarDecl via inputs->[0] (the lhs
# PadAccess), then inputs->[0] of that (the VarDecl).
# ---------------------------------------------------------------------------

# _lower_vardecl: store the initializer's SSA value in var_table; return it.
sub _lower_vardecl {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'VarDecl');
    if ($repr eq 'Scalar') {
        die "VarDecl with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $init_node = $node->inputs->[1];    # inputs[1] = init value (or undef)
    my $init_ref;
    if (defined $init_node) {
        $init_ref = $self->lower_value($init_node);
    }
    else {
        # No initializer: use a zero/empty value for the type.
        if ($repr eq 'Str') {
            die "GAP: VarDecl with repr=Str and no initializer reached LLVM backend — "
              . "uninit Str is not yet lowered (would require an empty-string global).";
        }
        # A zero of the declared representation's own machine type, materialized
        # by that type's own add-identity instruction. Naming `double`/`0.0`
        # here would re-decide what Num is at a site whose only actual question
        # is "what is zero".
        my $zero = $self->_fresh;
        my $z    = _repr_zero($repr);
        $self->_emit("  $zero = " . _repr_opcode('add', $repr) . ' '
            . _repr_to_llvm_type($repr) . " $z, $z  ; VarDecl uninit $repr -> $z");
        $init_ref = $zero;
    }

    # Store the SSA value in the var_table under this VarDecl's id.
    # Also record the representation for this VarDecl so the if/else merge
    # phi can derive the correct LLVM type (B2 fix).
    $self->{var_table}{ $node->id }  = $init_ref;
    $self->{cache}{ $node->id }      = $init_ref;
    $self->{_vd_repr}{ $node->id }   = $repr;

    # Undef representation: propagate the defined-bit and payload from the init
    # node to this VarDecl, indexed by VarDecl id. DefinedOr looks up the payload
    # by the PadAccess node's VarDecl id to complete the phi merge.
    if ($repr eq 'Undef' && defined $init_node) {
        my $init_id = $init_node->id;
        if (exists $self->{_undef_defined_bit}{$init_id}) {
            $self->{_undef_defined_bit}{ $node->id } = $self->{_undef_defined_bit}{$init_id};
        }
        if (exists $self->{_undef_payload}{$init_id}) {
            $self->{_undef_payload}{ $node->id } = $self->{_undef_payload}{$init_id};
        }
    }

    return $init_ref;
}

# _lower_padaccess: read the current SSA value from the var_table.
sub _lower_padaccess {
    my ($self, $node) = @_;

    # A LOCATION (a shared file lexical, a `my $x` kept in memory) is read
    # from its %Slot, at this read's memory version (frozen there by
    # _freeze_memory_reads), and unboxed to the reading's repr.
    return $self->_lex_aggregate_ptr($node) if $node->shared && $node->sigil =~ /\A[@%]\z/;
    if ($node->is_location) {
        my $g    = $self->_location_ptr($node);
        my $slot = $self->_fresh;
        $self->_emit("  $slot = load %Slot, %Slot* $g  ; read lexical " . $node->name);
        my $repr = $node->stamp // '';
        my $ref  = $repr =~ /\A(?:Int|Num|Str|Boolean)\z/
            ? $self->_emit_coercion($slot, 'Scalar', $repr, 'shared lexical ' . $node->name)
            : $slot;
        $self->{cache}{ $node->id } = $ref;
        return $ref;
    }

    # The method receiver `$self`: a PadAccess with varname '$self' and NO VarDecl
    # input (it is not a declared lexical -- it is the method's implicit object
    # pointer). Inside a method body the object arrives as %self; a self-method
    # dispatch ($self->m()) lowers its receiver to that pointer. Handle before the
    # VarDecl lookup, which would die "no VarDecl input" (zhi 019f5dec).
    if ($self->{_in_method_body}
            && $node->can('name') && $node->name() eq '$self'
            && !defined $node->inputs->[0]) {
        my $self_ref = $self->{_method_self_name}
            // die "LLVM backend: a \$self receiver PadAccess in a method body "
                 . "has no _method_self_name to lower to.";
        $self->{cache}{ $node->id } = $self_ref;
        return $self_ref;
    }

    # A DECLARED PARAMETER IS BACKED BY AN LLVM ARGUMENT, NOT A VarDecl.
    # `method outer($k) { $self->inner($k) }` reads $k as a pad access with no
    # declaration in the body -- the binding comes from the signature, and the
    # value arrives in %argN. This is the SAME shape as the `$self` case above:
    # an unbacked PadAccess whose value is a register the function already has.
    #
    # Kept as a second arm rather than folded into that one because the two
    # answer different questions -- $self is the invocant at a fixed position,
    # a parameter is positional by declared index -- and collapsing them would
    # make the invocant just another entry in a table it is not part of.
    if ($self->{_in_method_body}
            && $node->can('name')
            && !defined $node->inputs->[0]) {
        my $vn  = $node->name();
        my $idx = $self->{_method_param_index}{$vn};
        if (defined $idx) {
            my $ref = "%arg$idx";
            $self->{cache}{ $node->id } = $ref;
            return $ref;
        }
    }

    # AN ARRAY DECLARED EMPTY (`my @r;` at a graph's top level) arrives as a
    # bare @ PadAccess: no VarDecl, no literal. It is one empty %Array, built
    # where its graph's lowering began -- the function's entry for the
    # program, the call point for an inlined sub, so a call inside a loop
    # gets a fresh one each pass, as perl's `my` does. A `my @r` re-run in a
    # loop arrives instead as an ArrayLiteral on the control chain.
    # A `my %h;` is the same, an empty %Hash that grows as keys are stored.
    if (!defined $node->inputs->[0]
            && ( ( ($node->sigil // '') eq '@' && ($node->stamp // '') eq 'Array' )
              || ( ($node->sigil // '') eq '%' && ($node->stamp // '') eq 'Hash' ) )) {
        # Once: a PadAccess is a mutable read, re-lowered at every use, and
        # each re-lowering allocated another empty array -- push filled one
        # and "@r" printed another.
        return $self->{_empty_arrays}{ $node->id } if $self->{_empty_arrays}{ $node->id };
        my ($saved, $nblocks) = ($self->{current_idx}, scalar @{ $self->{blocks} });
        $self->{current_idx} = $self->{_graph_entry_idx} // 0;
        my $ref = $node->sigil eq '%' ? $self->_lower_hash_ref($node) : $self->_lower_array_ref($node);
        $self->{current_idx} = $saved;
        die "GAP: an empty array's allocation opened blocks in the entry block\n"
            if @{ $self->{blocks} } != $nblocks;
        $self->{cache}{ $node->id } = $self->{_empty_arrays}{ $node->id } = $ref;
        return $ref;
    }

    my $repr = _require_repr($node, 'PadAccess');
    if ($repr eq 'Scalar') {
        die "PadAccess with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    # Locate the VarDecl via inputs->[0].
    my $vd = $node->inputs->[0];
    unless (defined $vd) {
        die "LLVM backend: PadAccess has no VarDecl input (inputs->[0] is undef); "
          . "hand-authored graphs must wire PadAccess.inputs[0] = VarDecl";
    }

    # Ensure the VarDecl has been lowered (it may be in the data-chain, in
    # which case lower_value(VarDecl) processes it here; or it was already
    # processed by process_control_node).
    my $vd_id = $vd->id;
    unless (exists $self->{var_table}{$vd_id}) {
        $self->lower_value($vd);
    }

    my $val_ref = $self->{var_table}{$vd_id};
    unless (defined $val_ref) {
        die "LLVM backend: PadAccess var_table has no entry for VarDecl id=$vd_id";
    }

    # PadAccess emits no instructions; it returns the current SSA ref from
    # var_table. Cache it so non-PadAccess nodes that take this as an input
    # (e.g. an Add that shares the same PadAccess) get the same %tmp ref.
    # lower_value() always bypasses the cache for PadAccess ops (the cache-hit
    # path checks $op ne 'PadAccess') so this write is only used by non-PadAccess
    # consumers of the same node id — a safe sharing pattern.
    $self->{cache}{ $node->id } = $val_ref;

    # Undef representation: propagate _undef_defined_bit and _undef_payload
    # from the VarDecl to this PadAccess node id. DefinedOr looks up the
    # payload by the LHS node's id (the PadAccess), not the VarDecl's id.
    if ($repr eq 'Undef') {
        if (exists $self->{_undef_defined_bit}{$vd_id}) {
            $self->{_undef_defined_bit}{ $node->id } = $self->{_undef_defined_bit}{$vd_id};
        }
        if (exists $self->{_undef_payload}{$vd_id}) {
            $self->{_undef_payload}{ $node->id } = $self->{_undef_payload}{$vd_id};
        }
    }

    return $val_ref;
}


# _lower_list_assign_into_locations($node): `my ($a, $b) = (1, 2)` where the
# targets are kept in memory. Pairwise, all values read before any store.
# Anything else on the wire's list form -- a target that is not a scalar
# location, a value that would flatten -- is refused by name.
sub _lower_list_assign_into_locations {
    my ($self, $node) = @_;
    my @in = $node->inputs->@*;
    my $n  = $node->targets;
    my @t  = @in[ 0 .. $n - 1 ];
    my @v  = @in[ $n .. $#in ];
    for my $t (@t) {
        die "GAP: a list assignment to a " . ( blessed($t) ? $t->operation : 'undef' )
          . " that is not a scalar kept in memory is not lowered\n"
            unless blessed($t) && $t->operation eq 'PadAccess'
                && ( $t->sigil // '' ) eq '$' && ( $t->shared || $t->is_location );
    }
    for my $v (@v) {
        my $s = $v->operation eq 'Print' ? 'Boolean' : ( $v->stamp // '' );
        die "GAP: a list assignment of a $s value, which may flatten, is not lowered\n"
            unless $s =~ /\A(?:Int|Num|Str|Boolean|Undef|Scalar|Slot)\z/;
    }
    my @boxed = map {
        my $v = $v[$_];
        my $s = $v->operation eq 'Print' ? 'Boolean' : $v->stamp;
        my $r = $self->lower_value($v);
        ($r, $s) = $self->_miss_kept($v, $r, $s);
        $s =~ /\A(?:Scalar|Slot)\z/ ? $r
            : $s eq 'Undef' ? $self->_build_slot('false', '0', 'Undef', 'list assign')
            : $self->_emit_coercion($r, $s, 'Scalar', 'list assign');
    } 0 .. ( $#v < $#t ? $#v : $#t );
    for my $i (0 .. $#t) {
        my $val = $boxed[$i] // $self->_build_slot('false', '0', 'Undef', 'list assign: no value');
        $self->_emit("  store %Slot $val, %Slot* " . $self->_location_ptr($t[$i])
            . "  ; list assign: " . $t[$i]->name);
    }
    # In scalar context a list assignment is the count of its values.
    return $self->{cache}{ $node->id } = scalar @v;
}
# _lower_assign: lower the RHS value and update the target.
# Returns the new SSA value (the RHS).
# Two modes:
#  (a) Subscript-lvalue: inputs[0] is a Subscript node → emit an element store
#      (bounds-checked slot write into the container array or hash).
#  (b) Scalar rebind: inputs[0] is a PadAccess(VarDecl) or VarDecl →
#      update var_table with the new SSA value.
sub _lower_assign {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'Assign');

    # pos($s) = N sets where its next m//g starts (undef: the start).
    {
        my ($lhs, $val) = $node->inputs->@[0, 1];
        if (blessed($lhs) && $lhs->operation eq 'Call' && ( $lhs->dispatch_kind // '' ) eq 'builtin'
                && ( $lhs->name // '' ) eq 'pos') {
            my ($v) = grep { blessed($_) } $lhs->inputs->@*;
            die "GAP: a store to pos() of what is not a variable a scalar m//g matches is not lowered\n"
                unless blessed($v) && $v->operation eq 'PadAccess' && $POS_VARS{ $v->name } && $self->_pos_var_ok($v);
            my $from = $self->_repr_of($val) // $val->stamp // '';
            die "GAP: a store to pos() of a $from value is not lowered\n" unless $from eq 'Int';
            my $n = $self->lower_value($val);
            $self->_emit("  store i64 $n, i64* " . $self->_pos_cell($v) . "  ; pos() = ...");
            return $self->{cache}{ $node->id } = $n;
        }
        # A STORE TO A VARIABLE m//g MATCHES clears its pos(), as perl's does.
        $self->_emit("  store i64 -1, i64* " . $self->_pos_cell($lhs) . "  ; a store clears pos()")
            if blessed($lhs) && $lhs->operation eq 'PadAccess' && $POS_VARS{ $lhs->name };
    }

    # A `local` STORE is put back where its scope ends, by the ElemRestore
    # B::SoN places there. Without one (an explicit return, pvm 176) the old
    # value would never be put back: refused.
    die "GAP: a local store is not lowered -- what it replaced is not put back\n"
        if $node->can('local') && $node->local
        && !_local_restore_of($node);
    # WHAT IT REPLACES is read now, before the store: left to the restore it
    # read the local value back.
    if ($node->can('local') && $node->local) {
        for my $r (_local_restore_of($node)) {
            $self->lower_value($_) for $r->inputs->@[2, 3];
        }
    }

    # A LIST ASSIGNMENT INTO LOCATIONS: each target its own value, pairwise,
    # every value read before any target is stored (a swap), a target past
    # the values undef. Lowered as `t1 = t2` it stored the wrong value.
    if ($node->can('targets') && defined $node->targets && !( blessed($node->inputs->[-1]) && _is_args_array($node->inputs->[-1]) )) {
        return $self->_lower_list_assign_into_locations($node);
    }

    # `my (...) = @_` INTO A LOCATION (a target passed on to another sub, kept
    # in memory): inlining bound each target to its argument, but a later read
    # loads the location -- so each bound value is stored there. Lowered as a
    # value of @_, it was refused (pvm 102 154 203 220).
    if (blessed($node->inputs->[-1]) && _is_args_array($node->inputs->[-1]) && $self->{_arg_bind}) {
        my @t = $node->inputs->@[ 0 .. $#{ $node->inputs } - 1 ];
        if (grep { blessed($_) && $_->operation eq 'PadAccess' && ( $_->shared || $_->is_location ) } @t) {
            for my $t (@t) {
                my $b = $self->{_arg_bind}{ refaddr($t) };
                die "GAP: `my (...) = \@_` into a target inlining did not bind is not lowered\n"
                    unless $b && defined $b->{ref} && ( $t->sigil // '$' ) eq '$';
                next unless $t->shared || $t->is_location;
                my $r = $b->{repr} // 'Scalar';
                my $val = $r =~ /\A(?:Scalar|Slot)\z/ ? $b->{ref}
                        : $self->_emit_coercion($b->{ref}, $r, 'Scalar', 'my (...) = @_');
                $self->_emit("  store %Slot $val, %Slot* " . $self->_location_ptr($t) . "  ; my (...) = \@_: " . $t->name);
            }
            return $self->{cache}{ $node->id } = scalar @t;
        }
    }

    my $lhs = $node->inputs->[0];
    my $rhs = $node->inputs->[1];

    my $rhs_ref = $self->lower_value($rhs);

    # Mode (fa): FieldAccess-lvalue — field store into a class object struct.
    # Dissolves F9: the FieldAccess carries field_stash (class name) explicitly,
    # so no ambient _method_class_name is needed to identify the class.
    # The object pointer still comes from the ambient _method_self_name (the
    # implicit $self in method and ADJUST body contexts).
    if (defined $lhs && $lhs->can('operation') && $lhs->operation eq 'FieldAccess') {
        my $field_index = $lhs->field_index;
        my $class_name  = $lhs->field_stash;
        my $val_repr    = _require_repr($rhs, 'Assign(FieldAccess-lvalue).rhs');
        my $slot_idx    = $field_index + 1;
        # An object field IS a %Slot cell. Its subfield indices come from
        # _slot_idx, never a literal: a field added to @_SLOT_FIELDS must
        # not silently re-aim these GEPs at the wrong bytes.
        my ($fi_def, $fi_tag, $fi_pay) =
            (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
        # Self pointer: must be in method/ADJUST body context
        my $obj_raw = $self->{_method_self_name}
            // die "LLVM MOP: Assign(FieldAccess-lvalue) used outside method/ADJUST body context "
                 . "— _method_self_name not set";
        my $obj_typed = $self->_fresh;
        $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; Assign(FieldAccess-lvalue): typed self");
        # A VALUE READ BY ITS TAG is a whole %Slot: it IS the field's cell, tag
        # and all (`$count++` on an Int field is a Scalar, pvm 242).
        if ($val_repr =~ /\A(?:Scalar|Slot)\z/) {
            my $cell = $self->_fresh;
            $self->_emit("  $cell = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx  ; FieldAccess-lvalue[$field_index] cell");
            $self->_emit("  store %Slot $rhs_ref, %Slot* $cell  ; FieldAccess-lvalue[$field_index] = a Scalar");
            return $self->{cache}{ $node->id } = $rhs_ref;
        }
        # Store defined=true
        my $def_gep = $self->_fresh;
        $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 $fi_def  ; FieldAccess-lvalue[$field_index] defined");
        $self->_emit("  store i1 true, i1* $def_gep  ; FieldAccess-lvalue[$field_index] defined=true");
        my $tag_gep = $self->_fresh;
        my $tag_nm  = _slot_tag_for_repr($val_repr);
        $self->_emit("  $tag_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 $fi_tag  ; FieldAccess-lvalue[$field_index] tag");
        $self->_emit("  store i8 " . _slot_tag_value($tag_nm) . ", i8* $tag_gep  ; FieldAccess-lvalue[$field_index] tag=$tag_nm");

        # Store payload — the repr-dispatched boxing (Str StrPair, Boolean zext,
        # ref ptrtoint, Int identity) is owned by _store_field_payload, shared
        # with the :param binding and default-value paths so every field write
        # boxes a given repr identically. The Assign expression's value is what
        # the helper returns (the i8* for Str, the boxed i64 otherwise).
        my $pay_gep = $self->_fresh;
        $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 $fi_pay  ; FieldAccess-lvalue[$field_index] payload");
        my $stored = $self->_store_field_payload($rhs_ref, $val_repr, $pay_gep,
                                                 "FieldAccess-lvalue[$field_index]");
        $self->{cache}{ $node->id } = $stored;
        return $stored;
    }

    # Mode (sa): EntryDef-lvalue -- a package scalar store (`our $g = 5`),
    # boxed into its %Slot global like an EntryWrite. See _pkg_slot_name.
    if (defined $lhs && $lhs->can('operation') && $lhs->operation eq 'EntryDef') {
        my $stored = $self->_store_package_scalar($lhs, $rhs, $rhs_ref);
        $self->{cache}{ $node->id } = $stored;
        return $stored;
    }

    # Mode (a): Subscript-lvalue — element store into Array or Hash.
    if (defined $lhs && $lhs->operation eq 'Subscript') {
        # Unwrap a Ref container (`$r->[0]=...` where $r=\@a) to its aliased
        # target: \@a and @a share backing storage, so the store must resolve to
        # the SAME aggregate the array name resolves to (memory-SSA phase 2d).
        my $container = $self->_unwrap_ref_container($lhs->inputs->[0]);
        my $key_idx   = $lhs->inputs->[1];
        my $ctr_repr  = $self->_repr_of($container) // '';
        # A CONTAINER READ BY ITS TAG: the reference it holds, or one made where
        # an undef stood -- perl autovivifies it (pvm 176 184 225 232 233).
        my $autoviv = 0;
        if ($ctr_repr =~ /\A(?:Scalar|Slot)\z/ && ( $lhs->can('kind') ? $lhs->kind // '' : '' ) =~ /\A(array|hash)\z/) {
            $ctr_repr = $1 eq 'array' ? 'ArrayRef' : 'HashRef';
            $autoviv  = 1;
        }

        if ($ctr_repr eq 'Array' || $ctr_repr eq 'ArrayRef') {
            # Array element store: bounds-checked (same as _lower_array_write body).
            $self->{_need_aggregate_types} = 1;

            # Typed pointer resolved at THIS use — see _container_ptr.
            my $arr_ref = $self->_container_ptr($container, 'Array', autoviv => $autoviv);
            my $idx_ref = $self->_index_i64($key_idx);
            # Past the end the array grows; from the end, it counts back.
            $idx_ref = $self->_emit_array_extend_to($arr_ref, $idx_ref);

            # Load elems pointer and write the slot.
            my $elem_ptr = $self->_fresh;
            my $elems    = $self->_fresh;
            $self->_emit("  $elem_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 2  ; Assign(Array-lvalue): elems ptr");
            $self->_emit("  $elems = load %Slot*, %Slot** $elem_ptr  ; Assign(Array-lvalue): load elems");
            my $slot_def = $self->_fresh;
            my $slot_tag = $self->_fresh;
            my $slot_pay = $self->_fresh;
            my ($gi_def, $gi_tag, $gi_pay) =
                (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
            $self->_emit("  $slot_def = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx_ref, i32 $gi_def  ; Assign(Array-lvalue): slot def ptr");
            $self->_emit("  $slot_tag = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx_ref, i32 $gi_tag  ; Assign(Array-lvalue): slot tag ptr");
            $self->_emit("  $slot_pay = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx_ref, i32 $gi_pay  ; Assign(Array-lvalue): slot pay ptr");
            # THE VALUE'S OWN THREE FIELDS: its defined bit, the reading a read
            # decodes it by (reads go by the stored tag, so a Num or a Scalar
            # stored into an array of Ints reads back as itself), its payload.
            my ($wdef, $wtag, $wpay) = $self->_slot_fields_of_value($rhs, $rhs_ref, 'Assign(Array-lvalue)');
            $self->_emit("  store i1 $wdef, i1* $slot_def  ; Assign(Array-lvalue): defined");
            $self->_emit("  store i8 $wtag, i8* $slot_tag  ; Assign(Array-lvalue): tag");
            $self->_emit("  store i64 $wpay, i64* $slot_pay  ; Assign(Array-lvalue): store value");

            $self->{cache}{ $node->id } = $rhs_ref;
            return $rhs_ref;
        }
        elsif ($ctr_repr eq 'Hash' || $ctr_repr eq 'HashRef') {
            # Hash element store: linear-scan key lookup and value update (same body as _lower_hash_write).
            $self->{_need_aggregate_types} = 1;
            $self->{_need_malloc_memcpy}   = 1;
            $self->{_need_memcmp}          = 1;

            # Typed pointer resolved at THIS use — see _container_ptr.
            my $hash_ref = $self->_container_ptr($container, 'Hash', autoviv => $autoviv);
            my $wkey_ref = $self->_hash_key_str($key_idx);
            # See HashRead: a 0-length key makes the memcmp match any entry.
            # Die loudly on an untracked length rather than default to 0.
            my ($wkey_ptr, $wkey_len) = $self->_str_parts($wkey_ref);
            $wkey_ref = $wkey_ptr;
            defined $wkey_len
                or die "GAP: Assign(Hash-lvalue) key (ref=$wkey_ref) has no tracked "
                     . "length — would emit a 0-length memcmp matching any entry.";

            # THE VALUE, BOXED ONCE, before the search: its defined bit, its
            # reading (the tag a read decodes by), its payload word.
            my ($wdef, $wtag, $wpay) = $self->_slot_fields_of_value($rhs, $rhs_ref, 'Assign(Hash-lvalue)');
            $self->_emit_hash_upsert($hash_ref, $wkey_ref, $wkey_len, $wdef, $wtag, $wpay);

            $self->{cache}{ $node->id } = $rhs_ref;
            return $rhs_ref;
        }
        else {
            die "GAP: Assign(Subscript-lvalue) container has repr=$ctr_repr; "
              . "only Array/ArrayRef element stores are lowered runtime-free.";
        }
    }

    # $$r = V stores through the reference into the %Slot it names.
    if (defined $lhs && $lhs->can('operation') && $lhs->operation eq 'PostfixDeref'
            && ($lhs->sigil // '') eq '$') {
        my $ptr  = $self->_scalar_ref_target($lhs->inputs->[0]);
        my $from = $rhs->operation eq 'Print' ? 'Boolean' : ($rhs->stamp // '');
        my $boxed = $from =~ /\A(?:Scalar|Slot)\z/ ? $rhs_ref
                  : $from =~ /\A(?:Int|Num|Str|Boolean)\z/
                      ? $self->_emit_coercion($rhs_ref, $from, 'Scalar', 'store through $$ref')
                  : die "GAP: a store through a scalar reference of a $from value is not lowered\n";
        $self->_emit("  store %Slot $boxed, %Slot* $ptr  ; \$\$ref = ...");
        $self->{cache}{ $node->id } = $rhs_ref;
        return $rhs_ref;
    }

    # A LOCATION is stored to its %Slot: the value boxed into the Slot every
    # reading unboxes. Not a rebind -- another graph, or a callee through
    # `@_`, reads it.
    if (defined $lhs && $lhs->can('operation') && $lhs->operation eq 'PadAccess'
            && ($lhs->shared || $lhs->is_location)) {
        # A WHOLE SHARED AGGREGATE ASSIGNED: the new header copied over the
        # one every graph holds, in place, so a reference taken before still
        # names it.
        if ($lhs->sigil =~ /\A[@%]\z/) {
            my $ty  = $lhs->sigil eq '@' ? '%Array' : '%Hash';
            my $rs  = $rhs->stamp // '';
            die "GAP: a whole shared " . $lhs->name . " assigned from a $rs is not lowered\n"
                unless $rs eq ( $ty eq '%Array' ? 'Array' : 'Hash' );
            my $src = $rhs->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/
                ? $rhs_ref : $self->_emit_aggregate_copy($rhs_ref, $rs);
            my $dst = $self->_lex_aggregate_ptr($lhs);
            my $v   = $self->_fresh;
            $self->_emit("  $v = load $ty, $ty* $src  ; the new contents");
            $self->_emit("  store $ty $v, $ty* $dst  ; into " . $lhs->name . ", in place");
            $self->{cache}{ $node->id } = $rhs_ref;
            return $rhs_ref;
        }
        die "GAP: a store to a shared file lexical " . $lhs->name
          . " that is not a scalar is not lowered\n" unless $lhs->sigil eq '$';
        my $g    = $self->_location_ptr($lhs);
        my $from = $rhs->operation eq 'Print' ? 'Boolean' : ($rhs->stamp // '');
        ($rhs_ref, $from) = $self->_miss_kept($rhs, $rhs_ref, $from);
        die "GAP: a store to shared lexical " . $lhs->name . " of a $from value "
          . "is not lowered\n" unless $from =~ /\A(?:Int|Num|Str|Boolean|Undef|Scalar|Slot|ArrayRef|HashRef|ScalarRef|CodeRef)\z/;
        # A reference is boxed by its tag, as any other reading is.
        my $boxed = $from =~ /\A(?:Scalar|Slot)\z/
            ? $rhs_ref
            : $self->_emit_coercion($rhs_ref, $from, 'Scalar', 'store to ' . $lhs->name);
        $self->_emit("  store %Slot $boxed, %Slot* $g  ; store lexical " . $lhs->name);
        $self->{cache}{ $node->id } = $rhs_ref;
        return $rhs_ref;
    }

    # Mode (b): scalar rebind — find the VarDecl the lhs points to.
    my $vd = $lhs;
    if (defined $vd && $vd->operation eq 'PadAccess') {
        $vd = $lhs->inputs->[0];
    }
    unless (defined $vd && $vd->operation eq 'VarDecl') {
        die "LLVM backend: Assign lhs must be a PadAccess(VarDecl), VarDecl, or Subscript(lvalue); "
          . "got " . (defined $vd ? $vd->operation : 'undef');
    }

    $self->{var_table}{ $vd->id } = $rhs_ref;
    $self->{cache}{ $node->id }   = $rhs_ref;
    return $rhs_ref;
}

# ---------------------------------------------------------------------------
# Comparison operators and TernaryExpr (Phase 3c — D6 ternary/select path)
#
# Numeric comparisons lower to LLVM icmp instructions (signed for i64),
# producing i1 results (Boolean representation). These are used as conditions
# for select (TernaryExpr) and eventually for branch instructions.
#
# LLVM icmp predicate mapping (signed integers):
#   NumGt -> sgt (signed greater-than)
#   NumLt -> slt (signed less-than)
#   NumGe -> sge (signed greater-or-equal)
#   NumLe -> sle (signed less-or-equal)
#   NumEq -> eq  (equality, sign-independent)
#   NumNe -> ne  (inequality, sign-independent)
#
# TernaryExpr ($cond ? $true : $false) lowers to `select` when:
#   - condition has Boolean representation (i1, from icmp)
#   - both branches have Int representation (i64)
# This covers D6 from the gap-map without needing Phi or basic blocks.
# ---------------------------------------------------------------------------

my %ICMP_PREDICATE = (
    NumGt => 'sgt',
    NumLt => 'slt',
    NumGe => 'sge',
    NumLe => 'sle',
    NumEq => 'eq',
    NumNe => 'ne',
);

# Float predicates for the same comparison ops, used when an operand is Num or
# Str (numified to a double). ORDERED predicates (o*) for </<=/>/>=/==; UNORDERED
# not-equal (une) for != — matches perl's numeric != on non-NaN doubles and
# treats NaN operands as "not equal", the perl-consistent NaN behavior.
my %FCMP_PREDICATE = (
    NumGt => 'ogt',
    NumLt => 'olt',
    NumGe => 'oge',
    NumLe => 'ole',
    NumEq => 'oeq',
    NumNe => 'une',
);

# _coerce_ref_to_num($ref, $repr): return a `double` SSA ref for a value, coercing
# by its representation. Int -> sitofp; Num -> passthrough; Str -> the perl
# leading-numeric rule via @chalk_str_to_num (same emit as Coerce[Str->Num]).
# Used by numeric comparison over non-Int operands (`"0" == "0"`, the cond.t
# blocker). A Boolean/aggregate operand is a loud GAP (numeric compare over a
# boolean is not a shape we lower runtime-free).
sub _coerce_ref_to_num {
    my ($self, $ref, $repr, $op) = @_;
    return $ref if defined $repr && $repr eq 'Num';
    if (!defined $repr || $repr eq 'Int') {
        # Which instruction (if any) bridges Int to Num is _repr_convert_op's
        # answer, read out of both reprs' machine types. Undef here means the
        # two share a type and the value is already in the right shape --
        # unreachable while Num is a double, correct the moment it is not.
        my $conv = _repr_convert_op('Int', 'Num') or return $ref;
        my $d = $self->_fresh;
        $self->_emit("  $d = $conv " . _repr_to_llvm_type('Int') . " $ref to "
            . _repr_to_llvm_type('Num') . "  ; $op: Int operand -> Num");
        return $d;
    }
    if ($repr eq 'Str') {
        my ($str_ptr, $tracked) = $self->_str_parts($ref);
        $ref = $str_ptr;
        my $len_ref = $tracked // 0;
        $self->{_need_str_to_num_helper} = 1;
        $self->{_need_malloc_memcpy}     = 1;   # it parses a terminated copy
        my $d = $self->_fresh;
        $self->_emit("  $d = call double \@chalk_str_to_num(i8* $ref, i64 $len_ref)  ; $op: Str operand -> double (leading-numeric)");
        return $d;
    }
    die "GAP: $op numeric comparison over a $repr operand is not lowered "
      . "runtime-free (only Int, Num, and Str operands numify). Coerce the "
      . "operand or fix TypeInference.";
}

# _lower_num_cmp($node) -> i64: `<=>`, -1, 0 or 1. Two Ints compare exactly;
# otherwise as doubles. A NaN, where perl's answer is undef, stops the
# program (exit 255).
sub _lower_num_cmp {
    my ($self, $node) = @_;
    my ($l, $r) = $node->inputs->@[0, 1];
    my ($lr, $rr) = map { $_->stamp // '' } $l, $r;
    my ($lv, $rv) = map { $self->lower_value($_) } $l, $r;
    my ($gt, $lt) = map { $self->_fresh } 1 .. 2;
    if ($lr eq 'Int' && $rr eq 'Int') {
        $self->_emit("  $gt = icmp sgt i64 $lv, $rv  ; <=>");
        $self->_emit("  $lt = icmp slt i64 $lv, $rv");
    }
    else {
        my $ld = $self->_coerce_ref_to_num($lv, $lr, 'NumCmp');
        my $rd = $self->_coerce_ref_to_num($rv, $rr, 'NumCmp');
        my ($uno, $nan, $ok) = ($self->_fresh, $self->_fresh_label('cmp.nan.'), $self->_fresh_label('cmp.ok.'));
        my $nty = _repr_to_llvm_type('Num');
        $self->_emit("  $uno = fcmp uno $nty $ld, $rd  ; <=>: a NaN?");
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $uno, label %$nan, label %$ok");
        $self->_new_block($nan);
        $self->_emit("  call void \@exit(i32 255)  ; <=> of a NaN is undef, not lowered");
        $self->_set_terminator("  unreachable");
        $self->_new_block($ok);
        $self->_emit("  $gt = fcmp ogt $nty $ld, $rd  ; <=>");
        $self->_emit("  $lt = fcmp olt $nty $ld, $rd");
    }
    my ($g, $s, $res) = map { $self->_fresh } 1 .. 3;
    $self->_emit("  $g = zext i1 $gt to i64");
    $self->_emit("  $s = zext i1 $lt to i64");
    $self->_emit("  $res = sub i64 $g, $s  ; <=>: -1, 0 or 1");
    return $self->{cache}{ $node->id } = $res;
}

# _lower_str_cmp($node) -> i64: `cmp`, -1, 0 or 1 -- bytes compared over the
# shorter length, then the shorter first.
sub _lower_str_cmp {
    my ($self, $node) = @_;
    my $lhs = $self->_str_compare_operand($node->inputs->[0], 'StrCmp', 'lhs');
    my $rhs = $self->_str_compare_operand($node->inputs->[1], 'StrCmp', 'rhs');
    my ($lp, $ll) = $self->_str_parts($lhs);
    my ($rp, $rl) = $self->_str_parts($rhs);
    $self->{_need_memcmp} = 1;
    my ($shorter, $min, $m, $mgt, $mlt, $lgt, $llt, $meq, $gt, $lt, $g, $s, $res) = map { $self->_fresh } 1 .. 13;
    $self->_emit("  $shorter = icmp ult i64 $ll, $rl");
    $self->_emit("  $min = select i1 $shorter, i64 $ll, i64 $rl");
    $self->_emit("  $m = call i32 \@memcmp(i8* $lp, i8* $rp, i64 $min)  ; cmp: the common bytes");
    $self->_emit("  $mgt = icmp sgt i32 $m, 0");
    $self->_emit("  $mlt = icmp slt i32 $m, 0");
    $self->_emit("  $meq = icmp eq i32 $m, 0");
    $self->_emit("  $lgt = icmp ugt i64 $ll, $rl");
    $self->_emit("  $llt = icmp ult i64 $ll, $rl");
    my ($eg, $el) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $eg = and i1 $meq, $lgt");
    $self->_emit("  $el = and i1 $meq, $llt");
    $self->_emit("  $gt = or i1 $mgt, $eg  ; cmp: after");
    $self->_emit("  $lt = or i1 $mlt, $el  ; cmp: before");
    $self->_emit("  $g = zext i1 $gt to i64");
    $self->_emit("  $s = zext i1 $lt to i64");
    $self->_emit("  $res = sub i64 $g, $s  ; cmp: -1, 0 or 1");
    return $self->{cache}{ $node->id } = $res;
}

sub _lower_icmp_int {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    my $op   = $node->operation;

    if (defined $repr && $repr eq 'Scalar') {
        die "$op with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $inputs  = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];
    my $lhs_repr = $lhs_node->stamp;
    my $rhs_repr = $rhs_node->stamp;
    my $lhs_ref = $self->lower_value($lhs_node);
    my $rhs_ref = $self->lower_value($rhs_node);

    # If BOTH operands are Int, compare as i64 (the fast integer path). If either
    # is Num or Str, perl numifies both and compares as numbers -> coerce each to
    # a double and fcmp. `"0" == "0"` (Str operands) is the t/base/cond.t blocker;
    # `3 == 3.0` (Int vs Num) also lands here.
    my $lhs_int = !defined $lhs_repr || $lhs_repr eq 'Int';
    my $rhs_int = !defined $rhs_repr || $rhs_repr eq 'Int';
    if ($lhs_int && $rhs_int) {
        my $pred = $ICMP_PREDICATE{$op}
            or die "LLVM backend: unknown comparison op=$op";
        my $ref = $self->_fresh;
        $self->_emit("  $ref = icmp $pred i64 $lhs_ref, $rhs_ref  ; $op(Boolean) -> i1 icmp $pred");
        $self->{cache}{$node->id} = $ref;
        return $ref;
    }

    # Both operands are numified to the Num representation, so WHICH predicate
    # table applies -- and which compare instruction -- follows from Num's
    # machine type rather than from the fact that it is called Num. The two
    # tables are not a naming variation: NumNe is `une` here and `ne` there,
    # because unordered-not-equal is what makes NaN compare perl-style. Picking
    # the table IS the representation decision, so it is asked for.
    my $numeric = _repr_is_float('Num');
    my $cmp     = _repr_opcode('icmp', 'Num');
    my $fpred   = ($numeric ? $FCMP_PREDICATE{$op} : $ICMP_PREDICATE{$op})
        or die "LLVM backend: unknown comparison op=$op";
    my $nty   = _repr_to_llvm_type('Num');
    my $lhs_d = $self->_coerce_ref_to_num($lhs_ref, $lhs_repr, $op);
    my $rhs_d = $self->_coerce_ref_to_num($rhs_ref, $rhs_repr, $op);
    my $ref = $self->_fresh;
    $self->_emit("  $ref = $cmp $fpred $nty $lhs_d, $rhs_d  ; $op(Boolean) -> i1 $cmp $fpred (numified operands)");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# ---------------------------------------------------------------------------
# String comparison: StrEq (eq) and StrNe (ne).
#
# A Str value in this backend is {ptr (i8*), len} — the byte-length tracked in
# _str_len_table keyed by the ptr's SSA ref (the same accessor Concat and the
# regex slices use). String equality is: same length AND memcmp(a, b, len) == 0.
# The length guard must gate the memcmp — memcmp reads len_a bytes from BOTH
# buffers, so calling it when the lengths differ would over-read the shorter
# one. So a branch, not a select (a select evaluates both arms):
#
#   entry:      len_eq = icmp eq i64 len_a, len_b
#               br i1 len_eq, %cmp, %end     ; unequal length -> not equal
#   cmp:        m = call i32 @memcmp(a, b, len_a)
#               bytes_eq = icmp eq i32 m, 0
#               br %end
#   end:        equal = phi i1 [ false, %entry ], [ bytes_eq, %cmp ]
#
# StrEq returns `equal`; StrNe returns `xor i1 equal, true` (the negation).
# Both yield an i1 (Boolean repr), consumed by the ternary condition / return.
# ---------------------------------------------------------------------------
# _str_compare_operand($input, $op, $side) -> an i8* Str ref (with a tracked
# length) for a StrEq/StrNe operand. A Str operand lowers as-is; an Int operand
# is stringified to its decimal form (perl stringifies a number for `eq`/`ne`);
# any other repr (Num, aggregate) is a loud GAP.
sub _str_compare_operand {
    my ($self, $input, $op, $side) = @_;
    my $repr = $self->_repr_of($input) // $input->stamp // '';
    my $ref  = $self->lower_value($input);
    return $ref if $repr eq 'Str';
    # A SCALAR IS STRINGIFIED BY ITS TAG -- the Coerce the producer would
    # have inserted had it known the operand's type (a method's value).
    return $self->_emit_coercion($ref, 'Scalar', 'Str', "$op $side") if $repr eq 'Scalar';
    # StrEq/StrNe's signature is (Str, Str). A non-Str operand arrives through
    # an explicit Stringify inserted by the producer, exactly as Print's
    # arguments do -- `eq` does not know how to render any representation.
    #
    # It used to call _emit_int_to_str itself, which put the int-to-decimal
    # renderer in two places (here and Stringify) and left Num "unbuilt for
    # eq/ne" even after Stringify could render one. One coercion, one renderer.
    die "GAP: $op $side operand has repr=$repr; string comparison takes Str, so "
      . "this needs a Coerce(X -> Str) (the producer inserts one for a "
      . "stamped non-Str operand).";
}

sub _lower_str_compare {
    my ($self, $node, $is_eq) = @_;

    my $op = $node->operation;
    my $repr = $node->stamp;
    if (defined $repr && $repr eq 'Scalar') {
        die "$op with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $inputs  = $node->inputs;
    # `eq`/`ne` compare STRINGS: an Int operand (`$a eq "1"` where $a is an int)
    # is stringified to its decimal form first (perl's string context), so both
    # operands become length-tracked {ptr,len} Str values for the memcmp.
    my $lhs_ref = $self->_str_compare_operand($inputs->[0], $op, 'lhs');
    my $rhs_ref = $self->_str_compare_operand($inputs->[1], $op, 'rhs');

    # Both operand lengths must be tracked; a Str with no recorded length can't
    # be compared byte-exact (an untracked length would make the len guard and
    # the memcmp size guesses). GAP loudly rather than emit a wrong-size memcmp.
    my ($lhs_ptr, $lhs_len) = $self->_str_parts($lhs_ref);
    my ($rhs_ptr, $rhs_len) = $self->_str_parts($rhs_ref);
    ($lhs_ref, $rhs_ref) = ($lhs_ptr, $rhs_ptr);
    my $len_a = $lhs_len
        // die "$op cannot lower — lhs operand length not tracked in "
             . "_str_len_table (ptr=$lhs_ref). String compare needs both {ptr,len}.";
    my $len_b = $rhs_len
        // die "$op cannot lower — rhs operand length not tracked in "
             . "_str_len_table (ptr=$rhs_ref). String compare needs both {ptr,len}.";

    $self->{_need_memcmp} = 1;

    my $entry_label = $self->_current_block_label;
    my $len_eq = $self->_fresh;
    $self->_emit("  $len_eq = icmp eq i64 $len_a, $len_b  ; $op: same length?");

    my $cmp_label = $self->_fresh_label('streq.cmp.');
    my $end_label = $self->_fresh_label('streq.end.');
    $self->_set_terminator("  br i1 $len_eq, label %$cmp_label, label %$end_label  ; $op: length guard gates memcmp");

    # cmp block: lengths equal, byte-compare.
    $self->_new_block($cmp_label);
    my $memcmp_res = $self->_fresh;
    my $bytes_eq   = $self->_fresh;
    $self->_emit("  $memcmp_res = call i32 \@memcmp(i8* nocapture readonly $lhs_ref, i8* nocapture readonly $rhs_ref, i64 $len_a)  ; $op: byte compare");
    $self->_emit("  $bytes_eq = icmp eq i32 $memcmp_res, 0  ; $op: bytes equal?");
    my $cmp_end_label = $self->_current_block_label;   # memcmp emits no blocks; == $cmp_label
    $self->_set_terminator("  br label %$end_label  ; $op: cmp falls through to end");

    # end block: phi. Length-mismatch path is false; byte path carries bytes_eq.
    $self->_new_block($end_label);
    my $equal = $self->_fresh;
    $self->_emit("  $equal = phi i1 [ false, %$entry_label ], [ $bytes_eq, %$cmp_end_label ]  ; $op: equal?");

    my $result = $equal;
    unless ($is_eq) {
        # StrNe = negation of equality (xor i1 equal, true).
        $result = $self->_fresh;
        $self->_emit("  $result = xor i1 $equal, true  ; StrNe: negate equality");
    }

    $self->{cache}{$node->id} = $result;
    return $result;
}

# _lower_ternary_by_slot($node) -> %Slot: `C ? A : B` whose join is a Scalar.
# BRANCHED, not a select: an arm need not be safe to evaluate when not taken
# -- a foreach over @_ reads `exists $_[$i] ? $$alias : $_[$i]`, and the
# deref of the alias it did not make is a load through null. Each arm is
# lowered in its own block, boxed (an element read keeping its miss), and
# what it cached is dropped with it, as an if arm's is.
sub _lower_ternary_by_slot {
    my ($self, $node) = @_;
    my ($c, $t, $f) = $node->inputs->@*;
    my $cond = $self->_ensure_i1($self->lower_value($c), $self->_repr_of($c) // _require_repr($c, 'TernaryExpr.condition'));
    my ($tl, $fl, $end) = map { $self->_fresh_label("tern.$_.") } qw(t f end);
    $self->_set_terminator("  br i1 $cond, label %$tl, label %$fl  ; ?: (Scalar)");
    my @in;
    for my $arm ([$tl, $t], [$fl, $f]) {
        my ($label, $n) = @$arm;
        $self->_new_block($label);
        my %before = map { $_ => 1 } keys %{ $self->{cache} };
        my $ref  = $self->lower_value($n);
        my $from = $n->operation eq 'Print' ? 'Boolean' : ($n->stamp // '');
        ($ref, $from) = $self->_miss_kept($n, $ref, $from);
        my $slot = $self->_slot_of_value($n, $ref, '?: arm');
        push @in, "[ $slot, %" . $self->_current_block_label . " ]";
        $self->_set_terminator("  br label %$end");
        delete @{ $self->{cache} }{ grep { !$before{$_} } keys %{ $self->{cache} } };
    }
    $self->_new_block($end);
    my $res = $self->_fresh;
    $self->_emit("  $res = phi %Slot " . join(', ', @in) . "  ; ?: (Scalar)");
    return $self->{cache}{ $node->id } = $res;
}

sub _lower_ternary {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    my $op   = $node->operation;

    return $self->_lower_ternary_by_slot($node) if defined $repr && $repr eq 'Scalar';

    my $inputs    = $node->inputs;
    my $cond_node = $inputs->[0];
    my $true_node = $inputs->[1];
    my $fals_node = $inputs->[2];

    # Lower the condition. Any scalar is a valid Perl guard (`$x = 7 if $c`,
    # `$c ? 7 : 9`), so coerce to i1 via truthiness: Boolean passes through,
    # Int -> icmp ne, Num -> fcmp une (the same rule _lower_not applies).
    my $cond_ref  = $self->lower_value($cond_node);
    my $cond_repr = $self->_repr_of($cond_node) // _require_repr($cond_node, 'TernaryExpr.condition');
    $cond_ref = $self->_ensure_i1($cond_ref, $cond_repr);

    # BOTH ARMS ARRAYS (`for ($c ? @$x : ())`): the list is the taken arm's
    # array itself, as perl's is (its elements aliased), and the other arm
    # is never made -- branched, each arm lowered in its own block.
    if (( $true_node->stamp // '' ) eq 'Array' && ( $fals_node->stamp // '' ) eq 'Array') {
        my ($tl, $fl, $end) = map { $self->_fresh_label("tern.$_.") } qw(t f end);
        $self->_set_terminator("  br i1 $cond_ref, label %$tl, label %$fl  ; ?: (Array)");
        my @in;
        for my $arm ([$tl, $true_node], [$fl, $fals_node]) {
            my ($label, $n) = @$arm;
            $self->_new_block($label);
            my %before = map { $_ => 1 } keys %{ $self->{cache} };
            my $ref = $self->lower_value($n);
            push @in, "[ $ref, %" . $self->_current_block_label . " ]";
            $self->_set_terminator("  br label %$end");
            delete @{ $self->{cache} }{ grep { !$before{$_} } keys %{ $self->{cache} } };
        }
        $self->_new_block($end);
        my $res = $self->_fresh;
        $self->_emit("  $res = phi " . _repr_to_llvm_type('Array') . " " . join(', ', @in) . "  ; ?: (Array)");
        return $self->{cache}{ $node->id } = $res;
    }

    # Lower the true and false branches: must be same type (Int -> i64).
    my $true_ref = $self->lower_value($true_node);
    my $fals_ref = $self->lower_value($fals_node);

    # Determine the branch type for the select.
    my $true_repr = _require_repr($true_node, 'TernaryExpr.true_branch');
    my $fals_repr = _require_repr($fals_node, 'TernaryExpr.false_branch');

    # A merge yields one of its ARMS, so `$c ? 42 : "hi"` really is an Int on
    # one path and a Str on the other. The select is ONE instruction and needs
    # ONE machine type, so a non-conforming arm is bridged by a coercion to the
    # node's own repr -- which the loader already set to the JOIN of the arms.
    # This is the operator rule (Part J) applied to a merge: the merge states
    # its type, the arms conform. NOT a wider repr on the node; the arms are
    # what disagree, and widening the node would leave the select ill-typed.
    if (defined $repr && $true_repr ne $fals_repr) {
        $true_ref  = $self->_emit_coercion($true_ref, $true_repr, $repr,
                                           'TernaryExpr.true_branch');
        $fals_ref  = $self->_emit_coercion($fals_ref, $fals_repr, $repr,
                                           'TernaryExpr.false_branch');
        ($true_repr, $fals_repr) = ($repr, $repr);
    }

    # Both arms statically Undef (a discarded if/else field-mutation residual):
    # the result is Undef regardless of the guard. The Undef repr is the i1
    # defined-bit (always false), so short-circuit to a constant 0 -- no select.
    if ($true_repr eq 'Undef' && $fals_repr eq 'Undef') {
        $self->{cache}{$node->id} = '0';
        return '0';
    }

    # Str branches (`print $c ? "y\n" : "n\n"`): a Str is {ptr, len}. Select the
    # i8* ptr on the guard, AND select the length so _str_len_table tracks the
    # chosen arm's byte count (a downstream print/concat slices exactly len
    # bytes). Both arms must be Str; a length must be tracked for each.
    if ($true_repr eq 'Str' && $fals_repr eq 'Str') {
        my ($true_ptr, $true_len_t) = $self->_str_parts($true_ref);
        my ($fals_ptr, $fals_len_t) = $self->_str_parts($fals_ref);
        ($true_ref, $fals_ref) = ($true_ptr, $fals_ptr);
        my $true_len = $true_len_t
            // die "LLVM backend: TernaryExpr Str true-branch (ref=$true_ref) has no tracked length";
        my $fals_len = $fals_len_t
            // die "LLVM backend: TernaryExpr Str false-branch (ref=$fals_ref) has no tracked length";
        my $ptr = $self->_fresh;
        $self->_emit("  $ptr = select i1 $cond_ref, i8* $true_ref, i8* $fals_ref"
            . "  ; TernaryExpr(Str) -> select ptr");
        my $len = $self->_fresh;
        $self->_emit("  $len = select i1 $cond_ref, i64 $true_len, i64 $fals_len"
            . "  ; TernaryExpr(Str) -> select len");
        $ptr = $self->_set_str_len($ptr, $len);
        $self->{cache}{$node->id} = $ptr;
        return $ptr;
    }

    # The two-arm literal chain that stood here ('i64' for Int, 'double' for
    # Num) was a copy of %_REPR_LLVM_TYPE narrowed to two entries. The real
    # condition is that the arms AGREE on a representation; what that
    # representation looks like on the machine is not this site's question.
    die "LLVM backend: TernaryExpr branches have mismatched or unsupported types "
      . "(true=$true_repr, false=$fals_repr)"
        unless ($true_repr eq 'Int' || $true_repr eq 'Num')
            && $true_repr eq $fals_repr;
    my $branch_type = _repr_to_llvm_type($true_repr);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = select i1 $cond_ref, $branch_type $true_ref, $branch_type $fals_ref"
        . "  ; TernaryExpr -> select");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# ---------------------------------------------------------------------------
# Short-circuit logical operators: And (&&) and Or (||)
#
# Both operators return ONE OF THEIR OPERANDS, not a boolean.
# Implementation uses basic blocks + conditional branch + phi.
#
# And(a, b):
#   Evaluate a. Test a != 0 (truthy). If true -> evaluate b, go to end.
#   If false -> skip b, go to end with a.
#   phi merges: [a from entry/prior-block] or [b from rhs-block].
#
# Or(a, b):
#   Evaluate a. Test a != 0 (truthy). If true -> skip b, go to end with a.
#   If false -> evaluate b, go to end.
#   phi merges: [a from entry/prior-block] or [b from rhs-block].
#
# The RHS is evaluated INSIDE a separate block (short-circuit: side effects
# in the RHS only happen if the test takes the rhs branch).
# ---------------------------------------------------------------------------

# _shortcircuit_i1_cond: emit the i1 branch condition for an And/Or LHS given
# its representation, and validate the operand repr for the short-circuit path.
#
# Int truthiness is `icmp ne i64 %v, 0`. Boolean is already an i1 (a comparison
# result, a `!`, or a print's builtin::is_bool return) — its truthiness is the
# identity, so we branch on the value directly with no extra instruction. Any
# other repr (Num, Str, ...) is a loud GAP: reinterpreting a double/i8* as i64
# would miscompile. $op_tag ('And'/'Or') and $side ('LHS'/'RHS') name the GAP.
sub _shortcircuit_i1_cond {
    my ($self, $ref, $repr, $op_tag, $side) = @_;
    my $sym = $op_tag eq 'And' ? '&&' : '||';
    unless (defined $repr) {
        die "$op_tag ($sym) $side operand has no representation at lowering time (G.7/F8). "
          . "Fix TypeInference to annotate the operand.";
    }
    if ($repr eq 'Int') {
        my $cond = $self->_fresh;
        $self->_emit("  $cond = icmp ne i64 $ref, 0  ; $op_tag: test $side truthiness (Int)");
        return $cond;
    }
    if ($repr eq 'Boolean') {
        # Already an i1 — the value IS the branch condition.
        return $ref;
    }
    # ANY OTHER SCALAR by perl's truth for it -- the same test an if takes
    # (_ensure_i1). Not an aggregate: `@a && X` yields the COUNT when false
    # (scalar context), which merging the array would not (pvm 089).
    return $self->_ensure_i1($ref, $repr) if $repr =~ /\A(?:Str|Num|Scalar)\z/;
    die "GAP: $op_tag ($sym) $side operand has repr=$repr; only Int and Boolean truthiness are "
      . "lowered runtime-free (G.7/F8). Insert an explicit Coerce(*->Boolean) node before the "
      . "$op_tag, or fix TypeInference.";
}

# _shortcircuit_phi_repr: pick the repr (hence LLVM type) for the merge phi of an
# And/Or. `A && B` returns one of its operands, so the phi's arms are the two
# operand refs and its type must be a single machine type both arms share.
#
# The And/Or node's own repr is often unannotated for the short-circuit form
# (`$x eq $x && print ...`), so we derive the phi type from the operands: if both
# operands share a repr, use it; if the node itself carries a concrete repr, trust
# it. A genuine mismatch (Int LHS, Boolean RHS) can't phi over two machine types —
# GAP loudly rather than emit invalid IR.
sub _shortcircuit_phi_repr {
    my ($self, $node_repr, $lhs_repr, $rhs_repr, $op_tag) = @_;
    my $sym = $op_tag eq 'And' ? '&&' : '||';
    if (defined $lhs_repr && defined $rhs_repr && $lhs_repr eq $rhs_repr) {
        return $lhs_repr;
    }
    # Operands disagree. A node repr does NOT rescue this: the phi's two arms are
    # the operand SSA refs themselves, so they must already share a machine type
    # (Int=i64, Boolean=i1, Num=double, Str=ptr). Trusting $node_repr here emitted
    # invalid IR — measured: And(Int, Num) produced
    #   %t3 = fadd double 0.0, 2.5
    #   %t4 = phi i64 [ %t1, %entry ], [ %t3, %and.rhs ]
    # a double feeding an i64 phi. The RHS is NOT a branch condition (it is the
    # expression's value when the LHS is truthy), so _shortcircuit_i1_cond never
    # inspects it — this was the only place the mismatch could be caught, and the
    # fallback below skipped it. GAP loudly instead, per this function's own
    # stated contract.
    die "GAP: $op_tag ($sym) operands have mismatched reprs (LHS="
      . (defined $lhs_repr ? $lhs_repr : 'undef') . ", RHS="
      . (defined $rhs_repr ? $rhs_repr : 'undef') . "); a merge phi needs one shared "
      . "machine type. Insert a Coerce so both operands share a repr, or fix TypeInference.";
}

sub _lower_and {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    # NO Scalar REFUSAL HERE ANY MORE. It predated `Scalar` having a machine
    # type: it does now (%Slot), `_emit_coercion` boxes any narrowed reading
    # into one, and `_emit_read_slot_as` reads it back by tag. What was
    # genuinely missing was at T1 -- `%_COERCIBLE_TO` had no Scalar row at all,
    # so `Scalar -> Boolean` did not exist as far as the type layer knew, and
    # this path could not ask for the bridge it needed.
    #
    # WHY THE MERGE IS Scalar AT ALL, since it looks like a defect and is not:
    # `$x eq $x && (print ...)` has a Boolean guard and a Boolean-returning
    # print -- but a FAILED print returns undef, so the join is Scalar. That is
    # the honest type of "one of these two values", and the %Slot ABI is what
    # carries it. Narrowing it away would be the claim that print cannot fail.

    my $inputs = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];

    # Validate operand reprs: Int (icmp ne i64) and Boolean (already i1) both lower
    # runtime-free. `$x eq $y && (print ...)` is Boolean && Boolean (a comparison guard
    # and a print's builtin::is_bool return) — the cond.t idiom. Any other repr is
    # a loud GAP (see _shortcircuit_i1_cond).
    my $lhs_repr = $self->_repr_of($lhs_node) // $lhs_node->stamp;   # an inlined argument as held
    my $rhs_repr = $rhs_node->operation eq "Print" ? "Boolean" : $self->_repr_of($rhs_node) // $rhs_node->stamp;

    # `&&` yields one of its OPERANDS, not a boolean -- measured:
    # `my $a=5; my $b="hi"; $a && $b` is "hi", and with $a=0 it is 0. So the two
    # arms genuinely differ in type, and the merge phi (ONE instruction, ONE
    # machine type) needs them bridged. The merge repr is the node's own when it
    # has one; otherwise the arms must already agree and
    # _shortcircuit_phi_repr GAPs.
    #
    # The bridge must be emitted where each value is LIVE: the LHS in the entry
    # block, the RHS in the rhs block. Coercing both after _new_block($end) --
    # the obvious place, next to the phi -- would reference the LHS in a block
    # it never flowed to, which is invalid IR rather than a wrong answer.
    # BRIDGE AGAINST THE MERGE TYPE, NOT AGAINST THE OTHER ARM. This asked
    # whether the two arms differ FROM EACH OTHER, which is the wrong
    # comparison: the phi's machine type comes from the NODE's repr, so an arm
    # needs a coercion whenever it differs from THAT -- and two arms can agree
    # with each other while both differ from it.
    #
    # Measured on `$x eq $x && (print "y\n")`: a Boolean guard and a
    # Boolean-returning print, so `$lhs_repr eq $rhs_repr` and no coercion was
    # emitted -- but the And's own repr is Scalar (a failed print returns undef,
    # so the join of the two arms is Scalar, not Boolean). Two i1 values then
    # fed a `phi %Slot` and lli refused: "'%tmp_23' defined with type 'i1' but
    # expected '%Slot'".
    #
    # _emit_coercion is a no-op when a side already matches, so widening the
    # condition costs nothing on the paths that were already correct.
    # A MERGE NOTHING TYPED -- an operand an inlined argument, known only
    # here -- boxes its arms to the Scalar they both are.
    if (( $repr // 'Unknown' ) eq 'Unknown' && defined $lhs_repr && defined $rhs_repr
            && !grep { !/\A(?:Int|Num|Str|Boolean|Undef|Scalar)\z/ } $lhs_repr, $rhs_repr) {
        $repr = $lhs_repr eq $rhs_repr ? $lhs_repr : 'Scalar';   # agreeing arms keep their type
        $self->{cache}{ 'repr:' . $node->id } = $repr;   # this lowering's, not the node's: inlined again, its arguments differ
    }
    my $merge_repr = (defined $repr && defined $lhs_repr && defined $rhs_repr
                        && ($lhs_repr ne $repr || $rhs_repr ne $repr))
                   ? $repr : undef;

    # Lower the LHS in the current block, then test its truthiness.
    my $lhs_ref    = $self->lower_value($lhs_node);
    my $cond = $self->_shortcircuit_i1_cond($lhs_ref, $lhs_repr, 'And', 'LHS');
    if (defined $merge_repr) {
        $lhs_ref = $self->_emit_coercion($lhs_ref, $lhs_repr, $merge_repr,
                                         'And.LHS');
    }
    # AFTER the coercion: its instructions land in this block, and a Str
    # conversion opens continuation blocks, so the phi's incoming label must be
    # whatever block the value actually ends up in.
    my $entry_label = $self->_current_block_label;

    # Allocate block labels.
    my $rhs_label = $self->_fresh_label('and.rhs.');
    my $end_label = $self->_fresh_label('and.end.');

    # Conditional branch: truthy -> rhs block; falsy -> end block with lhs.
    $self->_set_terminator("  br i1 $cond, label %$rhs_label, label %$end_label  ; And: short-circuit branch");

    # RHS block: evaluate the RHS, then jump to end. Validate its repr here so a
    # side-effect-only RHS (a print) is still checked against the phi type below.
    $self->_new_block($rhs_label);
    # What the right side makes is this block's: cached past it, a later use
    # of a shared node (a folded `2 < 1`) was not dominated (as an if arm's).
    my %before        = map { $_ => 1 } keys %{ $self->{cache} };
    my $rhs_ref       = $self->lower_value($rhs_node);
    if (defined $merge_repr) {
        $rhs_ref = $self->_emit_coercion($rhs_ref, $rhs_repr, $merge_repr,
                                         'And.RHS');
    }
    delete @{ $self->{cache} }{ grep { !$before{$_} && !/\Arepr:/ } keys %{ $self->{cache} } };
    my $rhs_end_label = $self->_current_block_label;   # may differ if rhs has its own blocks
    $self->_set_terminator("  br label %$end_label  ; And: rhs falls through to end");

    # End block: phi merges lhs (falsy path) and rhs (truthy path). The phi type is
    # the operands' common repr — the And node's own repr is often unannotated for the
    # short-circuit form, so derive it from the operands. Int && Int -> i64, Boolean &&
    # Boolean -> i1. Mixed operand reprs (Int LHS, Boolean RHS) would need a phi over two
    # machine types, which is invalid LLVM: GAP loudly rather than emit a bad phi.
    my $phi_repr = defined $merge_repr ? $merge_repr
        : $self->_shortcircuit_phi_repr($repr, $lhs_repr, $rhs_repr, 'And');
    $self->_new_block($end_label);
    my $result = $self->_emit_shortcircuit_phi($phi_repr, $lhs_ref, $entry_label,
                                               $rhs_ref, $rhs_end_label, 'And');

    $self->{cache}{$node->id} = $result;
    return $result;
}

sub _lower_or {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    # NO Scalar REFUSAL HERE ANY MORE. It predated `Scalar` having a machine
    # type: it does now (%Slot), `_emit_coercion` boxes any narrowed reading
    # into one, and `_emit_read_slot_as` reads it back by tag. What was
    # genuinely missing was at T1 -- `%_COERCIBLE_TO` had no Scalar row at all,
    # so `Scalar -> Boolean` did not exist as far as the type layer knew, and
    # this path could not ask for the bridge it needed.
    #
    # WHY THE MERGE IS Scalar AT ALL, since it looks like a defect and is not:
    # `$x eq $x || (print ...)` has a Boolean guard and a Boolean-returning
    # print -- but a FAILED print returns undef, so the join is Scalar. That is
    # the honest type of "one of these two values", and the %Slot ABI is what
    # carries it. Narrowing it away would be the claim that print cannot fail.

    my $inputs = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];

    # Validate operand reprs: Int (icmp ne i64) and Boolean (already i1) both lower
    # runtime-free. `$x ne $y || (print ...)` is Boolean || Boolean — the cond.t idiom.
    # Any other repr is a loud GAP (see _shortcircuit_i1_cond).
    my $lhs_repr = $self->_repr_of($lhs_node) // $lhs_node->stamp;   # an inlined argument as held
    my $rhs_repr = $rhs_node->operation eq "Print" ? "Boolean" : $self->_repr_of($rhs_node) // $rhs_node->stamp;

    # `||` yields one of its OPERANDS, so its arms can differ in type. Same rule
    # and same block-placement constraint as _lower_and: the bridge is emitted
    # where each value is LIVE, not next to the phi.
    # BRIDGE AGAINST THE MERGE TYPE, NOT AGAINST THE OTHER ARM. This asked
    # whether the two arms differ FROM EACH OTHER, which is the wrong
    # comparison: the phi's machine type comes from the NODE's repr, so an arm
    # needs a coercion whenever it differs from THAT -- and two arms can agree
    # with each other while both differ from it.
    #
    # Measured on `$x eq $x && (print "y\n")`: a Boolean guard and a
    # Boolean-returning print, so `$lhs_repr eq $rhs_repr` and no coercion was
    # emitted -- but the And's own repr is Scalar (a failed print returns undef,
    # so the join of the two arms is Scalar, not Boolean). Two i1 values then
    # fed a `phi %Slot` and lli refused: "'%tmp_23' defined with type 'i1' but
    # expected '%Slot'".
    #
    # _emit_coercion is a no-op when a side already matches, so widening the
    # condition costs nothing on the paths that were already correct.
    # A MERGE NOTHING TYPED -- an operand an inlined argument, known only
    # here -- boxes its arms to the Scalar they both are.
    if (( $repr // 'Unknown' ) eq 'Unknown' && defined $lhs_repr && defined $rhs_repr
            && !grep { !/\A(?:Int|Num|Str|Boolean|Undef|Scalar)\z/ } $lhs_repr, $rhs_repr) {
        $repr = $lhs_repr eq $rhs_repr ? $lhs_repr : 'Scalar';   # agreeing arms keep their type
        $self->{cache}{ 'repr:' . $node->id } = $repr;   # this lowering's, not the node's: inlined again, its arguments differ
    }
    my $merge_repr = (defined $repr && defined $lhs_repr && defined $rhs_repr
                        && ($lhs_repr ne $repr || $rhs_repr ne $repr))
                   ? $repr : undef;

    # Lower the LHS in the current block, then test its truthiness.
    my $lhs_ref    = $self->lower_value($lhs_node);
    my $cond = $self->_shortcircuit_i1_cond($lhs_ref, $lhs_repr, 'Or', 'LHS');
    if (defined $merge_repr) {
        $lhs_ref = $self->_emit_coercion($lhs_ref, $lhs_repr, $merge_repr,
                                         'Or.LHS');
    }
    my $entry_label = $self->_current_block_label;

    # Allocate block labels.
    my $rhs_label = $self->_fresh_label('or.rhs.');
    my $end_label = $self->_fresh_label('or.end.');

    # Conditional branch: truthy -> end block with lhs; falsy -> rhs block.
    $self->_set_terminator("  br i1 $cond, label %$end_label, label %$rhs_label  ; Or: short-circuit branch");

    # RHS block: evaluate the RHS, then jump to end.
    $self->_new_block($rhs_label);
    my %before        = map { $_ => 1 } keys %{ $self->{cache} };   # the arm's own (see _lower_and)
    my $rhs_ref       = $self->lower_value($rhs_node);
    if (defined $merge_repr) {
        $rhs_ref = $self->_emit_coercion($rhs_ref, $rhs_repr, $merge_repr,
                                         'Or.RHS');
    }
    delete @{ $self->{cache} }{ grep { !$before{$_} && !/\Arepr:/ } keys %{ $self->{cache} } };
    my $rhs_end_label = $self->_current_block_label;
    $self->_set_terminator("  br label %$end_label  ; Or: rhs falls through to end");

    # End block: phi merges lhs (truthy path) and rhs (falsy path). Same phi-type
    # rule as _lower_and: the operands' common repr, or a concrete node repr; a
    # mismatch GAPs loudly.
    my $phi_repr = defined $merge_repr ? $merge_repr
        : $self->_shortcircuit_phi_repr($repr, $lhs_repr, $rhs_repr, 'Or');
    $self->_new_block($end_label);
    my $result = $self->_emit_shortcircuit_phi($phi_repr, $lhs_ref, $entry_label,
                                               $rhs_ref, $rhs_end_label, 'Or');

    $self->{cache}{$node->id} = $result;
    return $result;
}

# _emit_shortcircuit_phi($repr, $lhs, $lhs_lbl, $rhs, $rhs_lbl, $tag) -> ref
#
# The merge phi for a short-circuit (&&/||). Shared by _lower_and and
# _lower_or, which differ only in which arm is the short-circuit path.
#
# A Str is a (ptr, len) PAIR, so merging two strings needs TWO phis: one over
# the pointers and one over the lengths. Without the length phi the result
# pointer has no tracked length and the first consumer GAPs ("Print of a Str
# arg whose length is not tracked") -- which is how this surfaced, since a
# same-repr Str && Str never reached here before the mixed-arm coercion made
# Str a possible merge type.
sub _emit_shortcircuit_phi {
    my ($self, $repr, $lhs_ref, $lhs_label, $rhs_ref, $rhs_label, $tag) = @_;

    my $result    = $self->_fresh;
    my $llvm_type = _repr_to_llvm_type($repr);
    $self->_emit("  $result = phi $llvm_type [ $lhs_ref, \%$lhs_label ], [ $rhs_ref, \%$rhs_label ]  ; $tag: phi");

    # NOTHING TO DO FOR Str — and that is the point of the %Str migration.
    #
    # This used to emit a SECOND, PARALLEL `phi i64` for the length beside the
    # pointer phi, and to die with "an arm's length is not tracked" when the
    # side table had lost one. A merge was exactly where the two could
    # desynchronize: the pointer phi'd and the length did not.
    #
    # The phi above is typed `%Str`, so the pointer, the length and the encoding
    # travel through the merge as ONE VALUE. They cannot disagree, so the guard
    # has nothing left to guard and the parallel phi has nothing left to carry.
    # The failure class is deleted BY CONSTRUCTION rather than by discipline.

    return $result;
}

# ---------------------------------------------------------------------------
# DefinedOr (//) and Defined lowering
#
# DefinedOr(lhs, rhs) :T — returns lhs when lhs is DEFINED, rhs otherwise.
# This is a definedness check, NOT a truthiness check (unlike || which uses
# icmp-ne-0). The definedness predicate is: is the value NOT Undef?
#
# Lowering strategy (static-dispatch on LHS representation):
#
#   LHS repr = Undef (always undef, static):
#     The LHS is an Undef-typed value. Its defined bit was set to false via
#     the alloca+store+load idiom in _lower_constant. We read it and branch:
#       br i1 %defined_bit, %dor.defined, %dor.undef
#     The phi in the end block merges LHS payload (defined path) or RHS value
#     (undef path). Since the defined bit is always false for Undef-typed LHS,
#     the optimizer is FREE to eliminate the dead defined path — but the IR
#     must be well-formed (both phi arms present) for lli to accept it.
#
#   LHS repr = Int / Num / Str / Boolean (always defined, static):
#     A non-Undef typed value is always defined. The definedness check is a
#     static i1 true. We still emit the branch+phi structure for structural
#     uniformity, but the branch on i1 true always takes the defined path.
#     The optimizer eliminates the dead undef path.
#
# The result representation is that of the DefinedOr node itself (typically
# the RHS repr, e.g. Int when both operands are Int).
#
# RUNTIME-undef guarantee: the defined bit for Undef-typed LHS is emitted via
# alloca+store+load in _lower_constant, making it a runtime-opaque i1 that
# LLVM cannot constant-fold without mem2reg. See U3 test for verification.
# ---------------------------------------------------------------------------

# _subscript_slot($node) -> the element read $node makes, as its whole
# %Slot, whatever it is stamped -- its defined bit included. The node's own
# cached value is left as it was.
sub _subscript_slot {
    my ($self, $node) = @_;
    my $id  = $node->id;
    # A READ FROZEN AT ITS MEMORY VERSION is read as its Slot there too
    # (_freeze_memory_reads): read again here, where its user is lowered, it
    # saw a later store (`$c ? $h{a} : 8` after `g($h{a})` wrote 5).
    return $self->{cache}{"slot:$id"} if exists $self->{cache}{"slot:$id"};
    my ($had, $c) = (exists $self->{cache}{$id}, $self->{cache}{$id});
    my $old = $node->stamp;
    $node->set_stamp('Slot');
    my $slot = eval { $self->_lower_subscript($node) };
    my $err  = $@;
    $node->set_stamp($old);
    if ($had) { $self->{cache}{$id} = $c } else { delete $self->{cache}{$id} }
    die $err if $err;
    return $slot;
}

# _lower_defined_or_by_slot($node, $slot) -> `LHS // RHS` where the LHS is
# a %Slot: defined by its bit, read as the result's repr; the RHS, lowered
# only on the undef path, is brought to that repr too.
sub _lower_defined_or_by_slot {
    my ($self, $node, $slot) = @_;
    my $to = $node->stamp // 'Scalar';
    $to = 'Scalar' if $to eq 'Slot';
    my $def  = $self->_slot_defined_bit($slot);
    my $lval = $to eq 'Scalar' ? $slot : $self->_emit_coercion($slot, 'Scalar', $to, '// lhs');
    my $lhs_end = $self->_current_block_label;
    my ($undef, $end) = ($self->_fresh_label('dor.undef.'), $self->_fresh_label('dor.end.'));
    $self->_set_terminator("  br i1 $def, label %$end, label %$undef  ; //: defined?");
    $self->_new_block($undef);
    my $rhs  = $node->inputs->[1];
    # WHAT THE ARM MAKES STAYS IN THE ARM: cached past it, a second `//` over
    # the same node took a value its own arm does not dominate (pvm 213).
    my $rval = do { local $self->{cache} = { $self->{cache}->%* }; $self->lower_value($rhs) };
    my $from = $rhs->operation eq 'Print' ? 'Boolean' : ($rhs->stamp // '');
    if ($from ne $to) {
        $rval = $from eq 'Undef' && $to eq 'Scalar'
            ? $self->_build_slot('false', '0', 'Undef', '// rhs')
            : $self->_emit_coercion($rval, $from, $to, '// rhs');
    }
    my $rhs_end = $self->_current_block_label;
    $self->_set_terminator("  br label %$end");
    $self->_new_block($end);
    my $res = $self->_fresh;
    $self->_emit("  $res = phi " . _repr_to_llvm_type($to)
        . " [ $lval, %$lhs_end ], [ $rval, %$rhs_end ]  ; //");
    $self->{cache}{ $node->id } = $res;
    return $res;
}

sub _lower_defined_or {
    my ($self, $node) = @_;

    my $repr = $node->stamp;
    # NO Scalar REFUSAL. Like the And/Or guards this mirrored, it predated
    # Scalar having a machine type -- it has one (%Slot), and the phi machinery
    # below already handles an aggregate result (it emits `undef` for the
    # statically-unreachable arm precisely because `add %Str 0, 0` is not an
    # instruction).
    #
    # `my $u; $u // 7` merges an undef LHS with an Int RHS, so the node's own
    # repr is the join: Scalar. The RESULT is never actually a maybe-value --
    # this function's own comment says so ("either the LHS was defined or the
    # RHS replaced it, so the value is defined by construction and the
    # maybe-ness has been discharged") -- but the STATIC type is still the
    # join, and boxing it is how the two arms are given one machine type.

    my $inputs   = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];

    my $lhs_repr = $self->_repr_of($lhs_node) // _require_repr($lhs_node, 'DefinedOr.lhs');
    $lhs_repr = _require_repr($lhs_node, 'DefinedOr.lhs') if $lhs_repr eq 'Unknown';

    # AN ELEMENT READ MAY MISS, whatever it is stamped (Analysis types it from
    # what the container holds), and a Scalar into a narrower result needs
    # unboxing: both decide by the Slot's own defined bit.
    if ($lhs_repr ne 'Slot'
            && ( $lhs_node->operation eq 'Subscript'
                 || ( $lhs_repr eq 'Scalar' && ( $repr // '' ) ne 'Scalar' ) )) {
        my $slot = $lhs_node->operation eq 'Subscript' && $lhs_repr ne 'Scalar'
            ? $self->_subscript_slot($lhs_node) : $self->lower_value($lhs_node);
        return $self->_lower_defined_or_by_slot($node, $slot);
    }

    # A DEFINITE LHS IS DEFINED: an Int, Num, Str or Boolean is never undef, so
    # the result is the LHS, boxed where the join is a Scalar. Phied unboxed
    # against the Scalar rhs, lli rejected the module (pvm unary.md).
    if (($repr // '') eq 'Scalar' && $lhs_repr =~ /\A(?:Int|Num|Str|Boolean)\z/) {
        my $ref = $self->_emit_coercion($self->lower_value($lhs_node), $lhs_repr, 'Scalar', '// lhs');
        return $self->{cache}{ $node->id } = $ref;
    }

    # Lower the LHS. For Undef-typed LHS, this produces the defined bit (i1).
    # For Int/Num/Str/Boolean-typed LHS, this produces the payload value.
    my $lhs_ref    = $self->lower_value($lhs_node);
    my $entry_label = $self->_current_block_label;

    # Get the definedness condition (i1).
    my $defined_cond;
    if (defined( my $bit = $self->_env_defined_bit($lhs_node) )) {
        # An %ENV read is defined only when getenv found the key.
        $defined_cond = $bit;
    }
    elsif ($lhs_repr eq 'Undef') {
        # The defined bit was set by _lower_constant to the alloca/load result.
        # lhs_ref IS the defined bit (i1 false for Constant(undef)).
        $defined_cond = $lhs_ref;
    }
    elsif ($lhs_repr eq 'Slot' || $lhs_repr eq 'Scalar') {  # a Scalar is its %Slot, defined bit and all
        # A Slot LHS (an array/hash element read) is runtime-decided: read the
        # defined bit off the aggregate and branch on it. Folding to
        # always-defined would make `$a[$i] // rhs` on an out-of-bounds index
        # yield the element rather than the rhs (019f6654).
        $defined_cond = $self->_slot_defined_bit($lhs_ref);
    }
    else {
        # Non-Undef LHS: always defined. Emit i1 true as a compile-time constant.
        # The optimizer will take the defined branch always, but the IR is
        # well-formed (both phi arms present).
        my $always_true = $self->_fresh;
        $self->_emit("  $always_true = add i1 0, 1              ; DefinedOr: non-Undef LHS always defined (i1 true)");
        $defined_cond = $always_true;
    }

    # A Slot LHS's payload is extracted HERE, in the entry block, before the
    # branch below -- not at the phi that consumes it. LLVM requires every phi
    # to be at the top of its block, so an extractvalue emitted in the merge
    # block would land above the phi and make the module invalid ("PHI nodes not
    # grouped at top of basic block"). Extracting in the predecessor also
    # dominates the edge, which is what the phi needs.
    my $slot_payload;
    $slot_payload = $self->_slot_payload_of($lhs_ref) if $lhs_repr eq 'Slot';
    # A Scalar LHS IS its %Slot, and merges whole into a Scalar result; into
    # any other, its unboxing would open blocks before this branch. Its phi
    # operand was left empty, and lli rejected the module.
    die "GAP: a `//` over a Scalar whose result is a "
      . ( $node->stamp // 'NONE' ) . " is not lowered -- only a Scalar\n"
        if $lhs_repr eq 'Scalar' && ( $node->stamp // '' ) ne 'Scalar';

    # Allocate block labels.
    my $undef_label = $self->_fresh_label('dor.undef.');
    my $end_label   = $self->_fresh_label('dor.end.');

    # Conditional branch: defined -> end with lhs; undef -> rhs block.
    $self->_set_terminator("  br i1 $defined_cond, label %$end_label, label %$undef_label  ; DefinedOr: definedness branch");

    # RHS block: evaluate the RHS, then jump to end.
    $self->_new_block($undef_label);
    my $rhs_ref       = $self->lower_value($rhs_node);

    # BRIDGE THE RHS TO THE MERGE TYPE, in the block where it is live. The phi
    # is typed from the NODE's repr, and the RHS may be narrower: `my $u;
    # $u // 7` merges an undef LHS with an Int RHS into a Scalar result, so the
    # i64 must be boxed or lli refuses the phi operand.
    #
    # Emitted HERE, not next to the phi: a coercion in the merge block would
    # land above the phi (LLVM requires phis at the top of their block) and can
    # open continuation blocks of its own, so the incoming label is re-read
    # after it. Same reasoning the And/Or arms give for their own bridges.
    # `isa Chalk::IR::Node`, NOT `isa Chalk::IR::Value`. `stamp` is declared on
    # Node -- the BASE -- while Value is a SIBLING of the value-producing
    # control nodes: Print, Proj, VarDecl and ListAssign are each
    # `:isa(Chalk::IR::Node)` directly. A Value test therefore answers "no
    # stamp" for four node kinds that have one.
    #
    # Measured: none of those four reaches this site (or the sort/keys/Call
    # sites below) in today's corpus, so this is LATENT rather than a live
    # defect -- which is the moment to close it. The same pattern has shipped
    # twice already: 0cc04737 in the coercion guard, a404a718 in the corpus
    # harness, where it silently dropped a spec-declared `:Repr` and blamed
    # TypeInference for the result.
    #
    # Pinned class-wide by t/bootstrap/ir/a-stamp-question-is-not-a-class-question.t
    # so a third occurrence fails a test rather than a program.
    my $rhs_repr_now = $rhs_node isa Chalk::IR::Node ? $rhs_node->stamp : undef;
    my $node_repr_early = $node->stamp;
    if (defined $rhs_repr_now && defined $node_repr_early
            && $rhs_repr_now ne $node_repr_early
            && $node_repr_early ne 'Slot') {
        $rhs_ref = $self->_emit_coercion($rhs_ref, $rhs_repr_now,
                                         $node_repr_early, 'DefinedOr.RHS');
    }

    my $undef_end_label = $self->_current_block_label;
    $self->_set_terminator("  br label %$end_label  ; DefinedOr: undef path falls through");

    # End block: phi merges lhs value (defined path) and rhs value (undef path).
    $self->_new_block($end_label);
    my $result = $self->_fresh;
    # A DefinedOr RESULT is never a Slot, whatever the node is stamped: either
    # the LHS was defined (its payload) or the RHS replaced it, so the value is
    # defined by construction and the maybe-ness has been discharged. The phi
    # merges an i64 payload with the RHS, so it must be typed as the payload --
    # `%Slot` here would be an aggregate phi over two i64 operands.
    # ONE required fetch, hoisted: the expression reads the repr twice, and a
    # per-read fallback could not say which read had nothing to read.
    my $node_repr = _require_repr($node, 'DefinedOr');
    my $phi_repr  = ( $node_repr eq 'Slot' ) ? 'Int' : $node_repr;
    my $llvm_type = _repr_to_llvm_type($phi_repr);

    # LHS payload for the phi: when LHS is Undef-typed, use the recorded payload
    # (i64 0 for Constant(undef)) or a zero for the type. When LHS is a typed value,
    # lhs_ref IS the payload.
    my $lhs_phi_val;
    if ($lhs_repr eq 'Undef') {
        # The payload was recorded by _lower_constant in _undef_payload -- as an
        # i64, which is only usable when the RESULT is an i64. `my $u; $u // ""`
        # merges into a %Str, and feeding the recorded payload there produced
        # `phi %Str [ i64 ... ]`: a type mismatch that never compiled.
        #
        # This arm is UNREACHABLE at runtime: the LHS is statically undef, so
        # the branch always takes the RHS. It still has to be well-TYPED,
        # because LLVM checks every phi operand whether or not the edge is
        # taken. So the fallback below is not a fallback for this case -- it is
        # the correct answer, and the recorded payload is what needs the guard.
        my $recorded = $self->{_undef_payload}{ $lhs_node->id };
        $lhs_phi_val = $recorded if defined $recorded && $llvm_type eq 'i64';
        unless (defined $lhs_phi_val) {
            # Fallback: emit a zero of the result type if no payload was recorded.
            if (_repr_is_float($phi_repr)) {
                # Asked the table for $llvm_type at :3831 and then compared it
                # to the string 'double' to re-decide the zero. Both halves now
                # come from the representation, so they cannot disagree.
                my $z = _repr_zero($phi_repr);
                $lhs_phi_val = $self->_fresh;
                $self->_emit("  $lhs_phi_val = " . _repr_opcode('add', $phi_repr)
                    . " $llvm_type $z, $z  ; DefinedOr: undef LHS payload fallback ($phi_repr)");
            }
            elsif ($llvm_type =~ /^%/) {
                # An aggregate result (%Str, %Slot). `add %Str 0, 0` is not an
                # instruction; LLVM's own name for a value of any type that is
                # never read is `undef`, which is exactly what this operand is.
                $lhs_phi_val = 'undef';
            }
            else {
                $lhs_phi_val = $self->_fresh;
                $self->_emit("  $lhs_phi_val = add $llvm_type 0, 0  ; DefinedOr: undef LHS payload fallback");
            }
        }
    }
    elsif ($lhs_repr eq 'Slot') {
        # The element value on the defined path is field 1 of the aggregate,
        # extracted in the entry block above (see the comment there).
        $lhs_phi_val = $slot_payload;
    }
    else {
        $lhs_phi_val = $lhs_ref;
    }

    $self->_emit("  $result = phi $llvm_type [ $lhs_phi_val, %$entry_label ], [ $rhs_ref, %$undef_end_label ]  ; DefinedOr: phi");

    $self->{cache}{$node->id} = $result;
    return $result;
}

# _lower_defined: lower a Defined(operand) -> i1 definedness predicate.
#
# defined($x) is true iff $x is NOT Undef.
# Static dispatch on the operand's representation:
#   Undef repr: always false (the operand IS undef). Returns the stored defined bit.
#   Slot repr:  runtime-decided. A Slot is the tagged {defined, payload} an
#               array/hash element read produces; its lowered value IS the
#               runtime defined bit (i1) from the bounds/key check. A dynamic
#               (or provably-OOB) element read can MISS at runtime, so defined()
#               must consult that bit -- folding to true silently miscompiles
#               defined($a[$i]) on an out-of-bounds index (019f61ab).
#   Other repr: always true (Int/Num/Str/Boolean are always defined). Returns i1 1.
# _env_defined_bit($node) -> the i1 an EnvRead recorded when it was lowered
# (true when getenv found the key), or undef for any other node.
sub _env_defined_bit {
    my ($self, $node) = @_;
    return undef unless $node isa Chalk::IR::Node;
    my $op = $node->operation;
    return $self->{_env_defined}{ $node->id } if $op eq 'EnvRead';
    # THE BIT FOLLOWS THE VALUE through `//` and `?:`. Taken only off the
    # EnvRead itself, `$ENV{U} // $ENV{U} // "z"` gave "" for perl's "z".
    # undef is "always defined", as above.
    if ($op eq 'DefinedOr') {
        # Defined when either side is; a side with no bit always is.
        my ($l, $r) = map { $self->_env_defined_bit($_) } $node->inputs->@[0, 1];
        return undef unless defined $l && defined $r;
        my $t = $self->_fresh;
        $self->_emit("  $t = or i1 $l, $r  ; defined(//): either side");
        return $t;
    }
    if ($op eq 'TernaryExpr') {
        my ($c, $a, $b) = $node->inputs->@*;
        my ($l, $r) = map { $self->_env_defined_bit($_) } $a, $b;
        return undef unless defined $l || defined $r;
        my $cond = $self->_ensure_i1($self->lower_value($c),
                                     _require_repr($c, 'TernaryExpr.condition'));
        my $t = $self->_fresh;
        $self->_emit("  $t = select i1 $cond, i1 " . ($l // 'true') . ", i1 " . ($r // 'true')
                   . "  ; defined(?:): the arm taken");
        return $t;
    }
    return undef;
}

sub _lower_defined {
    my ($self, $node) = @_;

    my $inputs  = $node->inputs;
    my $operand = $inputs->[0];
    # A bound argument's reading is the caller's (_repr_of), not the
    # callee node's Unknown -- "always defined" over an undef argument.
    my $op_repr = $self->_repr_of($operand) // _require_repr($operand, 'Defined.operand');
    $op_repr = _require_repr($operand, 'Defined.operand') if $op_repr eq 'Unknown';

    # AN ELEMENT READ MAY MISS whatever it is stamped: `defined $a[$i]` past
    # the end said yes for an Int-stamped read. Its own Slot decides.
    # An Undef-stamped one (a static miss) too: lowered as a Slot, its Undef
    # arm branched on the aggregate (backlog 9c217485).
    if ($operand->operation eq 'Subscript' && $op_repr !~ /\A(?:Slot|Scalar)\z/) {
        my $bit = $self->_slot_defined_bit($self->_subscript_slot($operand));
        $self->{cache}{$node->id} = $bit;
        return $bit;
    }

    # Lower the operand to get its value ref (or defined bit for Undef-typed).
    my $op_ref = $self->lower_value($operand);

    if (defined( my $bit = $self->_env_defined_bit($operand) )) {
        $self->{cache}{$node->id} = $bit;
        return $bit;
    }
    elsif ($op_repr eq 'Slot' || $op_repr eq 'Scalar') {  # a Scalar is its %Slot, defined bit and all
        # A Slot's value is the %Slot aggregate; its defined bit is field 0.
        # Split from the Undef arm below, which is genuinely a bare i1 -- the
        # two shared a branch while a Slot was ALSO carried as its defined bit.
        my $bit = $self->_slot_defined_bit($op_ref);
        $self->{cache}{$node->id} = $bit;
        return $bit;
    }
    elsif ($op_repr eq 'Undef') {
        # op_ref IS the defined bit (i1), from _lower_constant's alloca/load.
        $self->{cache}{$node->id} = $op_ref;
        return $op_ref;
    }
    else {
        # Non-Undef operand: always defined. Return i1 true.
        my $true_ref = $self->_fresh;
        $self->_emit("  $true_ref = add i1 0, 1  ; Defined($op_repr): always defined, returns i1 true");
        $self->{cache}{$node->id} = $true_ref;
        return $true_ref;
    }
}

# ---------------------------------------------------------------------------
# CFG node lowering: If, Proj, Region, Phi, Loop
#
# These implement control flow for if/else, while, foreach, and postfix forms.
#
# The hand-authored ir-blocks use these nodes directly. The emitter processes
# them during the control chain pre-pass AND when referenced from the value
# subgraph. Only value-producing nodes (Phi, Region's phi result) return a
# meaningful SSA ref; control-only nodes (If, Proj, Loop) return undef or a
# sentinel that should not be used as a value operand.
# ---------------------------------------------------------------------------

# _lower_if: emit the conditional branch for an If node.
# If nodes are control-flow-only; they do not produce a value themselves.
# Called during process_control_node for the control chain.
#
# inputs[0] = control predecessor (already lowered or unused here)
# inputs[1] = condition (a Boolean/i1 value)
#
# After _lower_if emits the branch, the caller (_lower_if_region_pair or
# process_control_node) must set up the then/else/merge blocks.
sub _lower_if {
    my ($self, $node) = @_;

    # If is control-only; its "value" is a sentinel.
    # The actual branch emission is driven by process_control_node.
    # Here we just return a sentinel if called from lower_value context
    # (should not normally happen in well-authored ir-blocks).
    return undef;
}

# _lower_region: process the merge point.
# Region merges control from multiple predecessor blocks.
# Returns undef (control-only). Value merging happens via Phi nodes.
sub _lower_region {
    my ($self, $node) = @_;
    return undef;
}

# _lower_proj: Proj selects one output from a multi-output node (If, Loop).
# Returns undef (control-only).
sub _lower_proj {
    my ($self, $node) = @_;
    return undef;
}

# _lower_phi: emit a phi instruction merging values from predecessor blocks.
#
# The Phi node carries:
#   $phi->region : the Region merge node
#   $phi->inputs : the incoming values (one per predecessor)
#
# The emitter uses $phi->inputs and the already-determined predecessor block
# labels to emit:
#   %result = phi i64 [ %val_from_pred0, %pred0_label ], [ %val_from_pred1, %pred1_label ]
#
# ADVERSARIAL GUARD: a Phi with missing or undef incoming values must die
# loudly — empty or partially-undef inputs produce undef-poisoned phi IR
# that lli would silently miscompile.
sub _lower_phi {
    my ($self, $node) = @_;

    my $inputs = $node->inputs;
    unless (defined $inputs && scalar @$inputs > 0) {
        die "LLVM backend: Phi node has no incoming values (empty inputs) — "
          . "a missing predecessor edge would produce undef-poisoned phi IR; "
          . "every Phi must have at least one incoming value per predecessor block";
    }

    # Extended guard: reject any undef slot in the inputs array (H4/H5).
    # An undef incoming value means a predecessor edge was not wired — the
    # resulting phi instruction would reference an undefined SSA name, causing
    # a verifier error or silent miscompile in lli.
    for my $i (0 .. $#$inputs) {
        unless (defined $inputs->[$i]) {
            die "LLVM backend: Phi node (id=" . $node->id . ") has undef incoming "
              . "value at slot $i — every phi incoming slot must be a valid node "
              . "(missing predecessor wire); this would produce invalid phi IR";
        }
    }

    # The phi instruction has already been emitted by the if/loop lowering
    # machinery which drives block construction. This path handles Phi nodes
    # referenced directly from lower_value (the data-flow path). Return the
    # cached result if already emitted.
    if (exists $self->{cache}{ $node->id }) {
        return $self->{cache}{ $node->id };
    }

    # PHI-BEFORE-REGION. The phi is being READ before the control structure
    # that defines it has been emitted.
    #
    # This used to be an unconditional die telling the ir-block author to
    # reorder the control chain. That is the right advice when the Region IS on
    # the control chain and simply appears too late — but it is not always the
    # author's mistake. A Region reaches the control chain today only when a
    # memory-Phi pins it there, which happens when an arm stores to an element.
    # An arm that only REBINDS A SCOPE SLOT advances no memory chain, so its
    # Region is control-path-invisible and its value-Phi was unreachable by
    # construction: the producer's own 2b-3 refusal
    # (perl5-son FromOptree.pm:495-502) exists solely to avoid emitting one,
    # and names this site as the reason —
    #
    #     "with no element store advancing the memory chain the backend has no
    #      Region/If in the Return's control path to place that Phi against
    #      (Phi-before-Region)"
    #
    # So: drive the structure from the phi. A Phi knows its Region, and a
    # Region knows the If/Loop that owns it (`head`, wired by set_region), so
    # the enclosing structure is reachable from here without any control-chain
    # walk. Process it, then return the phi the emission just cached.
    #
    # The recursion guard matters: _process_if_node lowers the arms, which can
    # read this same phi again. Marking it in-progress turns that into the
    # honest die below rather than an infinite descent.
    my $region = $node->can('region') ? $node->region : undef;
    my $head   = (defined $region && blessed($region) && $region->can('head'))
        ? $region->head : undef;
    # A LOOP'S OWN PHI has the loop for its region (no Region, no head): it is
    # the structure to drive -- read from an arm's value (a slice by a grep,
    # pvm 220) it was not.
    $head = $region if !defined $head && blessed($region) && $region->can('operation')
        && $region->operation =~ /\A(?:If|Loop)\z/
        # ONLY ONE MADE ALREADY, and only when it changes nothing (a grep whose
        # phi an arm's value reads after the arm dropped it). One not made yet
        # is the control chain's to place: driven from an early read it ran
        # out of place and again in place ("A A C A C" for "A C").
        && $self->{_loops_made}{ refaddr($region) }
        && !( grep { blessed($_) && $_->operation eq 'Phi' && _is_memory_phi($_)
                        && blessed($_->region) && refaddr($_->region) == refaddr($region) }
                  ($region->consumers // [])->@* );

    if (defined $head && blessed($head) && !$self->{_phi_forcing}{ $node->id }++) {
        my $op = $head->can('operation') ? $head->operation : '';
        if ($op eq 'If' || $op eq 'Loop') {
            $self->process_control_node($head);
            delete $self->{_phi_forcing}{ $node->id };
            return $self->{cache}{ $node->id }
                if exists $self->{cache}{ $node->id };
        }
        else {
            delete $self->{_phi_forcing}{ $node->id };
        }
    }

    die "LLVM backend: Phi node encountered in lower_value before its enclosing "
      . "if/loop structure was processed, and forcing that structure did not "
      . "define it (region="
      . (defined $region ? $region->id : 'undef')
      . ", head=" . (defined $head ? $head->id : 'undef') . "); author the "
      . "ir-block so Region/If/Loop appear in the control chain before Phi "
      . "values are read";
}

# ---------------------------------------------------------------------------
# _repr_to_llvm_type($repr) -> LLVM type string
#
# T2 CONSTRAINT, RECORDED 2026-08-29 (perigrin). This function's SHAPE encodes
# an assumption T2 must be free to break: that a representation is a function of
# the TYPE ALONE. It takes one argument and consults a hash, so it can only ever
# answer the context-free default.
#
# The problem T2 actually faces is MAPPING BETWEEN DISJOINT ORDERS. Chalk's
# lattice is ordered — `Int <: Num <: Str <: Scalar`. LLVM's types are NOT: there
# is no relation whatsoever between `i64` and `double`, no subtyping and no
# implicit conversion, only an explicit `sitofp`/`fptosi`. So T2 is not a
# homomorphism from one ordered structure onto another. The order information
# cannot be PRESERVED; it has to be DISCHARGED, and discharged as instructions.
#
# The consequence, which this signature cannot express: **a `Num` need not be a
# `double`.** If every value reaching a Num-typed slot is provably integral,
# `i64` is the better representation and the `sitofp` should not exist at all —
# and that is T2 CHOOSING with context in hand, not an optimiser cleaning up
# after a fixed lowering. Same for a `Scalar` whose payload is only ever an Int:
# the cell may be unnecessary.
#
# **And it runs the whole chain, not one link** (perigrin, 2026-08-29). Since
# `Int <: Num <: Str`, a `Str` whose STRINGINESS is never observed may be an
# `i64` — or a `double`, for exactly the same reason. The type says what the
# value may BE; the representation may drop whatever no use OBSERVES.
#
# The general form, stated closed rather than by its effect (perigrin,
# 2026-08-29): **a Chalk type may be represented by the representation of ANY
# OF ITS SUBTYPES, or by its own.** `Str`'s candidates are `%Str` plus its whole
# downward cone — Num's, Int's, Boolean's, VString's — which is why a `Str` may
# be a `double` with no special case needed.
#
# An earlier version of this note said the candidates are "the ways of not
# representing what nothing looks at". That describes the EFFECT and mistakes it
# for the rule: observation analysis is how T2 PROVES which subtype's
# representation applies to a given site; the SUBTYPE RELATION is what makes it
# legal in the first place. So `Int -> i64` is not "the" representation of Int —
# it is Int's own, and it is equally available to Num, Str and Scalar.
#
# T2's input is therefore NOT a type per site. It is a type PLUS THE SET OF
# OBSERVATIONS made on that value, which is a materially harder analysis than a
# lookup and is the reason this function's shape cannot be the final one.
#
# So when T2 is built, this becomes a per-SITE or per-REGION decision rather than
# a total function, and the hash below degrades to the default it always was.
# Until then, seven call sites read it as authoritative — which is correct for
# the context-free case and is exactly the fluidity T1 must not have taken away
# from T2 (see the store guard at Call(new), which refuses for this reason).
#
# THIS TARGET'S `type_for`: the map from a Chalk representation to the machine
# type that holds it. It is TOTAL over every representation Chalk can construct
# — every input gets a defined answer, and where that answer is a refusal the
# refusal names WHICH upstream bug fired.
#
# The shapes below are the ones docs/architecture/typed-ir-representation.md
# records in its "Realized representation lattice" table and the ones
# Target/LLVM.pm:1210-1213 emits. They are not invented here.
#
# WHY THE REFUSALS ARE SEPARATE. Four different bugs used to share one
# `no LLVM type for '$repr'` fallthrough, which said only that a lookup missed —
# merging "narrowing did not run", "inference did not run", "signature
# vocabulary leaked into the value pipeline" and "this never reaches runtime"
# into one undiagnosable report. That is exactly the merge the Unknown/Scalar
# split was created to undo (TypeLibrary.pm:101-104), and re-creating it one
# layer down would waste that fix.
#
# NOTE the layer this function does NOT answer. Whether a coercion is needed is
# TWO questions: `is_subtype(A,B)` (semantics, target-independent) AND
# `type_for(A) eq type_for(B)` (encoding, this function). Machine-type equality
# alone is NECESSARY BUT NOT SUFFICIENT — Boolean and Undef are both `i1` yet a
# Boolean is not an Undef, and conflating them would license a silent
# bit-reinterpretation. See
# docs/plans/2026-08-14-representation-is-the-targets-type-system.md.
# ---------------------------------------------------------------------------

# The concrete representations: those with a machine type.
#
# Undef is HERE, not among the refusals. It is a UNIT TYPE — one value carrying
# no information — so the target may pick whatever constant suits it, and this
# one picks the defined-bit it already uses. (The backend proves the point in
# DefinedOr's fallback at :2445-2453, which synthesizes a type-appropriate zero
# from nothing when no payload was recorded.)
my %_REPR_LLVM_TYPE = (
    Int      => 'i64',
    Num      => 'double',
    Boolean     => 'i1',
    # A Str VALUE is the first-class aggregate { ptr, len, enc }. This is what
    # a phi or select over Str values must be typed as: the pointer and the
    # length travel together, so a merge cannot desynchronize them.
    Str      => '%Str',
    Undef    => 'i1',
    Slot     => '%Slot',      # { i1, i8, i64 }: the uniform field/element cell
    # Scalar IS that cell (perigrin, 2026-08-29). `Scalar` is the TYPE -- the
    # top of the scalar spine, what the join yields when nothing narrower was
    # proven -- and `%Slot` is its ENCODING: a value that may be any scalar and
    # may be undef is exactly { i1 defined, i8 tag, i64 payload }. Two axes, one cell;
    # `Slot` above is the same encoding named on the representation axis.
    Scalar   => '%Slot',
    Array    => '%Array*',    # { i64, i64, %Slot* }
    Hash     => '%Hash*',     # { i64, i64, %HashEntry* }
    ArrayRef => 'i8*',        # boxed pointer to an %Array
    HashRef  => 'i8*',        # boxed pointer to a %Hash
    CodeRef  => 'i8*',
    # A ScalarRef is a pointer exactly like its siblings -- measured, `\$x`
    # is ROK with an address, structurally identical to `\@a` and `\%h`. Its
    # absence here was an omission, not a decision: it was the only ref type
    # with neither a machine type nor a named refusal.
    ScalarRef => 'i8*',
    # `Ref` IS INHABITED: perl reports `\\$y` (a ref to a ref) as `REF` from
    # both ref() and reftype(), a kind distinct from SCALAR. So it is a
    # concrete type, not a classifier -- an earlier version of this file
    # refused it as "abstract" on the strength of nothing having
    # `ref() eq 'Ref'`, which was a claim about CAPITALISATION rather than
    # about inhabitants.
    #
    # And its layout needs no thought: a ref-to-ref is a pointer like every
    # other reference. T2 mapping two Chalk types onto one LLVM type is
    # ordinary -- Boolean and Undef already share i1 -- and T1 does not need
    # to care that they coincide here (perigrin, 2026-09-02).
    Ref      => 'i8*',
    Object   => 'i8*',        # pointer to { %Cls.vt*, %Slot, ... }
);

# The representations with NO machine type, each mapped to its own diagnosis.
# Keep these messages distinct: the whole point is that the reader learns which
# bug to go fix without reading the backend.
my %_REPR_NO_MACHINE_TYPE = (
    # Arity 1: denotes a SINGLE value whose concrete type was never determined.
    # It COULD acquire a representation once narrowed, so this is "not yet".
    # Scalar was HERE until 2026-08-29, on the reading that runtime-free
    # lowering has no box for it. That was wrong: the box exists and every class
    # already emits it. `%Slot` is the object struct's field cell (`:560`), with
    # a constructor (`:922`) and an extractor (`:931`) already in use. Scalar
    # now maps to it in %_REPR_LLVM_TYPE above.

    # Arity 0+: does not denote one value at all, so it can never have a layout.
    # This is also the vocabulary a variadic signature position uses, so it
    # answers 'what does this parameter position accept?' and no value is ever
    # 'a List'.
    List    => "'List' is signature vocabulary, not a value type — it answers "
             . "'what does this parameter position accept?', and denotes a "
             . "SEQUENCE rather than one value, so no single-value layout "
             . "exists. Reaching machine-type selection means signature "
             . "vocabulary leaked into the value pipeline: a LAYER VIOLATION.",

    # BOTTOM. The join identity, and an INFERENCE value with no runtime
    # counterpart. THE QUESTION IS MALFORMED, not merely unanswered.
    #
    # `None` is the EMPTY TYPE -- `$TYPE_BITSET{None} = 0`, no bits, inhabited
    # by nothing. "What is the representation of None" is not a question whose
    # answer is missing; it is a question with no content, in the way that
    # asking the width of the empty set is not. A layout describes the values a
    # type has, and this type has none. Adding an encoding here would not be
    # completing the table -- it would be inventing an inhabitant for a type
    # defined by having none.
    #
    # This is why it sits in THIS table rather than %_REPR_LLVM_TYPE, and why
    # its entry can never move: unlike `Scalar`, which was here until 2026-08-29
    # on a reading that turned out to be wrong (the %Slot box existed all
    # along), no future work makes `None` representable.
    #
    # The lattice already uses it honestly elsewhere: `die` has
    # `return_type => 'None'` (TypeLibrary.pm:249), which is exact -- `die` does
    # not return a value of some type, it does not return. Bottom is the type of
    # "there is no value here".
    #
    # AND `void` IS NOT THE ANSWER, though it is the obvious guess: an empty
    # type has nothing to move, so it looks like the EASIEST thing to represent
    # rather than the impossible one. The lattice already separates the two
    # nothings, and they behave differently under join -- measured:
    #
    #     join(Void, Int) = List      Void is a value-ARITY claim: "yields
    #                                 nothing" merged with "yields an Int" is
    #                                 "yields some number of things". It
    #                                 PARTICIPATES.
    #     join(None, Int) = Int       None is the IDENTITY. It contributes no
    #                                 constraint because there is nothing to
    #                                 constrain.
    #
    # So `void` is the encoding of `Void` (TypeLibrary.pm:43, "arity 0: yields
    # nothing", sibling of Scalar) -- a position that RUNS and produces no
    # value, which the backend already emits for ADJUST blocks (`ret void`).
    # Something happens there.
    #
    # `None` arriving here is not a position that yields nothing; it is a
    # request for the VALUE of an expression that has none. The correct emission
    # is not `void`, it is that the code path should not exist. Emitting `void`
    # would answer a question about arity when the question was about a value.
    #
    # WHY IT IS SEEDED ANYWAY, and where. A self-recursive call contributes
    # `None` on the first pass (Analysis.pm, _resolve_direct_calls) because it
    # is the join IDENTITY: `join(None, T) == T`, so a recursive sub types from
    # its BASE CASE instead of bailing on an absent arm or collapsing to
    # `Unknown`, which absorbs. That use is about the LATTICE, and it never
    # intends a value to flow.
    #
    # SO ARRIVING HERE IS A REAL SIGNAL, distinct from Unknown's. Unknown means
    # inference FAILED and the node could be anything. `None` means a position
    # holding no value reached codegen as though it held one: the seeded arm was
    # never joined away by a typed sibling, or a genuinely non-returning
    # expression was consumed for its value. Read it as "nothing flows here, and
    # something asked what it looks like".
    None    => "'None' is the type lattice's BOTTOM -- the EMPTY type, "
             . "inhabited by nothing (its bitset is 0). It has no layout "
             . "because there is nothing to lay out, so this is a malformed "
             . "question rather than a missing table entry, and no future work "
             . "makes it representable. It is seeded on a self-recursive call "
             . "as the JOIN IDENTITY (join(None,T) == T) so a recursive sub can "
             . "type from its base case; that use never intends a value to "
             . "flow. Reaching machine-type selection means a position holding "
             . "NO value was asked what it looks like -- the seeded arm was "
             . "never joined away by a typed sibling, or a non-returning "
             . "expression was consumed for its value. Contrast Unknown, which "
             . "means inference FAILED and the node could be anything.",

    # An ERROR STATE, not a kind of value, and NOT merely "higher than Scalar".
    # The distinction is the KIND of absence
    # (docs/architecture/2026-08-09-types-fetches-and-contexts.md): Scalar is
    # absent from THIS target's map and an SV*-based target would have it;
    # Unknown is absent from EVERY target's map, permanently.
    #
    # It is also RARE BY CONSTRUCTION, which is why arriving here is a signal
    # rather than a resting state -- but not because nothing climbs to it. An
    # earlier version of this comment claimed that, from a sample that happened
    # to omit the four types it is true of. Measured EXHAUSTIVELY over all 26
    # %PARENT members: 180 ordered pairs join to Unknown with neither operand
    # Unknown, and EVERY ONE involves Code, Glob, IO or Format (48 appearances
    # each; every other type appears only when paired with one of those four).
    #
    # Those four are the NON-ARITY entities: a callable or a symbol-table slot
    # is not a plural value, so it has no least upper bound with one. Ordinary
    # joins stay put -- join(List,Int), join(List,Array), join(Array,Int) are
    # all `List`; join(Int,ArrayRef) is `Scalar`. So Unknown is reached by
    # ABSORPTION, by DECLARATION, or by joining a callable/slot with a value,
    # and that last case is a program-level error rather than an imprecision.
    Unknown => "'Unknown' is the lattice TOP: this value may be anything, so no "
             . "machine type can hold it. That is an answer, not necessarily a "
             . "failure -- but the program cannot be compiled until something "
             . "NARROWS it: a producer stamp, a flow refinement, or a callsite. "
             . "If no such information exists, this construct is legitimately "
             . "un-compilable and the GAP is correct.",

    # A legitimate, fully-known type that exists only at compile time.
    # THE FUNCTOR NEED NOT BE TOTAL, but it must not be SILENT. T2 maps the
    # arrows it can map; an unmapped one is a legitimate outcome PROVIDED IT
    # IS NAMED. These five had neither a machine type nor a reason, so a
    # consumer reaching one got "not a known representation" -- true, and
    # silent about whether that was intended.

    LValueRef => "'LValueRef' aliases a RANGE rather than a whole scalar "
             . "(`\\substr(\$s, 0, 1)`), so a pointer alone cannot express it "
             . "-- it needs a base, an offset and a length, and writes through "
             . "it must land back in the original buffer. A layout exists in "
             . "principle; it is not i8* and has not been designed.",

    GlobRef => "'GlobRef' points at a symbol-table entry -- a name bound to "
             . "several slots at once (scalar, array, hash, code, IO). That is "
             . "a runtime symbol table, which the runtime-free lowering does "
             . "not have, so there is nothing for a pointer to point AT.",

    DualVar => "'DualVar' is TWO INDEPENDENT VALUES in one cell: a string and "
             . "a number that need not agree (`\$!` is the canonical one). No "
             . "single scalar layout holds both, and picking either half is a "
             . "silent wrong answer rather than a narrowing.",

    VString => "'VString' is a Str carrying V magic -- the bytes are ordinary "
             . "but the value also remembers it was written `v1.2.3`, which "
             . "changes how it compares and prints. %Str has nowhere to put "
             . "that, and dropping it would make a version string sort as its "
             . "raw bytes.",

    Regex   => "'Regex' is resolved STATICALLY and never reaches runtime: a qr// "
             . "literal is compiled by _compile_regex_pattern at compile time and "
             . "the pattern is never an SSA value. Reaching machine-type "
             . "selection means something treated a pattern as a RUNTIME value — "
             . "the unbuilt qr//-as-function case (see :5752).",
);

sub _repr_to_llvm_type ($repr //= die "node reached machine-type selection with NO representation (undef) — fix TypeInference so this node carries an explicit repr before lowering.") {
    return $_REPR_LLVM_TYPE{$repr} if exists $_REPR_LLVM_TYPE{$repr};

    die "LLVM backend: $_REPR_NO_MACHINE_TYPE{$repr}\n"
        if exists $_REPR_NO_MACHINE_TYPE{$repr};

    # Not a representation this compiler knows at all — as opposed to one that
    # knowingly has no machine type. A new repr reaching here needs a decision,
    # not a default.
    die "LLVM backend: no LLVM type for representation '$repr' — this is not a "
      . "known representation. Add it to %_REPR_LLVM_TYPE with its machine type, "
      . "or to %_REPR_NO_MACHINE_TYPE with the reason it has none.";
}

# The zero VALUE for each representation, in that representation's own machine
# type. This is the second half of the object map: `%_REPR_LLVM_TYPE` says what
# type a Num is, and this says what literal writes a zero AT that type. The two
# must move together -- if Num ever maps to an integer type its zero stops being
# `0.0` -- so keeping them apart as `_repr_to_llvm_type(...)` plus a hardcoded
# `0.0` is exactly the parallel authority the type map was written to prevent.
my %_REPR_ZERO = (
    Int     => '0',
    Num     => '0.0',
    Boolean => '0',
    Undef   => '0',
);

# Accessors returning the two maps THEMSELVES, so a caller can ask what the
# functor currently maps -- and, under `local`, ask what it WOULD emit under a
# different mapping. That second use is the point: the claim "this branch picks
# `add` rather than `fadd` the day Num maps to i64" is only checkable if the
# mapping can be moved without editing an emit site.
sub _repr_llvm_type_map { return \%_REPR_LLVM_TYPE }
sub _repr_zero_map      { return \%_REPR_ZERO }

sub _repr_zero ($repr //= die "asked for the zero literal with NO representation (undef)") {
    return $_REPR_ZERO{$repr} // die
        "LLVM backend: no zero literal for representation '$repr' — add it to "
      . "%_REPR_ZERO beside its machine type in %_REPR_LLVM_TYPE.";
}

# The ARROW half of T2. `%_REPR_LLVM_TYPE` maps Chalk types to machine types
# (objects); this maps a Chalk operation AT a representation to the machine
# instruction that performs it (arrows). Naming an opcode inline -- `fadd`
# because the repr is Num -- asserts a machine type at a site that never asked
# for one, which is how `Num |-> double` got baked into ~40 places.
#
# Keyed by the INTEGER mnemonic because that is the operation's identity
# independent of representation: `add` IS "the addition arrow", and which
# instruction realizes it is what the representation decides. A repr whose
# machine type is integral therefore picks the integer opcode by falling
# through -- no per-site edit needed the day Num maps to i64.
my %_FLOAT_OPCODE = (
    add   => 'fadd',
    sub   => 'fsub',
    mul   => 'fmul',
    div   => 'fdiv',
    'icmp' => 'fcmp',
);

# _repr_is_float($repr) -> whether this representation's machine type is a
# floating-point type. The ONE predicate the opcode/instruction choices consult,
# derived from %_REPR_LLVM_TYPE rather than from the repr NAME. Ask this, never
# `$repr eq 'Num'`, when the question is "which instruction family".
sub _repr_is_float ($repr //= die "asked whether a NO representation (undef) is float") {
    my $ty = _repr_to_llvm_type($repr);
    return $ty eq 'double' || $ty eq 'float';
}

# _repr_opcode($int_mnemonic, $repr) -> the instruction to emit for that
# operation at that representation. Int-typed reprs get the integer mnemonic
# unchanged; float-typed reprs get the float sibling.
sub _repr_opcode {
    my ($mnemonic, $repr) = @_;
    return $mnemonic unless _repr_is_float($repr);
    return $_FLOAT_OPCODE{$mnemonic} // die
        "GAP: no float instruction for '$mnemonic' at repr=$repr — add it to "
      . "%_FLOAT_OPCODE.";
}

# _repr_convert_op($from, $to) -> the instruction that converts a value of
# representation $from into representation $to, or undef when the two share a
# machine type and no instruction is needed (the arrow is the identity).
#
# This is where `Int <: Num |-> sitofp` actually lives. The subtyping is a fact
# about the TYPES; that it costs a `sitofp` is a fact about the current
# REPRESENTATION choice, and holds only while Int is integral and Num is not.
# Map Num to i64 and every one of these arrows becomes the identity -- which is
# what returning undef says.
sub _repr_convert_op {
    my ($from, $to) = @_;
    my $ft = _repr_to_llvm_type($from);
    my $tt = _repr_to_llvm_type($to);
    return undef if $ft eq $tt;               # identity: nothing to emit

    my $ff = _repr_is_float($from);
    my $tf = _repr_is_float($to);
    return 'sitofp' if !$ff && $tf && $from ne 'Boolean';   # signed int -> float
    return 'uitofp' if !$ff && $tf;                          # i1 is UNsigned
    return 'fptosi' if  $ff && !$tf;                         # float -> signed int
    return undef;   # int<->int of differing widths: caller's business, not ours
}

# ---------------------------------------------------------------------------
# process_control_node: called during the control-chain pre-pass for each
# side-effect node in forward order. Processes VarDecl, Assign, CompoundAssign,
# If (with its Region pair), and Loop (with its exit Region).
# ---------------------------------------------------------------------------
# _open_evals_entered($node): AN EVAL'S BODY BEGINS at a node that follows
# its entry -- in an arm or a loop body as on the main chain (which opens its
# own first, so one already open is left).
sub _open_evals_entered {
    my ($self, $node) = @_;
    return unless $node->can('control_in') && blessed($node->control_in);
    for my $r (( $Chalk::Target::LLVM::Context::EVAL_BY_ENTRY{ refaddr($node->control_in) } // [] )->@*) {
        $self->open_eval($r) unless $self->{_eval_open_now}{ refaddr($r) };
    }
    return;
}

sub process_control_node {
    my ($self, $node) = @_;
    my $op = $node->operation;
    $self->_open_evals_entered($node);
    if ($op eq 'If') {
        $self->_process_if_node($node);
    }
    elsif ($op eq 'Loop') {
        $self->_process_loop_node($node);
    }
    elsif (Chalk::IR::NodeFactory::is_statement_node($op)) {
        # Every statement node (VarDecl + the shared statement-effect table:
        # Assign, CompoundAssign, Call, RegexSubst, RegexMatch, Match,
        # NotMatch, BacktickExpr, TryCatch, Print, and B::SoN's EntryWrite,
        # Delete, ElemRestore, LocalAlias, Transliterate) is lowered here so its side
        # effect — a store, a dispatched call's field mutation, a
        # substitution — is emitted at its control position, before any
        # later read.
        $self->lower_value($node);
        # Memory-SSA: an element-store Assign PRODUCES a new memory version.
        # Emit + freeze the element reads that observe THIS version (its
        # Subscript consumers whose memory input is this store) right after the
        # store, before the next store supersedes it. Their frozen value is used
        # by their (later-processed) consumers, so a read observes the memory
        # state at its own program point. A shift/pop Call is likewise a memory
        # version producer (it mutates the array header) -- an element read whose
        # memory input is THIS shift/pop must be frozen here, before a later
        # shift/pop advances the header again (WAR hazard).
        # A DIRECT CALL IS A MEMORY VERSION TOO: an inlined sub may store a
        # shared lexical, and a read at that call's version must be taken
        # there, not at its use after a later store.
        $self->_freeze_memory_reads($node)
            if $op eq 'Assign' || $op eq 'RegexSubst' || $op eq 'EntryWrite' || $op eq 'Delete' || $op eq 'ElemRestore'
            || $self->_is_array_mutating_call($node)
            || ($op eq 'Call' && ($node->dispatch_kind // '') eq 'direct');
    }
    elsif ($op eq 'Unwind') {
        # A MAINLINE `die` — one not inside an if/else arm. Its Unwind sits
        # directly on the Return's control chain (Return.control_in -> Unwind),
        # so it arrives here rather than through _find_unwind_consumer, which
        # only finds an Unwind hanging off an If-arm's Proj.
        #
        # Before this arm existed, a mainline die was SILENTLY DROPPED: the
        # program fell through and returned a value where perl aborts (measured:
        # lli exit 0 "Int:1" vs perl exit 255 "boom"). That was a
        # GAP-not-miscompile invariant violation, pinned by corpus T2c.
        #
        # _emit_unwind_terminator is idempotent (see its emitted-set guard), so
        # an Unwind that is somehow reachable BOTH here and via an If-arm Proj
        # aborts once, not twice.
        $self->_emit_unwind_terminator($node, 'mainline die (abort)');
        # Caught, it branched away: what the body has after it is dead.
        $self->_new_block($self->_fresh_label('after_die'))
            if ($self->{_eval_frames} // [])->@*;
    }
    elsif ($op eq 'Region' && $node->can('eval_entry') && defined $node->eval_entry) {
        # an empty body: nothing followed the entry to open it
        $self->open_eval($node) unless $self->{_eval_open_now}{ refaddr($node) };
        $self->close_eval($node);
    }
    elsif ($op eq 'Region' && (my $j = ($self->{_jump_merges} // {})->{ $node->id })) {
        $self->_close_jump_merge($j);
    }
    # A READ OF $@ PINNED ON THE CHAIN is taken where it stands: an eval
    # rewrites $@ with no store, so its memory version does not place it.
    elsif ($op eq 'EntryDef' && ($node->symbol // '') eq '@' && ($node->package // '') eq 'main') {
        $self->{cache}{ $node->id } = $self->lower_value($node);
        $self->{_frozen_reads}{ $node->id } = 1;
    }
    # SO IS A FIELD READ PINNED ON THE CHAIN, which has no memory version to
    # place it: lowered at its use instead, `my $id = $count++` read the field
    # after the increment's store (1,2 for perl's 0,1; pvm 242).
    elsif ($op eq 'FieldAccess') {
        $self->{cache}{ $node->id } = $self->lower_value($node);
        $self->{_frozen_reads}{ $node->id } = 1;
    }
    # A PACKAGE CHANGE computes nothing: the producer has already qualified
    # every name the following statements use.
    elsif ($op eq 'PackageMark') {
    }
    # A STORE TO A CAPTURED VARIABLE goes to its cell -- its location.
    # Dropped here before, unseen: CellWrite is neither a statement node nor
    # fixed, so `$k = 4` after a closure over $k was lost.
    elsif ($op eq 'CellWrite') {
        $self->lower_value($node);
    }
    # A WRITE NOTHING ABOVE LOWERS IS REFUSED, not dropped: an EntryWrite
    # reached this branch before it was a statement node, and `our $g = 1;
    # $g = 2; print $g` printed 0.
    elsif ($node->is_fixed && $op !~ /\A(?:Return|Region|Proj|Phi|Start)\z/) {
        die "GAP: $op on the control chain is not lowered -- refusing to drop its effect\n";
    }
    # Other ops in the control chain (Return, Region, Proj, Phi, etc.) are
    # either handled by their driving structure or ignored here.
}

# _has_branch_guarded_store — true if the graph is NOT straight-line for the
# purpose of element memory: it contains an element-store Assign AND a control
# region (If/Loop). Memory-SSA phase 2a handles straight-line only; a store under
# a branch/loop needs a memory-Phi (2b). Computed ONCE from the return-reachable
# graph (inputs + control_in) and cached on $self; set by _scan_memory_shape at
# the lowering entry hook (where the return node is in scope).
sub _has_branch_guarded_store {
    my ($self) = @_;
    return $self->{_branch_guarded_store} // 0;
}

sub _scan_memory_shape {
    my ($self, $return_node) = @_;

    # A store is memory-SSA-SAFE (phase 2a) only if it is on the return's linear
    # control_in EFFECT CHAIN -- a straight-line store the memory scheduler
    # orders. A store reachable ONLY via consumers (an orphaned branch-arm store
    # the producer did not merge into the return path -- phase 2b) is UNSAFE: its
    # effect is not on the chain, so a following element read would silently
    # observe the wrong memory version. Collect on-chain stores, then check for
    # any element store NOT on the chain.
    # Walk the control graph backward from the Return, collecting on-chain Assign
    # stores. A store is on-chain if control reaches it from the Return. Control
    # flows two ways: a straight-line effect links its predecessor via control_in,
    # but a merge/loop links its predecessor through control-flow INPUTS -- a
    # Region reaches its arms via Proj inputs, a Proj reaches its owner via the
    # Loop/If input, and a Loop reaches its pre-loop predecessor via control_in.
    # So a straight-line store BEFORE a loop is reached as
    # Return -control_in-> Region -input-> Proj -input-> Loop -control_in-> store.
    # Following control_in ALONE stops at the Region (whose control_in is undef),
    # misclassifying the pre-loop store off-chain and false-GAPing the read
    # (019f342f). Follow both control_in AND the control-flow inputs of
    # Region/Proj/Loop/If nodes.
    my %CF_NODE = map { $_ => 1 } qw(Region Proj Loop If);
    my %on_chain;
    my %cseen;
    my @cq;
    push @cq, $return_node->control_in
        if $return_node->can('control_in') && defined $return_node->control_in;
    while (my $c = shift @cq) {
        next unless blessed($c) && !$cseen{ $c->id }++;
        $on_chain{ $c->id } = 1 if $c->operation eq 'Assign';
        push @cq, $c->control_in
            if $c->can('control_in') && defined $c->control_in;
        # A control-flow node reaches its control predecessors through its inputs
        # (Region<-Proj, Proj<-Loop/If, Loop<-body/entry), so follow those too.
        # A Region's inputs are ALL control predecessors: an arm that ends in
        # another effect (a `local`'s ElemRestore) still leads back to its stores.
        push @cq, grep { blessed($_) && ($c->operation eq 'Region'
                || $CF_NODE{ $_->operation } || $_->operation eq 'Assign') }
            $c->inputs->@*
            if $CF_NODE{ $c->operation } && $c->can('inputs') && defined $c->inputs;
    }

    # Data-reachable set: nodes reachable from the Return via inputs + control_in
    # (NOT consumers). A node in the full graph but NOT here is DEAD (orphaned).
    my %data_reachable;
    {
        my @dq = ($return_node);
        while (my $n = shift @dq) {
            next unless blessed($n);
            next if $data_reachable{ $n->id }++;
            push @dq, grep { blessed($_) } $n->inputs->@*
                if $n->can('inputs') && defined $n->inputs;
            push @dq, $n->control_in
                if $n->can('control_in') && defined $n->control_in;
        }
    }

    # Stores merged through a memory-Phi (the branch/loop 2b shape): collect the
    # store nodes that are an INPUT of some memory-Phi. Checked by INPUT, not by
    # the store's consumers -- the JSON loader does not reconstruct the back-edge
    # consumer edge (a loop memory-Phi's back-edge store has empty consumers), so
    # a consumer-side check would miss it. Two passes: gather merged-store ids
    # first, then flag off-chain stores that are NOT in that set.
    my %merged_store;
    {
        my %s2; my @q2 = ($return_node);
        while (my $n = shift @q2) {
            next unless blessed($n);
            next if $s2{ $n->id }++;
            if ($n->operation eq 'Phi' && _is_memory_phi($n)) {
                # THE STORES BEFORE A MERGED ONE in its arm or loop body reach
                # it by control, so they are ordered as it is: walked back
                # along control_in to the arm's start (pvm 125, 191).
                for my $in ($n->inputs->@*) {
                    for (my $s = $in; blessed($s) && !$CF_NODE{ $s->operation };
                         $s = $s->can('control_in') ? $s->control_in : undef) {
                        $merged_store{ $s->id } = 1 if $s->operation eq 'Assign';
                    }
                }
            }
            push @q2, grep { blessed($_) } $n->inputs->@*
                if $n->can('inputs') && defined $n->inputs;
            push @q2, $n->control_in
                if $n->can('control_in') && defined $n->control_in;
            push @q2, grep { blessed($_) } $n->consumers->@*
                if $n->can('consumers') && defined $n->consumers;
        }
    }

    my $unsafe = 0;
    my %seen;
    my @q = ($return_node);
    while (my $n = shift @q) {
        next unless blessed($n);
        next if $seen{ $n->id }++;
        if ($n->operation eq 'Assign' && $self->_is_element_store($n)
                && !$on_chain{ $n->id }
                && !$merged_store{ $n->id }) {
            $unsafe = 1;   # an element store neither on the effect chain nor
                           # merged through a memory-Phi (unhandled shape)
        }
        # An element read-modify-write ($a[i] += / ++) whose store-back was
        # dropped by the producer (pre-existing, zhi 019f342f): the arithmetic op
        # reads an element Subscript, but its result is DEAD (not on the Return's
        # data path) -- the store-back is missing. A following read then observes
        # the pre-modify value: a silent miscompile. Flag unsafe so the read GAPs
        # loudly. A legitimate `$a[0]+$a[1]` differs: its Add IS data-reachable
        # (the return value), so it is not flagged.
        if ($self->_is_arith_over_element($n) && !$data_reachable{ $n->id }) {
            $unsafe = 1;
        }
        push @q, grep { blessed($_) } $n->inputs->@*
            if $n->can('inputs') && defined $n->inputs;
        push @q, $n->control_in
            if $n->can('control_in') && defined $n->control_in;
        push @q, grep { blessed($_) } $n->consumers->@*
            if $n->can('consumers') && defined $n->consumers;
    }
    $self->{_branch_guarded_store} = $unsafe;
    return;
}

# The element read-modify-write pattern ($a[i] += x): an arithmetic op
# (Add/Subtract/Multiply/Divide/Modulo) that READS an element Subscript AND whose
# result feeds an element STORE back. Both halves are required: a scalar
# accumulator over an array element (`$s += $x` in a foreach, lowered to
# Add($s_phi, Subscript(arr,i))) reads a Subscript too, but its result feeds the
# accumulator Phi/return, not an element store -- it is NOT an RMW, and flagging
# it as one spuriously GAPs a legitimate foreach accumulator whose value is dead
# (e.g. the sub returns `scalar @a`, not the accumulator). Require the store side
# so only a true $a[i]-op= is caught (zhi 019f5da9 foreach false-positive).
sub _is_arith_over_element {
    my ($self, $node) = @_;
    my %arith = map { $_ => 1 } qw(Add Subtract Multiply Divide Modulo);
    return 0 unless $arith{ $node->operation };
    my $reads_element = grep {
        blessed($_) && $_->operation eq 'Subscript'
    } $node->inputs->@*;
    return 0 unless $reads_element;
    # The RMW store-back: a consumer Assign whose lhs is an element Subscript.
    return 0 unless $node->can('consumers') && defined $node->consumers;
    for my $c ($node->consumers->@*) {
        return 1 if blessed($c) && $c->operation eq 'Assign'
            && $self->_is_element_store($c);
    }
    return 0;
}

# An element store Assign has a Subscript lhs (inputs[0] after control split, or
# inputs[1] with control) -- distinguish from a scalar/field rebind.
sub _is_element_store {
    my ($self, $assign) = @_;
    # Its TARGETS, not the values it reads: `my ($a, $b) = ($r->[0], $r->[1])`
    # stores no element (pvm 166 refused every read after it).
    my $n = ( $assign->can('targets') && $assign->targets ) || 1;
    for my $in (grep { defined } $assign->inputs->@[0 .. $n - 1]) {
        return 1 if blessed($in) && $in->operation eq 'Subscript';
    }
    return 0;
}

# _find_memstart($return_node) — the graph's MemStart node (the initial memory
# value), found by walking the return-reachable inputs + control_in. One per
# graph. Returns undef if the graph has no MemStart (no element reads).
sub _find_memstart {
    my ($self, $return_node) = @_;
    my %seen;
    my @q = ($return_node);
    while (my $n = shift @q) {
        next unless blessed($n);
        next if $seen{ $n->id }++;
        return $n if $n->operation eq 'MemStart';
        push @q, grep { blessed($_) } $n->inputs->@*
            if $n->can('inputs') && defined $n->inputs;
        # INTO A STRUCTURE'S BODY: a sub whose body is a loop reaches its
        # entry memory only through the loop's statements, which consume the
        # control nodes; from the Return alone it was never found, and that
        # sub's entry reads went unfrozen (a copy-deref re-made after a store).
        push @q, grep { blessed($_) } ( $n->consumers // [] )->@*
            if $n->operation =~ /\A(?:Loop|If|Proj|Region|Start)\z/ && $n->can('consumers');
        push @q, $n->control_in
            if $n->can('control_in') && defined $n->control_in;
    }
    return undef;
}

# _freeze_memory_reads($mem_node) — emit and cache the element-read Subscripts
# whose MEMORY input (inputs[2]) is $mem_node, so they load against the memory
# version $mem_node represents (MemStart = entry, a store = post-store) and are
# frozen at that point. A memory-having Subscript is thus lowered ONCE at its
# memory version's control position, not re-read at its consumer (which is
# processed later, after subsequent stores). The consumer then uses the frozen
# SSA ref. This is the memory-SSA scheduler: the memory edge places the load.
# _is_array_mutating_call($node) — true for a shift/pop builtin Call, which
# mutates its array's header (a new memory version). Such a Call must freeze its
# memory-consuming element reads at its program point, exactly like an element
# store, so an interleaved read is not sunk past a later mutation (WAR hazard).
sub _is_array_mutating_call {
    my ($self, $node) = @_;
    return 0 unless blessed($node) && $node->operation eq 'Call';
    return 0 unless $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'builtin';
    my $name = $node->name // '';
    return ($name eq 'shift' || $name eq 'pop' || $name eq 'push') ? 1 : 0;
}

# _reaches_an_unlowered_phi($self, $node) -> bool: does $node read, through
# its inputs, a loop Phi not yet emitted? Such a read belongs in that loop,
# not frozen at entry -- the Phi has no SSA ref until its loop is lowered.
# Memory inputs are not followed (a read's own version is what freezes it).
sub _reaches_an_unlowered_phi {
    my ($self, $node) = @_;
    my (%seen, @q);
    @q = grep { blessed($_) } $node->inputs->@*;
    while (defined(my $n = shift @q)) {
        next if $seen{ refaddr($n) }++;
        next if exists $self->{cache}{ $n->id };
        my $op = $n->operation;
        return 1 if $op eq 'Phi' && !( $n->can('memory') && $n->memory );
        next if $op =~ /\A(?:MemStart|Phi)\z/ || ( $op eq 'Assign' );
        push @q, grep { blessed($_) } $n->inputs->@*;
    }
    return 0;
}

sub _freeze_memory_reads {
    my ($self, $mem_node, $within) = @_;
    return unless $mem_node->can('consumers');
    for my $c ($mem_node->consumers->@*) {
        next unless blessed($c);
        next if $within && !$within->{ refaddr($c) };
        # A CAPTURE CARRIES THE VERSION ON: MakeCell(var, version) is the
        # memory a closure's capture reads at, made where that version is.
        # Its reads are this version's too, so they freeze here as well --
        # not at a use after later stores (`my @k = sort keys %h` beside a
        # closure over %h read %h's last contents).
        if ($c->operation eq 'MakeCell' && blessed($c->inputs->[1])
                && $c->inputs->[1]->id eq $mem_node->id) {
            $self->_freeze_memory_reads($c, $within);
            next;
        }
        # A FIELD READ IS ONE TOO, its memory version its only input (an
        # lvalue FieldAccess has none). Lowered at its use instead, `my $old =
        # $n; $n = 5` read the 5.
        my $mem;
        if ($c->operation eq 'FieldAccess' || $c->operation eq 'EntryDef'
                || ($c->operation eq 'PadAccess' && $c->is_location)) {
            $mem = $c->inputs->[0];
        }
        # A READ OF THE WHOLE AGGREGATE at its memory version -- its count, or
        # a builtin that walks it without changing it. Lowered at its use, a
        # later store to a shared aggregate (one cell every graph writes) had
        # already changed what it read: `my $a = "@p"; @p = ()` read the ().
        elsif ($c->operation eq 'Count') {
            $mem = $c->inputs->[1];
        }
        elsif ($c->operation eq 'Call' && $c->can('memory_input') && $c->memory_input
                && ( $c->dispatch_kind // '' ) eq 'builtin'
                && ( $c->name // '' ) =~ /\A(?:join|sort|reverse|keys|values)\z/) {
            $mem = $c->inputs->[-1];
        }
        elsif ($c->operation eq 'PostfixDeref' && ( ($c->sigil // '') eq '$' || $c->copy )) {
            # $$r, or a copy through a reference, at its memory version: made
            # where it is used, the copy took a later store's value.
            $mem = $c->inputs->[1];
        }
        else {
            next unless $c->operation eq 'Subscript' || $c->operation eq 'Exists';
            # A memory-having read: inputs[2] is the memory version. Guard against a
            # 2-input lvalue Subscript (no memory input).
            $mem = $c->inputs->[2];
        }
        next unless defined $mem && blessed($mem) && $mem->id eq $mem_node->id;
        # Already lowered -- by a read of this version frozen before it (a
        # sort over a copy-deref lowers the copy) -- is lowered HERE, so it is
        # frozen too. Left unmarked, a copy re-made itself at each later use,
        # after the stores it must not see.
        if (exists $self->{cache}{ $c->id }) {
            $self->{_frozen_reads}{ $c->id } = 1;
            next;
        }
        # A PUNCTUATION VARIABLE has no global to read (`$"`, which join
        # takes as its separator without lowering the read); a consumer that
        # does need it refuses by name when it lowers it.
        # $@ IS ONE, but an eval sets it with no store. A read at a version
        # made inside an open eval is held to that eval's join (close_eval):
        # it follows the eval, the version does not say how far. (A read the
        # producer pins on the control chain is lowered where it stands.)
        if ($c->operation eq 'EntryDef' && ($c->symbol // '') eq '@' && ($c->package // '') eq 'main') {
            next if blessed($c->control_in);
            if (my $f = ($self->{_eval_frames} // [])->[-1]) {
                push $f->{held}->@*, $c;
                next;
            }
        }
        elsif ($c->operation eq 'EntryDef' && ($c->symbol // '') !~ /\A\w+\z/) {
            next;
        }
        # A read whose INDEX (or container) is a loop-header Phi cannot be frozen
        # at entry -- the Phi has no SSA ref until _lower_loop emits it inside the
        # header. An `arr[$i]` element read in a foreach body is exactly this: its
        # index is the induction Phi, so it belongs in the loop body, not at
        # MemStart. Freezing it here would lower the Phi before its Loop is
        # processed (the Phi-before-loop guard). Leave it for the loop body walk.
        next if _reaches_an_unlowered_phi($self, $c);
        # A READ THROUGH A SCALAR exits when it holds no reference; made here,
        # ahead of the branch that guards it, it exited where perl never read
        # it (pvm 152). With no later version of this memory, its use reads
        # the same contents, so it is left there.
        # ...LEFT WHERE IT IS USED, it is recorded: a store through a reference
        # (which may be the same aggregate) refuses while one is pending -- a
        # direct call storing through its argument versions no memory here.
        my $by_tag = sub ($n) { blessed($n) && ( $self->_repr_of($n) // $n->stamp // '' ) =~ /\A(?:Scalar|Slot|Unknown)\z/ };
        my $through_tag = $by_tag->($c->inputs->[0])
            || ( blessed($c->inputs->[0]) && $c->inputs->[0]->operation eq 'PostfixDeref' && $by_tag->($c->inputs->[0]->inputs->[0]) );
        # AT A LOOP'S BODY START every such read waits: hoisted to the start of
        # the pass it ran ahead of the arm guarding it (pvm 124's `if (ref $i)`).
        if ($through_tag && ( $self->{_freezing_a_pass}
                || $c->operation eq 'Subscript' && !grep { blessed($_) && _is_memory_version($_) } $mem_node->consumers->@* )) {
            $self->{_pending_tag_reads}{ refaddr($c) } = $c;
            next;
        }
        my $ref = $self->lower_value($c);
        $self->{cache}{ $c->id } = $ref;           # freeze at this memory version
        $self->{_frozen_reads}{ $c->id } = 1;
        # ...and as its whole Slot, for a user that keeps a miss its narrowed
        # reading drops (_miss_kept, _subscript_slot).
        $self->{cache}{ 'slot:' . $c->id } = $self->_subscript_slot($c)
            if $c->operation eq 'Subscript' && ( $c->stamp // '' ) !~ /\A(?:Scalar|Slot)\z/
            && !( $self->{_arg_bind} && $self->{_arg_bind}{ refaddr($c) } );   # a bound read is the caller's value
    }
}

# if/else lowering. Phis are placed from the Elaborate pass's records
# (dominator-tree driven); a Context built without an `elab` never reaches
# these paths because a graph with no If has no merge to lower.
# _process_if_node: elaboration-driven version.
# Reads phi records from the Elaborate pass for this Region's merge block.
sub _process_if_node {
    my ($self, $if_node) = @_;

    # AN IF REACHED AGAIN INSIDE ITS OWN ARM is a cycle in the arm walk, and
    # recursing on it never returns (pvm chalk-found-gaps.md: a foreach over
    # a deref nested in a foreach). Refused by name, so the compiler ends.
    die "GAP: an if is reached again inside its own arm -- the arm walk "
      . "cycles here, which is not lowered\n"
        if $self->{_if_in_progress}{ refaddr($if_node) };
    local $self->{_if_in_progress} = { ($self->{_if_in_progress} // {})->%*, refaddr($if_node) => 1 };

    my $cond_input = $if_node->inputs->[1];
    die "LLVM backend (elaboration): If node has no condition (inputs[1] is undef)"
        unless defined $cond_input;

    my $cond_ref = $self->lower_value($cond_input);

    # A parameter nothing typed, inlined, is the caller's value: its truth.
    my $cond_repr = $self->_repr_of($cond_input) // 'Boolean';
    if ($cond_repr eq 'Int') {
        my $bool_ref = $self->_fresh;
        $self->_emit("  $bool_ref = icmp ne i64 $cond_ref, 0  ; If (elab): coerce Int to i1");
        $cond_ref = $bool_ref;
    }
    # ANY OTHER REPR TOO, by perl's truthiness for it: a %Str condition went
    # to `br i1` as it was and lli rejected the module (`my $c = $ENV{X} // 1;
    # if ($c)`). _emit_coercion refuses, naming the repr, where it has no rule.
    elsif ($cond_repr ne 'Boolean') {
        $cond_ref = $self->_emit_coercion($cond_ref, $cond_repr, 'Boolean', 'If.cond');
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
    $self->{_arm_dropped} = {};
    $self->_process_branch_from_if($if_node, 0, $merge_label);
    my $then_cache = delete $self->{_arm_dropped};
    my $then_end_label = $self->_current_block_label;
    my %then_var = %{ $self->{var_table} };

    # Restore to pre-branch state before processing else-branch.
    %{ $self->{var_table} } = %pre_var;

    # Process else-branch. var_table starts from pre-branch state.
    $self->_new_block($else_label);
    $self->{_arm_dropped} = {};
    $self->_process_branch_from_if($if_node, 1, $merge_label);
    my $else_cache = delete $self->{_arm_dropped};
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
            $region, $then_end_label, $else_end_label, \%then_var, \%else_var, $then_cache, $else_cache);

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
            my $var_repr  = $self->{_vd_repr}{$vd_id}
                // die "GAP: elab merge Phi for VarDecl vd=$vd_id has NO "
                     . "representation recorded — fix TypeInference so the "
                     . "VarDecl carries an explicit repr before lowering.";
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
    my ($self, $region, $then_label, $else_label, $then_vars, $else_vars, $then_cache, $else_cache) = @_;

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
    my @phis = grep { !Chalk::Target::LLVM::Context::_is_memory_phi($_) } @all_phis;

    # 2b-3 mixed effect (an arm that BOTH rebinds a scalar and stores an element,
    # so a value-Phi and a memory-Phi merge on the same Region) USED to refuse
    # here. Its stated reason was that "the value-Phi's arm order for this shape
    # is not yet reconciled with the element store", i.e. a PAIRING problem --
    # and pairing is no longer a search. The value-Phi's arm is read from the
    # Phi's own `predecessors` field just below (_phi_slot_from_predecessors),
    # which the producer populates for exactly this shape; the memory-Phi is
    # skipped as before and the post-merge read re-loads from the aggregate.
    #
    # Re-measured 2026-08-20 across 14 bilateral shapes: store-then-rebind and
    # rebind-then-store, a print ahead of both, a Str rebind, two stores in one
    # arm, an if/ELSE where both arms store and rebind, and a HASH element store
    # -- all 14 match perl on stdout and exit status. See
    # docs/plans/2026-08-20-mixed-effect-refusal-lifted.md.

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
        # whose value is a print's Boolean produces
        #   phi i64 [ %int, ... ], [ %i1, ... ]
        # which lli rejects outright. The arms are bridged to the Phi's own
        # repr — the operator rule (Part J) applied to a merge, the same fix
        # _lower_ternary and _lower_and/_lower_or use.
        #
        # The coercion must land in the ARM's block, where its value is live,
        # which is exactly where _lower_arm_in_tail leaves the emitter. Doing
        # it in pass 2 (next to the phi) would reference each arm from the
        # merge block, which is invalid IR rather than a wrong answer.
        my $phi_repr = $phi_node->stamp;
        # A MERGE NOTHING TYPED whose arms are scalars -- one an inlined
        # argument, known only here (`return "none" unless $k` falls off
        # with $k) -- is what they are; held as this lowering's (_lower_and).
        # Stamped Unknown, not unstamped: no stamp at all is an analysis
        # gap, which stays _require_repr's loud refusal.
        if (defined $phi_repr && $phi_repr eq 'Unknown') {
            my @r = map { $self->_repr_of($_) } grep { blessed($_) } $inputs->@*;
            if (@r == 2 && !grep { !defined || !/\A(?:Int|Num|Str|Boolean|Undef|Scalar)\z/ } @r) {
                $phi_repr = $r[0] eq $r[1] ? $r[0] : 'Scalar';
                $self->{cache}{ 'repr:' . $phi_node->id } = $phi_repr;
            }
        }

        # WHICH PHI SLOT IS THE THEN ARM? Read it off the Region, do not
        # assume slot 0.
        #
        # A Phi's incoming values are positionally paired with its Region's
        # CONTROL inputs -- slot i comes from the predecessor at Region input
        # i. That pairing is a fact the graph records, and it is not always
        # (then, else): perl5-son's StackSim::merge builds
        # `Region(inputs => [$control, $other->control])` with $control the
        # CONTINUING path and $other the ARM, so for an `if` in void context
        # the Region reads (false-Proj, true-Proj) and slot 0 is the ELSE arm.
        #
        # Assuming slot 0 == then wired the base binding to the taken branch.
        # Measured on `my $n=5; my $x=0; $x = 1 if $n > 0; print $x`:
        # perl prints 1, chalk printed 0 -- the rebind silently did not take
        # effect. Well-formed IR, wrong value, which is why no verifier caught
        # it (docs/plans/2026-08-17-step4-measured-2b3-is-load-bearing.md).
        # Prefer the Phi's own record. When the producer supplied
        # `predecessors`, arm identity is a FIELD READ; the Region search below
        # is the fallback for graphs built before that existed.
        my $then_slot = _phi_slot_from_predecessors($phi_node, 0)
                     // _phi_slot_for_proj($region, 0);
        my $else_slot = 1 - $then_slot;

        my ($then_val, $else_val);
        ($then_val, $then_label) =
            $self->_lower_arm_in_tail($inputs->[$then_slot], $then_label, $then_vars, $then_cache);
        ($then_val, $then_label) = $self->_coerce_arm($inputs->[$then_slot], $then_val, $phi_repr,
                                       $then_label, 'Region.Phi.then');
        ($else_val, $else_label) =
            $self->_lower_arm_in_tail($inputs->[$else_slot], $else_label, $else_vars, $else_cache);
        ($else_val, $else_label) = $self->_coerce_arm($inputs->[$else_slot], $else_val, $phi_repr,
                                       $else_label, 'Region.Phi.else');
        push @wired, [$phi_node, $then_val, $else_val];
    }

    # Pass 2: emit all phi lines into the merge block with the final labels.
    $self->{current_idx} = $merge_idx;
    for my $w (@wired) {
        my ($phi_node, $then_val, $else_val) = @$w;
        my $repr      = $self->{cache}{ 'repr:' . $phi_node->id }
                     // Chalk::Target::LLVM::Context::_require_repr($phi_node, 'ElaboratedContext.Region.Phi');
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

    return wantarray ? ($arm_val, $arm_label) : $arm_val unless defined $phi_repr && defined $arm_val;
    return wantarray ? ($arm_val, $arm_label) : $arm_val unless ref($arm_node) && $arm_node isa Chalk::IR::Node;
    # A PRINT IS ITS i1, whatever its stamp says: B::SoN stamps it Scalar,
    # and an if/else ending a sub merged two prints' i1s in a %Slot phi --
    # lli rejected the module (review of 4e1e9969).
    my $arm_repr = $arm_node->operation eq 'Print' ? 'Boolean' : $self->_repr_of($arm_node);
    return wantarray ? ($arm_val, $arm_label) : $arm_val unless defined $arm_repr && $arm_repr ne $phi_repr;

    my $idx = $self->_find_block_idx($arm_label);
    return wantarray ? ($arm_val, $arm_label) : $arm_val unless defined $idx;
    my $saved = $self->{current_idx};
    $self->{current_idx} = $idx;
    # A COERCION THAT OPENS BLOCKS (an Int stringified loops over its digits)
    # leaves the arm in its last one: the arm's own branch to the merge moves
    # there, and the phi names it -- left in the first, the merge named the
    # wrong predecessor and the last block had no terminator (invalid IR).
    my $arm_term = $self->{blocks}[$idx]{terminator};
    my $ref = Chalk::Target::LLVM::Context::_emit_coercion(
        $self, $arm_val, $arm_repr, $phi_repr, $what);
    my $end_label = $arm_label;
    if ($self->{current_idx} != $idx) {
        $self->_set_terminator($arm_term);
        $end_label = $self->_current_block_label;
    }
    $self->{current_idx} = $saved;
    return wantarray ? ($ref, $end_label) : $ref;
}

# _lower_arm_in_tail($arm_node, $tail_label, $var_snapshot) -> ($val, $end_label)
# Lower a phi arm value inside the named predecessor tail block, with the
# branch's var_table snapshot swapped in (when provided) so variable reads
# are branch-correct. If the arm expands into continuation blocks, its
# control flow consumed the tail's terminator: re-attach the saved
# branch-to-merge to the new tail and report the new tail's label as the
# phi's incoming label.
sub _lower_arm_in_tail {
    my ($self, $arm_node, $tail_label, $var_snapshot, $arm_cache) = @_;

    my $idx = $self->_find_block_idx($tail_label);
    $self->{current_idx} = $idx;
    my $saved_term = $self->{blocks}[$idx]{terminator};

    my %merge_vars;
    if (defined $var_snapshot) {
        %merge_vars = %{ $self->{var_table} };
        %{ $self->{var_table} } = %$var_snapshot;
    }
    # The arm's own cached values hold here, in its tail, and nowhere else:
    # what this lowering caches is dropped again, as the arm's were.
    my %cached_before = map { $_ => 1 } keys %{ $self->{cache} };
    for my $id (keys %{ $arm_cache // {} }) {
        $self->{cache}{$id} //= $arm_cache->{$id};
    }
    my $val = $self->lower_value($arm_node);
    delete @{ $self->{cache} }{ grep { !$cached_before{$_} } keys %{ $self->{cache} } };
    if (defined $var_snapshot) {
        %{ $self->{var_table} } = %merge_vars;
    }

    my $end_label = $self->_current_block_label;
    if ($end_label ne $tail_label) {
        $self->_set_terminator($saved_term);
    }
    return ($val, $end_label);
}

# _phi_slot_for_proj($region, $want_index) -> 0 or 1
#
# Which Phi incoming slot corresponds to the If arm whose Proj carries
# $want_index (0 = then/taken, 1 = else)?
#
# A Phi's values are positionally paired with its Region's CONTROL inputs, so
# the answer is the position of that Proj among them. Read from the graph
# rather than assumed, because the order is a producer build-site choice and
# not a convention: perl5-son's StackSim::merge emits
# `Region(inputs => [$control, $other->control])` -- continuing path first, arm
# second -- which puts the ELSE arm in slot 0 for a void `if`.
#
# Defaults to 0 when the Region's inputs cannot be read or no Proj matches,
# preserving the previous behaviour for any shape this cannot classify.

# _phi_slot_from_predecessors($phi, $want_index) -> slot, or undef
#
# The LOOKUP the search below approximates. A Phi that records its
# predecessors pairs inputs[i] with predecessors[i], so "which slot is the arm
# whose Proj has index N" is a scan of two stored nodes with no graph walk and
# no control_in traversal at all.
#
# Returns undef when the Phi did not record them -- a graph from a producer
# that has not been migrated, or a loop Phi, which pairs with entry/backedge
# rather than a predecessor list. The caller falls back to the search.
sub _phi_slot_from_predecessors {
    my ($phi, $want_index) = @_;
    return undef unless defined $phi && $phi->can('predecessors');

    my $preds = $phi->predecessors;
    return undef unless defined $preds && ref $preds eq 'ARRAY' && @$preds;

    for my $slot (0 .. $#$preds) {
        my $p = $preds->[$slot];
        next unless defined $p && blessed($p);
        next unless $p->can('operation') && $p->operation eq 'Proj';
        next unless $p->can('index');
        return $slot if $p->index == $want_index;
    }
    return undef;
}

sub _phi_slot_for_proj {
    my ($region, $want_index) = @_;
    return 0 unless defined $region && $region->can('inputs');

    my $inputs = $region->inputs;
    return 0 unless defined $inputs;

    # Region inputs may be a flat list or a single arrayref of controls.
    my @controls = @$inputs;
    @controls = @{ $controls[0] }
        if @controls == 1 && ref $controls[0] eq 'ARRAY';

    for my $slot (0, 1) {
        my $idx = _proj_index_of_control($controls[$slot]);
        return $slot if defined $idx && $idx == $want_index;
    }
    return 0;
}

# _proj_index_of_control($node) -> the index of the Proj this control input
# descends from, or undef.
#
# A Region's control input is NOT always the arm's Proj. It is the LAST control
# node in that arm, which is the Proj only when the arm is empty of effects.
# An arm carrying a void call or a print ends on that effect instead:
#
#     %10 = Region(%7, %9)     # %7 = Proj(index 1), %9 = Print
#
# Matching only a direct Proj therefore failed to classify slot 1 above, fell
# back to 0, and wired the Phi arms BACKWARDS -- measured on
# `if ($x > 3) { print "call\n"; $n = 5 }` as n=0 where perl says 5, and n=5
# where perl says 0, i.e. inverted in BOTH polarities.
#
# So walk back along control_in until a Proj is reached. The walk is bounded by
# a seen-set: a control chain is acyclic within an arm, but a loop back-edge
# elsewhere in the graph must not turn a misclassification into a hang -- the
# same failure that made an earlier producer-side descent recurse forever.
sub _proj_index_of_control {
    my ($node) = @_;
    my %seen;
    while (defined $node && Scalar::Util::blessed($node)) {
        last if $seen{ $node->id }++;
        my $op = $node->can('operation') ? $node->operation : '';
        if ($op eq 'Proj') {
            return $node->can('index') ? $node->index : undef;
        }
        # Stop at another merge: its own arms are a different question, and
        # descending past it would attribute this slot to the wrong branch.
        last if $op eq 'Region';
        $node = $node->can('control_in') ? $node->control_in : undef;
    }
    return undef;
}

# _process_branch_from_if: lower the body of one If branch (then=0, else=1).
# Walks the consumers of the Proj node for this branch, executing any
# VarDecl/Assign side-effect nodes and leaving the current block at the
# end of the branch.
# _prelower_branch_store_operands($if_node): for each element-store Assign guarded
# by one of $if_node's Projs, lower its container and index NOW (in the current,
# pre-branch block). A branch-guarded store and a post-merge read share these
# (hash-consed); lowering them before the branch makes their refs dominate every
# use. Pure ops (Constant, ArrayRef/HashRef container) -- lowering is idempotent
# and cached, so the store/read reuse the cached, dominating refs.
sub _prelower_branch_store_operands {
    my ($self, $if_node) = @_;
    # Collect the set of nodes that belong to a branch body so a pre-branch emit
    # never hoists a value that is itself branch-local (defined inside the arm).
    my %branch_body;
    my @bodies;
    for my $proj (grep { blessed($_) && $_->operation eq 'Proj' }
                       $if_node->consumers->@*) {
        my @nodes = _collect_branch_body($proj);
        push @bodies, @nodes;
        $branch_body{ $_->id } = 1 for @nodes;
    }

    # Descend into NESTED branches. _collect_branch_body stops at an If/Loop
    # (their bodies are discovered from their own Projs by _process_if_node),
    # so a store one level down -- `if ($c) { if ($d) { $a[0] = 9 } }` -- is
    # invisible here and its operands are never pre-lowered.
    #
    # The consequence is a dominance failure, not a missed optimisation. The
    # array literal is a PRE-BRANCH value; lowered lazily it lands in the
    # innermost block that happens to reach it first, and a post-merge read
    # then uses a value its own block is not dominated by. Measured on the
    # parked producer branch: `%tmp_14` defined in `if.then.1`, used in
    # `if.merge.3` -- "Instruction does not dominate all uses", lli exit 1.
    #
    # Nested Ifs reached this way are appended to the SAME work list, so the
    # descent is transitive: a store three levels down is pre-lowered too.
    my %seen_if = ($if_node->id => 1);
    for (my $i = 0; $i < @bodies; $i++) {
        my $node = $bodies[$i];
        next unless $node->operation eq 'If' || $node->operation eq 'Loop';
        next if $seen_if{ $node->id }++;
        for my $proj (grep { blessed($_) && $_->operation eq 'Proj' }
                           ($node->consumers // [])->@*) {
            for my $n (_collect_branch_body($proj)) {
                next if $branch_body{ $n->id }++;
                push @bodies, $n;
            }
        }
    }
    for my $node (@bodies) {
        if ($node->operation eq 'Assign') {
            # An element store: inputs = [target, value] with target a Subscript
            # (control is control_in, split off by the loader).
            my ($target) = grep { blessed($_) && $_->operation eq 'Subscript' }
                                $node->inputs->@*;
            next unless defined $target;
            # container = inputs[0], index = inputs[1] of the Subscript lvalue.
            $self->lower_value($target->inputs->[0]);
            $self->lower_value($target->inputs->[1]);
        }
        elsif ($node->operation eq 'Call'
            && $node->can('dispatch_kind')
            && ($node->dispatch_kind // '') eq 'method') {
            # A branch-guarded void method call (`$c->inc if ...`). Its INVOCANT
            # (inputs[0] after the control_in edge is split off by the loader) is
            # a value defined BEFORE the branch (e.g. the `Call new` bound to $c)
            # and is ALSO used post-merge by a later read. Lazy lowering would
            # emit it inside the guarded arm block, so the post-merge use would
            # not be dominated ("instruction does not dominate all uses"). Lower
            # it HERE, in the pre-branch block (which dominates both the arm and
            # the merge), so the shared ref is cached and dominance-correct --
            # the same pre-lowering the element-store operands above rely on.
            # Skip an invocant that is itself branch-local (defined in the arm):
            # hoisting it out of its guard would be unsound.
            my ($invocant) = grep { blessed($_) && $_->operation ne 'Proj' }
                                  $node->inputs->@*;
            next unless defined $invocant;
            next if $branch_body{ $invocant->id };
            $self->lower_value($invocant);
        }
        elsif ($self->_is_array_mutating_call($node)) {
            # A branch-guarded push/shift/pop: its ARRAY is a pre-branch value
            # a post-merge read shares, as an element store's container is.
            # Lowered lazily inside the arm, `push @a, 3 if $n; scalar(@a)`
            # read a value the arm does not dominate and lli rejected it.
            my ($array) = grep {
                blessed($_) && ( ($_->stamp // '') =~ /\AArray(?:Ref)?\z/
                    || $_->operation eq 'ArrayLiteral' )
            } $node->inputs->@*;
            next unless defined $array;
            next if $branch_body{ $array->id };
            $self->lower_value($array);
        }
    }
    return;
}

# _prelower_loop_store_operands($loop_node): for each element-store Assign in
# the loop body, lower its aggregate CONTAINER now (in the current preheader
# block) so the container's SSA ref dominates the in-body store AND the post-loop
# read (the loop may run zero times -> the body block does not dominate the
# exit). The container is a pre-loop aggregate (loop-invariant); lowering it here
# is idempotent and cached, so the body/read reuse the dominating ref. The index
# is deliberately NOT pre-lowered -- it may be the loop-Phi (header-defined).
sub _prelower_loop_store_operands {
    my ($self, $loop_node) = @_;
    my $body_proj = _find_proj_consumer($loop_node, 0);
    return unless defined $body_proj;
    # THE WHOLE BODY: a store in a loop in it, or in an arm, is the body's too
    # -- its aggregate made inside was made again after (older: "0 0;0 0").
    my (@body, %in);
    my @todo = _collect_branch_body($body_proj);
    while (defined(my $n = shift @todo)) {
        next if $in{ refaddr($n) }++;
        push @body, $n;
        next unless $n->operation =~ /\A(?:Loop|If)\z/;
        push @todo, map { _collect_branch_body($_) }
            grep { blessed($_) && $_->operation eq 'Proj' && !( $n->operation eq 'Loop' && $_->index != 0 ) }
            ($n->consumers // [])->@*;
    }
    for my $node (@body) {
        next unless $node->operation eq 'Assign';
        my ($target) = grep { blessed($_) && $_->operation eq 'Subscript' }
                            $node->inputs->@*;
        next unless defined $target;
        # ONE THE PASS MAKES (an element read at the loop key) is not the same
        # every pass: it reaches the loop's phi, which is not made yet. Its
        # aggregate is (`$r[$i]`'s @r): made in the body, it was made again
        # after the loop, and the stores went to the one the body made.
        my $c = $target->inputs->[0];
        $c = $c->inputs->[0]
            while blessed($c) && $c->operation =~ /\A(?:Subscript|PostfixDeref)\z/
                && _reaches_an_unlowered_phi($self, $c);
        next if !blessed($c) || _reaches_an_unlowered_phi($self, $c);
        $self->lower_value($c);   # container only
    }
    # SO IS ANY LOOP-INVARIANT AGGREGATE THE BODY TOUCHES -- read, referenced,
    # handed to a call: a `my @a = qw(a b c)` first lowered by a read in the
    # body, then interpolated after the loop, did not dominate that use. One
    # unpinned and built from constants alone is the same every pass.
    my (%seen, @q) = ();
    @q = map { $_->inputs->@* } @body;
    while (defined(my $n = shift @q)) {
        next unless blessed($n) && !$seen{ refaddr($n) }++;
        my $op = $n->operation;
        next if $op eq 'Phi' || Chalk::IR::NodeFactory::is_statement_node($op);
        if ($op eq 'ArrayLiteral' || $op eq 'HashLiteral') {
            $self->lower_value($n)
                if !( $n->can('control_in') && blessed($n->control_in) )
                && !grep { !blessed($_) || $_->operation ne 'Constant' } $n->inputs->@*;
            next;
        }
        push @q, $n->inputs->@*;
    }
    return;
}

# _reads_at_its_memory_version($node) -> bool: a read of an aggregate that
# carries the memory version it reads at -- an element read, a count, a
# builtin with memory_input -- which _freeze_memory_reads pins there.
sub _reads_at_its_memory_version {
    my ($u) = @_;
    my $op = $u->operation;
    return blessed($u->inputs->[2]) ? 1 : 0 if $op eq 'Subscript' || $op eq 'Exists';
    return blessed($u->inputs->[1]) ? 1 : 0 if $op eq 'Count';
    return 1 if $op eq 'Call' && $u->can('memory_input') && $u->memory_input
        && ( $u->name // '' ) =~ /\A(?:join|sort|reverse|keys|values)\z/;
    return 0;
}

# _prelower_loop_drain_operands($loop_node): a shift/pop that drains an array in
# the loop condition or body carries the ARRAY as a loop-invariant operand (the
# literal `@q` is built once, pre-loop; the shift mutates its header in place
# each iteration). Lower that array in the PREHEADER so it is constructed ONCE
# and its SSA ref dominates every iteration -- otherwise the ArrayRef is emitted
# inside the header and re-initialized each iteration (an infinite drain). Mirror
# of _prelower_loop_store_operands for the shift/pop drain primitive.
sub _prelower_loop_drain_operands {
    my ($self, $loop_node) = @_;
    # A drain Call (shift/pop) reads the loop's memory-Phi and produces the next
    # memory version (the memory-Phi's backedge input). Find the memory-Phis on
    # this Loop, then any array-mutating Call among their inputs/consumers, and
    # pre-lower its loop-invariant array operand in the preheader.
    my %seen;
    for my $c (($loop_node->consumers // [])->@*) {
        next unless blessed($c) && $c->operation eq 'Phi' && _is_memory_phi($c);
        my $r = $c->region;
        next unless defined $r && $r->id eq $loop_node->id;
        for my $n ($c->inputs->@*, ($c->consumers // [])->@*) {
            next unless blessed($n) && !$seen{$n->id}++;
            next unless $self->_is_array_mutating_call($n);
            # Identify the array by op OR repr (its repr may be unset when the
            # drained value is off the return path); match _lower_builtin_shift_pop.
            my ($array) = grep {
                my $op  = blessed($_) ? $_->operation : '';
                my $rep = (blessed($_) && $_->stamp) // '';
                $op eq 'ArrayLiteral' || $op eq 'HashLiteral'
                    || $rep eq 'Array' || $rep eq 'ArrayRef'
            } $n->inputs->@*;
            next unless defined $array;

            # SOUNDNESS (GAP-not-miscompile): the drain mutates the array header
            # IN PLACE, so the pre-loop array literal is destroyed as the loop
            # runs. That is safe ONLY when the array is consumed by nothing but
            # its shift/pop drain Call(s) -- any OTHER consumer (a pre-loop
            # `scalar @q` Length, an element Subscript, a `push` re-fill) would
            # observe the drained/corrupted array, not the value it expects. GAP
            # loudly on that shape rather than mislower. A bare ArrayRef literal
            # drained-only has exactly its drain Calls as consumers.
            # A FILL (push) is no drain: the array grows, and what reads it at
            # its own version reads it. Only a shift/pop empties it in place.
            for my $u ( ( ( $n->name // '' ) =~ /\A(?:shift|pop)\z/ ? ($array->consumers // []) : [] )->@*) {
                next unless blessed($u);
                next if $self->_is_array_mutating_call($u);   # a drain Call: fine
                # A READ AT ITS OWN MEMORY VERSION is frozen there
                # (_freeze_memory_reads), so it sees the array as it stood --
                # before the loop, or after it -- not half-mutated.
                next if _reads_at_its_memory_version($u);
                die "GAP: a drained array is also read/mutated elsewhere "
                  . "(op=@{[$u->operation]}) — the in-place drain would corrupt "
                  . "that use (pre-loop scalar/element read, push re-fill, or a "
                  . "second drain); not yet lowered.";
            }
            $self->lower_value($array);
        }
    }
    return;
}

sub _process_branch_from_if {
    my ($self, $if_node, $branch_idx, $merge_label) = @_;

    # Find the Proj node for this branch: it is a consumer of the If node
    # with index == branch_idx.
    my $proj = _find_proj_consumer($if_node, $branch_idx);

    # A mid-body `last` break arm: this arm's Proj feeds the enclosing loop's
    # exit Region. The arm leaves the loop -- terminate with a branch to the
    # loop's exit block (NOT the If merge), mirroring the die-arm's non-rejoining
    # terminator. The exit block reads the loop's header phis. Checked before the
    # no-body early return so an empty break arm (`last if C` with nothing after)
    # is handled too.
    my $break_exit = defined $proj ? $self->_arm_loop_exit_label($proj) : undef;

    unless (defined $proj) {
        if (defined $break_exit) {
            $self->_record_break_block($break_exit);
            $self->_set_terminator("  br label %$break_exit  ; if branch $branch_idx: mid-body last -> loop exit");
            return;
        }
        # No body for this branch — just jump to merge.
        $self->_set_terminator("  br label %$merge_label  ; if branch $branch_idx: no body, jump to merge");
        return;
    }

    # Walk consumers of the Proj node that are side-effect nodes (VarDecl,
    # Assign, CompoundAssign) or nested If/Loop nodes. These form the body
    # of the branch. Dispatch each through process_control_node so nested
    # If nodes are handled recursively via _process_if_node.
    my @body_nodes = _collect_branch_body($proj);
    my %cached_before = map { $_ => 1 } keys %{ $self->{cache} };
    for my $body_node (@body_nodes) {
        $self->process_control_node($body_node);
    }
    # A VALUE LOWERED IN AN ARM IS THE ARM'S: hash-consed, the same `"$i"`
    # served a use after the merge from inside the arm, where it did not
    # dominate. What the arm cached is dropped when it ends -- save its own
    # statements, which run once -- and a later use lowers it again. A value
    # of the arm's that the merge carries reaches it through the merge's phi.
    # The merge lowers its phi arms in the arm's tail, so the dropped values
    # are kept aside (_arm_dropped) for _lower_arm_in_tail to put back there.
    my %stmt = map { $_->id => 1 } @body_nodes;
    my $drop_arm = sub {
        for my $id (grep { !$cached_before{$_} && !$stmt{$_} } keys %{ $self->{cache} }) {
            $self->{_arm_dropped}{$id} = $self->{cache}{$id};
            delete $self->{cache}{$id};
        }
    };
    # A `next` or `last` arm takes what the pass carries FROM the arm -- a
    # loop in it made its phis here -- so that is read before the arm's
    # values are dropped.
    if (defined $break_exit && !defined _find_unwind_consumer($proj)) {
        $self->_record_break_block($break_exit, $proj);
        $drop_arm->();
        $self->_set_terminator("  br label %$break_exit  ; if branch $branch_idx: mid-body last or next");
        return;
    }
    $drop_arm->();

    # A `die` arm carries an Unwind whose control is this Proj: the arm aborts
    # (exit + unreachable) and does NOT rejoin the merge. Emit the abort as this
    # block's terminator instead of `br %merge`, so the merge block's predecessor
    # from this arm is dead (its phi never sees a value from here). The other
    # (live) arm's value dominates the merge unconditionally.
    my $unwind = _find_unwind_consumer($proj);
    if (defined $unwind) {
        $self->_emit_unwind_terminator($unwind, "if branch $branch_idx: die (abort)");
        return;
    }

    # Mid-body `last` break arm (Proj feeds the enclosing loop's exit Region):
    # branch to the loop exit instead of the merge (see the early-return note).
    if (defined $break_exit) {
        $self->_record_break_block($break_exit, $proj);
        $self->_set_terminator("  br label %$break_exit  ; if branch $branch_idx: mid-body last or next");
        return;
    }

    $self->_set_terminator("  br label %$merge_label  ; if branch $branch_idx: jump to merge");
}

# _arm_loop_exit_label($proj) -> the loop.exit label if this If-arm Proj feeds
# the enclosing loop's exit Region (a mid-body `last`), else undef. The producer
# adds the break arm's Proj as an input of the loop's exit Region, so the Proj's
# Region consumer whose id matches the top-of-stack loop context is the exit.
sub _arm_loop_exit_label {
    my ($self, $proj) = @_;
    # An arm into a jump merge (a `return` from inside a loop) goes there.
    for my $j (values %{ $self->{_jump_merges} // {} }) {
        return $j->{label} if exists $j->{arms}{ $proj->id };
    }
    my $stack = $self->{_loop_ctx_stack};
    return undef unless $stack && @$stack;
    my $ctx = $stack->[-1];
    my $exit_id = $ctx->{exit_region_id};
    return undef unless defined $exit_id;
    my @regions = grep { defined $_ && ref($_) && $_->can('operation') && $_->operation eq 'Region' }
        ($proj->consumers // [])->@*;
    # AN ARM WITH STATEMENTS before its `next` or `last` reaches the latch or
    # the exit from its last one (`{ push @o, "B"; last }`): the Region's
    # input is that push, not the Proj. Follow the arm's chain to its end.
    # Missed, a `last` arm was taken for an ordinary one and the loop ran on.
    my @arm_regions = @regions;
    my %been;
    for (my $n = $proj; blessed($n) && !$been{ refaddr($n) }++; ) {
        my @c = grep { blessed($_) } ($n->consumers // [])->@*;
        push @arm_regions, grep { $_->operation eq 'Region' } @c;
        my ($next) = grep {
            $_->operation !~ /\A(?:Region|Proj|Phi)\z/
                && $_->can('control_in') && blessed($_->control_in) && refaddr($_->control_in) == refaddr($n)
        } @c;
        # A loop or an if in the arm: the arm goes on past its merge.
        $next = $next->region
            if blessed($next) && $next->operation =~ /\A(?:If|Loop)\z/ && $next->can('region');
        $n = $next;
    }
    for my $c (@arm_regions) {
        return $ctx->{exit_label} if $c->id eq $exit_id;
    }
    # A REGION THIS LOOP HEADS THAT IS NOT ITS EXIT is where the body's arms
    # merge before the back-edge: the arm is a `next`. Branched to the exit,
    # it ended the loop; a next needs a branch to the latch with phis for
    # what the body carries, which is not built -- so it is refused.
    my $loop = $ctx->{exit_region} && $ctx->{exit_region}->can('head')
        ? $ctx->{exit_region}->head : undef;
    # It goes to the loop's LATCH, where every path that ends a pass meets
    # (_process_loop_node builds it and merges what the pass carries there).
    if (blessed($loop)) {
        # Not the loop's EXIT, which the loop heads too: a `last` arm with
        # statements reaches it the same way, and taken for the latch it ran
        # as a `next` (`a B c` for perl's `a B`).
        my ($latch) = grep {
            $_->can('head') && blessed($_->head) && refaddr($_->head) == refaddr($loop)
                && $_->id ne $exit_id
        } @arm_regions;
        if ($latch) {
            $ctx->{latch_loop} = $loop;
            return $ctx->{latch_label} //= $self->_fresh_label('loop.latch.');
        }
    }
    # A JUMP TO AN ENCLOSING LOOP (`next OUTER`, `last OUTER`): the arm joins a
    # Region that control reaches only by leaving this loop -- past its exit.
    # Placed inside this loop's body it ran as this loop's own `next` (`acacac`
    # for perl's `aaa`). Lowering it needs a branch into the enclosing loop's
    # latch or exit with phis for the extra predecessor; until then, refused.
    if (@regions) {
        # `last OUTER` joins an enclosing loop's own exit Region directly.
        my %outer_exit = map { ( $_->{exit_region_id} // '' ) => 1 } @$stack[ 0 .. $#$stack - 1 ];
        die "GAP: a jump from inside a loop to an enclosing loop (next or last with a label) "
          . "is not lowered -- it needs a branch into that loop's latch or exit\n"
            if grep { $outer_exit{ $_->id } } @regions;
        my $exit = $ctx->{exit_region};
        my (%past, @q) = ();
        @q = ($exit) if $exit;
        while (my $n = shift @q) {
            next if $past{ $n->id }++;
            push @q, grep {
                defined $_ && ref($_) && $_->can('operation')
                    && ( $_->operation eq 'Region'
                         || ( $_->can('control_in') && defined $_->control_in && $_->control_in == $n ) )
            } ($n->consumers // [])->@*;
        }
        die "GAP: a jump from inside a loop to an enclosing loop (next or last with a label) "
          . "is not lowered -- it needs a branch into that loop's latch or exit\n"
            if grep { $past{ $_->id } } @regions;
    }
    return undef;
}

# _record_break_block($exit_label): note the CURRENT block as a break predecessor
# of the loop whose exit is $exit_label. The exit block's multi-exit Phi needs
# each break arm's [value, %break_block] pair; the break block is whatever block
# is current when the break terminator is emitted (an If-arm block). Recorded in
# the matching loop-ctx-stack entry so the exit-block emission can build the Phi.
sub _record_break_block {
    my ($self, $exit_label, $proj) = @_;
    # INTO A JUMP MERGE: what this arm brings to the merge's Phis, lowered
    # here; the block that branches is the one after it.
    if (my ($j) = grep { $_->{label} eq $exit_label } values %{ $self->{_jump_merges} // {} }) {
        my %cached_before = map { $_ => 1 } keys %{ $self->{cache} };
        my %vals;
        for my $phi (_merge_phis($j->{region})) {
            # The Phi names the arm by its Proj, or by its last statement.
            my $i = _phi_input_along($phi, $j->{region}, $proj)
                // _phi_input_along($phi, $j->{region}, $j->{arms}{ $proj->id })
                // die "GAP: a merge Phi with no input along a jump into it is not lowered\n";
            $vals{ $phi->id } = $self->_as_phi_reading($self->lower_value($phi->inputs->[$i]),
                $phi->inputs->[$i], $phi, 'a jump: its value');
        }
        delete $self->{cache}{$_} for grep { !$cached_before{$_} } keys %{ $self->{cache} };
        push $j->{preds}->@*, { label => $self->_current_block_label, vals => \%vals };
        return;
    }
    my $stack = $self->{_loop_ctx_stack} // return;
    # A `next` arm: what it brings to each latch Phi is lowered here, in the
    # arm, before it branches.
    if (@$stack && ($stack->[-1]{latch_label} // '') eq $exit_label) {
        my $ctx = $stack->[-1];
        my %vals;
        # What is lowered for it belongs to this arm: not served to another.
        my %cached_before = map { $_ => 1 } keys %{ $self->{cache} };
        for my $phi (_latch_phis($ctx->{latch_loop})) {
            my @v = map { $_->[1] } grep { blessed($_->[0]) && $_->[0]->id eq $proj->id }
                _latch_paths($phi, $phi->region);
            die "GAP: a latch Phi without one input from a `next` arm is not lowered\n" unless @v == 1;
            $vals{ $phi->id } = $self->_as_phi_reading($self->lower_value($v[0]),
                $v[0], $phi, 'next: what the pass carries');
        }
        push @{ $ctx->{latch_preds} //= [] },
            { label => $self->_current_block_label, proj => $proj, vals => \%vals };
        delete $self->{cache}{$_} for grep { !$cached_before{$_} } keys %{ $self->{cache} };
        return;
    }
    for my $ctx (reverse @$stack) {
        next unless ($ctx->{exit_label} // '') eq $exit_label;
        # WHAT THIS BREAK BRINGS TO EACH LIVE EXIT Phi is lowered here, in the
        # arm: its input after the header's, in break order. Lowered in the
        # exit block instead, it came after the Phi (and did not dominate it).
        my $i = 1 + scalar(($ctx->{break_blocks} // [])->@*);
        my %cached_before = map { $_ => 1 } keys %{ $self->{cache} };
        for my $phi (grep {
            blessed($_) && $_->operation eq 'Phi' && !_is_memory_phi($_) && _phi_has_live_consumer($_)
                && $_->inputs->@* > $i
        } ( blessed($ctx->{exit_region}) ? $ctx->{exit_region}->consumers // [] : [] )->@*) {
            $ctx->{break_vals}[$i]{ $phi->id } = $self->lower_value($phi->inputs->[$i]);
        }
        delete $self->{cache}{$_} for grep { !$cached_before{$_} } keys %{ $self->{cache} };
        # The block that branches, after what the values opened.
        push @{ $ctx->{break_blocks} //= [] }, $self->_current_block_label;
        return;
    }
    return;
}

# register_jump_merge($region, $way_in) / the merge's Phis / the input along
# a predecessor. A JUMP MERGE is a headless Region one ordinary path reaches
# and If arms jump into from inside it (a `return` in a loop): the arms
# branch to its label as they are lowered, and the chain lowers it where it
# stands (_close_jump_merge).
sub register_jump_merge {
    my ($self, $region, $way_in, $arms) = @_;
    $self->{_jump_merges}{ $region->id } = { region => $region, way_in => $way_in,
        arms => $arms, label => $self->_fresh_label('merge.'), preds => [] };
    return;
}

sub _merge_phis {
    my ($region) = @_;
    return grep {
        blessed($_) && $_->operation eq 'Phi' && blessed($_->region)
            && $_->region->id eq $region->id && !_is_memory_phi($_)
    } ($region->consumers // [])->@*;
}

sub _phi_input_along {
    my ($phi, $region, $pred) = @_;
    my @p = $phi->can('predecessors') && $phi->predecessors ? $phi->predecessors->@* : $region->inputs->@*;
    my ($i) = grep { blessed($p[$_]) && $p[$_]->id eq $pred->id } 0 .. $#p;
    return $i;
}

sub _close_jump_merge {
    my ($self, $j) = @_;
    my @preds = $j->{preds}->@*;
    if (!defined $self->{blocks}[ $self->{current_idx} ]{terminator}) {
        my %cached_before = map { $_ => 1 } keys %{ $self->{cache} };
        my %vals;
        for my $phi (_merge_phis($j->{region})) {
            my $i = _phi_input_along($phi, $j->{region}, $j->{way_in})
                // die "GAP: a merge Phi with no input along its ordinary way in is not lowered\n";
            $vals{ $phi->id } = $self->_as_phi_reading($self->lower_value($phi->inputs->[$i]),
                $phi->inputs->[$i], $phi, 'the way in: its value');
        }
        push @preds, { label => $self->_current_block_label, vals => \%vals };
        $self->_set_terminator("  br label %$j->{label}  ; to the merge");
    }
    $self->_new_block($j->{label});
    for my $phi (_merge_phis($j->{region})) {
        my $r = $self->_fresh;
        $self->_emit("  $r = phi " . _repr_to_llvm_type(_require_repr($phi, 'jump merge Phi')) . " "
            . join(', ', map { "[ $_->{vals}{ $phi->id }, %$_->{label} ]" } @preds)
            . "  ; the merge of a jump and the way in");
        $self->{cache}{ $phi->id } = $r;
    }
    return;
}

# _latch_phis($loop) -> the value Phis a loop's latch merges: the back-edges
# of its value Phis that are Phis of a Region the Loop heads (not its exit).
# B::SoN builds one such Region per `next`, each merging the one before it.
sub _latch_phis {
    my ($loop) = @_;
    my $exit = $loop->can('region') ? $loop->region : undef;
    my %seen;
    # The back-edge itself, or -- a C-style for's step over the merge, `$i +=
    # 2` of what the `next` arm left -- a Phi among its pure operands.
    my $latch_phi = sub ($n) {
        blessed($n) && $n->operation eq 'Phi' && blessed($n->region)
            && _is_latch_region($n->region, $loop);
    };
    my @found;
    for my $back (map { $_->inputs->[1] } _collect_loop_phis($loop)) {
        my (%been, @q);
        @q = ($back);
        while (defined(my $n = shift @q)) {
            next unless blessed($n) && !$been{ refaddr($n) }++;
            if ($latch_phi->($n)) { push @found, $n; next }
            next if $n->operation eq 'Phi' || !$PURE_DESCEND_OPS{ $n->operation };
            push @q, $n->inputs->@*;
        }
    }
    return grep { !$seen{ $_->id }++ } @found;
}

sub _is_latch_region {
    my ($r, $loop) = @_;
    return blessed($r) && $r->operation eq 'Region' && $r->can('head') && blessed($r->head)
        && refaddr($r->head) == refaddr($loop)
        && !grep { blessed($_) && $_->operation eq 'Proj' && ($_->index // -1) == 1
                   && blessed($_->inputs->[0]) && refaddr($_->inputs->[0]) == refaddr($loop) } $r->inputs->@*;
}

# _latch_paths($value, $region) -> ([pred, value_node], ...): what reaches
# $region along each of its paths, a nested latch Region opened into its own.
# pred is the Proj the value comes along (a `next` arm's, or the body end's).
sub _latch_paths {
    my ($v, $r) = @_;
    my $loop = $r->head;
    my $of_r = blessed($v) && $v->operation eq 'Phi' && blessed($v->region) && $v->region->id eq $r->id;
    my @p = $of_r && $v->can('predecessors') && $v->predecessors ? $v->predecessors->@* : $r->inputs->@*;
    return map {
        my $in = $of_r ? $v->inputs->[$_] : $v;
        _is_latch_region($p[$_], $loop) ? _latch_paths($in, $p[$_]) : [ $p[$_], $in ];
    } 0 .. $#p;
}

# _find_unwind_consumer($proj) -> the Unwind node reachable by walking the
# arm's control chain forward from $proj, or undef.
#
# A die arm's Unwind has control_in set to whatever node was CURRENT CONTROL
# at the point of the die (see the producer, FromOptree.pm: "$unwind->
# set_control_in($sim->control)") -- the arm's Proj only when `die` is the
# FIRST statement in the arm. When another effect (e.g. a Print) precedes the
# die, that effect is Unwind's control_in instead, so Unwind is a consumer of
# the effect, not of the Proj directly -- a one-hop scan from the Proj misses
# it (zhi F2).
#
# Walk consumers transitively, following only nodes whose control_in is the
# node just visited (i.e. staying on THIS arm's control chain, mirroring
# _collect_body_recursive), and stop at a Region -- the arm's control chain
# cannot pass through the merge without terminating first.
sub _find_unwind_consumer {
    my ($node) = @_;
    my (%visited, %walked);
    my @queue = ($node);
    while (my $cur = shift @queue) {
        my $id = $cur->id;
        next if $visited{$id}++;
        $walked{ refaddr($cur) } = 1;
        for my $c (($cur->consumers // [])->@*) {
            next unless defined $c && $c->can('operation');
            # AN EVAL'S JOIN this arm opened is reached by its input, not by
            # control_in; the arm goes on past it -- a die after it ends the
            # arm (stopped here, an outer eval's die was dropped).
            if ($c->operation eq 'Region' && $c->can('eval_entry') && blessed($c->eval_entry)
                    && $walked{ refaddr($c->eval_entry) }
                    && grep { blessed($_) && refaddr($_) == refaddr($cur) } $c->inputs->@*) {
                push @queue, $c;
                next;
            }
            next unless $c->can('control_in') && defined $c->control_in
                && $c->control_in->id eq $id;
            # A DIE AN EVAL IN THIS ARM CATCHES does not end the arm: the
            # eval's entry is on the walk, and its join goes on.
            if ($c->operation eq 'Unwind' && defined $c->eval_id
                    && grep { ( $_->eval_id // '' ) eq $c->eval_id && $walked{ refaddr($_->eval_entry) } }
                       map { @$_ } values %Chalk::Target::LLVM::Context::EVAL_BY_ENTRY) {
                push @queue, $c;
                next;
            }
            return $c if $c->operation eq 'Unwind';
            next if $c->operation eq 'Region';
            push @queue, $c;
        }
    }
    return undef;
}

# _emit_unwind_terminator($unwind, $why) -> terminate the current block with a
# runtime-free abort: `call void @exit(i32 255)` + `unreachable`. A `die` is
# lowered as a process abort (no libperl, no exception machinery). The message
# operand (the Unwind's non-control input) is not printed runtime-free; the abort
# is the observable effect (non-zero exit). Sets _need_exit so the prologue
# declares @exit.
sub _emit_unwind_terminator {
    my ($self, $unwind, $why) = @_;
    # IDEMPOTENT per Unwind node. Two independent paths can reach an Unwind: the
    # If-arm path (_find_unwind_consumer on the arm's Proj) and the control-chain
    # path (process_control_node, for a mainline die). They are disjoint for the
    # shapes measured today — a die arm aborts and never rejoins the merge, so its
    # Unwind is not on the Return's control chain — but emitting the abort twice
    # would put two `call @exit` in one block, so guard rather than rely on that.
    my $id = $unwind->can('id') ? $unwind->id : refaddr($unwind);
    return if $self->{_unwind_emitted}{$id}++;
    $self->_open_evals_entered($unwind);

    # INSIDE A BLOCK EVAL A DIE IS A BRANCH: it sets $@ and goes to the
    # eval's end. What the body calls is inlined, so every die it reaches
    # is here.
    my $f = ($self->{_eval_frames} // [])->[-1];
    # A DIE INSIDE AN EVAL in its own graph belongs to that eval. One the
    # control chain did not open (in an arm, a loop body) is not a branch here:
    # sent to another eval's end, or out of the program, it would be wrong.
    die "GAP: a die in a block eval that is not lowered as a branch (in an arm or a "
      . "loop body) is not lowered\n"
        if defined $unwind->eval_id
        && !($f && ($f->{region}->eval_id // '') eq $unwind->eval_id);
    if ($f) {
        $self->_store_eval_error($self->_die_message($unwind));
        # What was made before the first die dominates the join: only what
        # comes after it may not.
        $f->{cached_at_first_die} //= { map { $_ => 1 } keys %{ $self->{cache} } };
        $f->{dies}++;
        $self->_set_terminator("  br label %$f->{catch}  ; $why: caught by its eval");
        return;
    }

    $self->{_need_exit} = 1;
    $self->_emit("  call void \@exit(i32 255)  ; $why");
    $self->_set_terminator("  unreachable  ; $why");
    return;
}

# open_eval($region) / close_eval($region): a BLOCK EVAL lowered as a branch.
# The control chain opens it before its body's first node and closes it at
# its join (the Region carrying eval_entry). A die in between stores $@ and
# branches to the catch block (_emit_unwind_terminator); the join takes the
# body's value from the end of the body and undef from the catch. $@ is
# cleared by the producer's own store as the body begins, and here where it
# ends without dying.
sub open_eval {
    my ($self, $region) = @_;
    die "GAP: a block eval whose body makes a value that may die (a division by what "
      . "may be zero, an element reference) is not lowered -- perl's message names the "
      . "file and line, and an unused one is not in the graph\n"
        if $region->eval_may_die;
    push $self->{_eval_frames}->@*,
        { region => $region, catch => $self->_fresh_label('eval_catch'), dies => 0, held => [],
          cached_before => { map { $_ => 1 } keys %{ $self->{cache} } } };
    $self->{_eval_open_now}{ refaddr($region) } = 1;
    return;
}

sub close_eval {
    my ($self, $region) = @_;
    my $f = pop( ($self->{_eval_frames} // [])->@* );
    die "GAP: a block eval's join was reached without its body being opened\n"
        unless $f && $f->{region}->id eq $region->id;
    delete $self->{_eval_open_now}{ refaddr($region) };
    # IN LIST CONTEXT a die gives the empty list, not undef: the one value
    # this join carries cannot say that.
    die "GAP: a block eval in list or caller context that can die is not lowered -- "
      . "it yields the empty list there, not undef\n"
        if $f->{dies} && defined $region->eval_want;

    my @phis = grep {
        blessed($_) && $_->operation eq 'Phi' && blessed($_->region) && $_->region->id eq $region->id
    } ($region->consumers // [])->@*;
    my %normal;
    for my $phi (@phis) {
        my ($v)  = $phi->inputs->[0];
        my $to   = $f->{dies} ? 'Scalar' : ($phi->stamp // '');
        die "GAP: a block eval's value is a " . ($phi->stamp // 'untyped')
          . " where a die makes it undef -- only a Scalar holds both\n"
            if $f->{dies} && ($phi->stamp // '') ne 'Scalar';
        my $from = $v->stamp // '';
        my $ref  = $self->lower_value($v);
        $ref = $self->_emit_coercion($ref, $from, $to, 'eval value') if $from ne $to;
        $normal{ $phi->id } = $ref;
    }
    $self->_store_eval_error($self->_set_str_len($self->_str_const_parts('', 'eval: no error')));

    if (!$f->{dies}) {
        $self->{cache}{ $_->id } = $normal{ $_->id } for @phis;
    }
    else {
        my $join      = $self->_fresh_label('eval_join');
        my $from_body = $self->_current_block_label;
        $self->_set_terminator("  br label %$join  ; eval: the body ended");
        $self->_new_block($f->{catch});
        my %caught = map {
            ( $_->id => $self->_build_slot('false', '0', 'Undef', 'eval: died') )
        } @phis;
        $self->_set_terminator("  br label %$join  ; eval: a die was caught");
        $self->_new_block($join);
        for my $phi (@phis) {
            my $r = $self->_fresh;
            $self->_emit("  $r = phi %Slot [ $normal{ $phi->id }, %$from_body ], "
              . "[ $caught{ $phi->id }, %$f->{catch} ]  ; eval value");
            $self->{cache}{ $phi->id } = $r;
        }
        # A VALUE THE BODY MADE, READ PAST THE JOIN by a later merge (`try {
        # $c = g() } catch { $c = "x" }` reads g's value on the no-error arm):
        # made in the body, it does not dominate the join. It reaches past it
        # through a phi -- undef along a die, where no path reads it.
        my %made_here = map { $_ => 1 } grep { !$f->{cached_before}{$_} } keys %{ $self->{cache} };
        my %done;
        for my $later (grep { blessed($_) && $_->operation eq 'Phi' && !_is_memory_phi($_) } @Chalk::Target::LLVM::Context::PROGRAM) {
            for my $v (grep { blessed($_) && $made_here{ $_->id } } $later->inputs->@*) {
                next if $done{ $v->id }++ || $v->operation eq 'Phi';
                my $repr = $self->_repr_of($v) // next;
                my $ty   = eval { _repr_to_llvm_type($repr) } // next;
                my $r = $self->_fresh;
                $self->_emit("  $r = phi $ty [ $self->{cache}{ $v->id }, %$from_body ], [ undef, %$f->{catch} ]"
                  . "  ; eval: a body value past the join");
                $self->{cache}{ $v->id } = $r;
            }
        }
        # ANYTHING ELSE THE BODY MADE does not dominate the join either. A
        # constant is made again where it is next used; any other value read
        # past the join is refused: a variable the body stored keeps its old
        # value on a die, and nothing here merges the two (`eval { $c = g() };
        # print $c` read the body's value straight: invalid IR).
        my %node_of = map { $_->id => $_ } grep { blessed($_) } @Chalk::Target::LLVM::Context::PROGRAM;
        for my $id (grep { !$done{$_} && exists $self->{cache}{$_}
                           && !( $f->{cached_at_first_die} // {} )->{$_} } keys %made_here) {
            my $n = $node_of{$id};
            next if $n && $n->operation eq 'Phi' && blessed($n->region) && $n->region->id eq $region->id;
            if ($n && $n->operation eq 'Constant') { delete $self->{cache}{$id}; next }
            # A `my @a` / `my %h` is made at its graph's entry: it dominates.
            next if $n && $n->operation eq 'PadAccess' && ( $n->sigil // '' ) =~ /\A[\@%]\z/;
            $self->{_past_a_died_eval}{$id} = 1;
        }
    }

    # $@ as the eval left it: the reads held back while it was open.
    for my $c (grep { !exists $self->{cache}{ $_->id } } $f->{held}->@*) {
        next if _reaches_an_unlowered_phi($self, $c);
        $self->{cache}{ $c->id } = $self->lower_value($c);
        $self->{_frozen_reads}{ $c->id } = 1;
    }
    return;
}

# _refuse_inside_eval($what) -- a body lowered as its own function (a class
# method, ADJUST) aborts the program on a die; inside an eval perl catches it.
sub _refuse_inside_eval {
    my ($self, $what) = @_;
    die "GAP: $what inside a block eval is not lowered -- a die in its body would "
      . "end the program, where perl catches it\n"
        if ($self->{_eval_frames} // [])->@*;
    return;
}

# start_eval_error_empty -- perl's $@ starts defined and empty; the global
# starts as an undefined Slot. Stored at the top of the entry block, once
# the graph is lowered and it is known whether $@ is used.
# shortcut: only a $@ the program graph names; one only a class method body reads starts undef.
sub start_eval_error_empty {
    my ($self) = @_;
    return unless $self->{_pkg_slots}{'main::@'};
    my $at    = $self->{current_idx};
    my $entry = $self->{blocks}[0]{insts};
    my $n0    = @$entry;
    $self->_new_block('eval_error_start');
    $self->_store_eval_error($self->_set_str_len($self->_str_const_parts('', '$@ starts empty')));
    my $insts = (pop $self->{blocks}->@*)->{insts};
    # What it hoisted to the entry block (the string's address) goes first.
    my @hoisted = splice @$entry, $n0;
    unshift @$entry, @hoisted, @$insts;
    $self->{current_idx} = $at;
    return;
}

# _store_eval_error($str) -- $@ = the Str $str.
sub _store_eval_error {
    my ($self, $str) = @_;
    my $slot = $self->_emit_coercion($str, 'Str', 'Scalar', 'store to $@');
    $self->_emit("  store %Slot $slot, %Slot* " . $self->_pkg_slot_ptr('main', '@')
        . "  ; store package scalar \$main::@");
    return;
}

# _die_message($unwind) -> the Str a die sets $@ to. Only a message that
# ends in a newline: perl appends " at FILE line N." to any other.
sub _die_message {
    my ($self, $unwind) = @_;
    die "GAP: a caught die of " . scalar($unwind->inputs->@*) . " arguments is not lowered -- "
      . "perl joins them into \$@\n" unless $unwind->inputs->@* == 1;
    my $m = $unwind->inputs->[0];
    my $ends_nl;
    $ends_nl = sub ($n) {
        return 0 unless blessed($n);
        return ($n->value // '') =~ /\n\z/
            if $n->operation eq 'Constant' && ($n->const_type // '') eq 'string';
        return $ends_nl->($n->inputs->[-1]) if $n->operation eq 'Concat';
        return 0;
    };
    die "GAP: a caught die whose message may not end in a newline is not lowered -- "
      . "perl appends \" at FILE line N.\", which this lowering does not know\n"
        unless $ends_nl->($m);
    my $ref = $self->lower_value($m);
    my $from = $m->stamp // '';
    $ref = $self->_emit_coercion($ref, $from, 'Str', 'die message') if $from ne 'Str';
    return $ref;
}

# _lower_builtin_exit($node) -> undef (it produces no value)
#
# `exit N` sets the process exit status and does not return. It is the same
# terminator shape as a `die` (_emit_unwind_terminator above) with the status
# taken from the operand rather than hardcoded to 255.
#
# Returns undef because exit HAS no value: perl's `exit` never returns, so any
# consumer of its "result" is unreachable code. Statements after it are not
# emitted — the `unreachable` terminator is what makes that true in the IR
# rather than merely true at runtime.
sub _lower_builtin_exit {
    my ($self, $node) = @_;

    my $inputs = $node->inputs // [];
    # Bare `exit;` is exit(0) in perl. An explicit operand must be an Int: the
    # status is an i32, and perl truncates anything else to an integer — which
    # is a coercion the operand should already carry (Part J: the operator
    # states its operand type). Refuse rather than guess a conversion here.
    my $status_ref = '0';
    if (@$inputs) {
        my $operand = $inputs->[0];
        my $repr    = _require_repr($operand, 'Call(builtin,exit).status');
        die "GAP: exit status has repr=$repr; only Int is lowered (perl "
          . "truncates a non-integer status, which belongs in an explicit "
          . "Coerce on the operand, not a guess here)."
            unless $repr eq 'Int';
        my $i64 = $self->lower_value($operand);
        # The status is an i32 at the C boundary; an i64 operand truncates.
        $status_ref = $self->_fresh;
        $self->_emit("  $status_ref = trunc i64 $i64 to i32  ; exit: status -> i32");
    }

    $self->{_need_exit} = 1;
    $self->_emit("  call void \@exit(i32 $status_ref)  ; exit(N)");
    $self->_set_terminator("  unreachable  ; exit does not return");
    $self->{cache}{ $node->id } = undef;
    return undef;
}

# _process_loop_node: lower a Loop node (while/foreach/postfix-while).
#
# Control flow:
#   preheader block (current): ... br label %loop.header
#   loop.header: phi for loop-carried values; test condition; br to body or exit
#   loop.body: execute body; update loop vars; br label %loop.header  (back-edge)
#   loop.exit: phi for exit values (loop_var state on exit)
#
# The Loop node carries:
#   inputs[0] = entry_ctrl (the control predecessor — already processed)
#   inputs[1] = backedge_ctrl (wired after the body — set by set_backedge_ctrl)
#   $loop->region = exit Region
#
# The loop is structured as a counted loop when the body is a simple range.
# This method handles the general case (condition test in the header).
sub _process_loop_node {
    my ($self, $loop_node) = @_;
    $self->{_loops_made}{ refaddr($loop_node) } = 1;   # see _lower_phi's forcing

    my $header_label    = $self->_fresh_label('loop.header.');
    my $body_label      = $self->_fresh_label('loop.body.');
    my $exit_label      = $self->_fresh_label('loop.exit.');

    # The loop's exit Region (its consumers are the exit-Phi merge for a mid-body
    # `last`; its id identifies "the block that routes to this loop's exit" for
    # the loop-context stack below).
    my $exit_region = $loop_node->region;
    # THE EXIT IS THE REGION THE EXIT PROJ FEEDS. Every Region the producer
    # heads with this Loop sets Loop.region at load, the last one winning --
    # and a body whose if has a `next` arm adds a second, where the body's
    # arms merge. Taken for the exit, it sent the next arm out of the loop
    # (backlog 2c7696e7: e for perl's ee).
    if (my $exit_proj = _find_proj_consumer($loop_node, 1)) {
        my ($r) = grep { blessed($_) && $_->operation eq 'Region' }
            ($exit_proj->consumers // [])->@*;
        $exit_region = $r if $r;
    }

    # ---- Lower init values in the preheader block ----
    # Each loop phi's inputs[0] is the initial value. Lower it NOW (while still
    # in the preheader block) so the SSA definition of the init value precedes
    # the phi instruction in the header block. If lowered after opening the
    # header, the init value's definition would appear after the phi that
    # references it — invalid LLVM IR (forward reference not allowed in phi).
    #
    # This happens BEFORE the preheader's terminator is set and BEFORE its
    # label is captured: a multi-block init value (bounds-checked Subscript,
    # And/Or, ternary) consumes the current block's terminator and opens
    # continuation blocks, so the block that actually falls through to the
    # header is whatever is current AFTER lowering.
    my @loop_phis = _collect_loop_phis($loop_node);

    # A body element store's aggregate container (`my @a=...` defined pre-loop)
    # must be lowered in the PREHEADER so its SSA ref dominates BOTH the in-body
    # store and the post-loop read (the loop may run zero times, so the body
    # block does not dominate the exit). Mirrors _prelower_branch_store_operands.
    # The index is NOT pre-lowered here -- it may be the loop-Phi (defined in the
    # header), which the body lowering resolves.
    $self->_prelower_loop_store_operands($loop_node);
    # A shift/pop drain's array is loop-invariant (built once, mutated in place):
    # pre-lower it in the preheader so it is not re-initialized each iteration.
    $self->_prelower_loop_drain_operands($loop_node);

    my @phi_records;    # [ { node, phi_ref, init_ref } ]

    for my $phi_node (@loop_phis) {
        my $inputs = $phi_node->inputs;
        unless (defined $inputs && scalar @$inputs >= 1) {
            die "LLVM backend: Loop Phi (id=" . $phi_node->id . ") has no incoming values";
        }
        # Lower init value in the preheader block (current block before _new_block).
        my $init_ref = $self->lower_value($inputs->[0]);
        # Coerced here, in the preheader, where it is lowered.
        $init_ref = $self->_as_phi_reading($init_ref, $inputs->[0], $phi_node, 'loop phi init');
        my $phi_ref  = $self->_fresh;
        push @phi_records, {
            node     => $phi_node,
            phi_ref  => $phi_ref,
            init_ref => $init_ref,
        };
    }

    # A NAMED AGGREGATE DECLARED BEFORE THE LOOP is made HERE, once: first
    # lowered where an arm's store pre-lowers its container -- inside the
    # body -- each pass made a fresh one, and the read after the loop saw
    # the original (`my @o = (0); for (...) { next if ...; $o[0] += 1 }`).
    $self->_prelower_aggregates_before($loop_node);

    # Re-capture the preheader label (multi-block inits may have moved us),
    # then jump from the preheader tail to the loop header.
    my $preheader_label = $self->_current_block_label;
    $self->_set_terminator("  br label %$header_label  ; Loop: enter header");

    # ---- Loop header ----
    # Open the header block. Phi instructions for loop-carried values are
    # prepended to this block after the body is lowered (two-pass approach:
    # we need the backedge SSA refs from the body to complete each phi).
    $self->_new_block($header_label);

    # Cache the phi refs so body lowering can reference them via lower_value.
    for my $rec (@phi_records) {
        $self->{cache}{ $rec->{node}->id } = $rec->{phi_ref};
        _update_var_table_for_phi($self, $rec->{node}, $rec->{phi_ref});
    }

    # A READ OF A LOCATION AT THIS PASS'S MEMORY is taken here, in the header,
    # which dominates the body and the exit. Lowered at its use, a value the
    # loop carries round (`$o .= $p * 10`, the back edge) read the location
    # after the pass stored the next pass's `$p`: perl's 0.10.20. printed
    # 10.20.30. (found under pvm 154).
    for my $m (grep { blessed($_) && $_->operation eq 'Phi' && _is_memory_phi($_)
                      && blessed($_->region) && refaddr($_->region) == refaddr($loop_node) }
               ($loop_node->consumers // [])->@*) {
        for my $c (grep { blessed($_) && $_->operation eq 'PadAccess' && $_->is_location
                          && blessed($_->inputs->[0]) && refaddr($_->inputs->[0]) == refaddr($m) }
                   ($m->consumers // [])->@*) {
            next if $self->{_frozen_reads}{ $c->id };
            $self->{cache}{ $c->id } = $self->lower_value($c);
            $self->{_frozen_reads}{ $c->id } = 1;
        }
    }

    # Emit the loop condition. The condition is drawn from consumers of the
    # Loop header: a Proj 0 consumer carries the body Proj, Proj 1 carries
    # the exit Proj.
    my $cond_val_ref = $self->_lower_loop_condition($loop_node);

    # A CONDITION-mutated slot (`while ($i-- > 0)`) runs its mutation on the
    # failing (N+1th) pass too, so its post-loop value is the Phi back-edge
    # (`Subtract(phi, 1)`), which the producer binds the post-loop read to. That
    # back-edge is otherwise lowered at the body tail -- a block the loop-exit does
    # NOT descend through -- so a post-loop read of it fails LLVM dominance. Detect
    # such a back-edge by its consumer set: a plain body-carried recurrence is
    # consumed ONLY by its own Phi (post-loop reads take the Phi), whereas a
    # condition-mutation back-edge has an EXTRA consumer (the post-loop read).
    # Pre-lower those HERE, in the header block (which dominates both body and
    # exit) -- they are pure functions of the header Phi + preheader values, all
    # of which are already defined -- so the cached SSA ref dominates every use.
    $self->_prelower_condition_mutation_backedges(\@phi_records);

    # Conditional branch: condition true -> body; false -> exit. From the
    # header's LAST block: one that stringified opened blocks of its own, and
    # the exit's merge names this one as its predecessor.
    my $header_exit_from = $self->_current_block_label;
    $self->_set_terminator("  br i1 $cond_val_ref, label %$body_label, label %$exit_label  ; Loop: header branch");

    # ---- Loop body ----
    $self->_new_block($body_label);
    # What the body lowers is the body's: it need not run, so it does not
    # dominate the exit, and a use after the loop lowers its own (dropped
    # below, after the back-edge -- as an if arm's is when the arm ends).
    my %cached_before_body = map { $_ => 1 } keys %{ $self->{cache} };
    $self->_lower_pass_elements($loop_node);
    # A READ AT THIS PASS'S MEMORY is taken here, before the body's first store
    # -- as one at any other version is taken where that version is made.
    # Lowered at its use, in an arm after the pass stored the element, it read
    # the store (`my $s = $v{$k}; $v{$k} = "z"; if (...) { push @l, $s }`
    # printed "z z" for "x y"). A read after the loop is at the exit's memory,
    # not this; the header runs once more than the body, so not there.
    {
        local $self->{_freezing_a_pass} = 1;
        $self->_freeze_memory_reads($_)
            for grep { blessed($_) && $_->operation eq 'Phi' && _is_memory_phi($_)
                       && blessed($_->region) && refaddr($_->region) == refaddr($loop_node) }
                ($loop_node->consumers // [])->@*;
    }

    # Save pre-body var_table for collecting backedge updates.
    my %pre_body_vars = %{ $self->{var_table} };

    # Loop context for a mid-body `last`: a nested If whose taken arm's Proj
    # feeds THIS loop's exit Region branches to the exit block (not the If
    # merge). _process_branch_from_if consults the top of this stack. Push
    # before the body walk, pop after (nested loops stack).
    my $exit_region_id = defined $exit_region ? $exit_region->id : undef;
    push @{ $self->{_loop_ctx_stack} //= [] },
        { exit_label => $exit_label, exit_region_id => $exit_region_id,
          exit_region => $exit_region, preheader_label => $preheader_label };

    # Process the body: VarDecl/Assign nodes reachable from the body Proj.
    $self->_process_loop_body($loop_node, $header_label);

    # Capture the ctx (with any mid-body `last` break-block labels the body walk
    # recorded) before popping it -- the exit-block Phi emission below needs them.
    my $loop_ctx = pop @{ $self->{_loop_ctx_stack} };

    # THE LATCH, if a `next` arm branched to it: the body's end comes here
    # too, and each value the pass carries is merged from every path.
    if (defined $loop_ctx->{latch_label}) {
        my @preds = ($loop_ctx->{latch_preds} // [])->@*;
        my %arm   = map { $_->{proj}->id => 1 } @preds;
        my $open  = !defined $self->{blocks}[ $self->{current_idx} ]{terminator};
        # EVERY PATH AN ARM (the last if's arms both go to the latch): the block
        # after it has no predecessor, and brings nothing to the latch.
        if ($open && _latch_phis($loop_node) && !grep {
                !( blessed($_->[0]) && $arm{ $_->[0]->id } )
            } map { _latch_paths($_, $_->region) } _latch_phis($loop_node)) {
            $self->_set_terminator("  unreachable  ; every path of the pass left by a next");
            $open = 0;
        }
        my %fall;
        for my $phi (_latch_phis($loop_node)) {
            my @paths = _latch_paths($phi, $phi->region);
            my @rest  = grep { !( blessed($_->[0]) && $arm{ $_->[0]->id } ) } @paths;
            die "GAP: a latch Phi whose inputs do not pair with its `next` arms and the "
              . "body's end is not lowered\n"
                unless @rest == ($open ? 1 : 0) && @paths == @preds + @rest;
            $fall{ $phi->id } = $self->_as_phi_reading($self->lower_value($rest[0][1]),
                $rest[0][1], $phi, 'latch: the body ran to its end') if $open;
        }
        push @preds, { label => $self->_current_block_label, vals => \%fall } if $open;
        $self->_set_terminator("  br label %$loop_ctx->{latch_label}  ; Loop: the body ends") if $open;
        $self->_new_block($loop_ctx->{latch_label});
        for my $phi (_latch_phis($loop_node)) {
            my $r = $self->_fresh;
            $self->_emit("  $r = phi " . _repr_to_llvm_type(_require_repr($phi, 'Loop.latch.Phi')) . " "
                . join(', ', map { "[ $_->{vals}{ $phi->id }, %$_->{label} ]" } @preds)
                . "  ; latch: what the pass carries");
            $self->{cache}{ $phi->id } = $r;
        }
    }

    # Collect the backedge values for each phi.
    my %body_vars = %{ $self->{var_table} };

    # ---- Lower backedge values at the body tail ----
    # The backedge value (phi inputs[1], wired via set_backedge) may not be
    # pre-lowered by the body chain — and a multi-block backedge value
    # (bounds-checked Subscript etc.) consumes the current block's terminator
    # and opens continuation blocks. Lower BEFORE capturing the body-end
    # label and setting the back-edge branch, so the phi's incoming label
    # names the block that actually branches to the header.
    for my $rec (@phi_records) {
        $rec->{backedge_ref} = $self->_as_phi_reading(
            $self->_find_phi_backedge_value($rec->{node}, \%body_vars, $rec->{phi_ref}),
            $rec->{node}->inputs->[1], $rec->{node}, 'loop phi back-edge');
    }

    my $body_end_label = $self->_current_block_label;

    # Back-edge branch back to header.
    $self->_set_terminator("  br label %$header_label  ; Loop: back-edge");
    # A read frozen at a version the body made stays: it is that version's.
    delete $self->{cache}{$_}
        for grep { !$cached_before_body{$_} && !$self->{_frozen_reads}{$_} } keys %{ $self->{cache} };

    # ---- NOW emit the phi instructions at the TOP of the header block ----
    # We insert them at index 0 of the header block's insts.
    my $header_block = $self->{blocks}[ $self->_find_block_idx($header_label) ];
    my @phi_lines;
    for my $rec (@phi_records) {
        my $phi_node = $rec->{node};
        my $phi_ref  = $rec->{phi_ref};
        my $init_ref = $rec->{init_ref};
        my $backedge_ref = $rec->{backedge_ref};

        my $repr      = _require_repr($phi_node, 'Loop.Phi');
        my $llvm_type = _repr_to_llvm_type($repr);
        my $phi_line  = "  $phi_ref = phi $llvm_type [ $init_ref, %$preheader_label ], [ $backedge_ref, %$body_end_label ]  ; Loop phi";
        push @phi_lines, $phi_line;
    }
    # Prepend phi lines to the header block.
    unshift $header_block->{insts}->@*, @phi_lines;

    # ---- Exit block ----
    $self->_new_block($exit_label);
    # A LOCALALIAS IS UNDONE WHERE THE PASS ENDS: the pointer it moved
    # points again where it did before the loop.
    for my $a (sort keys %{ $loop_ctx->{alias_saves} // {} }) {
        my ($save, $g) = $loop_ctx->{alias_saves}{$a}->@*;
        my $o = $self->_fresh;
        $self->_emit("  $o = load %Slot*, %Slot** $save  ; \$$a as before the loop");
        $self->_emit("  store %Slot* $o, %Slot** ${g}_at");
    }

    # A single-exit loop's exit block has ONE predecessor (the header's
    # false-condition branch), so loop-carried values flow through the HEADER
    # phis and no exit-Region phi is needed. A MID-BODY `last` makes the exit
    # a real 2-way merge (header-false OR break); its exit Region carries a Phi
    # per slot that DIFFERS between the two paths. Such a Phi is:
    #   - DEAD (no live consumer): the differing slot is not read post-loop (the
    #     common `last` that only breaks); the producer attaches it defensively
    #     and it DCEs away. Skip it silently.
    #   - LIVE (has a consumer): a slot rebound before the break AND read after
    #     the loop (`while(C){...$x=..; last if D} $x`). Emit a real exit Phi over
    #     the two paths: [header-Phi value, %header] + [break-point value, %break].
    if (defined $exit_region) {
        my @live_exit_phis = grep {
            defined $_ && ref($_) && $_->can('operation') && $_->operation eq 'Phi'
                && !exists $self->{cache}{ $_->id }
                && !_is_memory_phi($_)
                && _phi_has_live_consumer($_)
        } ($exit_region->consumers // [])->@*;

        # The exit block's predecessors, in the exit Region's input order: the
        # header-false edge (from the header block) first, then each break block
        # recorded as the body's mid-body `last` arms terminated. The exit Phi's
        # inputs align 1:1 with these predecessors (the producer builds the Phi
        # over [header-value, break-value...] matching the Region predecessors).
        my @break_blocks = ($loop_ctx->{break_blocks} // [])->@*;
        my @pred_labels  = ($header_exit_from, @break_blocks);

        for my $phi (@live_exit_phis) {
            my $inputs = $phi->inputs;
            unless (defined $inputs && @$inputs == @pred_labels) {
                die "GAP: loop-exit Phi (id=" . $phi->id . ") has "
                  . (defined $inputs ? scalar(@$inputs) : 0) . " inputs but the "
                  . "exit block has " . scalar(@pred_labels) . " predecessor(s) "
                  . "(header + " . scalar(@break_blocks) . " break) — cannot align "
                  . "a multi-exit merge Phi.";
            }
            my $repr      = _require_repr($phi, 'Loop.exit.Phi');
            my $llvm_type = _repr_to_llvm_type($repr);
            # Each input value (the header Phi and the break-point value) is
            # computed in a block that dominates the exit (the header block for
            # both the header Phi and the loop-body Add), so lower_value returns a
            # dominating SSA ref.
            my @arms = map {
                my $v = $loop_ctx->{break_vals}[$_]{ $phi->id } // $self->lower_value($inputs->[$_]);
                "[ $v, %$pred_labels[$_] ]"
            } 0 .. $#pred_labels;
            my $phi_ref = $self->_fresh;
            $self->_emit("  $phi_ref = phi $llvm_type " . join(", ", @arms)
                . "  ; loop-exit multi-exit merge (header OR mid-body last)");
            $self->{cache}{ $phi->id } = $phi_ref;
        }
    }

    # Update var_table with the final values (from exit path = body_vars at
    # the point of the exit branch, which is the last state of the header
    # phi values since the condition was false, meaning the body did NOT run
    # one more time. For loop-exit values, we use the phi_ref from the header
    # (the value at the top of the header when the condition was checked).
    # This is correct: loop exits when condition is false, which is tested
    # BEFORE the body runs, so the exit value is the phi at the header.
    for my $rec (@phi_records) {
        my $phi_node = $rec->{node};
        my $phi_ref  = $rec->{phi_ref};
        _update_var_table_for_phi($self, $phi_node, $phi_ref);
    }
}

# _lower_loop_condition: find and lower the condition value for a loop header.
#
# Selection strategy (structural, not heuristic):
#
#   1. Find a comparison node whose control_in is the Loop node itself. This
#      is the canonical structural link authored by ir-block builders to mark
#      the condition as belonging to the header branch (not the body). Return
#      the first such node found (only one should be wired this way).
#
#   2. Fallback: walk consumers of each loop-header Phi and return the first
#      icmp-predicate node found. This covers older ir-block graphs that do
#      not wire control_in on the condition. Iterate in sorted-id order for
#      determinism (CLAUDE.md: sort all hash iteration).
#
# The structural strategy is preferred because the fallback is ambiguous when
# the loop body contains its own comparisons that also consume the induction
# phi — a first-icmp heuristic would pick the body comparison instead of the
# header condition (H3 bug).
sub _lower_loop_condition {
    my ($self, $loop_node) = @_;

    # Strategy 1: structural — look for a comparison whose control_in is
    # the loop node. This link is set by the ir-block author via
    # $cond->set_control_in($loop) to mark the header condition explicitly.
    my $loop_consumers = $loop_node->consumers // [];
    for my $c (@$loop_consumers) {
        next unless defined $c && $c->can('operation');
        # A comparison, or any truth test (`while (my $n = $h{$k})` is
        # Not(Not(...)), `while (defined $x)` a Defined), the producer pins to
        # the loop: the header's condition, not a body comparison.
        next unless exists $ICMP_PREDICATE{ $c->operation }
            || ( blessed($c->control_in) && refaddr($c->control_in) == refaddr($loop_node)
                 && ( $c->stamp // '' ) eq 'Boolean' );
        return $self->lower_value($c);
    }

    # Strategy 2: fallback — first icmp consumer of any loop phi.
    # Collect all phi-consumer icmps, sort by node id for determinism.
    my @candidates;
    for my $phi_node (_collect_loop_phis($loop_node)) {
        my $consumers = $phi_node->consumers // [];
        for my $consumer (@$consumers) {
            next unless defined $consumer && $consumer->can('operation');
            next unless exists $ICMP_PREDICATE{ $consumer->operation };
            push @candidates, $consumer;
        }
    }
    if (@candidates) {
        # Sort by id for deterministic selection (earliest-constructed condition
        # is the induction-variable test in well-structured loops).
        my ($first) = sort { $a->id cmp $b->id } @candidates;
        return $self->lower_value($first);
    }

    die "LLVM backend: could not find loop condition — the loop ir-block must "
      . "express the condition as a comparison (NumGt/NumLt/etc.) that "
      . "either has control_in wired to the Loop node (structural) or "
      . "consumes a loop-header Phi (the induction variable)";
}

# _process_loop_body: lower the body of a loop (the statements in the body Proj).
# _prelower_aggregates_before($loop): lower, in the block before $loop, each
# array or hash literal (`my @o = (...)`, stamped Array/Hash; unpinned:
# declared outside any loop) a node downstream of $loop reads or stores through, when what it
# holds is already known here -- constants, values already lowered, and pure
# operations over them. One declared inside the loop is pinned there, and
# made each pass where it stands.
sub _prelower_aggregates_before {
    my ($self, $loop) = @_;
    my $known;
    $known = sub ($n, $seen) {
        return 1 unless blessed($n);
        return 1 if exists $self->{cache}{ $n->id };
        return 1 if $seen->{ refaddr($n) }++;
        my $op = $n->operation;
        return 1 if $op eq 'Constant';
        return 0 unless $PURE_DESCEND_OPS{$op} || $op =~ /\A(?:ArrayLiteral|HashLiteral|HashRef)\z/;
        return 0 if $n->can('control_in') && blessed($n->control_in);
        return !grep { !$known->($_, $seen) } grep { blessed($_) } $n->inputs->@*;
    };
    my (%seen, @q, @lits);
    @q = ($loop);
    while (defined(my $n = shift @q)) {
        next if $seen{ refaddr($n) }++;
        for my $in (grep { blessed($_) } $n->inputs->@*) {
            # An Array or Hash, not a reference: `[...]` / `{...}` is a new
            # one each time it is evaluated (`push @r, [0]` in a loop).
            push @lits, $in if $in->operation =~ /\A(?:ArrayLiteral|HashLiteral|HashRef)\z/
                && ( $in->stamp // '' ) =~ /\A(?:Array|Hash)\z/
                && !( $in->can('control_in') && blessed($in->control_in) );
        }
        push @q, grep { blessed($_) } ($n->consumers // [])->@*;
    }
    # ONLY ONE AN ELEMENT STORE WRITES THROUGH, and never a loop's seed: the
    # empty list a grep or map collects into is a Phi's input, and is new
    # each time that loop runs (`my @p = grep { } ...` in a loop -- shared,
    # it gathered every pass's elements, pvm 159).
    my $stored_through = sub ($lit) {
        my @c = grep { blessed($_) } ($lit->consumers // [])->@*;
        return 0 if grep { $_->operation =~ /\A(?:Phi|ListAppend)\z/ } @c;
        for my $sub (grep { $_->operation eq 'Subscript' } @c) {
            return 1 if grep { blessed($_) && $_->operation eq 'Assign' && blessed($_->inputs->[0])
                               && refaddr($_->inputs->[0]) == refaddr($sub) } ($sub->consumers // [])->@*;
        }
        return 0;
    };
    my %done;
    for my $lit (@lits) {
        next if $done{ refaddr($lit) }++ || exists $self->{cache}{ $lit->id };
        next unless $stored_through->($lit);
        next unless !grep { !$known->($_, {}) } grep { blessed($_) } $lit->inputs->@*;
        $self->lower_value($lit);
    }
    return;
}

sub _process_loop_body {
    my ($self, $loop_node, $header_label) = @_;

    # Find body nodes: consumers of the body Proj (index 0).
    my $body_proj = _find_proj_consumer($loop_node, 0);
    return unless defined $body_proj;

    my @body_nodes = _collect_branch_body($body_proj);
    # EVERY STATEMENT through process_control_node, as an if arm's are: an
    # eval in the body opens there (and its join closes it), a die in it is
    # a branch to that eval's end. Lowered by lower_value, a block eval in a
    # loop body was never opened (pvm 171-173).
    for my $body_node (@body_nodes) {
        $self->process_control_node($body_node);
    }
}

# _lower_pass_elements($loop) -- at the top of the body, each element read
# indexed by one of this loop's value Phis at this loop's own memory version
# (a foreach's `$x`): that is where its version says it is read.
#
# A LOOP WHOSE BODY CALLS A SUB THAT CAN REACH THE ARRAY IT WALKS is refused:
# perl's loop variable aliases the element, and a shift or splice in the call
# moves it out from under the index B::SoN reads it by (pvm 185 printed
# "bb;dd;" for perl's "aa;cc;").
sub _lower_pass_elements {
    my ($self, $loop) = @_;
    my (@walked, @reads);
    for my $p (_collect_loop_phis($loop)) {
        for my $s (grep { blessed($_) && $_->operation eq 'Subscript' && blessed($_->inputs->[1])
                          && refaddr($_->inputs->[1]) == refaddr($p) } ($p->consumers // [])->@*) {
            push @walked, $s->inputs->[0];
            my $mem = $s->inputs->[2];
            push @reads, $s if blessed($mem) && $mem->operation eq 'Phi' && blessed($mem->region)
                && refaddr($mem->region) == refaddr($loop);
        }
    }
    return unless @walked;
    for my $call (_calls_in_body($loop)) {
        die "GAP: a loop whose body calls a sub that can reach the array it walks is not "
          . "lowered -- perl's loop variable aliases the element, which the call may move\n"
            if _callee_moves_elements($call) && grep { _call_reaches($call, $_) } @walked;
    }
    for my $s (@reads) {
        next if exists $self->{cache}{ $s->id };
        $self->{cache}{ $s->id } = $self->lower_value($s);
    }
    return;
}

# _calls_in_body($loop) -> the non-builtin Calls downstream of the Loop whose
# control chain leads back to its body Proj (nested arms and loops too).
sub _calls_in_body {
    my ($loop) = @_;
    my $body = _find_proj_consumer($loop, 0) // return ();
    my (%seen, @calls);
    my @q = ($loop);
    while (defined(my $n = shift @q)) {
        next if $seen{ refaddr($n) }++;
        push @q, grep { blessed($_) } ($n->consumers // [])->@*;
        next unless $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) ne 'builtin';
        my %been;
        for (my $c = $n->control_in; blessed($c); ) {
            last if $been{ refaddr($c) }++;
            if (refaddr($c) == refaddr($body)) { push @calls, $n; last }
            last if refaddr($c) == refaddr($loop);
            $c = $c->operation eq 'Proj' ? $c->inputs->[0]
               : $c->can('control_in') ? $c->control_in : undef;
        }
    }
    return @calls;
}

# _callee_moves_elements($call) -- can the sub this call runs (or any sub it
# calls) move an element of an array: shift, unshift, splice, pop, or assign
# the whole array? A push or an element store moves none. A callee with no
# graph to look at is assumed to.
sub _callee_moves_elements {
    my ($call, $seen) = @_;
    $seen //= {};
    my $t = $call->can('target') ? $call->target : undef;
    my $g = blessed($t) && $t->can('graph') ? $t->graph : undef;
    return 1 unless blessed($g);
    return 0 if $seen->{ refaddr($g) }++;
    for my $n (grep { blessed($_) } $g->nodes->@*) {
        my $op = $n->operation;
        if ($op eq 'Call') {
            if (( $n->dispatch_kind // '' ) eq 'builtin') {
                return 1 if ( $n->name // '' ) =~ /\A(?:shift|unshift|splice|pop)\z/;
            }
            elsif (_callee_moves_elements($n, $seen)) { return 1 }
        }
        return 1 if $op eq 'Assign' && grep {
            blessed($_) && $_->can('stamp') && ( $_->stamp // '' ) eq 'Array'
        } $n->inputs->@*;
    }
    return 0;
}

# _call_reaches($call, $container) -- can the call see this array? It is
# passed the array, its reference, or the variable holding either (matched by
# name: each read of it is its own node), or the array lives where a callee
# can name it (a shared lexical, a package variable).
sub _call_reaches {
    my ($call, $c) = @_;
    my $root = $c;
    $root = $root->inputs->[0] while blessed($root) && $root->operation eq 'PostfixDeref';
    return 1 unless blessed($root);
    return 1 if $root->operation =~ /\A(?:EntryDef|CellRead)\z/
        || ( $root->operation eq 'PadAccess' && $root->can('shared') && $root->shared );
    my $name = $root->operation eq 'PadAccess' ? ($root->sigil // '') . ($root->symbol // '') : undef;
    for my $a (grep { blessed($_) } $call->inputs->@*) {
        my $x = $a;
        $x = $x->inputs->[0] while blessed($x) && $x->operation =~ /\A(?:PostfixDeref|Ref)\z/;
        next unless blessed($x);
        return 1 if refaddr($x) == refaddr($root) || refaddr($a) == refaddr($c);
        return 1 if defined $name && $x->operation eq 'PadAccess'
            && ($x->sigil // '') . ($x->symbol // '') eq $name;
    }
    return 0;
}


# _collect_loop_phis: find all VALUE Phi nodes whose region is this Loop node.
# A memory-Phi (its inputs are memory versions: MemStart or an element-store
# Assign) is a scheduling token, NOT a runtime value -- it is excluded here (it
# has no repr and no lowerable init) and instead threads through the memory
# scheduler: the post-loop read whose memory input IS this Phi loads the merged
# heap (see _lower_subscript's Phi-memory path).
# A Phi is LIVE if any node consumes its value. An exit-Region Phi built for a
# mid-body `last`'s differing slot is DEAD (no consumer) when that slot is not
# read post-loop -- the producer attaches it defensively so a genuine post-loop
# read (a live consumer) surfaces as a loud multi-exit GAP instead of a
# miscompile. Distinguishes the common break-only `last` (dead) from the
# unsupported multi-exit value merge (live).
sub _phi_has_live_consumer {
    my ($phi) = @_;
    my $consumers = $phi->consumers // [];
    return scalar(grep { defined $_ && ref($_) } @$consumers) > 0;
}

sub _collect_loop_phis {
    my ($loop_node) = @_;
    my @phis;
    my $consumers = $loop_node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c && $c->can('operation');
        if ($c->operation eq 'Phi' && !_is_memory_phi($c)) {
            # Check that this Phi's region IS the loop node.
            my $r = $c->region;
            if (defined $r && $r->id eq $loop_node->id) {
                push @phis, $c;
            }
        }
    }
    return @phis;
}

# A memory-Phi merges memory versions (MemStart / element-store Assign), not
# scalar values. It is a scheduling token: the read that consumes it loads the
# merged heap. Distinguished from a value-Phi by its inputs being memory nodes.
sub _is_memory_phi {
    my ($phi, $seen) = @_;
    return 0 unless blessed($phi) && $phi->operation eq 'Phi';
    $seen //= {};
    return 0 if $seen->{ refaddr($phi) }++;   # a loop's phis reach each other
    my $inputs = $phi->inputs // [];
    return 0 unless @$inputs;
    for my $in (@$inputs) {
        next unless blessed($in);
        return 1 if $in->operation eq 'MemStart';
        # an element store: an Assign whose lhs is a Subscript -- or a field,
        # or a shared file lexical, each a location stored through memory
        if ($in->operation eq 'Assign') {
            return 1 if grep { blessed($_) && $_->operation eq 'Subscript' }
                             $in->inputs->@*;
            my $lhs = $in->inputs->[0];
            return 1 if blessed($lhs) && ( $lhs->operation eq 'FieldAccess'
                || ( $lhs->operation eq 'PadAccess' && $lhs->is_location )
                || ( $lhs->operation eq 'PostfixDeref' && ($lhs->sigil // '') eq '$' ) );
        }
        # a package scalar's store
        return 1 if $in->operation eq 'EntryWrite';
        # a direct call: an inlined sub may store any of those
        # ...or a method call, which runs one (taking the producer's flag
        # wholesale instead let an arm walk that cycles through, pvm 124)
        return 1 if $in->operation eq 'Call' && ($in->dispatch_kind // '') =~ /\A(?:direct|method)\z/
            && !( defined $phi->memory && !$phi->memory );
        # ...or a builtin that versions memory (a push, a sort that runs code),
        # on a phi the producer says is memory (a value phi may merge a
        # sort's result).
        return 1 if $in->operation eq 'Call' && ( $in->dispatch_kind // '' ) eq 'builtin'
            && $phi->can('memory') && $phi->memory;
        # a memory phi of a nested structure
        return 1 if $in->operation eq 'Phi' && _is_memory_phi($in, $seen);
    }
    return 0;
}

# _prelower_condition_mutation_backedges: lower, in the CURRENT (header) block,
# any loop-Phi back-edge value that is read post-loop -- a CONDITION-mutated slot
# (`while ($i-- > 0)`). Perl runs a while condition N+1 times: the failing pass
# still applies the mutation, so the post-loop value is the back-edge, not the
# header Phi. The producer binds the post-loop read to that back-edge. Its natural
# lowering site is the body tail, which the loop-exit block does not descend
# through -- so a post-loop use is not dominated. But a condition-mutation
# back-edge is a pure function of the header Phi (defined at the header top) plus
# preheader-invariant values, so lowering it HERE (header block, dominating both
# body and exit) makes its cached SSA ref valid at every use.
#
# Detection is structural: a plain body-carried recurrence's back-edge is consumed
# ONLY by its own Phi (post-loop reads take the Phi itself), so it needs no header
# hoist. A condition-mutation back-edge has an ADDITIONAL consumer (the post-loop
# read). Hoist only those -- a body back-edge stays body-lowered (it may depend on
# body values not yet defined here).
sub _prelower_condition_mutation_backedges {
    my ($self, $phi_records) = @_;
    my %phi_id = map { $_->{node}->id => 1 } @$phi_records;
    for my $rec (@$phi_records) {
        my $backedge = $rec->{node}->inputs->[1];
        next unless defined $backedge && blessed($backedge);
        # A back-edge read outside the loop-Phi set: a non-Phi consumer, or a Phi
        # that is not one of THIS loop's header Phis.
        my $read_post_loop = grep {
            defined $_ && blessed($_)
                && !($_->operation eq 'Phi' && $phi_id{ $_->id })
        } ($backedge->consumers // [])->@*;
        next unless $read_post_loop;
        # ONE AN INNER LOOP MAKES (a value carried out through it, read again by
        # a `last LABEL` merge) is not the header's to make: that loop is not
        # made yet (pvm 115).
        next if _reaches_an_unlowered_phi($self, $backedge);
        # Lower it in the header block; the cache now holds a header-dominating ref
        # that the body tail (_find_phi_backedge_value) and the post-loop read reuse.
        $self->lower_value($backedge);
    }
}

# _find_phi_backedge_value: find the backedge value for a Loop phi node.
# The backedge value is the SSA ref of the updated variable at the end of
# the loop body — i.e. the value in var_table after the body ran.
#
# Primary strategy: read inputs[1] of the Phi, which is the explicitly wired
# backedge value (set via set_backedge after the body is constructed). Lower
# it to get the SSA ref produced by the body update.
#
# Fallback strategy: if inputs[1] is absent, look in body_vars for the VarDecl
# that this phi tracks (via _phi_to_vd). Iterate in sorted key order so the
# result is deterministic across Perl hash-iteration orders.
sub _find_phi_backedge_value {
    my ($self, $phi_node, $body_vars, $fallback_ref) = @_;

    # Primary: use inputs[1] of the phi (the explicitly wired backedge).
    my $inputs = $phi_node->inputs;
    if (defined $inputs && scalar @$inputs >= 2 && defined $inputs->[1]) {
        my $backedge_ref = $self->lower_value($inputs->[1]);
        return $backedge_ref if defined $backedge_ref;
    }

    # Fallback: look in body_vars for the VarDecl this phi tracks.
    # Sort keys for deterministic iteration (CLAUDE.md: sort all hash iteration).
    for my $vd_id (sort keys %$body_vars) {
        my $body_ref = $body_vars->{$vd_id};
        # Skip if the body value is unchanged from the phi_ref (no update).
        next if $body_ref eq $fallback_ref;
        # Check if this phi is known to track this vd_id (set by _update_var_table_for_phi).
        if (defined $self->{_phi_to_vd}{ $phi_node->id }
            && $self->{_phi_to_vd}{ $phi_node->id } eq $vd_id) {
            return $body_ref;
        }
    }

    return $fallback_ref;
}

# _update_var_table_for_phi: find the VarDecl that a Loop phi tracks and
# update var_table to point to the phi's SSA ref.
sub _update_var_table_for_phi {
    my ($self, $phi_node, $phi_ref) = @_;

    # The phi's inputs[0] is the initial value. If inputs[0] is a VarDecl,
    # or if inputs[0]'s producer is a VarDecl, we can find the vd_id.
    my $inputs = $phi_node->inputs;
    return unless defined $inputs && @$inputs;

    my $init_node = $inputs->[0];
    return unless defined $init_node;

    # Walk back: if init_node is a VarDecl, use its id.
    if ($init_node->operation eq 'VarDecl') {
        my $vd_id = $init_node->id;
        $self->{var_table}{$vd_id} = $phi_ref;
        $self->{_phi_to_vd}{ $phi_node->id } = $vd_id;
        return;
    }
    # If init_node is a PadAccess, its inputs[0] is the VarDecl.
    if ($init_node->operation eq 'PadAccess') {
        my $vd = $init_node->inputs->[0];
        if (defined $vd && $vd->operation eq 'VarDecl') {
            my $vd_id = $vd->id;
            $self->{var_table}{$vd_id} = $phi_ref;
            $self->{_phi_to_vd}{ $phi_node->id } = $vd_id;
            return;
        }
    }
}

# _find_proj_consumer($node, $idx) -> Proj node with index == $idx, or undef.
sub _find_proj_consumer {
    my ($node, $idx) = @_;
    my $consumers = $node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c && $c->can('operation');
        next unless $c->operation eq 'Proj';
        return $c if $c->index == $idx;
    }
    return undef;
}

# _collect_branch_body($proj_node) -> ordered list of body side-effect nodes.
# Walks consumers of the Proj node and collects statement-effect + control
# nodes in topological order (simplified: consumers of consumers).
sub _collect_branch_body {
    my ($proj_node) = @_;
    my @body;
    my %visited;
    $visited{owned}{ $proj_node->id } = 1;
    _collect_body_recursive($proj_node, \%visited, \@body);
    return @body;
}

sub _collect_body_recursive {
    my ($node, $visited, $body) = @_;
    return unless defined $node;
    my $id = $node->id;
    return if $visited->{$id}++;

    my $op = $node->can('operation') ? $node->operation : '';

    # A Region is the MERGE point where the branch arms rejoin: anything reached
    # only THROUGH it is post-branch, not part of this arm. Stop here so an
    # unconditional statement effect that follows the branch (control_in=Region,
    # e.g. `$c->inc if $x>3; $c->inc;`) is NOT swept into the then-arm body and
    # dropped when the guard is false (zhi 019f2df7). The Region itself and its
    # post-merge consumers are handled by the outer control chain.
    # AN EVAL'S JOIN IN THIS ARM is a statement of it -- it closes the eval
    # its entry opened here -- and the arm goes on past it.
    if ($op eq 'Region' && $node->can('eval_entry') && blessed($node->eval_entry)
            && $visited->{owned}{ $node->eval_entry->id }) {
        $visited->{owned}{$id} = 1;
        $visited->{continues}{$id} = 1;
        push @$body, $node;
        _collect_body_recursive($_, $visited, $body) for grep { defined } ($node->consumers // [])->@*;
        return;
    }
    return if $op eq 'Region';

    # ON THE ARM'S CONTROL CHAIN is any node pinned to it -- a statement, or
    # a read pinned between two (an element read the next store's control
    # names). _owned_by_arm asks this of a statement's control_in.
    #
    # A PINNED NODE NOT ON IT YET is left unvisited: the walk follows data
    # edges too, and may reach a statement before its control predecessor.
    # Marked visited then, it was never taken when the chain did reach it --
    # `print ld($s); $s =~ s/a/Q/` in an arm dropped the s///, reached first
    # through the read it rewrites. A node outside the arm stays outside;
    # the walk does not go on through it.
    if ($node->can('control_in') && blessed($node->control_in)) {
        unless (_owned_by_arm($node, $visited)) {
            delete $visited->{$id};
            return;
        }
        $visited->{owned}{$id} = 1 unless $op eq 'If' || $op eq 'Loop';
    }

    # Statement nodes (is_statement_node: VarDecl + the shared
    # statement-effect table) and control flow (If/Loop) go into the body.
    # If/Loop branch bodies are discovered from their own Proj consumers by
    # _process_if_node, so we do not recurse through them here.
    #
    # OWNERSHIP: a statement belongs to this arm only if its own control_in
    # says so. The Region stop above catches a post-merge effect reached
    # THROUGH the Region, but the walk below follows DATA edges too, and a
    # data path can leave the arm without touching a Region:
    #
    #   Assign(a[0],9) -> Phi(mem) -> Subscript(a[0]) -> Print
    #
    # The Print's control_in is the merge Region, yet it is reachable from the
    # arm's Assign through the memory Phi. Collected into the arm, it is
    # emitted inside `if.then` and never runs when the guard is false --
    # measured as a SILENT miscompile (perl "1\n" vs chalk "", both exit 0;
    # docs/plans/2026-08-16-postmerge-baseline-remeasured.md).
    #
    # The outer control chain ALREADY reaches it: _process_control_chain walks
    # back from Return.control_in and finds exactly this node. Dropping it here
    # therefore does not lose it -- it lets the node be emitted where its
    # control_in says it lives. That is the half attempt 4 was missing: it cut
    # the data edge but had no rule for who owns the result, so nothing emitted
    # the Print at all.
    if ($op eq 'If' || $op eq 'Loop'
        || Chalk::IR::NodeFactory::is_statement_node($op)
        # a field read the producer pinned on the chain is taken where it
        # stands (process_control_node), not at its use after a store
        || ( $op eq 'FieldAccess' && blessed($node->control_in) )
        # a die an eval opened in this arm catches is one of its statements
        # (one caught by an eval outside the arm ends the arm, as before)
        || ( $op eq 'Unwind' && defined $node->eval_id
             && grep { ( $_->eval_id // '' ) eq $node->eval_id && $visited->{owned}{ $_->eval_entry->id } }
                map { @$_ } values %Chalk::Target::LLVM::Context::EVAL_BY_ENTRY )) {
        my $owned = _owned_by_arm($node, $visited);
        push @$body, $node if $owned;
        $visited->{owned}{$id} = 1 if $owned;
        if ($op eq 'If' || $op eq 'Loop') {
            # THE ARM GOES ON PAST A NESTED STRUCTURE'S MERGE. What follows
            # an inner if or loop has that structure's Region as its
            # control_in; stopping here left it in no arm and on no chain, and
            # `foreach (...) { foreach (...) { print $y } print "|" }` printed
            # abab for perl's ab|ab| (backlog c7113f1e). The structure's own
            # arms are its processor's; its merge Region is this arm's again.
            my $merge = $owned && $node->can('region') ? $node->region : undef;
            if (blessed($merge) && !$visited->{ $merge->id }++) {
                $visited->{continues}{ $merge->id } = 1;
                _collect_body_recursive($_, $visited, $body)
                    for grep { defined } ($merge->consumers // [])->@*;
            }
            return;
        }
    }

    # Recurse into consumers that have this node as a control predecessor.
    my $consumers = $node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c;
        _collect_body_recursive($c, $visited, $body);
    }
}

# _owned_by_arm($node, $visited) -> bool
#
# Does this statement belong to the arm currently being collected?
#
# YES when its control_in is on the arm's control chain -- the arm's Proj,
# or another statement already owned by the arm. That is what "in this arm" means:
# the control chain from the arm's Proj passes through it.
#
# NO when its control_in is a Region (the merge: it is post-branch, owned by
# the outer control chain).
#
# A node with NO control_in keeps the historical behaviour and is collected.
# Statement nodes are normally pinned by the producer, but the hand-written
# frontend and hand-built test graphs do not always set it, and treating
# "unpinned" as "not mine" would silently drop those. Unpinned means unknown,
# and the safe answer for an unknown is the one that emits.
sub _owned_by_arm {
    my ($node, $visited) = @_;
    # AN UNPINNED NODE READING A MERGE THE ARM DOES NOT CONTAIN comes after
    # that merge: `keys %h` after a loop that fills %h reads the loop exit's
    # memory phi, and collected into the body it was emitted there, used
    # after the loop where it did not dominate.
    my $after_a_merge = sub {
        grep {
            blessed($_) && $_->operation eq 'Phi' && $_->can('region')
                && blessed($_->region) && $_->region->operation eq 'Region'
                && !$visited->{continues}{ $_->region->id }
                && !$visited->{owned}{ $_->region->id }
        } $node->inputs->@*;
    };
    return ($after_a_merge->() ? 0 : 1) unless $node->can('control_in');
    my $ctrl = $node->control_in;
    return ($after_a_merge->() ? 0 : 1) unless defined $ctrl && blessed($ctrl);

    my $cop = $ctrl->can('operation') ? $ctrl->operation : '';
    # A merge is post-branch -- unless it closes a structure inside this arm,
    # whose merge the arm continues from.
    return $visited->{continues}{ $ctrl->id } ? 1 : 0 if $cop eq 'Region';

    # On the arm's control chain => in the arm. Not merely REACHED: the walk
    # follows data edges too, and from a store in the arm through a loop's
    # memory phi it reaches the next pass's statements -- the If this arm
    # belongs to among them, which then counted as its own arm's and
    # recursed without end (backlog 34066162).
    return $visited->{owned}{ $ctrl->id } ? 1 : 0;
}

# _find_block_idx($label) -> index in $self->{blocks} for the given label.
sub _find_block_idx {
    my ($self, $label) = @_;
    my $blocks = $self->{blocks};
    for my $i (0 .. $#$blocks) {
        return $i if $blocks->[$i]{label} eq $label;
    }
    die "LLVM backend: internal error — block '$label' not found";
}

# ===========================================================================
# G4 Array/Hash aggregate lowering
# ===========================================================================
#
# Array representation: %Array = { i64 len, i64 cap, %Slot* elems }
# Hash representation:  %Hash  = { i64 count, i64 cap, %HashEntry* entries }
# Slot type:            %Slot  = { i1 defined, i8 tag, i64 payload }
# HashEntry type:       %HashEntry = { i8* key_ptr, i64 key_len, i32 key_enc,
#                                      i1 val_defined, i64 val_payload }
# Ref types:  ArrayRef = bitcast %Array* to i8* (pointer, no additional tag needed)
#             HashRef  = bitcast %Hash* to i8*
#
# All allocation uses libc malloc — NOT libperl AV*/HV*. The slot model is
# the tagged-scalar {i1,i64} from L3 (SPIKE confirmed: OOB -> defined=false
# = undef by construction; plain-i64 rejected because INT_MIN is a valid
# payload with no safe sentinel, as L3's analysis showed).
#
# Hash lookup: linear scan with memcmp on Str keys. Sufficient for the small
# literal hashes in the R-corpus. Order-normalized for determinism (keys are
# stored in literal order; the R3/R5/R7 corpus cases only read, not iterate).
# ===========================================================================

# _lower_array_ref: canonical ref-producing array constructor.
# _emit_array_of(\@element_nodes) -> $arr (an %Array*)
#
# Materialise a list of already-typed element nodes into a fresh %Array of
# %Slot. Extracted from _lower_array_ref so a caller that has ELEMENTS but no
# ArrayLiteral node can build the same buffer: perl flattens a literal list
# into `sort`'s argument slots (`sort {$a<=>$b} (3,1,2)` is a Call with three
# scalar inputs, measured on the wire), so the sort lowering has N elements and
# no aggregate to point at.
# _lower_list_append($node) -> the accumulator %Array* (unchanged pointer)
#
# map/grep's loop-carried accumulator step. `inputs[0]` is the accumulator --
# always a loop Phi in the shapes the producer builds -- and `inputs[1..]` are
# this iteration's contributions.
#
# ARITY DOES NOT IDENTIFY THE SHAPE, which is the whole difficulty and is
# documented on the node itself. Measured against the producer:
#
#   grep { $_ > 1 } (3,1,2)   ListAppend(Phi:Array, Subscript:Int, NumGt:Boolean)
#   map  { $_ * 2 } (1,2)     ListAppend(Phi:Array, Multiply:Int)
#   map  { ($_,$_) } (1,2)    ListAppend(Phi:Array, Subscript:Int, Subscript:Int)
#
# The first and third have THE SAME ARITY and mean different things: grep's
# last input is a BOOLEAN GATE deciding whether to append at all, map's is a
# SECOND ELEMENT. So the gate is recognised by its STAMP -- a trailing
# Boolean-repr input -- and never by counting inputs. A lowering that counted
# would be wrong for one of the two whichever way it guessed, and the corpus
# would only catch it on the shape it happened to guess against.
#
# THE ACCUMULATOR IS ONE HEAP BUFFER, MUTATED IN PLACE. `%Array*` is a
# pointer, so the loop Phi carries the same address every iteration and the
# append writes through it. That is what makes this a loop-carried value
# without a copy per iteration -- and it is why this returns the accumulator
# pointer unchanged rather than a new one.
#
# GROWTH IS malloc+memcpy, not realloc: only malloc and memcpy are declared,
# and realloc is what they compose to. Capacity doubles (from a floor of 4),
# so N appends cost O(N) copying rather than O(N^2).
# _lower_parameter($node) -> the SSA name of the function argument
#
# Inside an EMITTED FUNCTION BODY a parameter is a real LLVM argument, named
# positionally as %arg0, %arg1, ... That is the whole lowering: the value is
# already there, and this returns its name.
#
# METHOD OR SUB, the same answer. A method's arguments sit beside the `%self`
# invocant and a sub's do not, but the invocant is a separate fact -- see
# `_in_function_body` vs `_in_method_body` in configure_as_method_body. Gating
# this on the METHOD flag meant a `sub twice($n)` define refused its own
# parameter, which is why the two were split.
#
# It is NOT the question the direct-sub inliner answers. That path
# (_collect_positional_arg_reads) substitutes the CALLER's already-lowered
# value for the callee's read, because an inlined body has no arguments of its
# own. A real define has arguments, so the value arrives in the ordinary way.
sub _lower_parameter {
    my ($self, $node) = @_;

    my $idx = $node->can('index') ? $node->index : undef;
    defined $idx
        or die "GAP: Parameter node has no index -- cannot name its argument";

    unless ($self->{_in_function_body}) {
        die "GAP: op=Parameter outside an emitted function body. A parameter "
          . "lowers to an LLVM argument, so it needs a function that HAS "
          . "arguments; reaching here means a Parameter escaped both that path "
          . "and the inliner's (_collect_positional_arg_reads), which "
          . "substitutes the caller's value into an inlined body instead.";
    }

    my $ref = "%arg$idx";
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

sub _lower_list_append {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    my $inputs = $node->inputs // [];
    my $acc_node = $inputs->[0]
        or die "GAP: ListAppend has no accumulator input";
    my @rest = grep { blessed($_) } @{[ @$inputs[1 .. $#$inputs] ]};

    my $acc = $self->lower_value($acc_node);

    # THE GATE, by stamp and only at the LAST position. A Boolean contribution
    # in the middle would be an element (`map { ($_ > 1, $_) }` is a pair whose
    # first member is a boolean), so position matters as well as type.
    # A GREP'S LAST INPUT IS ITS TEST whatever it yields (the producer names
    # the collector); without the name, a Boolean last input still is.
    my $gate_node;
    if (@rest && ( ( $node->can('collector') && ($node->collector // '') eq 'grep' )
                   || ($rest[-1]->stamp // '') eq 'Boolean' )) {
        $gate_node = pop @rest;
    }

    my $cont_label = $self->_fresh_label('la.cont.');
    my $body_label = $self->_fresh_label('la.body.');

    if (defined $gate_node) {
        my $gate = $self->lower_value($gate_node);
        my $gr   = $gate_node->operation eq 'Print' ? 'Boolean' : ($gate_node->stamp // '');
        $gate = $self->_emit_coercion($gate, $gr, 'Boolean', 'grep test') if $gr ne 'Boolean';
        $self->_set_terminator("  br i1 $gate, label %$body_label, label %$cont_label  ; ListAppend: predicate gate");
        $self->_new_block($body_label);
    }

    for my $elem_node (@rest) {
        $self->_emit_append_one($acc, $elem_node);
    }

    if (defined $gate_node) {
        $self->_set_terminator("  br label %$cont_label  ; ListAppend: rejoin after append");
        $self->_new_block($cont_label);
    }

    # The pointer is unchanged -- the buffer behind it is what moved.
    $self->{cache}{ $node->id } = $acc;
    return $acc;
}

# _emit_append_one($acc_ref, $elem_node) -> nothing
#
# Append one element to a %Array*, growing the slot buffer when it is full.
# Factored out because map's pair form appends TWICE per iteration, and two
# copies of this would be two places for the grow logic to drift.
sub _emit_append_one {
    my ($self, $acc, $elem_node) = @_;

    my ($gi_def, $gi_tag, $gi_pay) =
        (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));

    # Read the header.
    my $len_ptr = $self->_fresh;
    my $cap_ptr = $self->_fresh;
    my $elm_ptr = $self->_fresh;
    $self->_emit("  $len_ptr = getelementptr inbounds %Array, %Array* $acc, i32 0, i32 0  ; ListAppend: len ptr");
    $self->_emit("  $cap_ptr = getelementptr inbounds %Array, %Array* $acc, i32 0, i32 1  ; ListAppend: cap ptr");
    $self->_emit("  $elm_ptr = getelementptr inbounds %Array, %Array* $acc, i32 0, i32 2  ; ListAppend: elems ptr");
    my $len = $self->_fresh;
    my $cap = $self->_fresh;
    $self->_emit("  $len = load i64, i64* $len_ptr  ; ListAppend: current len");
    $self->_emit("  $cap = load i64, i64* $cap_ptr  ; ListAppend: current cap");

    # GROW WHEN FULL. The empty seed has cap=0, so the first append always
    # takes this path -- which is why the floor is 4 rather than `cap * 2`
    # (doubling zero stays zero, and the buffer would never grow).
    my $full      = $self->_fresh;
    my $grow_lbl  = $self->_fresh_label('la.grow.');
    my $store_lbl = $self->_fresh_label('la.store.');
    $self->_emit("  $full = icmp sge i64 $len, $cap  ; ListAppend: buffer full?");
    $self->_set_terminator("  br i1 $full, label %$grow_lbl, label %$store_lbl  ; ListAppend: grow if full");

    $self->_new_block($grow_lbl);
    my $dbl     = $self->_fresh;
    my $newcap  = $self->_fresh;
    my $small   = $self->_fresh;
    $self->_emit("  $dbl = mul i64 $cap, 2  ; ListAppend: doubled cap");
    $self->_emit("  $small = icmp slt i64 $dbl, 4  ; ListAppend: below the floor?");
    $self->_emit("  $newcap = select i1 $small, i64 4, i64 $dbl  ; ListAppend: new cap (floor 4)");
    my $slot_sz  = _sizeof_llvm_type('%Slot');
    my $newbytes = $self->_fresh;
    $self->_emit("  $newbytes = mul i64 $newcap, $slot_sz  ; ListAppend: new buffer bytes");
    my $newbuf = $self->_fresh;
    $self->_emit("  $newbuf = call i8* \@malloc(i64 $newbytes)  ; ListAppend: grow buffer");
    my $oldslots = $self->_fresh;
    my $oldbytes = $self->_fresh;
    my $oldraw   = $self->_fresh;
    $self->_emit("  $oldslots = load %Slot*, %Slot** $elm_ptr  ; ListAppend: old slots");
    $self->_emit("  $oldraw = bitcast %Slot* $oldslots to i8*  ; ListAppend: old slots as i8*");
    $self->_emit("  $oldbytes = mul i64 $len, $slot_sz  ; ListAppend: live bytes to copy");
    $self->_emit("  call i8* \@memcpy(i8* $newbuf, i8* $oldraw, i64 $oldbytes)  ; ListAppend: copy live elements");
    my $newslots = $self->_fresh;
    $self->_emit("  $newslots = bitcast i8* $newbuf to %Slot*  ; ListAppend: new slots ptr");
    $self->_emit("  store %Slot* $newslots, %Slot** $elm_ptr  ; ListAppend: install new buffer");
    $self->_emit("  store i64 $newcap, i64* $cap_ptr  ; ListAppend: install new cap");
    $self->_set_terminator("  br label %$store_lbl  ; ListAppend: grown");

    # STORE. Re-read the elems pointer: the grow path may have replaced it, and
    # a value carried across the branch would be the pre-grow buffer on one
    # edge -- a use-after-free with the shape of a phi nobody wrote.
    $self->_new_block($store_lbl);
    my $slots = $self->_fresh;
    $self->_emit("  $slots = load %Slot*, %Slot** $elm_ptr  ; ListAppend: slots (post-grow)");

    my $elem_ref  = $self->lower_value($elem_node);
    my $elem_repr = $elem_node->stamp // '';

    # AN ELEMENT THAT IS A SCALAR is its Slot, tag and defined bit as they
    # are -- an undef a map yields stays undef.
    if (( $self->_repr_of($elem_node) // $elem_repr ) eq 'Scalar') {
        my ($sp, $newlen) = map { $self->_fresh } 1 .. 2;
        $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $slots, i64 $len  ; ListAppend: slot[len]");
        $self->_emit("  store %Slot $elem_ref, %Slot* $sp  ; ListAppend: a Scalar, as it is");
        $self->_emit("  $newlen = add i64 $len, 1  ; ListAppend: len+1");
        $self->_emit("  store i64 $newlen, i64* $len_ptr  ; ListAppend: install new len");
        return;
    }

    my $d_gep = $self->_fresh;
    my $t_gep = $self->_fresh;
    my $p_gep = $self->_fresh;
    $self->_emit("  $d_gep = getelementptr inbounds %Slot, %Slot* $slots, i64 $len, i32 $gi_def  ; ListAppend: slot[len] defined");
    $self->_emit("  $t_gep = getelementptr inbounds %Slot, %Slot* $slots, i64 $len, i32 $gi_tag  ; ListAppend: slot[len] tag");
    $self->_emit("  $p_gep = getelementptr inbounds %Slot, %Slot* $slots, i64 $len, i32 $gi_pay  ; ListAppend: slot[len] payload");
    $self->_emit("  store i1 true, i1* $d_gep  ; ListAppend: defined=true");
    my $tag = _slot_tag_for_repr($elem_repr);
    $self->_emit("  store i8 " . _slot_tag_value($tag) . ", i8* $t_gep  ; ListAppend: tag=$tag");
    my $payload = $self->_box_payload($elem_ref, $elem_repr, 'ListAppend elem');
    $self->_emit("  store i64 $payload, i64* $p_gep  ; ListAppend: payload");

    my $newlen = $self->_fresh;
    $self->_emit("  $newlen = add i64 $len, 1  ; ListAppend: len+1");
    $self->_emit("  store i64 $newlen, i64* $len_ptr  ; ListAppend: install new len");

    return;
}

sub _emit_array_of {
    my ($self, $inputs) = @_;
    return $self->_emit_flattened_array_of($inputs)
        if grep { blessed($_) && ( $_->stamp // '' ) =~ /\A(?:Array|List|Hash)\z/ } @$inputs;
    return $self->_emit_flattened_array_of($inputs)
        if grep { _returns_nothing_in_a_list($_) } @$inputs;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    my $n = scalar @$inputs;

    # Allocate slot buffer: n * sizeof(%Slot), sized BY LLVM from the type.
    my $slot_bytes = _sizeof_times('%Slot', $n);
    my $slot_buf = $self->_fresh;
    $self->_emit("  $slot_buf = call i8* \@malloc(i64 $slot_bytes)  ; ArrayRef: alloc $n slots");
    my $slots = $self->_fresh;
    $self->_emit("  $slots = bitcast i8* $slot_buf to %Slot*  ; ArrayRef: slot array ptr");

    # INTS AMONG NUMS ARE STORED AS NUMS. The literal's reading is the join
    # of its elements, and a read stamped Num takes the payload as a double:
    # `(1.5, 2)` stored 2 as an i64, read back as 9.88e-324.
    # INTS AMONG STRS ARE STORED AS STRS, for the same reason: stringifying
    # an integer is exact, and `(1, "x")` read the 1 as a string pointer.
    # A Num among Strs is not -- its 15 digits are not the number.
    my %numeric = map { ( $_->stamp // '' ) => 1 } grep { blessed($_) } @$inputs;
    die "GAP: an array literal of Num and Str elements is not lowered -- read "
      . "as Str, its Nums would lose digits\n" if $numeric{Num} && $numeric{Str};
    my $as_num  = $numeric{Num} && $numeric{Int};
    my $as_str  = $numeric{Str} && $numeric{Int};

    # Store each element as a defined slot {i1=true, i64=value}.
    for my $i (0 .. $n - 1) {
        my $elem_ref = $self->lower_value($inputs->[$i]);
        my $slot_def = $self->_fresh;
        my $slot_tag = $self->_fresh;
        my $slot_pay = $self->_fresh;
        my ($gi_def, $gi_tag, $gi_pay) =
            (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
        $self->_emit("  $slot_def = getelementptr inbounds %Slot, %Slot* $slots, i64 $i, i32 $gi_def  ; ArrayRef: slot[$i] defined ptr");
        $self->_emit("  $slot_tag = getelementptr inbounds %Slot, %Slot* $slots, i64 $i, i32 $gi_tag  ; ArrayRef: slot[$i] tag ptr");
        $self->_emit("  $slot_pay = getelementptr inbounds %Slot, %Slot* $slots, i64 $i, i32 $gi_pay  ; ArrayRef: slot[$i] payload ptr");
        my $elem_repr = $inputs->[$i]->stamp // '';
        ($elem_ref, $elem_repr) = $self->_miss_kept($inputs->[$i], $elem_ref, $elem_repr);
        # AN UNDEF IS A SLOT WITH ITS DEFINED BIT CLEAR: it needs no payload.
        if ($elem_repr eq 'Undef') {
            $self->_emit("  store i1 false, i1* $slot_def  ; ArrayRef: slot[$i] undef");
            $self->_emit("  store i8 " . _slot_tag_value('Undef') . ", i8* $slot_tag");
            $self->_emit("  store i64 0, i64* $slot_pay");
            next;
        }
        # A SCALAR IS ALREADY A SLOT: its own defined bit, tag and payload are
        # the element's (an argument kept in memory, handed to @_).
        if ($elem_repr =~ /\A(?:Scalar|Slot)\z/) {
            my %f = (defined => ['i1', $slot_def], tag => ['i8', $slot_tag], payload => ['i64', $slot_pay]);
            for my $fname (qw(defined tag payload)) {
                my $v = $self->_fresh;
                $self->_emit("  $v = extractvalue %Slot $elem_ref, " . _slot_idx($fname) . "  ; ArrayRef: slot[$i] $fname");
                $self->_emit("  store $f{$fname}[0] $v, $f{$fname}[0]* $f{$fname}[1]  ; ArrayRef: slot[$i] $fname");
            }
            next;
        }
        $self->_emit("  store i1 true, i1* $slot_def  ; ArrayRef: slot[$i] defined=true");
        if (($as_num || $as_str) && $elem_repr eq 'Int') {
            my $to = $as_num ? 'Num' : 'Str';
            $elem_ref  = $self->_emit_coercion($elem_ref, 'Int', $to, "ArrayRef elem[$i]");
            $elem_repr = $to;
        }
        # The element's own repr IS the reading its payload carries -- the very
        # repr _box_payload boxes by on the next line. Recording it here is what
        # lets a later consumer read the payload back without guessing.
        my $elem_tag  = _slot_tag_for_repr($elem_repr);
        $self->_emit("  store i8 " . _slot_tag_value($elem_tag) . ", i8* $slot_tag  ; ArrayRef: slot[$i] tag=$elem_tag");
        my $elem_i64  = $self->_box_payload($elem_ref, $elem_repr,
                                            "ArrayRef elem[$i]");
        $self->_emit("  store i64 $elem_i64, i64* $slot_pay  ; ArrayRef: slot[$i] payload=$elem_i64");
    }

    # Allocate Array header: { i64 len, i64 cap, %Slot* elems }, sized by LLVM.
    my $arr_buf = $self->_fresh;
    my $arr_sz  = _sizeof_llvm_type('%Array');
    $self->_emit("  $arr_buf = call i8* \@malloc(i64 $arr_sz)  ; ArrayRef: alloc Array header");
    my $arr = $self->_fresh;
    $self->_emit("  $arr = bitcast i8* $arr_buf to %Array*  ; ArrayRef: Array ptr");
    my $len_ptr = $self->_fresh;
    my $cap_ptr = $self->_fresh;
    my $elm_ptr = $self->_fresh;
    $self->_emit("  $len_ptr = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; ArrayRef: len ptr");
    $self->_emit("  $cap_ptr = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 1  ; ArrayRef: cap ptr");
    $self->_emit("  $elm_ptr = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; ArrayRef: elems ptr");
    $self->_emit("  store i64 $n, i64* $len_ptr  ; ArrayRef: len=$n");
    $self->_emit("  store i64 $n, i64* $cap_ptr  ; ArrayRef: cap=$n");
    $self->_emit("  store %Slot* $slots, %Slot** $elm_ptr  ; ArrayRef: store slots ptr");

    return $arr;
}

# _lower_array_ref: canonical ref-producing array constructor.
# inputs = [elem0, elem1, ...]. Returns i8* (ArrayRef repr) or %Array* (Array).
sub _lower_array_ref {
    my ($self, $node) = @_;

    my $arr = $self->_emit_array_of($node->inputs);

    # BOX ONLY WHEN THE NODE IS A REF. An `ArrayRef` OPERATION is how the
    # producer spells a literal aggregate, and it is used for BOTH `[1,2,3]`
    # (a genuine reference, repr=ArrayRef, boxed i8*) and a plain lexical
    # `my @a = (10,20,30)` (repr=Array, an unboxed %Array*). perigrin, on
    # `for my $x (@a)`: "There is no ArrayRef here."
    #
    # Boxing unconditionally handed a raw i8* to consumers that read the
    # node's repr and expected %Array*, and lli rejected the module:
    #   '%tmp_26' defined with type 'i8*' but expected '%Array*'
    # Fixing it in _container_ptr instead -- by unboxing for `Array` too --
    # was WRONG and broke the five genuine-reference cases in
    # llvm-array-hash.t, which have nothing to unbox.
    my $repr = $node->stamp // 'ArrayRef';
    if ($repr eq 'Array') {
        $self->{cache}{ $node->id } = $arr;
        return $arr;
    }

    # The canonical ref result is the i8* (Array* bitcast).
    my $ref = $self->_fresh;
    $self->_emit("  $ref = bitcast %Array* $arr to i8*  ; ArrayRef: Array* -> i8* ref");

    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _lower_hash_from_pairs($node) -> a hash built pair by pair, a key seen again
# replacing its value, a key with no value after it undef: from its pairs as
# written, or -- a list among them (`@_`, an array, a map) -- from them all
# flattened, walked two at a time at run time.
sub _lower_hash_from_pairs {
    my ($self, $node) = @_;
    my @in = $node->inputs->@*;
    my ($hb, $hash) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $hb = call i8* \@malloc(i64 " . _sizeof_llvm_type('%Hash') . ")  ; hash from pairs: header");
    $self->_emit("  $hash = bitcast i8* $hb to %Hash*");
    $self->_emit("  store %Hash zeroinitializer, %Hash* $hash  ; empty: no entries, grown on insert");
    my $undef_tag = _slot_tag_value('Undef');
    if (!grep { blessed($_) && ( $_->stamp // '' ) =~ /\A(?:Hash|Array|List)\z/ } @in) {
        for (my $i = 0; $i < @in; $i += 2) {
            my ($kp, $kl) = $self->_str_parts($self->_hash_key_str($in[$i]));
            my @v = $i + 1 < @in
                ? $self->_slot_fields_of_value($in[$i + 1], $self->lower_value($in[$i + 1]), "hash value [$i]")
                : ('false', $undef_tag, '0');
            $self->_emit_hash_upsert($hash, $kp, $kl, @v);
        }
    }
    else {
        my $flat = $self->_emit_flattened_array_of(\@in);
        my ($lp, $len, $ep, $els, $ip) = map { $self->_fresh } 1 .. 5;
        $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $flat, i32 0, i32 0");
        $self->_emit("  $len = load i64, i64* $lp  ; hash from a list: its length");
        $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $flat, i32 0, i32 2");
        $self->_emit("  $els = load %Slot*, %Slot** $ep");
        $self->_emit_entry("  $ip = alloca i64  ; hash from a list: index");
        $self->_emit("  store i64 0, i64* $ip");
        my ($head, $body, $done) = map { $self->_fresh_label("hlist.$_.") } qw(head body done);
        $self->_set_terminator("  br label %$head");
        $self->_new_block($head);
        my ($i, $more) = ($self->_fresh, $self->_fresh);
        $self->_emit("  $i = load i64, i64* $ip");
        $self->_emit("  $more = icmp ult i64 $i, $len  ; hash from a list: another pair?");
        $self->_set_terminator("  br i1 $more, label %$body, label %$done");
        $self->_new_block($body);
        my ($kptr, $kslot, $i1, $has, $vi, $vptr, $vslot, $def, $tag, $pay, $i2) = map { $self->_fresh } 1 .. 11;
        $self->_emit("  $kptr = getelementptr inbounds %Slot, %Slot* $els, i64 $i");
        $self->_emit("  $kslot = load %Slot, %Slot* $kptr  ; hash from a list: key");
        my ($kp, $kl) = $self->_str_parts($self->_emit_read_slot_as($kslot, 'Str', 'hash from a list: key'));
        $self->_emit("  $i1 = add i64 $i, 1");
        $self->_emit("  $has = icmp ult i64 $i1, $len  ; hash from a list: a value after the key?");
        $self->_emit("  $vi = select i1 $has, i64 $i1, i64 $i");
        $self->_emit("  $vptr = getelementptr inbounds %Slot, %Slot* $els, i64 $vi");
        $self->_emit("  $vslot = load %Slot, %Slot* $vptr  ; hash from a list: value");
        my ($d0, $t0, $p0) = ($self->_slot_defined_bit($vslot), $self->_slot_tag_of($vslot), $self->_slot_payload_of($vslot));
        $self->_emit("  $def = and i1 $has, $d0  ; none: undef");
        $self->_emit("  $tag = select i1 $has, i8 $t0, i8 $undef_tag");
        $self->_emit("  $pay = select i1 $has, i64 $p0, i64 0");
        $self->_emit_hash_upsert($hash, $kp, $kl, $def, $tag, $pay);
        $self->_emit("  $i2 = add i64 $i, 2");
        $self->_emit("  store i64 $i2, i64* $ip");
        $self->_set_terminator("  br label %$head");
        $self->_new_block($done);
    }
    return $self->{cache}{ $node->id } = $hash if ( $node->stamp // 'HashRef' ) eq 'Hash';
    my $ref = $self->_fresh;
    $self->_emit("  $ref = bitcast %Hash* $hash to i8*  ; hash from pairs, as a reference");
    return $self->{cache}{ $node->id } = $ref;
}

# _lower_hash_ref: canonical ref-producing hash constructor.
# inputs = [key0, val0, key1, val1, ...]. Returns i8* (HashRef repr).
# Consumers resolve the typed %Hash* at their own use via _container_ptr.
sub _lower_hash_ref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;
    $self->{_need_memcmp}          = 1;

    my $inputs = $node->inputs;
    # A HASH SPREAD IN IT (`{ %a }`) is a copy of that hash. Counted as pairs,
    # `{ %a }` was half a pair.
    my $flattens = grep { blessed($_) && ( $_->stamp // '' ) =~ /\A(?:Hash|Array|List)\z/ } @$inputs;
    if ($flattens && @$inputs == 1 && ( $inputs->[0]->stamp // '' ) eq 'Hash') {
        my $copy = $self->_emit_aggregate_copy($self->_container_ptr($inputs->[0], 'Hash'), 'Hash');
        return $self->{cache}{ $node->id } = $copy if ( $node->stamp // '' ) eq 'Hash';
        my $ref = $self->_fresh;
        $self->_emit("  $ref = bitcast %Hash* $copy to i8*  ; { %h }: a copy, as a reference");
        return $self->{cache}{ $node->id } = $ref;
    }
    # EACH ENTRY ITS OWN KEY only when every key is a distinct constant, the
    # pairs whole, and nothing flattens: then the literal is its entries. Any
    # other is built pair by pair, a key seen again replacing its value --
    # entry by entry, `(a => 1, a => 3)` kept both and read 1.
    my %seen;
    my @keys = @$inputs[ grep { !( $_ % 2 ) } 0 .. $#$inputs ];
    return $self->_lower_hash_from_pairs($node)
        if $flattens || @$inputs % 2
        || grep { !( blessed($_) && $_->operation eq 'Constant' && defined $_->value ) || $seen{ $_->value }++ } @keys;
    my $npairs = scalar(@$inputs) / 2;

    # Sized by LLVM from %HashEntry: it embeds a slot's worth of value fields,
    # so a hand-written 48 goes wrong exactly when those change.
    my $entry_bytes = _sizeof_times('%HashEntry', $npairs);
    my $ent_buf = $self->_fresh;
    $self->_emit("  $ent_buf = call i8* \@malloc(i64 $entry_bytes)  ; HashRef: alloc $npairs entries");
    my $ents = $self->_fresh;
    $self->_emit("  $ents = bitcast i8* $ent_buf to %HashEntry*  ; HashRef: entry array ptr");

    for my $i (0 .. $npairs - 1) {
        my $key_ref = $self->_hash_key_str($inputs->[ $i * 2 ]);
        my $val_ref = $self->lower_value($inputs->[ $i * 2 + 1 ]);
        # The stored key length is later memcmp'd at read/update time; a 0-length
        # key would make every lookup match this entry. Die loudly on an untracked
        # length rather than default to 0 (matches the I-C loud-GAP contract).
        my ($key_ptr, $key_len) = $self->_str_parts($key_ref);
        $key_ref = $key_ptr;
        defined $key_len
            or die "GAP: HashRef key (ref=$key_ref) has no tracked length — "
                 . "stored key length 0 would make any lookup match this entry.";

        my $e_kp = $self->_fresh;
        my $e_kl = $self->_fresh;
        my $e_ke = $self->_fresh;
        my $e_vd = $self->_fresh;
        my $e_vp = $self->_fresh;
        $self->_emit("  $e_kp = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 " . _he_idx('key_ptr') . "  ; HashRef: entry[$i] key_ptr ptr");
        $self->_emit("  $e_kl = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 " . _he_idx('key_len') . "  ; HashRef: entry[$i] key_len ptr");
        $self->_emit("  $e_ke = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 " . _he_idx('key_enc') . "  ; HashRef: entry[$i] key_enc ptr");
        $self->_emit("  $e_vd = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 " . _he_idx('val_def') . "  ; HashRef: entry[$i] val_def ptr");
        $self->_emit("  $e_vp = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 " . _he_idx('val_pay') . "  ; HashRef: entry[$i] val_pay ptr");
        $self->_emit("  store i8* $key_ref, i8** $e_kp  ; HashRef: key ptr");
        $self->_emit("  store i64 $key_len, i64* $e_kl  ; HashRef: key len=$key_len");
        $self->_emit("  store i32 0, i32* $e_ke          ; HashRef: enc=0 (ASCII)");
        # A %HashEntry's value is the same {defined, tag, i64 payload} cell a
        # %Slot is: a value read by its tag (an argument `$_[1]`) is stored
        # as it is, an undef as undef, any other boxed by its reading.
        my $val_node = $inputs->[ $i * 2 + 1 ];
        my ($v_def, $v_tag, $v_pay) = $self->_slot_fields_of_value($val_node, $val_ref, "HashRef value[$i]");
        $self->_emit("  store i1 $v_def, i1* $e_vd         ; HashRef: defined");
        $self->_emit("  store i64 $v_pay, i64* $e_vp   ; HashRef: value");
        # ITS READING, stored beside it: a read decodes by this, not by its own
        # stamp (a hash of Int and Num values read the 1 as 4.94e-324).
        my $e_vt = $self->_fresh;
        $self->_emit("  $e_vt = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 "
            . _he_idx('val_tag') . "  ; HashRef: entry[$i] val_tag ptr");
        $self->_emit("  store i8 $v_tag, i8* $e_vt  ; HashRef: entry[$i] tag");
    }

    my $hash_buf = $self->_fresh;
    my $hash_sz  = _sizeof_llvm_type('%Hash');
    $self->_emit("  $hash_buf = call i8* \@malloc(i64 $hash_sz)  ; HashRef: alloc Hash header");
    my $hash = $self->_fresh;
    $self->_emit("  $hash = bitcast i8* $hash_buf to %Hash*  ; HashRef: Hash ptr");
    my $cnt_ptr = $self->_fresh;
    my $cap_ptr = $self->_fresh;
    my $ent_ptr = $self->_fresh;
    $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 0  ; HashRef: count ptr");
    $self->_emit("  $cap_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 1  ; HashRef: cap ptr");
    $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 2  ; HashRef: entries ptr");
    $self->_emit("  store i64 $npairs, i64* $cnt_ptr  ; HashRef: count=$npairs");
    $self->_emit("  store i64 $npairs, i64* $cap_ptr  ; HashRef: cap=$npairs");
    $self->_emit("  store %HashEntry* $ents, %HashEntry** $ent_ptr  ; HashRef: store entries ptr");

    # The canonical ref result is the i8* (Hash* bitcast).
    # BOX ONLY WHEN THE NODE IS A REF -- the twin of the %Array case above.
    # A `HashRef` OPERATION spells both `{a=>1}` (repr=HashRef, boxed i8*) and
    # a plain lexical `my %h = (...)` (repr=Hash, an unboxed %Hash*).
    my $hrepr = $node->stamp // 'HashRef';
    if ($hrepr eq 'Hash') {
        $self->{cache}{ $node->id } = $hash;
        return $hash;
    }

    my $ref = $self->_fresh;
        $self->_emit("  $ref = bitcast %Hash* $hash to i8*  ; HashRef: Hash* -> i8* ref");

    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _lower_length: repr-aware length of an Array or Str operand.
# Array repr: load the len field from the %Array struct (array element count).
# Str repr: load the len field from the %Str struct (byte length).
# Both return i64 (repr=Int).
sub _lower_length {
    my ($self, $node) = @_;

    my $operand = $node->inputs->[0];
    my $op_repr = _require_repr($operand, 'Length.operand');
    $op_repr = 'Array' if $op_repr eq 'List' && _is_walked_list($operand);   # the list made once

    if ($op_repr eq 'Array' || $op_repr eq 'ArrayRef') {
        $self->{_need_aggregate_types} = 1;
        # Typed pointer resolved at THIS use — see _container_ptr.
        my $arr_ref = $self->_container_ptr($operand, 'Array');
        my $len_ptr = $self->_fresh;
        my $len     = $self->_fresh;
        $self->_emit("  $len_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 0  ; Length(Array): len ptr");
        $self->_emit("  $len = load i64, i64* $len_ptr  ; Length(Array): load len");
        $self->{cache}{ $node->id } = $len;
        return $len;
    }
    elsif ($op_repr eq 'Hash' || $op_repr eq 'HashRef') {
        # scalar %h: the key count. The %Hash struct is
        # { i64 count, i64 cap, %HashEntry* entries }, so the count is field 0
        # (parallel to %Array's len). Modern perl's `scalar %h` yields the key
        # count, which is exactly this field.
        $self->{_need_aggregate_types} = 1;
        my $hash_ref = $self->_container_ptr($operand, 'Hash');
        my $cnt_ptr  = $self->_fresh;
        my $cnt      = $self->_fresh;
        $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 0  ; Length(Hash): count ptr");
        $self->_emit("  $cnt = load i64, i64* $cnt_ptr  ; Length(Hash): load key count");
        $self->{cache}{ $node->id } = $cnt;
        return $cnt;
    }
    elsif ($op_repr eq 'Str') {
        # lower_value for Str returns i8* (ptr to NUL-terminated bytes).
        # The length is tracked separately in _str_len_table, keyed by the i8* SSA ref.
        # Emit a compile-time literal via add i64 0, <len>.
        # If the length is not tracked (e.g., a Coerce(Boolean->Str) result), die loudly.
        my ($str_ref, $byte_len) = $self->_str_parts($self->lower_value($operand));
        unless (defined $byte_len) {
            die "Length(Str) — byte length not tracked for operand SSA ref $str_ref. "
              . "Only compile-time-known Str lengths are supported.";
        }
        my $len = $self->_fresh;
        $self->_emit("  $len = add i64 0, $byte_len  ; Length(Str): compile-time byte length");
        $self->{cache}{ $node->id } = $len;
        return $len;
    }
    # A SCALAR's length is its string's -- unless it is undef, where perl's
    # length is undef, which an Int cannot say: that stops the program.
    elsif ($op_repr eq 'Scalar') {
        my $slot = $self->lower_value($operand);
        my $def = $self->_slot_defined_bit($slot);
        my ($no, $yes) = map { $self->_fresh_label("length.$_.") } qw(undef def);
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $def, label %$yes, label %$no");
        $self->_new_block($no);
        $self->_emit("  call void \@exit(i32 255)  ; length of undef is undef, not lowered");
        $self->_set_terminator("  unreachable");
        $self->_new_block($yes);
        my (undef, $l) = $self->_str_parts($self->_emit_coercion($slot, 'Scalar', 'Str', 'Length(Scalar)'));
        return $self->{cache}{ $node->id } = $l;
    }
    else {
        die "GAP: Length operand has repr=$op_repr; only Array and Str are lowered runtime-free.";
    }
}

# _index_i64($node) -> an array index as an i64: perl reads an index as an
# integer. A Scalar is unboxed (a callee's `$_[1]` is one, and boxed it
# reached a GEP as a %Slot), a Num truncated.
sub _index_i64 {
    my ($self, $idx) = @_;
    my $r = $self->_repr_of($idx) // '';
    my $v = $self->lower_value($idx);   # a bound argument as $r reads it
    return $v if $r eq 'Int';
    return $self->_emit_coercion($v, 'Scalar', 'Int', 'array index') if $r eq 'Scalar';
    if ($r eq 'Num' || $r eq 'Boolean') {
        my $i = $self->_fresh;
        $self->_emit("  $i = " . ($r eq 'Num' ? 'fptosi ' . _repr_to_llvm_type('Num') : 'zext i1')
            . " $v to i64  ; array index as an integer");
        return $i;
    }
    die "GAP: an array index with repr=$r is not lowered\n";
}

# _slot_as_reading($slot, $repr, $what) -> an element's %Slot as a read
# stamped $repr reads it: unboxed by its tag (undef reads as perl does), its
# defined bit for an Undef-stamped read, a pointer for a ref, or the Slot.
sub _slot_as_reading {
    my ($self, $slot, $repr, $what) = @_;
    return $self->_emit_coercion($slot, 'Scalar', $repr, $what)
        if $repr =~ /\A(?:Int|Num|Str|Boolean)\z/;
    return $self->_slot_defined_bit($slot) if $repr eq 'Undef';
    if ($repr =~ /\A(?:ArrayRef|HashRef|CodeRef|ScalarRef)\z/) {
        my ($pay, $ptr) = ($self->_slot_payload_of($slot), $self->_fresh);
        $self->_emit("  $ptr = inttoptr i64 $pay to i8*  ; $what :$repr ptr");
        return $ptr;
    }
    return $slot;
}

# _lower_exists($node) -> i1. `exists $h{k}`: is the key there -- a key
# holding undef is (which is what makes it not `defined`). `exists $a[i]`:
# is the index inside the array, counting from the end when negative.
sub _lower_exists {
    my ($self, $node) = @_;
    my ($container, $key) = $node->inputs->@[0, 1];
    my $kind = $node->can('kind') ? ($node->kind // '') : '';
    $self->{_need_aggregate_types} = 1;
    my $res;
    if ($kind eq 'hash') {
        $self->{_need_memcmp} = 1;
        my $hash = $self->_container_ptr($container, 'Hash');
        my ($kp, $kl) = $self->_str_parts($self->_hash_key_str($key));
        defined $kl or die "GAP: exists over a hash key with no tracked length is not lowered\n";
        $res = $self->_emit_hash_has_key($hash, $kp, $kl);
    }
    elsif ($kind eq 'array') {
        my $arr = $self->_container_ptr($container, 'Array');
        my $i   = $self->_index_i64($key);
        my ($lp, $len, $neg, $adj, $idx, $in) = map { $self->_fresh } 1 .. 6;
        $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0");
        $self->_emit("  $len = load i64, i64* $lp  ; exists: len");
        $self->_emit("  $neg = icmp slt i64 $i, 0");
        $self->_emit("  $adj = add i64 $i, $len");
        $self->_emit("  $idx = select i1 $neg, i64 $adj, i64 $i  ; exists: from the end");
        $self->_emit("  $in = icmp ult i64 $idx, $len  ; exists: inside?");
        $res = $in;
    }
    else {
        die "GAP: exists over a $kind is not lowered\n";
    }
    $self->{cache}{ $node->id } = $res;
    return $res;
}


# _lower_local_alias($node): `local *_ = \$a[$i]`, the alias a foreach
# takes of its element when what it calls reads `$_`. `$_` is read through
# a pointer (%ALIASED), so pointing it at the element's slot makes every
# read and write of `$_` -- here or in a callee -- the element's. Saved in
# the loop's preheader, restored in its exit block. An alias outside a loop,
# or of anything but `$_`, is refused.
sub _lower_local_alias {
    my ($self, $node) = @_;
    my $name = $node->name // '';
    die "GAP: a foreach aliasing \$$name (not \$_) is not lowered\n" unless $name eq '_';
    die "GAP: a LocalAlias the module pre-scan did not see is not lowered\n"
        unless $ALIASED{'main::_'};
    my $ctx = ( $self->{_loop_ctx_stack} // [] )->[-1]
        // die "GAP: a LocalAlias outside a loop (no pass to end it) is not lowered\n";
    my $g = $self->_pkg_slot_name('main', '_');
    unless ($ctx->{alias_saves}{_}) {
        my $save = $self->_fresh;
        $self->_emit_entry("  $save = alloca %Slot*, align 8  ; \$_ before a foreach");
        my $o = $self->_fresh;
        my $pre = $self->{blocks}[ $self->_find_block_idx($ctx->{preheader_label}) ];
        push $pre->{insts}->@*, "  $o = load %Slot*, %Slot** ${g}_at  ; \$_ before the loop",
                                "  store %Slot* $o, %Slot** $save";
        $ctx->{alias_saves}{_} = [ $save, $g ];
    }
    # Over a VALUE (`for 1 .. 2`) rather than an element, each pass aliases a
    # fresh scalar holding it, as perl's does.
    my $in  = $node->inputs->[0];
    my $ptr;
    if (($in->stamp // '') =~ /\A(?:ScalarRef|Scalar|Slot)\z/) {
        $ptr = $self->_scalar_ref_target($in);
    }
    else {
        $ptr = $self->_fresh;
        $self->_emit_entry("  $ptr = alloca %Slot, align 8  ; a foreach pass's \$_");
        $self->_emit("  store %Slot " . $self->_slot_of_value($in, $self->lower_value($in), 'foreach value') . ", %Slot* $ptr");
    }
    $self->_emit("  store %Slot* $ptr, %Slot** ${g}_at  ; \$_ is the element");
    $self->{cache}{ $node->id } = '0';
    return '0';
}

# _scan_local_aliases($return) -> names: every LocalAlias reachable from a
# graph, through the callees its calls name.
sub _scan_local_aliases {
    my ($return) = @_;
    my %names = map { ( $_->name // '_' ) => 1 } grep { $_->operation eq 'LocalAlias' } _program_nodes($return);
    return sort keys %names;
}

# _program_nodes($return) -> every node of the program: this graph and the
# graph of every sub it calls.
sub _program_nodes {
    my ($return) = @_;
    my (%seen, @all);
    my @q = ($return);
    while (defined(my $n = shift @q)) {
        next unless blessed($n) && !$seen{ refaddr($n) }++;
        push @all, $n;
        push @q, grep { blessed($_) } $n->inputs->@*, ($n->can('control_in') ? $n->control_in : ()),
            ($n->consumers // [])->@*;
        if ($n->operation eq 'Call' && $n->can('target') && blessed(my $t = $n->target)) {
            push @q, $t->graph->returns->@* if $t->can('graph') && $t->graph;
        }
    }
    return @all;
}

# $READS_ERROR: does the program read $@? A die whose message this backend
# cannot spell (perl's names the file and line) is lowered only where it is
# never seen.
our $READS_ERROR;

# %ANON_SUBS: the AnonSub node of each anonymous sub's name, for a closure
# B::SoN calls directly (its Call names the sub, not the node with its cells).
our %ANON_SUBS;

# @PROGRAM: every node of the program (_program_nodes of its Return).
our @PROGRAM;

# %EVAL_BY_ENTRY: each block eval's join (a Region with eval_entry), by the
# refaddr of its entry -- the node its body follows. An eval in an arm or a
# loop body is opened where that body's first node is lowered.
our %EVAL_BY_ENTRY;

# $SELECTS: does the program select a handle? Then every bare print asks
# which handle is selected (@chalk_selected, null for STDOUT).
our $SELECTS;

# _lower_case_map($node) -> %Str: uc, lc, ucfirst, lcfirst. The operand as
# its string (a number stringifies), mapped by @chalk_case into a fresh
# buffer. ASCII only: a byte past it exits 255, since whether perl maps it
# turns on character semantics the bytes do not carry.
my %_CASE_MODE = (uc => 0, lc => 1, ucfirst => 2, lcfirst => 3);
sub _lower_case_map {
    my ($self, $node) = @_;
    my ($in) = grep { blessed($_) } $node->inputs->@*;
    die "GAP: " . $node->name . " with no operand (\$_) is not lowered\n" unless $in;
    my $from = $in->operation eq 'Print' ? 'Boolean' : ($self->_repr_of($in) // $in->stamp // '');
    my $ref  = $self->lower_value($in);
    $from = 'Scalar' if $from eq 'Slot';
    $ref  = $self->_emit_coercion($ref, $from, 'Str', $node->name . ' operand') unless $from eq 'Str';
    my ($p, $l) = $self->_str_parts($ref);
    $self->{$_} = 1 for qw(_need_case_helper _need_malloc_memcpy _need_exit _need_str_type);
    my $out = $self->_fresh;
    $self->_emit("  $out = call i8* \@chalk_case(i8* $p, i64 $l, i32 $_CASE_MODE{ $node->name })  ; " . $node->name);
    my $res = $self->_set_str_len($out, $l);
    return $self->{cache}{ $node->id } = $res;
}

sub _case_helper_lines {
    my ($self) = @_;
    return () unless $self->{_need_case_helper} && !$self->{_case_helper_emitted}++;
    return ('', <<'END_HELPER');
define internal i8* @chalk_case(i8* %p, i64 %len, i32 %mode) {
entry:
  %n1 = add i64 %len, 1
  %buf = call i8* @malloc(i64 %n1)
  %up = icmp eq i32 %mode, 0
  %ucf = icmp eq i32 %mode, 2
  %toup = or i1 %up, %ucf
  %first = icmp sge i32 %mode, 2
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %store ]
  %more = icmp ult i64 %i, %len
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr inbounds i8, i8* %p, i64 %i
  %c = load i8, i8* %sp
  %hi = icmp slt i8 %c, 0
  br i1 %hi, label %refuse, label %ascii
ascii:
  %isfirst = icmp eq i64 %i, 0
  %skip0 = xor i1 %isfirst, true
  %skip = and i1 %first, %skip0
  %la = sub i8 %c, 97
  %islo = icmp ult i8 %la, 26
  %ua = sub i8 %c, 65
  %isup = icmp ult i8 %ua, 26
  %mkup = and i1 %toup, %islo
  %tolo = xor i1 %toup, true
  %mklo = and i1 %tolo, %isup
  %cu = sub i8 %c, 32
  %cl = add i8 %c, 32
  %m1 = select i1 %mkup, i8 %cu, i8 %c
  %m2 = select i1 %mklo, i8 %cl, i8 %m1
  %m = select i1 %skip, i8 %c, i8 %m2
  br label %store
store:
  %dp = getelementptr inbounds i8, i8* %buf, i64 %i
  store i8 %m, i8* %dp
  %i1 = add i64 %i, 1
  br label %loop
refuse:
  call void @exit(i32 255)
  unreachable
done:
  %ep = getelementptr inbounds i8, i8* %buf, i64 %len
  store i8 0, i8* %ep
  ret i8* %buf
}
END_HELPER
}

# _lower_substr($node) -> %Str: `substr EXPR, OFFSET [, LENGTH]` as a value.
# A copy, NUL-terminated (a number read from it stops at its end), by perl's
# rules: a negative offset counts from the end, a negative length leaves
# that many off the end, a length past the end stops there. Outside the
# string perl answers undef, which a Str cannot hold: refused at run time.
# The four-argument form replaces, and is refused here.
sub _lower_substr {
    my ($self, $node) = @_;
    my @in = grep { blessed($_) } $node->inputs->@*;
    die "GAP: substr with " . scalar(@in) . " arguments (a replacement) is not lowered\n"
        unless @in == 2 || @in == 3;
    my $s    = $in[0];
    my $from = $self->_repr_of($s) // $s->stamp // '';
    $from = 'Scalar' if $from eq 'Slot';
    my $ref  = $self->lower_value($s);
    $ref = $self->_emit_coercion($ref, $from, 'Str', 'substr string') unless $from eq 'Str';
    my ($p, $l) = $self->_str_parts($ref);
    my $off = $self->_index_i64($in[1]);
    my $len = @in == 3 ? $self->_index_i64($in[2]) : '0';
    my $has = @in == 3 ? 'true' : 'false';
    $self->{$_} = 1 for qw(_need_substr_helper _need_malloc_memcpy _need_exit _need_str_type);
    my $lp = $self->_fresh;
    $self->_emit_entry("  $lp = alloca i64, align 8  ; substr length");
    my ($out, $n) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $out = call i8* \@chalk_substr(i8* $p, i64 $l, i64 $off, i64 $len, i1 $has, i64* $lp)  ; substr");
    $self->_emit("  $n = load i64, i64* $lp");
    return $self->{cache}{ $node->id } = $self->_set_str_len($out, $n);
}

sub _substr_helper_lines {
    my ($self) = @_;
    return () unless $self->{_need_substr_helper} && !$self->{_substr_helper_emitted}++;
    return ('', <<'END_HELPER');
define internal i8* @chalk_substr(i8* %p, i64 %slen, i64 %off, i64 %len, i1 %has, i64* %outlen) {
entry:
  %neg = icmp slt i64 %off, 0
  %o1 = add i64 %off, %slen
  %o = select i1 %neg, i64 %o1, i64 %off
  %b1 = icmp slt i64 %o, 0
  %b2 = icmp sgt i64 %o, %slen
  %bad = or i1 %b1, %b2
  br i1 %bad, label %refuse, label %ok
refuse:
  call void @exit(i32 255)
  unreachable
ok:
  %rest = sub i64 %slen, %o
  %lneg = icmp slt i64 %len, 0
  %end = add i64 %slen, %len
  %n1 = sub i64 %end, %o
  %n1neg = icmp slt i64 %n1, 0
  %n1c = select i1 %n1neg, i64 0, i64 %n1
  %over = icmp sgt i64 %len, %rest
  %npos = select i1 %over, i64 %rest, i64 %len
  %nh = select i1 %lneg, i64 %n1c, i64 %npos
  %n = select i1 %has, i64 %nh, i64 %rest
  %n1b = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1b)
  %src = getelementptr inbounds i8, i8* %p, i64 %o
  %c = call i8* @memcpy(i8* %buf, i8* %src, i64 %n)
  %ep = getelementptr inbounds i8, i8* %buf, i64 %n
  store i8 0, i8* %ep
  store i64 %n, i64* %outlen
  ret i8* %buf
}
END_HELPER
}

# _lex_aggregate_ptr($node) -> %Array* | %Hash*: a SHARED file-level `@x` or
# `%x` -- one aggregate every graph reads and writes. It lives behind a
# module global pointer (`@lexa_x` / `@lexh_x`), made empty the first time
# any graph reaches it (@chalk_lex_array / @chalk_lex_hash), so no graph
# needs to have run first.
sub _lex_aggregate_ptr {
    my ($self, $node) = @_;
    my $array = $node->sigil eq '@';
    my $ident = ( $array ? 'lexa_' : 'lexh_' ) . $node->symbol;
    die "GAP: shared lexical global '\@$ident' is not a legal unquoted LLVM identifier (\\w+)\n"
        unless $ident =~ /\A\w+\z/;
    my $ty = $array ? '%Array' : '%Hash';
    $self->{_lex_agg_globals}{"\@$ident"} = $ty;
    $self->{$_} = 1 for qw(_need_lex_agg _need_aggregate_types _need_malloc_memcpy);
    my $p = $self->_fresh;
    $self->_emit("  $p = call $ty* \@chalk_lex_" . ( $array ? 'array' : 'hash' )
        . "($ty** \@$ident)  ; shared " . $node->sigil . $node->symbol);
    return $p;
}

# _lex_aggregate_lines() -> the shared aggregates' globals and their helpers.
sub _lex_aggregate_lines {
    my ($self) = @_;
    return () unless $self->{_need_lex_agg} && !$self->{_lex_agg_emitted}++;
    my %g = %{ $self->{_lex_agg_globals} // {} };
    my @lines = ('', map { "$_ = internal global $g{$_}* null, align 8  ; a shared file-level aggregate" } sort keys %g);
    for my $k (['array', '%Array'], ['hash', '%Hash']) {
        my ($n, $ty) = @$k;
        push @lines, '', <<"END_HELPER";
define internal $ty* \@chalk_lex_$n($ty** %g) {
entry:
  %p = load $ty*, $ty** %g
  %none = icmp eq $ty* %p, null
  br i1 %none, label %make, label %have
make:
  %b = call i8* \@malloc(i64 ptrtoint ($ty* getelementptr ($ty, $ty* null, i64 1) to i64))
  %a = bitcast i8* %b to $ty*
  store $ty zeroinitializer, $ty* %a
  store $ty* %a, $ty** %g
  ret $ty* %a
have:
  ret $ty* %p
}
END_HELPER
    }
    return @lines;
}

# _returns_nothing_in_a_list($node) -> bool: a direct call to a sub that falls
# off its end on `()` -- in a list it is no element at all, whatever undef a
# scalar caller would read.
sub _returns_nothing_in_a_list {
    my ($n) = @_;
    return 0 unless blessed($n) && $n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'direct';
    my $t = $n->can('target') ? $n->target : undef;
    my ($r) = blessed($t) && $t->can('graph') ? $t->graph->returns->@* : ();
    return blessed($r) && $r->can('valueless') && $r->valueless ? 1 : 0;
}

# _emit_flattened_array_of(\@inputs) -> %Array*: a list with an array in it.
# `(0, @a, 3)` is each of @a's elements in its place, not @a as one slot:
# built by appending, an aggregate's elements one by one, a scalar as its
# own Slot. A reference is a scalar. A List that is not an array a builtin
# made, or a hash in a list (its pairs), is refused by name.
sub _emit_flattened_array_of {
    my ($self, $inputs) = @_;
    $self->{$_} = 1 for qw(_need_array_append _need_malloc_memcpy _need_aggregate_types);
    my $acc = $self->_emit_array_of([]);
    for my $in (@$inputs) {
        my $s = $in->stamp // '';
        if (_returns_nothing_in_a_list($in)) {
            $self->lower_value($in);   # its effects, and no element
            next;
        }
        if ($s eq 'Array' || ( $s eq 'List' && $in->operation eq 'Call'
                && ( $in->dispatch_kind // '' ) eq 'builtin'
                && ( $in->name // '' ) =~ /\A(?:sort|keys|values|reverse)\z/ )) {
            my $src = $s eq 'Array' ? $self->_container_ptr($in, 'Array') : $self->lower_value($in);
            $self->_emit("  call void \@chalk_array_append_all(%Array* $acc, %Array* $src)  ; list: flatten");
            next;
        }
        # A SUB'S LIST is what its callee returned: an array flattens, a
        # scalar is one element.
        if ($s eq 'List' && $in->operation eq 'Call' && ( $in->dispatch_kind // '' ) eq 'direct') {
            my $r    = $self->lower_value($in);
            my $from = $self->{_inline_value_repr}{ $in->id } // '';
            if ($from eq 'Array') {
                $self->_emit("  call void \@chalk_array_append_all(%Array* $acc, %Array* $r)  ; list: a sub's array");
                next;
            }
            if ($from =~ /\A(?:Int|Num|Str|Boolean|Scalar|Undef)\z/) {
                my $v = $from eq 'Scalar' ? $r
                      : $from eq 'Undef' ? $self->_build_slot('false', '0', 'Undef', 'list: an undef a sub returned')
                      : $self->_emit_coercion($r, $from, 'Scalar', 'list: a scalar a sub returned');
                $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $v)  ; list: a sub's scalar");
                next;
            }
        }
        # A RANGE OF INTEGERS is its numbers, low to high: none if it runs
        # backwards. One of strings counts by string increment -- refused below.
        # PERL COUNTS NUMBERS only when a bound IS one (pp_flop's
        # RANGE_IS_NUMERIC); two strings count by string increment even when
        # B::SoN coerced both to Int ("aa" .. "ad" counted 0 .. 0 here).
        my $is_number = sub ($b) {
            $b = $b->inputs->[0] while $b->operation eq 'Coerce';
            ( $b->stamp // '' ) =~ /\A(?:Int|Num|Boolean)\z/;
        };
        if ($in->operation eq 'Range'
                && !grep { ( $_->stamp // '' ) ne 'Int' } $in->inputs->@[0, 1]
                and grep { $is_number->($_) } $in->inputs->@[0, 1]) {
            my ($lo, $hi) = map { $self->lower_value($_) } $in->inputs->@[0, 1];
            my ($head, $body, $done) = map { $self->_fresh_label("range.$_.") } qw(head body done);
            my ($i, $more, $i1) = map { $self->_fresh } 1 .. 3;
            my $from = $self->_current_block_label;
            $self->_set_terminator("  br label %$head");
            $self->_new_block($head);
            my $head_idx = $self->{current_idx};
            $self->_emit("  $more = icmp sle i64 $i, $hi  ; range: another?");
            $self->_set_terminator("  br i1 $more, label %$body, label %$done");
            $self->_new_block($body);
            my $v = $self->_emit_coercion($i, 'Int', 'Scalar', 'range element');
            $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $v)  ; list: a range's number");
            $self->_emit("  $i1 = add i64 $i, 1");
            my $back = $self->_current_block_label;
            $self->_set_terminator("  br label %$head");
            unshift $self->{blocks}[$head_idx]{insts}->@*,
                "  $i = phi i64 [ $lo, %$from ], [ $i1, %$back ]  ; range: the number";
            $self->_new_block($done);
            next;
        }
        if ($in->operation eq 'Call' && ( $in->dispatch_kind // '' ) eq 'builtin'
                && ( $in->name // '' ) eq 'readline') {
            # lowered once, where it stands: read again here it would be empty
            my $lines = $self->lower_value($in);
            $self->_emit("  call void \@chalk_array_append_all(%Array* $acc, %Array* $lines)  ; list: the lines read");
            next;
        }
        if (_is_hash_slice($in)) {
            $self->_emit_hash_slice_into($acc, $in);
            next;
        }
        if (_is_array_slice($in)) {
            $self->_emit_array_slice_into($acc, $in);
            next;
        }
        if ($in->operation eq 'Ref' && $in->each) {
            $self->_emit_each_element_ref_into($acc, $in);
            next;
        }
        # A HASH IN A LIST is its pairs, key then value, in its entries' order
        # (pvm 176: `{ %$c, $n => 1 }`).
        if ($s eq 'Hash') {
            my $h = $self->_container_ptr($in, 'Hash');
            my ($cp, $cnt, $ep, $ents, $ip) = map { $self->_fresh } 1 .. 5;
            $self->_emit("  $cp = getelementptr inbounds %Hash, %Hash* $h, i32 0, i32 0");
            $self->_emit("  $cnt = load i64, i64* $cp  ; list: a hash's pairs");
            $self->_emit("  $ep = getelementptr inbounds %Hash, %Hash* $h, i32 0, i32 2");
            $self->_emit("  $ents = load %HashEntry*, %HashEntry** $ep");
            $self->_emit_entry("  $ip = alloca i64  ; list: a hash's entry index");
            $self->_emit("  store i64 0, i64* $ip");
            my ($head, $body, $done) = map { $self->_fresh_label("hflat.$_.") } qw(head body done);
            $self->_set_terminator("  br label %$head");
            $self->_new_block($head);
            my ($i, $more) = ($self->_fresh, $self->_fresh);
            $self->_emit("  $i = load i64, i64* $ip");
            $self->_emit("  $more = icmp ult i64 $i, $cnt");
            $self->_set_terminator("  br i1 $more, label %$body, label %$done");
            $self->_new_block($body);
            my $e = $self->_fresh;
            $self->_emit("  $e = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i");
            my %f;
            for my $name (qw(key_ptr key_len val_def val_tag val_pay)) {
                my ($g, $v) = ($self->_fresh, $self->_fresh);
                my $ty = { key_ptr => 'i8*', key_len => 'i64', val_def => 'i1', val_tag => 'i8', val_pay => 'i64' }->{$name};
                $self->_emit("  $g = getelementptr inbounds %HashEntry, %HashEntry* $e, i32 0, i32 " . _he_idx($name));
                $self->_emit("  $v = load $ty, $ty* $g  ; list: the entry's $name");
                $f{$name} = $v;
            }
            my $k = $self->_emit_coercion($self->_set_str_len($f{key_ptr}, $f{key_len}), 'Str', 'Scalar', 'list: a key');
            $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $k)  ; list: the key");
            my ($s0, $s1, $s2, $i1) = map { $self->_fresh } 1 .. 4;
            $self->_emit("  $s0 = insertvalue %Slot undef, i1 $f{val_def}, " . _slot_idx('defined'));
            $self->_emit("  $s1 = insertvalue %Slot $s0, i8 $f{val_tag}, " . _slot_idx('tag'));
            $self->_emit("  $s2 = insertvalue %Slot $s1, i64 $f{val_pay}, " . _slot_idx('payload'));
            $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $s2)  ; list: its value");
            $self->_emit("  $i1 = add i64 $i, 1");
            $self->_emit("  store i64 $i1, i64* $ip");
            $self->_set_terminator("  br label %$head");
            $self->_new_block($done);
            next;
        }
        die "GAP: a list with a $s in it is not lowered -- it would flatten, and "
          . "only an array does here\n" if $s eq 'List';
        my $v = $self->_slot_of_value($in, $self->lower_value($in), 'list element');
        $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $v)  ; list: one element");
    }
    return $acc;
}

# _emit_each_element_ref_into($acc, $ref): `\(@a)` pushes a reference to
# each element of the array -- its slot in the buffer, as `\$a[$i]` is --
# refused, as that is, for an array anything grows: a grown buffer is a new one.
sub _emit_each_element_ref_into {
    my ($self, $acc, $ref) = @_;
    my $x = $ref->inputs->[0];
    die "GAP: \\(...) of a " . ( blessed($x) ? $x->operation : 'nothing' )
      . " is not lowered -- only of an array\n"
        unless blessed($x) && ( $self->_repr_of($x) // '' ) eq 'Array';
    die "GAP: a reference to an element of an array that may grow is not lowered\n"
        if _array_may_grow($x);
    my $arr = $self->_container_ptr($x, 'Array');
    my ($lp, $len, $ep, $el) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; \\(\@a): len ptr");
    $self->_emit("  $len = load i64, i64* $lp");
    $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2");
    $self->_emit("  $el = load %Slot*, %Slot** $ep  ; \\(\@a): the elements");
    my ($head, $body, $done) = map { $self->_fresh_label("eachref.$_.") } qw(head body done);
    my ($k, $more, $k1, $p, $pi) = map { $self->_fresh } 1 .. 5;
    my $from = $self->_current_block_label;
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    $self->_emit("  $k = phi i64 [ 0, %$from ], [ $k1, %$body ]  ; \\(\@a): which element");
    $self->_emit("  $more = icmp slt i64 $k, $len");
    $self->_set_terminator("  br i1 $more, label %$body, label %$done");
    $self->_new_block($body);
    $self->_emit("  $p = getelementptr inbounds %Slot, %Slot* $el, i64 $k  ; \\(\@a): its slot");
    $self->_emit("  $pi = ptrtoint %Slot* $p to i64");
    my $v = $self->_build_slot('true', $pi, 'ScalarRef', '\\(@a) element');
    $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $v)  ; list: a reference to an element");
    $self->_emit("  $k1 = add i64 $k, 1");
    $self->_set_terminator("  br label %$head");
    $self->_new_block($done);
    return;
}

# IN-MEMORY HANDLES. `open(my $fh, "<", \"one\ntwo\n")` reads the string as
# a file; `open(my $out, ">", \my $buf)` writes into $buf. The handle is
# { i8* data, i64 len, i64 pos, i8* target } (malloc'd): what a read handle
# reads, or the %Slot a write handle appends to (null on a read handle). The
# variable holding it is an entry-block i8* cell, null until an open and
# again after a close -- so a read of an unopened or closed handle is undef,
# and a print to one writes nothing, as perl's do. Only a constant string is
# read and only a scalar variable written; a file on disk, or any other
# target, is refused by name.
my $HANDLE = '{ i8*, i64, i64, i8* }';

# _handle_cell($fh) -> the i8** cell the handle variable lives in.
sub _handle_cell {
    my ($self, $fh) = @_;
    # DATA reads the text after __DATA__ / __END__: a read handle open on it
    # from the start, one for the program (pvm 363, 364).
    if (blessed($fh) && $fh->operation eq 'Constant' && ( $fh->const_type // '' ) eq 'glob'
            && ( $fh->value // '' ) =~ /\A(?:main::)?DATA\z/) {
        my $text = $Chalk::IR::Serialize::JSON::DATA_SECTION;
        die "GAP: DATA in a program with no __DATA__ or __END__ section is not lowered\n"
            unless defined $text;
        die "GAP: DATA read in a method body is not lowered -- the program has one DATA\n"
            if defined $self->{_method_self_name};
        return $self->{_handle_cells}{'|DATA'} //= do {
            $self->{_need_malloc_memcpy} = 1;
            my ($p, $l) = $self->_str_const_parts($text, 'DATA: the section');
            my ($c, $h, $t, @f) = map { $self->_fresh } 1 .. 7;
            $self->_emit_entry("  $c = alloca i8*  ; handle DATA");
            $self->_emit_entry("  $h = call i8* \@malloc(i64 32)  ; DATA: a handle on the section");
            $self->_emit_entry("  $t = bitcast i8* $h to $HANDLE*");
            $self->_emit_entry("  $f[$_] = getelementptr inbounds $HANDLE, $HANDLE* $t, i32 0, i32 $_") for 0 .. 3;
            $self->_emit_entry("  store i8* $p, i8** $f[0]");
            $self->_emit_entry("  store i64 $l, i64* $f[1]");
            $self->_emit_entry("  store i64 0, i64* $f[2]");
            $self->_emit_entry("  store i8* null, i8** $f[3]");
            $self->_emit_entry("  store i8* $h, i8** $c");
            $c;
        };
    }
    die "GAP: a filehandle that is not a lexical `my \$fh` is not lowered\n"
        unless blessed($fh) && $fh->operation eq 'PadAccess' && ( $fh->stamp // '' ) eq 'GlobRef';
    # ONE PER SUB: inlined subs share this function, and each sub's `my $fh`
    # is its own. The subs being inlined name the one this is (recursion is
    # refused, so the set is the stack).
    my $key = join(',', sort keys %{ $self->{_inlining} // {} }) . '|' . ( $fh->targ // '' ) . $fh->name;
    return $self->{_handle_cells}{$key} //= do {
        my $c = $self->_fresh;
        $self->_emit_entry("  $c = alloca i8*  ; handle " . $fh->name);
        $self->_emit_entry("  store i8* null, i8** $c");
        $c;
    };
}

# _handle_field($h, $i) -> a pointer to field $i (0 data, 1 len, 2 pos, 3 target).
sub _handle_field {
    my ($self, $h, $i) = @_;
    my ($t, $f) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $t = bitcast i8* $h to $HANDLE*");
    $self->_emit("  $f = getelementptr inbounds $HANDLE, $HANDLE* $t, i32 0, i32 $i");
    return $f;
}

sub _lower_handle_op {
    my ($self, $node) = @_;
    my $name = $node->name;
    my @in   = grep { blessed($_) } $node->inputs->@*;
    pop @in if $node->can('memory_input') && $node->memory_input;
    my $cell = $self->_handle_cell($in[0]);
    if ($name eq 'open') {
        die "GAP: open with " . scalar(@in) . " arguments is not lowered -- only open(\$fh, MODE, \\\"...\")\n"
            unless @in == 3;
        my ($mode, $to) = @in[1, 2];
        my $m = $mode->operation eq 'Constant' ? ( $mode->value // '' ) : '';
        die "GAP: open in a mode other than \"<\", \">\" or \">>\" (or one known only at run time) is not lowered\n"
            unless $m =~ /\A(?:<|>|>>)\z/;
        my ($p, $l, $target) = ('null', 0, 'null');
        if ($m eq '<') {
            die "GAP: open of a file (or of anything but a reference to a string) is not lowered\n"
                unless $to->operation eq 'Constant' && ( $to->const_type // '' ) eq 'ref';
            ($p, $l) = $self->_str_const_parts($to->value, 'open: the string read');
        }
        else {
            my $var = $to->operation eq 'Ref' ? $to->inputs->[0] : undef;
            die "GAP: open for writing to a file (or to anything but a scalar variable) is not lowered\n"
                unless blessed($var) && $var->operation eq 'PadAccess' && ( $var->sigil // '' ) eq '$'
                && $var->is_location;
            my $slot = $self->_location_ptr($var);
            if ($m eq '>') {
                my $empty = $self->_emit_coercion($self->_str_value(( $self->_str_const_parts('', 'open: emptied') )[0], len => 0),
                    'Str', 'Scalar', 'open ">": empty');
                $self->_emit("  store %Slot $empty, %Slot* $slot  ; open \">\": the scalar is emptied");
            }
            $target = $self->_fresh;
            $self->_emit("  $target = bitcast %Slot* $slot to i8*  ; open: the scalar written");
        }
        $self->{_need_malloc_memcpy} = 1;
        my $h = $self->_fresh;
        $self->_emit("  $h = call i8* \@malloc(i64 32)  ; open: a handle in memory");
        $self->_emit("  store i8* $p, i8** " . $self->_handle_field($h, 0));
        $self->_emit("  store i64 $l, i64* " . $self->_handle_field($h, 1));
        $self->_emit("  store i64 0, i64* " . $self->_handle_field($h, 2));
        $self->_emit("  store i8* $target, i8** " . $self->_handle_field($h, 3));
        $self->_emit("  store i8* $h, i8** $cell  ; open: the handle");
        return $self->{cache}{ $node->id } = $self->_build_slot('true', '1', 'Int', 'open: true');
    }
    my $h = $self->_fresh;
    $self->_emit("  $h = load i8*, i8** $cell  ; $name: the handle");
    if ($name eq 'close') {
        # THE HANDLE ITSELF IS CLOSED, not only the variable: select may hold
        # it. Nothing left to read, nowhere to write.
        my $was = $self->_fresh;
        my ($shut, $done) = map { $self->_fresh_label("close.$_.") } qw(shut done);
        $self->_emit("  $was = icmp ne i8* $h, null  ; close: was it open?");
        $self->_set_terminator("  br i1 $was, label %$shut, label %$done");
        $self->_new_block($shut);
        $self->_emit("  store i64 0, i64* " . $self->_handle_field($h, 1) . "  ; close: nothing to read");
        $self->_emit("  store i8* null, i8** " . $self->_handle_field($h, 3) . "  ; close: nowhere to write");
        $self->_set_terminator("  br label %$done");
        $self->_new_block($done);
        $self->_emit("  store i8* null, i8** $cell  ; close");
        return $self->{cache}{ $node->id } = $was;
    }
    if ($name eq 'eof') {
        my ($open, $pos, $len, $at, $r) = map { $self->_fresh } 1 .. 5;
        my ($chk, $join) = map { $self->_fresh_label("eof.$_.") } qw(chk join);
        my $from = $self->_current_block_label;
        $self->_emit("  $open = icmp ne i8* $h, null");
        $self->_set_terminator("  br i1 $open, label %$chk, label %$join");
        $self->_new_block($chk);
        $self->_emit("  $pos = load i64, i64* " . $self->_handle_field($h, 2));
        $self->_emit("  $len = load i64, i64* " . $self->_handle_field($h, 1));
        $self->_emit("  $at = icmp sge i64 $pos, $len  ; eof: read it all?");
        my $chk_end = $self->_current_block_label;
        $self->_set_terminator("  br label %$join");
        $self->_new_block($join);
        $self->_emit("  $r = phi i1 [ 1, %$from ], [ $at, %$chk_end ]");
        return $r;
    }
    # readline in a list: every line left, as an array.
    if (( $node->stamp // '' ) =~ /\A(?:List|Array)\z/) {
        $self->{$_} = 1 for qw(_need_array_append _need_malloc_memcpy _need_aggregate_types);
        my $acc = $self->_emit_array_of([]);
        $self->_emit_lines_left_into($acc, $cell);
        return $self->{cache}{ $node->id } = $acc;
    }
    # In scalar context: the next line, or undef.
    die "GAP: readline whose result is a " . ( $node->stamp // 'Unknown' ) . " is not lowered\n"
        unless ( $node->stamp // '' ) eq 'Scalar';
    my ($slot) = $self->_emit_next_line($h);
    return $self->{cache}{ $node->id } = $slot;
}

# _emit_next_line($h) -> ($slot, $got_i1): the handle's next line -- up to
# and including a "\n", or the rest -- as a Str slot, and its position moved
# past it; undef (and false) when it is closed or read to the end.
sub _emit_next_line {
    my ($self, $h) = @_;
    $self->{_need_memchr} = 1;
    my ($open, $pos, $len, $more, $data, $rest, $rl, $nl, $found, $ni, $ri, $off, $off1, $ll, $np) = map { $self->_fresh } 1 .. 15;
    my ($chk, $read, $none, $join) = map { $self->_fresh_label("readline.$_.") } qw(chk read none join);
    $self->_emit("  $open = icmp ne i8* $h, null  ; readline: open?");
    $self->_set_terminator("  br i1 $open, label %$chk, label %$none");
    $self->_new_block($chk);
    my ($pp, $lp, $dp) = map { $self->_handle_field($h, $_) } 2, 1, 0;
    $self->_emit("  $pos = load i64, i64* $pp");
    $self->_emit("  $len = load i64, i64* $lp");
    $self->_emit("  $more = icmp slt i64 $pos, $len  ; readline: any left?");
    $self->_set_terminator("  br i1 $more, label %$read, label %$none");
    $self->_new_block($read);
    $self->_emit("  $data = load i8*, i8** $dp");
    $self->_emit("  $rest = getelementptr inbounds i8, i8* $data, i64 $pos");
    $self->_emit("  $rl = sub i64 $len, $pos");
    $self->_emit("  $nl = call i8* \@memchr(i8* $rest, i32 10, i64 $rl)  ; readline: the next newline");
    $self->_emit("  $found = icmp ne i8* $nl, null");
    $self->_emit("  $ni = ptrtoint i8* $nl to i64");
    $self->_emit("  $ri = ptrtoint i8* $rest to i64");
    $self->_emit("  $off = sub i64 $ni, $ri");
    $self->_emit("  $off1 = add i64 $off, 1");
    $self->_emit("  $ll = select i1 $found, i64 $off1, i64 $rl  ; readline: the line's length");
    $self->_emit("  $np = add i64 $pos, $ll");
    $self->_emit("  store i64 $np, i64* $pp  ; readline: past it");
    my $line = $self->_emit_coercion($self->_str_value($rest, len => $ll), 'Str', 'Scalar', 'readline: the line');
    my $read_end = $self->_current_block_label;
    $self->_set_terminator("  br label %$join");
    $self->_new_block($none);
    my $undef = $self->_build_slot('false', '0', 'Undef', 'readline: no more');
    my $none_end = $self->_current_block_label;
    $self->_set_terminator("  br label %$join");
    $self->_new_block($join);
    my ($slot, $got) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $slot = phi %Slot [ $line, %$read_end ], [ $undef, %$none_end ]  ; readline: the line, or undef");
    $self->_emit("  $got = phi i1 [ 1, %$read_end ], [ 0, %$none_end ]");
    return ($slot, $got);
}

# _emit_lines_left_into($acc, $cell): every line left on the handle in
# $cell, in order.
sub _emit_lines_left_into {
    my ($self, $acc, $cell) = @_;
    my ($head, $body, $done) = map { $self->_fresh_label("readlines.$_.") } qw(head body done);
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    my $h = $self->_fresh;
    $self->_emit("  $h = load i8*, i8** $cell  ; readline: the handle");
    my ($slot, $got) = $self->_emit_next_line($h);
    $self->_set_terminator("  br i1 $got, label %$body, label %$done");
    $self->_new_block($body);
    $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $slot)  ; list: a line");
    $self->_set_terminator("  br label %$head");
    $self->_new_block($done);
    return;
}

# _lower_reverse($node): in a list, its arguments flattened and backwards
# (an %Array*); in scalar context (stamp Str), its arguments joined with
# nothing and that string reversed. perl reverses characters: a byte past
# ASCII stops the program (exit 255) rather than split one.
sub _lower_reverse {
    my ($self, $node) = @_;
    my @in = grep { blessed($_) } $node->inputs->@*;
    pop @in if $node->can('memory_input') && $node->memory_input;
    # None in a list is an empty list; none in scalar context reverses $_.
    die "GAP: scalar reverse with no arguments (of \$_) is not lowered\n"
        unless @in || ( $node->stamp // '' ) ne 'Str';
    $self->{$_} = 1 for qw(_need_array_append _need_malloc_memcpy _need_aggregate_types);
    my $src = $self->_emit_flattened_array_of(\@in);
    my ($lp, $len, $ep, $el) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $src, i32 0, i32 0  ; reverse: len ptr");
    $self->_emit("  $len = load i64, i64* $lp");
    if (( $node->stamp // '' ) eq 'Str') {
        my $str = $self->_emit_join_loop(undef, $self->_empty_str_ref('reverse: no separator'), $src);
        my ($p, $l) = $self->_str_parts($str);
        my ($buf, $nul, $i, $more, $j, $from_p, $c, $hi, $to_p, $i1) = map { $self->_fresh } 1 .. 10;
        my ($head, $body, $ok, $bad, $done) = map { $self->_fresh_label("strrev.$_.") } qw(head body ok bad done);
        my $l1 = $self->_fresh;
        $self->_emit("  $l1 = add i64 $l, 1");
        $self->_emit("  $buf = call i8* \@malloc(i64 $l1)  ; reverse: the string backwards");
        $self->_emit("  $nul = getelementptr inbounds i8, i8* $buf, i64 $l");
        $self->_emit("  store i8 0, i8* $nul");
        my $from = $self->_current_block_label;
        $self->_set_terminator("  br label %$head");
        $self->_new_block($head);
        my $head_idx = $self->{current_idx};
        $self->_emit("  $more = icmp slt i64 $i, $l");
        $self->_set_terminator("  br i1 $more, label %$body, label %$done");
        $self->_new_block($body);
        $self->_emit("  $from_p = getelementptr inbounds i8, i8* $p, i64 $i");
        $self->_emit("  $c = load i8, i8* $from_p");
        $self->_emit("  $hi = icmp slt i8 $c, 0  ; reverse: a byte past ASCII?");
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $hi, label %$bad, label %$ok");
        $self->_new_block($bad);
        $self->_emit("  call void \@exit(i32 255)  ; reverse of a string past ASCII is not lowered");
        $self->_set_terminator("  unreachable");
        $self->_new_block($ok);
        my $jj = $self->_fresh;
        $self->_emit("  $j = sub i64 $l, $i");
        $self->_emit("  $jj = sub i64 $j, 1");
        $self->_emit("  $to_p = getelementptr inbounds i8, i8* $buf, i64 $jj");
        $self->_emit("  store i8 $c, i8* $to_p");
        $self->_emit("  $i1 = add i64 $i, 1");
        $self->_set_terminator("  br label %$head");
        unshift $self->{blocks}[$head_idx]{insts}->@*, "  $i = phi i64 [ 0, %$from ], [ $i1, %$ok ]  ; reverse: which byte";
        $self->_new_block($done);
        return $self->{cache}{ $node->id } = $self->_set_str_len($buf, $l);
    }
    die "GAP: reverse whose result is a " . ( $node->stamp // 'Unknown' ) . " is not lowered\n"
        unless ( $node->stamp // '' ) =~ /\A(?:List|Array)\z/;
    $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $src, i32 0, i32 2");
    $self->_emit("  $el = load %Slot*, %Slot** $ep  ; reverse: the elements");
    my $acc = $self->_emit_array_of([]);
    my ($head, $body, $done) = map { $self->_fresh_label("reverse.$_.") } qw(head body done);
    my ($k, $more, $k1, $sp, $sv) = map { $self->_fresh } 1 .. 5;
    my $from = $self->_current_block_label;
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    $self->_emit("  $k = phi i64 [ $len, %$from ], [ $k1, %$body ]  ; reverse: past the next one");
    $self->_emit("  $more = icmp sgt i64 $k, 0");
    $self->_set_terminator("  br i1 $more, label %$body, label %$done");
    $self->_new_block($body);
    $self->_emit("  $k1 = sub i64 $k, 1");
    $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $el, i64 $k1");
    $self->_emit("  $sv = load %Slot, %Slot* $sp");
    $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $sv)  ; reverse: from the end");
    $self->_set_terminator("  br label %$head");
    $self->_new_block($done);
    return $self->{cache}{ $node->id } = $acc;
}

# _lower_sprintf($node) -> %Str: a CONSTANT format, read here: each literal
# run as it is, each conversion rendered by C's snprintf with a format of its
# own -- %d %i %u %x %X %o as 64-bit integers, %f %F %e %E %g %G as doubles,
# %s by its length -- flags, widths and precisions (a `*` taken from the
# arguments) as written. perl's conversions agree with C's for these. Any
# other (%v, %c, %n$, a format known only at run time) is refused by name.
sub _lower_sprintf {
    my ($self, $node) = @_;
    my ($fmt, @args) = grep { blessed($_) } $node->inputs->@*;
    pop @args if $node->can('memory_input') && $node->memory_input;
    die "GAP: sprintf whose format is not a constant string is not lowered\n"
        unless blessed($fmt) && $fmt->operation eq 'Constant' && ( $fmt->const_type // '' ) eq 'string';
    die "GAP: sprintf of a list that flattens is not lowered\n"
        if grep { ( $_->stamp // '' ) =~ /\A(?:Array|List|Hash)\z/ } @args;
    my $text = $fmt->value // '';
    $self->{$_} = 1 for qw(_need_snprintf _need_malloc_memcpy);
    my $acc = $self->_empty_str_ref('sprintf: so far');
    my $append = sub ($str) { $acc = $self->_emit_str_append($acc, $str, 'sprintf') };
    my $literal = sub ($t) {
        return unless length $t;
        $append->($self->_set_str_len($self->_str_const_parts($t, 'sprintf: literal')));
    };
    my $take = sub ($what) {
        die "GAP: sprintf with too few arguments for its format is not lowered\n" unless @args;
        return shift @args;
    };
    my $as = sub ($arg, $to) {
        my $from = $arg->operation eq 'Print' ? 'Boolean' : ( $self->_repr_of($arg) // $arg->stamp // '' );
        my $v = $self->lower_value($arg);
        return $from eq $to ? $v : $self->_emit_coercion($v, $from, $to, "sprintf %-arg");
    };
    my $i32 = sub ($arg) {
        my $v = $as->($arg, 'Int');
        my $t = $self->_fresh;
        $self->_emit("  $t = trunc i64 $v to i32  ; sprintf: a * argument");
        return "i32 $t";
    };
    pos($text) = 0;
    while (pos($text) < length $text) {
        if ($text =~ /\G([^%]+)/gc) { $literal->($1); next }
        if ($text =~ /\G%%/gc)     { $literal->('%'); next }
        $text =~ /\G%([-+ 0#]*)(\*|\d+)?(?:\.(\*|\d*))?([sdiuxXofFeEgG])/gc
            or die "GAP: sprintf conversion '" . substr($text, pos($text), 6) . "' is not lowered\n";
        my ($flags, $w, $p, $conv) = ($1, $2, $3, $4);
        my @va;
        push @va, $i32->($take->('width')) if defined $w && $w eq '*';
        push @va, $i32->($take->('precision')) if defined $p && $p eq '*';
        my $arg = $take->('value');
        my $cfmt = '%' . $flags . ( $w // '' );
        if ($conv eq 's') {
            my ($sp, $sl) = $self->_str_parts($as->($arg, 'Str'));
            # A STRING BY ITS LENGTH: it need not end in a NUL. A precision
            # given shortens it, never lengthens it.
            my $l32 = $self->_fresh;
            $self->_emit("  $l32 = trunc i64 $sl to i32  ; sprintf %s: its length");
            my $lim = $l32;
            if (defined $p && $p ne '*') {
                my ($lt, $m) = map { $self->_fresh } 1 .. 2;
                my $pn = 0 + ( $p eq '' ? 0 : $p );
                $self->_emit("  $lt = icmp slt i32 $pn, $l32");
                $self->_emit("  $m = select i1 $lt, i32 $pn, i32 $l32");
                $lim = $m;
            }
            elsif (defined $p) {   # .* -- the argument taken above, capped at the length
                my $given = pop(@va) =~ s/\Ai32 //r;
                my ($lt, $m) = map { $self->_fresh } 1 .. 2;
                $self->_emit("  $lt = icmp slt i32 $given, $l32");
                $self->_emit("  $m = select i1 $lt, i32 $given, i32 $l32");
                $lim = $m;
            }
            $cfmt .= '.*s';
            push @va, "i32 $lim", "i8* $sp";
        }
        else {
            $cfmt .= '.' . $p if defined $p;
            if ($conv =~ /[diuxXo]/) {
                $cfmt .= 'll' . $conv;
                push @va, 'i64 ' . $as->($arg, 'Int');
            }
            else {
                $cfmt .= $conv;
                push @va, _repr_to_llvm_type('Num') . ' ' . $as->($arg, 'Num');
            }
        }
        my ($fp) = $self->_str_const_parts($cfmt, 'sprintf: a conversion');
        my $vargs = join(', ', @va);
        my ($need, $n64, $size, $buf, $wrote) = map { $self->_fresh } 1 .. 5;
        $self->_emit("  $need = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* null, i64 0, i8* $fp, $vargs)  ; sprintf: measure");
        $self->_emit("  $n64 = sext i32 $need to i64");
        $self->_emit("  $size = add i64 $n64, 1");
        $self->_emit("  $buf = call i8* \@malloc(i64 $size)");
        $self->_emit("  $wrote = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* $buf, i64 $size, i8* $fp, $vargs)  ; sprintf: render");
        $append->($self->_set_str_len($buf, $n64));
    }
    die "GAP: sprintf with arguments its format does not use is not lowered\n" if @args;
    return $self->{cache}{ $node->id } = $acc;
}

# _lower_formline($node) -> %Slot: a picture line of the format a `write`
# runs, filled from its values and printed to STDOUT. Text fields @<<< @>>>
# @||| take the value up to its first newline, cut or padded to the width;
# number fields @##.## render it as %W.Df ('#'s when it does not fit); the
# rest of the picture is literal; each line's trailing spaces are chopped.
# ^ fields, ~ and ~~, @*, a picture known at run time, a number field over a
# value that may be undef, and formline outside a format are refused.
sub _lower_formline {
    my ($self, $node) = @_;
    die "GAP: formline outside a format's write is not lowered -- it appends to \$^A\n"
        unless $self->{_in_format};
    die "GAP: write while the program selects a handle is not lowered\n" if $SELECTS;
    my ($pic, @args) = grep { blessed($_) } $node->inputs->@*;
    pop @args if $node->can('memory_input') && $node->memory_input;
    die "GAP: a format picture known only at run time is not lowered\n"
        unless blessed($pic) && $pic->operation eq 'Constant' && ( $pic->const_type // '' ) eq 'string';
    my $text = $pic->value // '';
    die "GAP: a format with a ^ field, ~ or \@* is not lowered\n" if $text =~ /[\^~]|\@\*/;
    $self->{$_} = 1 for qw(_need_snprintf _need_malloc_memcpy _need_memchr _need_print_str_fmt);
    my $take = sub {
        die "GAP: a format line with too few values for its fields is not lowered\n" unless @args;
        return shift @args;
    };
    my $render = sub ($cfmt, $vargs) {
        my ($fp) = $self->_str_const_parts($cfmt, 'format: a field');
        my ($need, $n64, $size, $buf, $wrote) = map { $self->_fresh } 1 .. 5;
        $self->_emit("  $need = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* null, i64 0, i8* $fp, $vargs)  ; format: measure");
        $self->_emit("  $n64 = sext i32 $need to i64");
        $self->_emit("  $size = add i64 $n64, 1");
        $self->_emit("  $buf = call i8* \@malloc(i64 $size)");
        $self->_emit("  $wrote = call i32 (i8*, i64, i8*, ...) \@snprintf(i8* $buf, i64 $size, i8* $fp, $vargs)  ; format: render");
        return ($buf, $n64);
    };
    my $i32 = sub ($v) {
        my $t = $self->_fresh;
        $self->_emit("  $t = trunc i64 $v to i32");
        return $t;
    };
    my ($nothing) = $self->_str_const_parts('', 'format: no padding');
    for my $line ($text =~ /([^\n]*\n?)/g) {
        next unless length $line;
        my $nl = $line =~ s/\n\z//;
        my $acc = $self->_empty_str_ref('format: the line');
        my $append = sub ($s) { $acc = $self->_emit_str_append($acc, $s, 'format') };
        pos($line) = 0;
        while (pos($line) < length $line) {
            if ($line =~ /\G([^\@]+)/gc) {
                $append->($self->_set_str_len($self->_str_const_parts($1, 'format: literal')));
                next;
            }
            $line =~ /\G\@(<+|>+|\|+|#+(?:\.#+)?|\.#+)?/gc;
            my $spec = $1 // '';
            my $w = 1 + length $spec;
            my $arg = $take->();
            my $from = $arg->operation eq 'Print' ? 'Boolean' : ( $self->_repr_of($arg) // $arg->stamp // '' );
            if ($spec =~ /#/) {
                my $d = $spec =~ /\.(#+)\z/ ? length $1 : 0;
                die "GAP: a number field over a $from value, which may be undef, is not lowered\n"
                    unless $from =~ /\A(?:Int|Num)\z/;
                my $v = $self->lower_value($arg);
                $v = $self->_emit_coercion($v, $from, 'Num', 'format: a number') if $from ne 'Num';
                my ($buf, $n) = $render->('%*.*f', "i32 $w, i32 $d, " . _repr_to_llvm_type('Num') . " $v");
                # TOO WIDE FOR THE FIELD: perl fills it with '#'s.
                my ($hp) = $self->_str_const_parts('#' x $w, 'format: a number too wide');
                my ($over, $p, $l) = map { $self->_fresh } 1 .. 3;
                $self->_emit("  $over = icmp sgt i64 $n, $w");
                $self->_emit("  $p = select i1 $over, i8* $hp, i8* $buf");
                $self->_emit("  $l = select i1 $over, i64 $w, i64 $n");
                $append->($self->_set_str_len($p, $l));
                next;
            }
            my $v = $self->lower_value($arg);
            $v = $self->_emit_coercion($v, $from, 'Str', 'format: a text field') if $from ne 'Str';
            my ($sp, $sl) = $self->_str_parts($v);
            # Up to the value's first newline, cut to the width.
            my ($nlp, $none, $pi, $si, $at, $cut, $lt, $n, $pad, $lp, $rp) = map { $self->_fresh } 1 .. 11;
            $self->_emit("  $nlp = call i8* \@memchr(i8* $sp, i32 10, i64 $sl)  ; format: a newline ends the value");
            $self->_emit("  $none = icmp eq i8* $nlp, null");
            $self->_emit("  $pi = ptrtoint i8* $nlp to i64");
            $self->_emit("  $si = ptrtoint i8* $sp to i64");
            $self->_emit("  $at = sub i64 $pi, $si");
            $self->_emit("  $cut = select i1 $none, i64 $sl, i64 $at");
            $self->_emit("  $lt = icmp slt i64 $cut, $w");
            $self->_emit("  $n = select i1 $lt, i64 $cut, i64 $w");
            $self->_emit("  $pad = sub i64 $w, $n");
            if    ($spec =~ /\A</ || $spec eq '') { $self->_emit("  $lp = add i64 0, 0");          $self->_emit("  $rp = add i64 $pad, 0") }
            elsif ($spec =~ /\A>/)                 { $self->_emit("  $lp = add i64 $pad, 0");       $self->_emit("  $rp = add i64 0, 0") }
            else                                   { $self->_emit("  $lp = udiv i64 $pad, 2");      $self->_emit("  $rp = sub i64 $pad, $lp") }
            my ($l32, $n32, $r32) = map { $i32->($_) } $lp, $n, $rp;
            $append->($self->_set_str_len($render->('%*s%.*s%*s',
                "i32 $l32, i8* $nothing, i32 $n32, i8* $sp, i32 $r32, i8* $nothing")));
        }
        # THE LINE'S TRAILING SPACES are chopped.
        my ($ap, $al) = $self->_str_parts($acc);
        my $from = $self->_current_block_label;
        my ($head, $chk, $done) = map { $self->_fresh_label("format.trim.$_.") } qw(head chk done);
        my ($k, $more, $k1, $cp, $c, $sp) = map { $self->_fresh } 1 .. 6;
        $self->_set_terminator("  br label %$head");
        $self->_new_block($head);
        $self->_emit("  $k = phi i64 [ $al, %$from ], [ $k1, %$chk ]  ; format: the line's length");
        $self->_emit("  $more = icmp sgt i64 $k, 0");
        $self->_set_terminator("  br i1 $more, label %$chk, label %$done");
        $self->_new_block($chk);
        $self->_emit("  $k1 = sub i64 $k, 1");
        $self->_emit("  $cp = getelementptr inbounds i8, i8* $ap, i64 $k1");
        $self->_emit("  $c = load i8, i8* $cp");
        $self->_emit("  $sp = icmp eq i8 $c, 32");
        $self->_set_terminator("  br i1 $sp, label %$head, label %$done");
        $self->_new_block($done);
        my $out = $self->_set_str_len($ap, $k);
        $out = $self->_emit_str_append($out, $self->_set_str_len($self->_str_const_parts("\n", 'format: end of line')), 'format')
            if $nl;
        my ($op, $ol) = $self->_str_parts($out);
        my ($ol32, $fp) = ($i32->($ol), $self->_fresh);
        $self->_emit("  $fp = getelementptr inbounds [5 x i8], [5 x i8]* \@fmt_print_str, i64 0, i64 0");
        $self->_emit("  call i32 (i8*, ...) \@printf(i8* $fp, i32 $ol32, i8* $op)  ; format: the line");
    }
    die "GAP: a format line with values its fields do not use is not lowered\n" if @args;
    return $self->{cache}{ $node->id } = $self->_build_slot('true', '1', 'Int', 'formline: true');
}

# _lower_split($node) -> %Array*: split in a list, its fields as views of
# the string. Three separators are lowered: a literal (a pattern with no
# regex metacharacter), " " (awk mode: runs of whitespace, leading ones
# skipped) and // (each character). Trailing empty fields are dropped, as
# with no limit. A regex, a limit, or split in scalar context is refused.
sub _lower_split {
    my ($self, $node) = @_;
    my ($pat, $str, $lim) = grep { blessed($_) } $node->inputs->@*;
    die "GAP: split whose result is a " . ( $node->stamp // 'Unknown' ) . " (scalar context) is not lowered\n"
        unless ( $node->stamp // '' ) =~ /\A(?:List|Array)\z/;
    die "GAP: split with no string (of \$_) is not lowered\n" unless blessed($str);
    die "GAP: split with a limit is not lowered\n"
        if blessed($lim) && !( $lim->operation eq 'Constant' && ( $lim->value // '' ) eq '0' );
    die "GAP: split by a pattern known only at run time is not lowered\n"
        unless blessed($pat) && $pat->operation eq 'Constant';
    die "GAP: split by a regex with flags (" . $pat->flags . ") is not lowered\n"
        if $pat->can('flags') && length( $pat->flags // '' );
    my $pv = $pat->value // '';
    my $mode = ( $pat->const_type // '' ) eq 'string' && $pv eq ' ' ? 'awk'
             : ( $pat->const_type // '' ) eq 'regex' && $pv eq ''  ? 'chars'
             : ( $pat->const_type // '' ) eq 'regex' && $pv !~ /[\\^\$.|?*+()\[\]{}]/ ? 'literal'
             : die "GAP: split by the regex /$pv/ is not lowered -- only a literal separator, \" \" or //\n";
    my $from = $self->_repr_of($str) // $str->stamp // '';
    my $sv = $self->lower_value($str);
    $sv = $self->_emit_coercion($sv, $from, 'Str', 'split: the string') if $from ne 'Str';
    my ($sp, $sl) = $self->_str_parts($sv);
    $self->{$_} = 1 for qw(_need_array_append _need_malloc_memcpy _need_aggregate_types _need_memcmp);
    my $acc = $self->_emit_array_of([]);
    my ($ia, $sa, $ka, $wa) = map { $self->_fresh } 1 .. 4;
    $self->_emit_entry("  $_ = alloca i64  ; split: state") for $ia, $sa, $ka, $wa;
    $self->_emit("  store i64 0, i64* $_") for $ia, $sa, $ka, $wa;
    # push the field [a, b); keep counts the fields up to the last non-empty
    my $push = sub ($a, $b) {
        my ($l, $p, $alp, $al, $ne, $k, $k1) = map { $self->_fresh } 1 .. 7;
        $self->_emit("  $l = sub i64 $b, $a");
        $self->_emit("  $p = getelementptr inbounds i8, i8* $sp, i64 $a");
        my $slot = $self->_emit_coercion($self->_set_str_len($p, $l), 'Str', 'Scalar', 'split: a field');
        $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $slot)  ; split: a field");
        $self->_emit("  $alp = getelementptr inbounds %Array, %Array* $acc, i32 0, i32 0");
        $self->_emit("  $al = load i64, i64* $alp");
        $self->_emit("  $ne = icmp ne i64 $l, 0");
        $self->_emit("  $k = load i64, i64* $ka");
        $self->_emit("  $k1 = select i1 $ne, i64 $al, i64 $k  ; split: up to the last non-empty");
        $self->_emit("  store i64 $k1, i64* $ka");
    };
    my ($head, $body, $tail, $done) = map { $self->_fresh_label("split.$_.") } qw(head body tail done);
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    my $i = $self->_fresh;
    $self->_emit("  $i = load i64, i64* $ia");
    if ($mode eq 'literal') {
        my ($seq, $seql) = $self->_str_const_parts($pv, 'split: the separator');
        my ($end, $fits, $at, $m, $hit, $i1, $st, $in) = map { $self->_fresh } 1 .. 8;
        my ($hitl, $adv) = map { $self->_fresh_label("split.$_.") } qw(hit adv);
        $self->_emit("  $end = add i64 $i, $seql");
        $self->_emit("  $fits = icmp ule i64 $end, $sl");
        $self->_set_terminator("  br i1 $fits, label %$body, label %$tail");
        $self->_new_block($body);
        $self->_emit("  $at = getelementptr inbounds i8, i8* $sp, i64 $i");
        $self->_emit("  $m = call i32 \@memcmp(i8* $at, i8* $seq, i64 $seql)  ; split: the separator here?");
        $self->_emit("  $hit = icmp eq i32 $m, 0");
        $self->_set_terminator("  br i1 $hit, label %$hitl, label %$adv");
        $self->_new_block($adv);
        $self->_emit("  $i1 = add i64 $i, 1");
        $self->_emit("  store i64 $i1, i64* $ia");
        $self->_set_terminator("  br label %$head");
        $self->_new_block($hitl);
        $self->_emit("  $st = load i64, i64* $sa");
        $push->($st, $i);
        $self->_emit("  store i64 $end, i64* $ia");
        $self->_emit("  store i64 $end, i64* $sa");
        $self->_set_terminator("  br label %$head");
        $self->_new_block($tail);
        my $st2 = $self->_fresh;
        $self->_emit("  $st2 = load i64, i64* $sa");
        $push->($st2, $sl);
    }
    elsif ($mode eq 'chars') {
        my ($more, $i1) = map { $self->_fresh } 1 .. 2;
        $self->_emit("  $more = icmp ult i64 $i, $sl");
        $self->_set_terminator("  br i1 $more, label %$body, label %$tail");
        $self->_new_block($body);
        $self->_emit("  $i1 = add i64 $i, 1");
        $push->($i, $i1);
        $self->_emit("  store i64 $i1, i64* $ia");
        $self->_set_terminator("  br label %$head");
        $self->_new_block($tail);
    }
    else {   # awk: fields are the runs of non-whitespace
        my ($more, $cp, $c, $i1, $inw, $was) = map { $self->_fresh } 1 .. 6;
        my ($wsl, $endw, $nonws, $startw, $next) = map { $self->_fresh_label("split.$_.") } qw(ws endw nonws startw next);
        $self->_emit("  $more = icmp ult i64 $i, $sl");
        $self->_set_terminator("  br i1 $more, label %$body, label %$tail");
        $self->_new_block($body);
        $self->_emit("  $cp = getelementptr inbounds i8, i8* $sp, i64 $i");
        $self->_emit("  $c = load i8, i8* $cp");
        my @ws = map { my $t = $self->_fresh; $self->_emit("  $t = icmp eq i8 $c, $_"); $t } 32, 9, 10, 11, 12, 13;
        my $any = shift @ws;
        for my $w (@ws) { my $t = $self->_fresh; $self->_emit("  $t = or i1 $any, $w"); $any = $t }
        $self->_emit("  $inw = load i64, i64* $wa");
        $self->_emit("  $was = icmp ne i64 $inw, 0  ; split: in a field?");
        $self->_set_terminator("  br i1 $any, label %$wsl, label %$nonws");
        $self->_new_block($wsl);
        $self->_set_terminator("  br i1 $was, label %$endw, label %$next");
        $self->_new_block($endw);
        my $st = $self->_fresh;
        $self->_emit("  $st = load i64, i64* $sa");
        $push->($st, $i);
        $self->_emit("  store i64 0, i64* $wa");
        $self->_set_terminator("  br label %$next");
        $self->_new_block($nonws);
        $self->_set_terminator("  br i1 $was, label %$next, label %$startw");
        $self->_new_block($startw);
        $self->_emit("  store i64 $i, i64* $sa");
        $self->_emit("  store i64 1, i64* $wa");
        $self->_set_terminator("  br label %$next");
        $self->_new_block($next);
        $self->_emit("  $i1 = add i64 $i, 1");
        $self->_emit("  store i64 $i1, i64* $ia");
        $self->_set_terminator("  br label %$head");
        $self->_new_block($tail);
        my ($w2, $was2) = map { $self->_fresh } 1 .. 2;
        my ($last, $after) = map { $self->_fresh_label("split.$_.") } qw(last after);
        $self->_emit("  $w2 = load i64, i64* $wa");
        $self->_emit("  $was2 = icmp ne i64 $w2, 0");
        $self->_set_terminator("  br i1 $was2, label %$last, label %$after");
        $self->_new_block($last);
        my $st3 = $self->_fresh;
        $self->_emit("  $st3 = load i64, i64* $sa");
        $push->($st3, $sl);
        $self->_set_terminator("  br label %$after");
        $self->_new_block($after);
    }
    # TRAILING EMPTY FIELDS ARE DROPPED: the array ends at the last non-empty.
    my ($k, $lp) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $k = load i64, i64* $ka");
    $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $acc, i32 0, i32 0");
    $self->_emit("  store i64 $k, i64* $lp  ; split: trailing empty fields dropped");
    $self->_set_terminator("  br label %$done");
    $self->_new_block($done);
    return $self->{cache}{ $node->id } = $acc;
}

# _is_array_slice($node) -- an `@a[...]`.
# _is_walked_list($n) -> true for a List grep/map walk as a container (its
# Count and Subscripts): an array slice, or a range of integers -- made once
# as a fresh array (lower_value).
sub _is_walked_list ($n) {
    return 1 if _is_array_slice($n);
    return blessed($n) && $n->operation eq 'Range'
        && !grep { !blessed($_) || ( $_->stamp // '' ) ne 'Int' } $n->inputs->@[0, 1];
}

sub _is_hash_slice ($n) {
    return blessed($n) && $n->operation eq 'Slice' && ( $n->kind // '' ) eq 'hash';
}

# _emit_hash_slice_into($acc, $slice): push onto $acc each key's value, in
# the keys' order, undef for a missing one -- as perl's hslice. Its inputs
# are the keys, then the hash. A key list that is itself a list (`@h{@k}`)
# is refused: the keys here are each one scalar.
sub _emit_hash_slice_into {
    my ($self, $acc, $slice) = @_;
    my @keys = grep { blessed($_) } $slice->inputs->@*;
    my $src  = pop @keys;
    die "GAP: a hash slice whose keys are a list (\@h{\@k}) is not lowered\n"
        if grep { ( $_->stamp // '' ) =~ /\A(?:Array|List|Hash)\z/ } @keys;
    my $hash = $self->_container_ptr($src, 'Hash');
    for my $k (@keys) {
        my $slot = $self->_emit_hash_slot_of($hash, $k);
        $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $slot)  ; list: a hash slice's value");
    }
    return;
}

sub _is_array_slice ($n) {
    return blessed($n) && $n->operation eq 'Slice' && ( $n->kind // '' ) eq 'array';
}

# _emit_array_slice_into($acc, $slice): push onto $acc a copy of each element
# of the slice's array (its last input) its indices (the rest) name, in order: from the end when
# negative, undef past either end -- as perl's aslice.
#
# A SLICE PERL WOULD ALIAS is refused. B::SoN walks `for (@a[1 .. 2])` as a
# fresh array of the slice, so an element passed to a sub or referenced (the
# loop's `$_`) would be a copy where perl's is the array's own (pvm 192).
sub _emit_array_slice_into {
    my ($self, $acc, $slice) = @_;
    for my $tmp (grep { blessed($_) && $_->operation eq 'ArrayLiteral' } ($slice->consumers // [])->@*) {
        for my $el (grep { blessed($_) && $_->operation eq 'Subscript' } ($tmp->consumers // [])->@*) {
            die "GAP: a loop over an array slice whose element is passed or referenced is not "
              . "lowered -- perl aliases the array's element, and the walk here is of a copy\n"
                if grep { blessed($_) && ( $_->operation eq 'Ref'
                    || ( $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) ne 'builtin' ) ) }
                    ($el->consumers // [])->@*;
        }
    }
    my @ix  = grep { blessed($_) } $slice->inputs->@*;   # the indices, then the array
    my $src = pop @ix;
    my $idx = $self->_emit_flattened_array_of(\@ix);
    my $arr = $self->_container_ptr($src, 'Array');
    my ($n, $ie, $len, $elems) = map { $self->_fresh } 1 .. 4;
    my ($np, $iep, $lp, $ep) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $np = getelementptr inbounds %Array, %Array* $idx, i32 0, i32 0  ; slice: index count ptr");
    $self->_emit("  $n = load i64, i64* $np");
    $self->_emit("  $iep = getelementptr inbounds %Array, %Array* $idx, i32 0, i32 2");
    $self->_emit("  $ie = load %Slot*, %Slot** $iep  ; slice: the indices");
    $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; slice: array len ptr");
    $self->_emit("  $len = load i64, i64* $lp");
    $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2");
    $self->_emit("  $elems = load %Slot*, %Slot** $ep  ; slice: the array's elements");
    my ($head, $body, $inb, $oob, $join, $done) = map { $self->_fresh_label("slice.$_.") } qw(head body inb oob join done);
    my ($k, $more, $k1) = map { $self->_fresh } 1 .. 3;
    my $from = $self->_current_block_label;
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    my $head_idx = $self->{current_idx};
    $self->_emit("  $more = icmp slt i64 $k, $n  ; slice: another index?");
    $self->_set_terminator("  br i1 $more, label %$body, label %$done");
    $self->_new_block($body);
    my ($isp, $is) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $isp = getelementptr inbounds %Slot, %Slot* $ie, i64 $k");
    $self->_emit("  $is = load %Slot, %Slot* $isp  ; slice: this index");
    my $i0 = $self->_slot_as_reading($is, 'Int', 'slice index');
    my ($neg, $adj, $i, $ok) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $neg = icmp slt i64 $i0, 0");
    $self->_emit("  $adj = add i64 $i0, $len  ; slice: from the end");
    $self->_emit("  $i = select i1 $neg, i64 $adj, i64 $i0");
    $self->_emit("  $ok = icmp ult i64 $i, $len  ; slice: inside the array?");
    $self->_set_terminator("  br i1 $ok, label %$inb, label %$oob");
    $self->_new_block($inb);
    my ($sp, $sv) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $elems, i64 $i");
    $self->_emit("  $sv = load %Slot, %Slot* $sp  ; slice: the element");
    $self->_set_terminator("  br label %$join");
    $self->_new_block($oob);
    my $undef = $self->_build_slot('false', '0', 'Undef', 'slice: past the end');
    my $oob_end = $self->_current_block_label;
    $self->_set_terminator("  br label %$join");
    $self->_new_block($join);
    my $v = $self->_fresh;
    $self->_emit("  $v = phi %Slot [ $sv, %$inb ], [ $undef, %$oob_end ]");
    $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $v)  ; list: a slice's element");
    $self->_emit("  $k1 = add i64 $k, 1");
    my $back = $self->_current_block_label;
    $self->_set_terminator("  br label %$head");
    unshift $self->{blocks}[$head_idx]{insts}->@*,
        "  $k = phi i64 [ 0, %$from ], [ $k1, %$back ]  ; slice: which index";
    $self->_new_block($done);
    return;
}

# _lower_bless($node) -> the reference, now of a class. THE CLASS IS KEPT
# BESIDE THE REFERENCE, in a table keyed by its address (@chalk_bless_set):
# the pointer and its contents are unchanged, so every copy of it sees the
# class, and only ref() and dispatch ask. A reblessed reference, or one
# whose ref() is read where a bless elsewhere changes it, is refused by
# _lower_reftype.
sub _lower_bless {
    my ($self, $node) = @_;
    my @in = grep { blessed($_) } $node->inputs->@*;
    pop @in if $node->can('memory_input') && $node->memory_input;
    die "GAP: a one-argument bless (into the current package) is not lowered\n" unless @in == 2;
    my ($r, $c) = @in;
    my $rs = $self->_repr_of($r) // '';
    die "GAP: bless of a $rs is not lowered -- only an array, hash or scalar reference\n"
        unless $rs =~ /\A(?:Array|Hash|Scalar)Ref\z/;
    my $ref = $self->lower_value($r);
    my $cr  = $self->lower_value($c);
    my $cs  = $self->_repr_of($c) // '';
    $cr = $self->_emit_coercion($cr, $cs, 'Str', 'bless class') if $cs ne 'Str';
    my ($p, $l) = $self->_str_parts($cr);
    $self->{$_} = 1 for qw(_need_bless _need_malloc_memcpy);
    $self->_emit("  call void \@chalk_bless_set(i8* $ref, i8* $p, i64 $l)  ; bless: the class");
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _bless_class($ref) -> ($is_blessed_i1, $str): the class bless recorded for
# an i8* reference, as a %Str (empty when not blessed).
sub _bless_class {
    my ($self, $ref) = @_;
    $self->{$_} = 1 for qw(_need_bless _need_malloc_memcpy);
    my ($lp, $p, $l, $is) = map { $self->_fresh } 1 .. 4;
    $self->_emit_entry("  $lp = alloca i64  ; ref(): the class's length");
    $self->_emit("  $p = call i8* \@chalk_bless_get(i8* $ref, i64* $lp)  ; ref(): blessed into?");
    $self->_emit("  $l = load i64, i64* $lp");
    $self->_emit("  $is = icmp ne i8* $p, null");
    return ($is, $p, $l);
}

# _lower_delete($node) -> %Slot: `delete $h{k}` takes the key out of the
# hash and is its value, undef for a key that is not there
# (@chalk_hash_delete). An array element's delete is refused.
sub _lower_delete {
    my ($self, $node) = @_;
    my $kind = $node->can('kind') ? ( $node->kind // '' ) : '';
    die "GAP: delete of an array element is not lowered\n" unless $kind eq 'hash';
    my ($c, $k) = $node->inputs->@[0, 1];
    my $hash = $self->_container_ptr($c, 'Hash');
    my ($kp, $kl) = $self->_str_parts($self->_hash_key_str($k));
    $self->{$_} = 1 for qw(_need_hash_delete _need_memcmp _need_aggregate_types);
    my $r = $self->_fresh;
    $self->_emit("  $r = call %Slot \@chalk_hash_delete(%Hash* $hash, i8* $kp, i64 $kl)  ; delete");
    return $self->{cache}{ $node->id } = $r;
}

# _hash_delete_lines -> @chalk_hash_delete: find the key; its value as a
# Slot; the entries after it shifted down one, so the rest keep their order.
sub _hash_delete_lines {
    my ($self) = @_;
    return () unless $self->{_need_hash_delete} && !$self->{_hash_delete_emitted}++;
    my ($KP, $KL, $VD, $VP, $VT) = map { _he_idx($_) } qw(key_ptr key_len val_def val_pay val_tag);
    my ($SD, $ST, $SP) = map { _slot_idx($_) } qw(defined tag payload);
    return ('', <<"END_HELPER");
define internal %Slot \@chalk_hash_delete(%Hash* %h, i8* %k, i64 %kl) {
entry:
  %cp = getelementptr inbounds %Hash, %Hash* %h, i32 0, i32 0
  %n  = load i64, i64* %cp
  %ep = getelementptr inbounds %Hash, %Hash* %h, i32 0, i32 2
  %e  = load %HashEntry*, %HashEntry** %ep
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp ult i64 %i, %n
  br i1 %more, label %chk, label %miss
chk:
  %p   = getelementptr inbounds %HashEntry, %HashEntry* %e, i64 %i
  %klp = getelementptr inbounds %HashEntry, %HashEntry* %p, i32 0, i32 $KL
  %el  = load i64, i64* %klp
  %leq = icmp eq i64 %el, %kl
  br i1 %leq, label %cmp, label %next
cmp:
  %kpp = getelementptr inbounds %HashEntry, %HashEntry* %p, i32 0, i32 $KP
  %ek  = load i8*, i8** %kpp
  %c   = call i32 \@memcmp(i8* %ek, i8* %k, i64 %kl)
  %hit = icmp eq i32 %c, 0
  br i1 %hit, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
found:
  %vdp = getelementptr inbounds %HashEntry, %HashEntry* %p, i32 0, i32 $VD
  %vtp = getelementptr inbounds %HashEntry, %HashEntry* %p, i32 0, i32 $VT
  %vpp = getelementptr inbounds %HashEntry, %HashEntry* %p, i32 0, i32 $VP
  %vd = load i1, i1* %vdp
  %vt = load i8, i8* %vtp
  %vp = load i64, i64* %vpp
  %s0 = insertvalue %Slot zeroinitializer, i1 %vd, $SD
  %s1 = insertvalue %Slot %s0, i8 %vt, $ST
  %s2 = insertvalue %Slot %s1, i64 %vp, $SP
  %last = sub i64 %n, 1
  br label %shift
shift:
  %j = phi i64 [ %i, %found ], [ %j1, %move ]
  %sm = icmp ult i64 %j, %last
  br i1 %sm, label %move, label %done
move:
  %j1  = add i64 %j, 1
  %dst = getelementptr inbounds %HashEntry, %HashEntry* %e, i64 %j
  %src = getelementptr inbounds %HashEntry, %HashEntry* %e, i64 %j1
  %ent = load %HashEntry, %HashEntry* %src
  store %HashEntry %ent, %HashEntry* %dst
  br label %shift
done:
  store i64 %last, i64* %cp
  ret %Slot %s2
miss:
  ret %Slot zeroinitializer
}
END_HELPER
}

sub _bless_lines {
    my ($self) = @_;
    return () unless $self->{_need_bless} && !$self->{_bless_emitted}++;
    return ('', <<'END_HELPER');
%BlessEntry = type { i8*, i8*, i64 }
@chalk_bless_tab = internal global %BlessEntry* null
@chalk_bless_n   = internal global i64 0
@chalk_bless_cap = internal global i64 0

define internal void @chalk_bless_set(i8* %r, i8* %p, i64 %l) {
entry:
  %n   = load i64, i64* @chalk_bless_n
  %tab = load %BlessEntry*, %BlessEntry** @chalk_bless_tab
  br label %find
find:
  %i    = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %look, label %add
look:
  %ep = getelementptr inbounds %BlessEntry, %BlessEntry* %tab, i64 %i, i32 0
  %er = load i8*, i8** %ep
  %hit = icmp eq i8* %er, %r
  br i1 %hit, label %put, label %next
next:
  %i1 = add i64 %i, 1
  br label %find
put:
  %pp = getelementptr inbounds %BlessEntry, %BlessEntry* %tab, i64 %i, i32 1
  store i8* %p, i8** %pp
  %lp = getelementptr inbounds %BlessEntry, %BlessEntry* %tab, i64 %i, i32 2
  store i64 %l, i64* %lp
  ret void
add:
  %cap  = load i64, i64* @chalk_bless_cap
  %full = icmp sge i64 %n, %cap
  br i1 %full, label %grow, label %store
grow:
  %dbl   = mul i64 %cap, 2
  %small = icmp slt i64 %dbl, 8
  %nc    = select i1 %small, i64 8, i64 %dbl
  %e1    = getelementptr %BlessEntry, %BlessEntry* null, i64 1
  %esz   = ptrtoint %BlessEntry* %e1 to i64
  %nb    = mul i64 %nc, %esz
  %buf   = call i8* @malloc(i64 %nb)
  %ob    = mul i64 %n, %esz
  %old   = bitcast %BlessEntry* %tab to i8*
  %cp    = call i8* @memcpy(i8* %buf, i8* %old, i64 %ob)
  %nt    = bitcast i8* %buf to %BlessEntry*
  store %BlessEntry* %nt, %BlessEntry** @chalk_bless_tab
  store i64 %nc, i64* @chalk_bless_cap
  br label %store
store:
  %t2  = load %BlessEntry*, %BlessEntry** @chalk_bless_tab
  %sr  = getelementptr inbounds %BlessEntry, %BlessEntry* %t2, i64 %n, i32 0
  store i8* %r, i8** %sr
  %sp  = getelementptr inbounds %BlessEntry, %BlessEntry* %t2, i64 %n, i32 1
  store i8* %p, i8** %sp
  %sl  = getelementptr inbounds %BlessEntry, %BlessEntry* %t2, i64 %n, i32 2
  store i64 %l, i64* %sl
  %n1  = add i64 %n, 1
  store i64 %n1, i64* @chalk_bless_n
  ret void
}

define internal i8* @chalk_bless_get(i8* %r, i64* %outl) {
entry:
  %n   = load i64, i64* @chalk_bless_n
  %tab = load %BlessEntry*, %BlessEntry** @chalk_bless_tab
  br label %find
find:
  %i    = phi i64 [ 0, %entry ], [ %i1, %next ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %look, label %none
look:
  %ep  = getelementptr inbounds %BlessEntry, %BlessEntry* %tab, i64 %i, i32 0
  %er  = load i8*, i8** %ep
  %hit = icmp eq i8* %er, %r
  br i1 %hit, label %found, label %next
next:
  %i1 = add i64 %i, 1
  br label %find
found:
  %pp = getelementptr inbounds %BlessEntry, %BlessEntry* %tab, i64 %i, i32 1
  %p  = load i8*, i8** %pp
  %lp = getelementptr inbounds %BlessEntry, %BlessEntry* %tab, i64 %i, i32 2
  %l  = load i64, i64* %lp
  store i64 %l, i64* %outl
  ret i8* %p
none:
  store i64 0, i64* %outl
  ret i8* null
}
END_HELPER
}

# _tr_lines -- @chalk_tr(src, len, map, in, out) -> the count: each byte of
# src whose `in` entry is set is counted and written as its `map` entry;
# every other byte is copied as it is. One table pair per tr/// (_lower_transliterate).
sub _tr_lines {
    my ($self) = @_;
    return () unless $self->{_need_tr} && !$self->{_tr_emitted}++;
    return ('', <<'END_HELPER');
define internal i64 @chalk_tr(i8* %src, i64 %len, i8* %map, i8* %in, i8* %out) {
entry:
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %next ]
  %n = phi i64 [ 0, %entry ], [ %n1, %next ]
  %more = icmp slt i64 %i, %len
  br i1 %more, label %body, label %done
body:
  %sp = getelementptr inbounds i8, i8* %src, i64 %i
  %b = load i8, i8* %sp
  %bi = zext i8 %b to i64
  %ip = getelementptr inbounds i8, i8* %in, i64 %bi
  %hit = load i8, i8* %ip
  %is = icmp ne i8 %hit, 0
  %mp = getelementptr inbounds i8, i8* %map, i64 %bi
  %m = load i8, i8* %mp
  %v = select i1 %is, i8 %m, i8 %b
  %op = getelementptr inbounds i8, i8* %out, i64 %i
  store i8 %v, i8* %op
  %inc = zext i1 %is to i64
  %n1 = add i64 %n, %inc
  br label %next
next:
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret i64 %n
}
END_HELPER
}

# _tr_expand($list) -> the bytes a tr/// list names, ranges expanded. Only
# ASCII and the plain escapes; anything else is refused by name.
sub _tr_expand {
    my ($list) = @_;
    my @c;
    my @ch = split //, $list;
    for (my $i = 0; $i < @ch; $i++) {
        my $c = $ch[$i];
        if ($c eq '\\') {
            my $e = $ch[++$i] // die "GAP: a tr/// list ending in a backslash is not lowered\n";
            my %esc = (n => "\n", t => "\t", r => "\r", '\\' => '\\', '-' => '-', '/' => '/', '.' => '.');
            die "GAP: a tr/// escape \\$e is not lowered\n" unless exists $esc{$e};
            $c = $esc{$e};
        }
        die "GAP: a tr/// list with a non-ASCII character is not lowered\n" if ord($c) > 127;
        if (@c && $c eq '-' && $i > 0 && $ch[$i - 1] ne '\\' && $i < $#ch) {
            my $to = $ch[++$i];
            die "GAP: a tr/// range to an escape is not lowered\n" if $to eq '\\';
            my $lo = $c[-1];
            die "GAP: a tr/// range running backwards is not lowered\n" if ord($to) < ord($lo);
            push @c, map { chr } ord($lo) + 1 .. ord($to);
            next;
        }
        push @c, $c;
    }
    return @c;
}

# _lower_transliterate($node) -> the new string (Str); its count is cached for
# TransliterateCount. Each byte of the from-list maps to the byte at its place
# in the to-list -- a short to-list repeats its last, an empty one is the
# from-list (counting only). The first mention of a byte wins. A location
# subject is stored back, as s/// does.
sub _lower_transliterate {
    my ($self, $node) = @_;
    die "GAP: tr///" . $node->flags . " is not lowered -- only tr/// with no flags\n"
        if length( $node->flags // '' );
    my @from = _tr_expand($node->from // '');
    my @to   = _tr_expand($node->to // '');
    @to = @from unless @to;
    push @to, $to[-1] while @to < @from;
    my ($map, $in) = ( "\0" x 256, "\0" x 256 );
    for my $k (0 .. $#from) {
        my $o = ord $from[$k];
        next if substr($in, $o, 1) ne "\0";
        substr($in, $o, 1)  = "\x01";
        substr($map, $o, 1) = $to[$k];
    }
    my $subj_node = $node->inputs->[0];
    my $subj_ref  = $self->lower_value($subj_node);
    my $sr = $self->_repr_of($subj_node) // '';
    $subj_ref = $self->_emit_coercion($subj_ref, $sr, 'Str', 'tr/// subject') if $sr ne 'Str';
    my ($sp, $sl) = $self->_str_parts($subj_ref);
    die "GAP: tr/// subject has no tracked length\n" unless defined $sl;
    $self->{_need_tr} = 1;
    $self->{_need_malloc_memcpy} = 1;
    my ($mg, undef, $mt) = $self->_module_global_name('tr_map', $map);
    my ($ig, undef, $it) = $self->_module_global_name('tr_in', $in);
    my ($mp, $ip, $sz, $out, $cnt, $nul) = map { $self->_fresh } 1 .. 6;
    $self->_emit("  $mp = getelementptr inbounds [$mt x i8], [$mt x i8]* $mg, i64 0, i64 0  ; tr///: map");
    $self->_emit("  $ip = getelementptr inbounds [$it x i8], [$it x i8]* $ig, i64 0, i64 0  ; tr///: in the set");
    $self->_emit("  $sz = add i64 $sl, 1");
    $self->_emit("  $out = call i8* \@malloc(i64 $sz)  ; tr///: the new string");
    $self->_emit("  $cnt = call i64 \@chalk_tr(i8* $sp, i64 $sl, i8* $mp, i8* $ip, i8* $out)  ; tr///: map and count");
    $self->_emit("  $nul = getelementptr inbounds i8, i8* $out, i64 $sl");
    $self->_emit("  store i8 0, i8* $nul");
    my $res = $self->_set_str_len($out, $sl);
    if ($subj_node->operation eq 'PadAccess' && $subj_node->is_location) {
        my $boxed = $self->_emit_coercion($res, 'Str', 'Scalar', 'tr/// store-back');
        $self->_emit("  store %Slot $boxed, %Slot* " . $self->_location_ptr($subj_node)
            . "  ; tr/// stores lexical " . $subj_node->name);
    }
    $self->{cache}{ 'trcount:' . $node->id } = $cnt;
    return $self->{cache}{ $node->id } = $res;
}

sub _array_append_lines {
    my ($self) = @_;
    return () unless $self->{_need_array_append} && !$self->{_array_append_emitted}++;
    my $sz = _sizeof_llvm_type('%Slot');
    return ('', <<"END_HELPER");
define internal void \@chalk_array_push_slot(%Array* %a, %Slot %v) {
entry:
  %lp = getelementptr inbounds %Array, %Array* %a, i32 0, i32 0
  %cp = getelementptr inbounds %Array, %Array* %a, i32 0, i32 1
  %ep = getelementptr inbounds %Array, %Array* %a, i32 0, i32 2
  %len = load i64, i64* %lp
  %cap = load i64, i64* %cp
  %full = icmp sge i64 %len, %cap
  br i1 %full, label %grow, label %store
grow:
  %dbl = mul i64 %cap, 2
  %small = icmp slt i64 %dbl, 4
  %nc = select i1 %small, i64 4, i64 %dbl
  %nb = mul i64 %nc, $sz
  %buf = call i8* \@malloc(i64 %nb)
  %old = load %Slot*, %Slot** %ep
  %oraw = bitcast %Slot* %old to i8*
  %ob = mul i64 %len, $sz
  %c = call i8* \@memcpy(i8* %buf, i8* %oraw, i64 %ob)
  %ns = bitcast i8* %buf to %Slot*
  store %Slot* %ns, %Slot** %ep
  store i64 %nc, i64* %cp
  br label %store
store:
  %el = load %Slot*, %Slot** %ep
  %sp = getelementptr inbounds %Slot, %Slot* %el, i64 %len
  store %Slot %v, %Slot* %sp
  %l1 = add i64 %len, 1
  store i64 %l1, i64* %lp
  ret void
}

define internal void \@chalk_array_append_all(%Array* %d, %Array* %s) {
entry:
  %slp = getelementptr inbounds %Array, %Array* %s, i32 0, i32 0
  %n = load i64, i64* %slp
  %sep = getelementptr inbounds %Array, %Array* %s, i32 0, i32 2
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %el = load %Slot*, %Slot** %sep
  %sp = getelementptr inbounds %Slot, %Slot* %el, i64 %i
  %v = load %Slot, %Slot* %sp
  call void \@chalk_array_push_slot(%Array* %d, %Slot %v)
  %i1 = add i64 %i, 1
  br label %loop
done:
  ret void
}
END_HELPER
}
# _lower_increment($node) -> %Slot (or the node's narrower reading)
#
# PERL'S ++ ON A VALUE NOT PROVEN A NUMBER. B::SoN emits Increment where the
# operand may be a string, since "Az"++ is "Ba" and an Add would make it 1.
# The operand's tag decides at run time (@chalk_slot_inc): undef is 1, a
# number adds one, a string of letters then digits counts in its own
# alphabet, any other string is its number plus one.
sub _lower_increment {
    my ($self, $node) = @_;
    my $in   = $node->inputs->[0];
    my $from = $in->operation eq 'Print' ? 'Boolean' : ($in->stamp // '');
    my $ref  = $self->lower_value($in);
    my $slot = $from =~ /\A(?:Scalar|Slot)\z/ ? $ref
             : $from eq 'Undef' ? $self->_build_slot('false', '0', 'Undef', '++ operand')
             : $from =~ /\A(?:Int|Num|Str|Boolean)\z/
                 ? $self->_emit_coercion($ref, $from, 'Scalar', '++ operand')
             : die "GAP: ++ on a $from value is not lowered\n";
    $self->{$_} = 1 for qw(_need_slot_inc _need_aggregate_types _need_malloc_memcpy
                           _need_exit _need_str_type _need_str_to_num_helper);
    my $r = $self->_fresh;
    $self->_emit("  $r = call %Slot \@chalk_slot_inc(%Slot $slot)  ; ++");
    my $to = $node->stamp // 'Scalar';
    return $self->{cache}{ $node->id } = $to =~ /\A(?:Scalar|Slot|Unknown)\z/ ? $r
        : $self->_emit_coercion($r, 'Scalar', $to, '++ result');
}

# _slot_inc_helper_lines() -> @chalk_slot_inc and @chalk_str_inc, once.
sub _slot_inc_helper_lines {
    my ($self) = @_;
    return () unless $self->{_need_slot_inc} && !$self->{_slot_inc_helper_emitted}++;
    return ('', 'declare {i64, i1} @llvm.sadd.with.overflow.i64(i64, i64)',
            _emit_slot_inc_helper());
}

# _emit_slot_inc_helper() -> the IR text of @chalk_slot_inc(%Slot) and
# @chalk_str_inc(%Str*). What perl gives that a Slot cannot hold is refused
# at run time (exit 255) rather than answered wrongly: ++ past the largest
# Int (perl's answer is an unsigned integer) and ++ on a reference.
sub _emit_slot_inc_helper {
    my ($d, $t, $p) = (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
    my %g = map { $_ => _slot_tag_value($_) } qw(Undef Int Num Str Boolean);
    my ($sp, $sl, $se) = (_str_idx('ptr'), _str_idx('len'), _str_idx('enc'));
    my $enc = _str_enc('utf8');
    my $num = _repr_to_llvm_type('Num');
    return <<"END_HELPER";
define internal %Slot \@chalk_slot_inc(%Slot %v) {
entry:
  %def = extractvalue %Slot %v, $d
  %tag = extractvalue %Slot %v, $t
  %pay = extractvalue %Slot %v, $p
  br i1 %def, label %bytag, label %one
bytag:
  switch i8 %tag, label %refuse [ i8 $g{Undef}, label %one
                                  i8 $g{Int}, label %int
                                  i8 $g{Num}, label %num
                                  i8 $g{Boolean}, label %bool
                                  i8 $g{Str}, label %str ]
one:
  %o0 = insertvalue %Slot undef, i1 true, $d
  %o1 = insertvalue %Slot %o0, i8 $g{Int}, $t
  %o2 = insertvalue %Slot %o1, i64 1, $p
  ret %Slot %o2
int:
  %ov = call {i64, i1} \@llvm.sadd.with.overflow.i64(i64 %pay, i64 1)
  %iv = extractvalue {i64, i1} %ov, 0
  %io = extractvalue {i64, i1} %ov, 1
  br i1 %io, label %refuse, label %intok
intok:
  %i0 = insertvalue %Slot %v, i64 %iv, $p
  ret %Slot %i0
num:
  %nf = bitcast i64 %pay to $num
  %nf1 = fadd $num %nf, 1.0
  %nb = bitcast $num %nf1 to i64
  %n0 = insertvalue %Slot %v, i64 %nb, $p
  ret %Slot %n0
bool:
  %bo = add i64 %pay, 1
  %c0 = insertvalue %Slot %v, i8 $g{Int}, $t
  %c1 = insertvalue %Slot %c0, i64 %bo, $p
  ret %Slot %c1
str:
  %sptr = inttoptr i64 %pay to %Str*
  %r = call %Slot \@chalk_str_inc(%Str* %sptr)
  ret %Slot %r
refuse:
  call void \@exit(i32 255)
  unreachable
}

define internal %Slot \@chalk_str_inc(%Str* %s) {
entry:
  %pp = getelementptr inbounds %Str, %Str* %s, i64 0, i32 $sp
  %p = load i8*, i8** %pp
  %lp = getelementptr inbounds %Str, %Str* %s, i64 0, i32 $sl
  %len = load i64, i64* %lp
  %empty = icmp eq i64 %len, 0
  br i1 %empty, label %one, label %scan
one:
  %o0 = insertvalue %Slot undef, i1 true, $d
  %o1 = insertvalue %Slot %o0, i8 $g{Int}, $t
  %o2 = insertvalue %Slot %o1, i64 1, $p
  ret %Slot %o2
scan:
  %i = phi i64 [ 0, %entry ], [ %i1, %sstep ]
  %dig = phi i1 [ false, %entry ], [ %dig1, %sstep ]
  %done = icmp eq i64 %i, %len
  br i1 %done, label %magic, label %sbody
sbody:
  %cp = getelementptr inbounds i8, i8* %p, i64 %i
  %c = load i8, i8* %cp
  %cd = sub i8 %c, 48
  %isd = icmp ult i8 %cd, 10
  %lc = or i8 %c, 32
  %la = sub i8 %lc, 97
  %isl0 = icmp ult i8 %la, 26
  %nodig = xor i1 %dig, true
  %isl = and i1 %isl0, %nodig
  %ok = or i1 %isd, %isl
  br i1 %ok, label %sstep, label %numeric
sstep:
  %dig1 = or i1 %dig, %isd
  %i1 = add i64 %i, 1
  br label %scan
numeric:
  %nv = call double \@chalk_str_to_num(i8* %p, i64 %len)
  %nv1 = fadd $num %nv, 1.0
  %nb = bitcast $num %nv1 to i64
  %u0 = insertvalue %Slot undef, i1 true, $d
  %u1 = insertvalue %Slot %u0, i8 $g{Num}, $t
  %u2 = insertvalue %Slot %u1, i64 %nb, $p
  ret %Slot %u2
magic:
  %n1 = add i64 %len, 1
  %n2 = add i64 %len, 2
  %buf = call i8* \@malloc(i64 %n2)
  %dst = getelementptr inbounds i8, i8* %buf, i64 1
  %cpy = call i8* \@memcpy(i8* %dst, i8* %p, i64 %len)
  br label %ml
ml:
  %j = phi i64 [ %len, %magic ], [ %jm, %mcarry ]
  %more = icmp ne i64 %j, 0
  br i1 %more, label %mbody, label %mprepend
mbody:
  %jm = sub i64 %j, 1
  %q = getelementptr inbounds i8, i8* %dst, i64 %jm
  %ch = load i8, i8* %q
  %isz = icmp eq i8 %ch, 122
  %isZ = icmp eq i8 %ch, 90
  %is9 = icmp eq i8 %ch, 57
  %wz = or i1 %isz, %isZ
  %wrap = or i1 %wz, %is9
  br i1 %wrap, label %mcarry, label %mstop
mcarry:
  %w0 = select i1 %isZ, i8 65, i8 48
  %w = select i1 %isz, i8 97, i8 %w0
  store i8 %w, i8* %q
  br label %ml
mstop:
  %ch1 = add i8 %ch, 1
  store i8 %ch1, i8* %q
  br label %mret
mprepend:
  %f = load i8, i8* %p
  %fd0 = sub i8 %f, 48
  %fd = icmp ult i8 %fd0, 10
  %fu0 = sub i8 %f, 65
  %fu = icmp ult i8 %fu0, 26
  %pre0 = select i1 %fu, i8 65, i8 97
  %pre = select i1 %fd, i8 49, i8 %pre0
  store i8 %pre, i8* %buf
  br label %mret
mret:
  %rp = phi i8* [ %dst, %mstop ], [ %buf, %mprepend ]
  %rl = phi i64 [ %len, %mstop ], [ %n1, %mprepend ]
  %term = getelementptr inbounds i8, i8* %rp, i64 %rl
  store i8 0, i8* %term
  %sb = call i8* \@malloc(i64 ptrtoint (%Str* getelementptr (%Str, %Str* null, i64 1) to i64))
  %ns = bitcast i8* %sb to %Str*
  %np = getelementptr inbounds %Str, %Str* %ns, i64 0, i32 $sp
  store i8* %rp, i8** %np
  %nl = getelementptr inbounds %Str, %Str* %ns, i64 0, i32 $sl
  store i64 %rl, i64* %nl
  %ne = getelementptr inbounds %Str, %Str* %ns, i64 0, i32 $se
  store i32 $enc, i32* %ne
  %spay = ptrtoint %Str* %ns to i64
  %m0 = insertvalue %Slot undef, i1 true, $d
  %m1 = insertvalue %Slot %m0, i8 $g{Str}, $t
  %m2 = insertvalue %Slot %m1, i64 %spay, $p
  ret %Slot %m2
}
END_HELPER
}

# _emit_hash_has_key($hash, $key_ptr, $key_len) -> i1, found
sub _emit_hash_has_key {
    my ($self, $hash, $kp, $kl) = @_;
    my ($cntp, $entp, $cnt, $ents) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $cntp = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 0");
    $self->_emit("  $entp = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 2");
    $self->_emit("  $cnt = load i64, i64* $cntp  ; exists: count");
    $self->_emit("  $ents = load %HashEntry*, %HashEntry** $entp  ; exists: entries");
    my ($loop, $chk, $cmp, $nxt, $done) = map { $self->_fresh_label("hex.$_.") } qw(loop chk cmp nxt done);
    my $pre = $self->_current_block_label;
    my ($i, $i1, $more) = map { $self->_fresh } 1 .. 3;
    $self->_set_terminator("  br label %$loop");
    $self->_new_block($loop);
    $self->_emit("  $i = phi i64 [ 0, %$pre ], [ $i1, %$nxt ]");
    $self->_emit("  $more = icmp ult i64 $i, $cnt");
    $self->_set_terminator("  br i1 $more, label %$chk, label %$done");
    $self->_new_block($chk);
    my ($e, $klp, $ekl, $leq) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $e = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i");
    $self->_emit("  $klp = getelementptr inbounds %HashEntry, %HashEntry* $e, i32 0, i32 " . _he_idx('key_len'));
    $self->_emit("  $ekl = load i64, i64* $klp");
    $self->_emit("  $leq = icmp eq i64 $ekl, $kl");
    $self->_set_terminator("  br i1 $leq, label %$cmp, label %$nxt");
    $self->_new_block($cmp);
    my ($kpp, $ekp, $r, $m) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $kpp = getelementptr inbounds %HashEntry, %HashEntry* $e, i32 0, i32 " . _he_idx('key_ptr'));
    $self->_emit("  $ekp = load i8*, i8** $kpp");
    $self->_emit("  $r = call i32 \@memcmp(i8* nocapture readonly $ekp, i8* nocapture readonly $kp, i64 $kl)");
    $self->_emit("  $m = icmp eq i32 $r, 0  ; exists: key match?");
    $self->_set_terminator("  br i1 $m, label %$done, label %$nxt");
    $self->_new_block($nxt);
    $self->_emit("  $i1 = add i64 $i, 1");
    $self->_set_terminator("  br label %$loop");
    $self->_new_block($done);
    my $found = $self->_fresh;
    $self->_emit("  $found = phi i1 [ false, %$loop ], [ true, %$cmp ]  ; exists: found");
    return $found;
}

# _miss_kept($node, $ref, $from) -> ($ref, $from): an element read stored
# somewhere is stored as its own Slot, which carries a miss its narrowed
# reading does not (a missing key read as Str is a defined "").
sub _miss_kept {
    my ($self, $node, $ref, $from) = @_;
    return ($ref, $from)
        unless $node->operation eq 'Subscript' && $from !~ /\A(?:Scalar|Slot)\z/;
    return ($self->_subscript_slot($node), 'Slot');
}


# _array_may_grow($ctr) -> bool: whether anything may reallocate the array's
# buffer -- a push, unshift or splice, or an element store (through the array
# or a reference to it) at an index not proven inside its literal length.
# An element's reference points into that buffer, so it is refused then.
sub _array_may_grow {
    my ($ctr) = @_;
    my $n = $ctr->operation eq 'ArrayLiteral' ? scalar(@{ $ctr->inputs }) : 0;
    my @q = ($ctr);
    my %seen;
    while (defined(my $c = shift @q)) {
        next if $seen{ refaddr($c) }++;
        for my $u (($c->consumers // [])->@*) {
            next unless blessed($u);
            my $op = $u->operation;
            return 1 if $op eq 'Call' && ( $u->name // '' ) =~ /\A(?:push|unshift|splice)\z/;
            push @q, $u if $op eq 'Ref';
            next unless $op eq 'Subscript' && refaddr($u->inputs->[0]) == refaddr($c);
            for my $a (($u->consumers // [])->@*) {
                next unless blessed($a) && $a->operation eq 'Assign' && refaddr($a->inputs->[0] // 0) == refaddr($u);
                my $ix = $u->inputs->[1];
                return 1 unless blessed($ix) && $ix->operation eq 'Constant'
                    && ( $ix->value // '' ) =~ /\A\d+\z/ && $ix->value < $n;
            }
        }
    }
    return 0;
}

# _emit_array_extend_to($arr, $idx) -> $idx': make index $idx storable, as
# perl's element store does. A negative index counts from the end (before
# the start, perl dies: exit 255). Past the end, the array grows -- the
# buffer doubled to cover it, floor 4 -- and the slots between are undef.
# Returns the index to store at.
sub _emit_array_extend_to {
    my ($self, $arr, $idx) = @_;
    $self->{_need_malloc_memcpy} = 1;
    $self->{_need_exit}          = 1;
    my $sz = _sizeof_llvm_type('%Slot');
    my ($lp, $cp, $ep, $len, $neg, $fromend, $i, $bad) = map { $self->_fresh } 1 .. 8;
    $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; extend: len ptr");
    $self->_emit("  $cp = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 1  ; extend: cap ptr");
    $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; extend: elems ptr");
    $self->_emit("  $len = load i64, i64* $lp");
    $self->_emit("  $neg = icmp slt i64 $idx, 0");
    $self->_emit("  $fromend = add i64 $idx, $len");
    $self->_emit("  $i = select i1 $neg, i64 $fromend, i64 $idx  ; extend: from the end");
    $self->_emit("  $bad = icmp slt i64 $i, 0  ; extend: before the start?");
    my ($die, $chk, $grow, $fill, $fbody, $done, $ok) =
        map { $self->_fresh_label("ext.$_.") } qw(die chk grow fill fbody done ok);
    $self->_set_terminator("  br i1 $bad, label %$die, label %$chk");
    $self->_new_block($die);
    $self->_refuse_inside_eval("a store that dies on a non-creatable element");
    $self->_emit("  call void \@exit(i32 255)  ; Modification of non-creatable array value attempted");
    $self->_set_terminator("  unreachable");

    $self->_new_block($chk);
    my ($past, $cap, $need, $full) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $past = icmp sge i64 $i, $len  ; extend: past the end?");
    $self->_emit("  $cap = load i64, i64* $cp");
    $self->_emit("  $need = add i64 $i, 1");
    $self->_emit("  $full = icmp sgt i64 $need, $cap");
    my $sized = $self->_fresh_label('ext.sized.');
    $self->_set_terminator("  br i1 $past, label %$sized, label %$ok");

    $self->_new_block($sized);
    $self->_set_terminator("  br i1 $full, label %$grow, label %$fill");

    $self->_new_block($grow);
    my ($dbl, $big, $c1, $small, $nc, $nb, $buf, $old, $oraw, $ob, $ns) = map { $self->_fresh } 1 .. 11;
    $self->_emit("  $dbl = mul i64 $cap, 2");
    $self->_emit("  $big = icmp sgt i64 $need, $dbl");
    $self->_emit("  $c1 = select i1 $big, i64 $need, i64 $dbl");
    $self->_emit("  $small = icmp slt i64 $c1, 4");
    $self->_emit("  $nc = select i1 $small, i64 4, i64 $c1  ; extend: new cap");
    $self->_emit("  $nb = mul i64 $nc, $sz");
    $self->_emit("  $buf = call i8* \@malloc(i64 $nb)  ; extend: grow buffer");
    $self->_emit("  $old = load %Slot*, %Slot** $ep");
    $self->_emit("  $oraw = bitcast %Slot* $old to i8*");
    $self->_emit("  $ob = mul i64 $len, $sz");
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $oraw, i64 $ob)  ; extend: copy live elements");
    $self->_emit("  $ns = bitcast i8* $buf to %Slot*");
    $self->_emit("  store %Slot* $ns, %Slot** $ep");
    $self->_emit("  store i64 $nc, i64* $cp");
    $self->_set_terminator("  br label %$fill");

    # The slots from the old end up to the new element are undef.
    $self->_new_block($fill);
    my $el = $self->_fresh;
    $self->_emit("  $el = load %Slot*, %Slot** $ep  ; extend: slots (post-grow)");
    $self->_set_terminator("  br label %$fbody");
    $self->_new_block($fbody);
    my ($j, $more, $sp, $j1) = map { $self->_fresh } 1 .. 4;
    my $floop = $self->_current_block_label;
    my $fstep = $self->_fresh_label('ext.fstep.');
    $self->_emit("  $j = phi i64 [ $len, %$fill ], [ $j1, %$fstep ]");
    $self->_emit("  $more = icmp slt i64 $j, $need");
    $self->_set_terminator("  br i1 $more, label %$fstep, label %$done");
    $self->_new_block($fstep);
    $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $el, i64 $j");
    $self->_emit("  store %Slot zeroinitializer, %Slot* $sp  ; extend: undef");
    $self->_emit("  $j1 = add i64 $j, 1");
    $self->_set_terminator("  br label %$floop");
    $self->_new_block($done);
    $self->_emit("  store i64 $need, i64* $lp  ; extend: new len");
    $self->_set_terminator("  br label %$ok");
    $self->_new_block($ok);
    $self->{_need_aggregate_types} = 1;
    return $i;
}
# _slot_of_value($node, $ref, $what) -> %Slot: any scalar value as one cell.
sub _slot_of_value {
    my ($self, $node, $ref, $what) = @_;
    my ($d, $t, $p) = $self->_slot_fields_of_value($node, $ref, $what);
    my ($s0, $s1, $s2) = map { $self->_fresh } 1 .. 3;
    $self->{_need_aggregate_types} = 1;
    $self->_emit("  $s0 = insertvalue %Slot undef, i1 $d, " . _slot_idx('defined') . "  ; $what");
    $self->_emit("  $s1 = insertvalue %Slot $s0, i8 $t, " . _slot_idx('tag'));
    $self->_emit("  $s2 = insertvalue %Slot $s1, i64 $p, " . _slot_idx('payload'));
    return $s2;
}

# _slot_fields_of_value($node, $ref, $what) -> ($def_i1, $tag_i8, $pay_i64)
#
# A scalar value as the three fields a %Slot or a %HashEntry holds.
sub _slot_fields_of_value {
    my ($self, $node, $ref, $what) = @_;
    my $repr = $node->operation eq 'Print' ? 'Boolean' : ($self->_repr_of($node) // '');
    # AN ELEMENT READ MAY MISS, whatever its stamp: stored as its narrowed
    # reading, a missing key read as Str was a defined "". Its own Slot
    # carries the miss. (An inlined argument `$_[0]` is the caller's value.)
    if ($node->operation eq 'Subscript' && $repr !~ /\A(?:Scalar|Slot)\z/
            && !defined $self->_bound_ref($node)) {
        $ref  = $self->_subscript_slot($node);
        $repr = 'Slot';
    }
    if ($repr eq 'Scalar' || $repr eq 'Slot') {
        return ($self->_slot_defined_bit($ref), $self->_slot_tag_of($ref), $self->_slot_payload_of($ref));
    }
    return ('false', _slot_tag_value('Undef'), '0') if $repr eq 'Undef';
    die "GAP: $what of a $repr value is not lowered\n"
        unless $repr =~ /\A(?:Int|Num|Str|Boolean|ArrayRef|HashRef|CodeRef|ScalarRef|Object)\z/;
    return ('true', _slot_tag_value(_slot_tag_for_repr($repr)),
            $self->_box_payload($ref, $repr, $what));
}

# _store_hash_value($entry_ptr, $def, $tag, $pay, $what): write a value's
# three fields into a %HashEntry.
sub _store_hash_value {
    my ($self, $ent, $def, $tag, $pay, $what) = @_;
    my %f = (val_def => ['i1', $def], val_tag => ['i8', $tag], val_pay => ['i64', $pay]);
    for my $name (qw(val_def val_tag val_pay)) {
        my ($ty, $v) = $f{$name}->@*;
        my $g = $self->_fresh;
        $self->_emit("  $g = getelementptr inbounds %HashEntry, %HashEntry* $ent, i32 0, i32 "
            . _he_idx($name) . "  ; $what: $name");
        $self->_emit("  store $ty $v, $ty* $g  ; $what: $name");
    }
}

# _emit_hash_upsert($hash, $key_ptr, $key_len, $def, $tag, $pay): store a
# value at a key -- the entry with that key updated, or one added -- by a
# linear scan of the entries (an element store, and a hash built from pairs).
sub _emit_hash_upsert {
    my ($self, $hash_ref, $wkey_ref, $wkey_len, $wdef, $wtag, $wpay) = @_;
    my $cnt_ptr = $self->_fresh;
    my $ent_ptr = $self->_fresh;
    my $count   = $self->_fresh;
    my $ents    = $self->_fresh;
    $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 0  ; Assign(Hash-lvalue): count ptr");
    $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 2  ; Assign(Hash-lvalue): entries ptr");
    $self->_emit("  $count = load i64, i64* $cnt_ptr  ; Assign(Hash-lvalue): load count");
    $self->_emit("  $ents  = load %HashEntry*, %HashEntry** $ent_ptr  ; Assign(Hash-lvalue): load entries");

    my $lbl_wins  = $self->_fresh_label('hwins');
    my $lbl_wloop = $self->_fresh_label('hwalp');
    my $lbl_wchk  = $self->_fresh_label('hwchk');
    my $lbl_wcmp  = $self->_fresh_label('hwcmp');
    my $lbl_wupd  = $self->_fresh_label('hwupd');
    my $lbl_wnxt  = $self->_fresh_label('hwnxt');
    my $lbl_wend  = $self->_fresh_label('hwend');
    my $lbl_wpre  = $self->_current_block_label;
    my $wi_next   = $self->_fresh;

    $self->_set_terminator("  br label \%$lbl_wloop");
    $self->_new_block($lbl_wloop);
    my $wi_phi = $self->_fresh;
    $self->_emit("  $wi_phi = phi i64 [ 0, \%$lbl_wpre ], [ $wi_next, \%$lbl_wnxt ]  ; Assign(Hash-lvalue): loop counter");
    my $wcond = $self->_fresh;
    $self->_emit("  $wcond = icmp ult i64 $wi_phi, $count  ; Assign(Hash-lvalue): i < count?");
    $self->_set_terminator("  br i1 $wcond, label \%$lbl_wchk, label \%$lbl_wins");

    $self->_new_block($lbl_wchk);
    my $went_p   = $self->_fresh;
    my $went_kpp = $self->_fresh;
    my $went_klp = $self->_fresh;
    my $went_kp  = $self->_fresh;
    my $went_kl  = $self->_fresh;
    $self->_emit("  $went_p   = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $wi_phi  ; Assign(Hash-lvalue): entry ptr");
    $self->_emit("  $went_kpp = getelementptr inbounds %HashEntry, %HashEntry* $went_p, i32 0, i32 " . _he_idx('key_ptr') . "  ; Assign(Hash-lvalue): key_ptr field");
    $self->_emit("  $went_klp = getelementptr inbounds %HashEntry, %HashEntry* $went_p, i32 0, i32 " . _he_idx('key_len') . "  ; Assign(Hash-lvalue): key_len field");
    $self->_emit("  $went_kp  = load i8*,  i8**  $went_kpp  ; Assign(Hash-lvalue): entry key ptr");
    $self->_emit("  $went_kl  = load i64,  i64*  $went_klp  ; Assign(Hash-lvalue): entry key len");
    my $wlen_eq = $self->_fresh;
    $self->_emit("  $wlen_eq = icmp eq i64 $went_kl, $wkey_len  ; Assign(Hash-lvalue): len eq");
    $self->_set_terminator("  br i1 $wlen_eq, label \%$lbl_wcmp, label \%$lbl_wnxt");

    $self->_new_block($lbl_wcmp);
    my $wcmp_res  = $self->_fresh;
    my $wis_match = $self->_fresh;
    $self->_emit("  $wcmp_res  = call i32 \@memcmp(i8* nocapture readonly $went_kp, i8* nocapture readonly $wkey_ref, i64 $wkey_len)  ; Assign(Hash-lvalue): key memcmp");
    $self->_emit("  $wis_match = icmp eq i32 $wcmp_res, 0  ; Assign(Hash-lvalue): key match?");
    $self->_set_terminator("  br i1 $wis_match, label \%$lbl_wupd, label \%$lbl_wnxt");

    $self->_new_block($lbl_wupd);
    $self->_store_hash_value($went_p, $wdef, $wtag, $wpay, 'Assign(Hash-lvalue): update');
    $self->_set_terminator("  br label \%$lbl_wend");

    $self->_new_block($lbl_wnxt);
    $self->_emit("  $wi_next = add i64 $wi_phi, 1  ; Assign(Hash-lvalue): i++");
    $self->_set_terminator("  br label \%$lbl_wloop");

    # A KEY NOT THERE IS ADDED. The search used to fall through to the
    # end, and `$h->{b} = 2` on a hash without b stored nothing.
    $self->_new_block($lbl_wins);
    $self->_emit_hash_insert($hash_ref, $wkey_ref, $wkey_len, $wdef, $wtag, $wpay);
    $self->_set_terminator("  br label \%$lbl_wend");

    $self->_new_block($lbl_wend);
    return;
}

# _emit_hash_insert($hash, $key_ptr, $key_len, $def, $tag, $pay): append a
# key the hash does not have, growing its entries when full -- malloc and
# memcpy, doubling from a floor of 4, as an array append grows.
sub _emit_hash_insert {
    my ($self, $hash, $kp, $kl, $def, $tag, $pay) = @_;
    $self->{_need_malloc_memcpy} = 1;
    my ($cntp, $capp, $entp, $cnt, $cap, $full) = map { $self->_fresh } 1 .. 6;
    $self->_emit("  $cntp = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 0  ; insert: count ptr");
    $self->_emit("  $capp = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 1  ; insert: cap ptr");
    $self->_emit("  $entp = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 2  ; insert: entries ptr");
    $self->_emit("  $cnt = load i64, i64* $cntp  ; insert: count");
    $self->_emit("  $cap = load i64, i64* $capp  ; insert: cap");
    $self->_emit("  $full = icmp sge i64 $cnt, $cap  ; insert: full?");
    my ($grow, $put) = ($self->_fresh_label('hins.grow.'), $self->_fresh_label('hins.put.'));
    $self->_set_terminator("  br i1 $full, label %$grow, label %$put");

    $self->_new_block($grow);
    my $esz = _sizeof_llvm_type('%HashEntry');
    my ($dbl, $small, $newcap, $nb, $buf, $old, $oldraw, $ob, $new) = map { $self->_fresh } 1 .. 9;
    $self->_emit("  $dbl = mul i64 $cap, 2  ; insert: doubled cap");
    $self->_emit("  $small = icmp slt i64 $dbl, 4");
    $self->_emit("  $newcap = select i1 $small, i64 4, i64 $dbl  ; insert: new cap (floor 4)");
    $self->_emit("  $nb = mul i64 $newcap, $esz");
    $self->_emit("  $buf = call i8* \@malloc(i64 $nb)  ; insert: grown entries");
    $self->_emit("  $old = load %HashEntry*, %HashEntry** $entp");
    $self->_emit("  $oldraw = bitcast %HashEntry* $old to i8*");
    $self->_emit("  $ob = mul i64 $cnt, $esz");
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $oldraw, i64 $ob)  ; insert: copy live entries");
    $self->_emit("  $new = bitcast i8* $buf to %HashEntry*");
    $self->_emit("  store %HashEntry* $new, %HashEntry** $entp");
    $self->_emit("  store i64 $newcap, i64* $capp");
    $self->_set_terminator("  br label %$put");

    # Re-read the entries: the grow path replaced them.
    $self->_new_block($put);
    my ($ents, $e, $c1) = map { $self->_fresh } 1 .. 3;
    $self->_emit("  $ents = load %HashEntry*, %HashEntry** $entp  ; insert: entries (post-grow)");
    $self->_emit("  $e = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $cnt  ; insert: new entry");
    my %k = (key_ptr => ['i8*', $kp], key_len => ['i64', $kl], key_enc => ['i32', '0']);
    for my $name (qw(key_ptr key_len key_enc)) {
        my ($ty, $v) = $k{$name}->@*;
        my $g = $self->_fresh;
        $self->_emit("  $g = getelementptr inbounds %HashEntry, %HashEntry* $e, i32 0, i32 " . _he_idx($name));
        $self->_emit("  store $ty $v, $ty* $g  ; insert: $name");
    }
    $self->_store_hash_value($e, $def, $tag, $pay, 'insert');
    $self->_emit("  $c1 = add i64 $cnt, 1");
    $self->_emit("  store i64 $c1, i64* $cntp  ; insert: count + 1");
}

# _lower_call_indirect($node): `$cb->(...)` where $cb is, through the
# arguments inlining bound, a code reference made in this program (an
# AnonSub): a direct call of its sub. Anything else is refused by name.
sub _lower_call_indirect {
    my ($self, $node) = @_;
    my ($callee, @args) = $node->inputs->@*;
    pop @args if $node->can('memory_input') && $node->memory_input;
    # A CALL THROUGH `\&name` runs that sub, which Analysis resolved.
    if (blessed($callee) && $callee->operation eq 'Ref' && blessed($node->target)) {
        my ($code) = $callee->inputs->@*;
        $self->{_call_via} = { name => $code->value, target => $node->target, args => \@args };
        return $self->_lower_call_direct($node);
    }
    my $anon = $self->_static_code_of($callee);
    die "GAP: an indirect call whose code is not a sub this program makes and passes down "
      . "is not lowered\n" unless $anon && $anon->sub;
    $self->{_call_via} = { name => $anon->name, target => $anon->sub, args => \@args, anon => $anon };
    return $self->_lower_call_direct($node);
}

# _static_code_of($node) -> the AnonSub a value is, through the arguments
# inlining bound, or undef.
sub _static_code_of {
    my ($self, $n) = @_;
    for (1 .. 32) {
        return undef unless blessed($n);
        return $n if $n->operation eq 'AnonSub';
        my $b = $self->{_arg_bind} ? $self->{_arg_bind}{ refaddr($n) } : undef;
        return undef unless $b && blessed($b->{node});
        $n = $b->{node};
    }
    return undef;
}

# _bind_captures($graph, $name, $anon): bind each CellRead in a closure's
# graph to a load of the variable its cell holds -- the location of that
# name in the frame that made it, found through the cell's memory version.
# A closure that writes a capture, or one whose cells are not known, is
# refused.
sub _bind_captures {
    my ($self, $graph, $name, $anon) = @_;
    my @reads = grep { blessed($_) && $_->operation eq 'CellRead' } _graph_component($graph);
    my @writes = grep { blessed($_) && $_->operation eq 'CellWrite' } _graph_component($graph);
    # A CELL USED BUT THROUGH A CELL READ OR WRITE is a shape not known here:
    # B::SoN spells `$t += 1` on a capture as Coerce(CellParam) + 1 -- the
    # cell's reference read as a number, and no write. Lowered, $t never
    # changed (silently wrong).
    for my $p (grep { blessed($_) && $_->operation eq 'CellParam' } _graph_component($graph)) {
        die "GAP: a closure ('$name') uses what it captured other than by reading or "
          . "writing it (an op-assign to a capture) -- not lowered\n"
            if grep { blessed($_) && $_->operation !~ /\A(?:CellRead|CellWrite|MakeCell)\z/ }
                    ($p->consumers // [])->@*;
    }
    return unless @reads || @writes;
    die "GAP: a closure ('$name') that writes what it captured is not lowered\n" if @writes;
    my $via_anon = defined $anon;
    $anon //= $ANON_SUBS{$name};
    die "GAP: a closure ('$name') whose cells are not known here is not lowered\n" unless blessed($anon);
    my @cells = grep { blessed($_) } $anon->inputs->@*;
    for my $r (@reads) {
        my $param = $r->inputs->[0];
        my $cell  = blessed($param) && $param->can('index') ? $cells[ $param->index ] : undef;
        my $var   = $cell ? _cell_variable($cell) : undef;
        die "GAP: a closure ('$name') capture whose variable is not a location here is not lowered\n"
            unless $var;
        # PASSED DOWN, its cells are where the frame that made it said
        # (_arg_binding); called directly by B::SoN, it is called in that frame.
        my $ptr = $via_anon ? $self->{_cell_slots}{ refaddr($cell) } : $self->_location_ptr($var);
        die "GAP: a closure ('$name') passed down whose cells were not found where it was made\n"
            unless defined $ptr;
        my $slot = $self->_fresh;
        $self->_emit("  $slot = load %Slot, %Slot* $ptr  ; closure: " . $var->name);
        $self->{_arg_bind}{ refaddr($r) } = { ref => $slot, repr => 'Scalar', node => $var };
    }
    return;
}

# _cell_storage($cell) -> the %Slot* a MakeCell's variable lives in: its
# location. Refused when it is not one.
sub _cell_storage {
    my ($self, $cell) = @_;
    my $var = blessed($cell) && $cell->operation eq 'MakeCell' ? _cell_variable($cell) : undef;
    die "GAP: a captured variable that is not a location here is not lowered\n" unless $var;
    return $self->_location_ptr($var);   # this frame's: each inline of the maker has its own
}

# _cell_variable($cell) -> the location a MakeCell holds: the variable of its
# name stored at the memory version it was made at.
sub _cell_variable {
    my ($cell) = @_;
    my $want = $cell->can('cell_name') ? ( $cell->cell_name // '' ) : '';
    my $mem = $cell->inputs->[1];
    for (1 .. 64) {
        return undef unless blessed($mem);
        my $v = $mem->inputs->[0];
        return $v if blessed($v) && $v->operation eq 'PadAccess' && $v->is_location && $v->name eq $want;
        return undef unless $mem->operation =~ /\A(?:Assign|EntryWrite|Call)\z/;
        ($mem) = grep { blessed($_) && $_->operation ne 'Constant' } reverse $mem->inputs->@*;
    }
    return undef;
}

# _arg_binding($arg, $ref) -> what a callee's argument read is bound to. An
# argument that is itself an inlined parameter holding a reference (an
# object handed on: `sub f { my ($n) = @_; $n->val }`) passes the reference
# on as it is -- its own lowering boxed it to the parameter's Scalar.
sub _arg_binding {
    my ($self, $arg, $ref) = @_;
    if ($arg->operation eq 'AnonSub') {
        # ITS CELLS ARE FOUND HERE, in the frame that made it: the callee's
        # frame has its own `my` locations, and a capture read there found a
        # fresh, empty one.
        $self->{_cell_slots}{ refaddr($_) } = $self->_cell_storage($_)
            for grep { blessed($_) && $_->operation eq 'MakeCell' } $arg->inputs->@*;
        return { ref => undef, repr => 'CodeRef', node => $arg };
    }
    my $rep = $self->_repr_of($arg) // '';
    my $raw = $self->_bound_ref($arg);
    return { ref => $raw, repr => $rep, node => $arg } if $rep =~ /Ref\z/ && defined $raw;
    # A VARIABLE KEPT IN MEMORY: its location, taken here in the caller's
    # frame, for a `\$_[N]` in the callee (_lower_ref).
    my $loc = $arg->operation eq 'PadAccess' && ( $arg->sigil // '$' ) eq '$'
              && ( $arg->shared || $arg->is_location ) ? $self->_location_ptr($arg) : undef;
    return { ref => $ref, repr => $arg->stamp, node => $arg, loc => $loc };
}

# _static_class_of($node) -> the class a value is an object of, where that is
# static: a `C->new(...)` of a package (whose sub blesses it), a bless into
# a literal class, or an inlined argument bound to one of those. Else undef.
sub _static_class_of {
    my ($self, $n) = @_;
    for (1 .. 32) {
        return undef unless blessed($n);
        my $b = $self->{_arg_bind} ? $self->{_arg_bind}{ refaddr($n) } : undef;
        if ($b && blessed($b->{node})) { $n = $b->{node}; next }
        last;
    }
    return undef unless blessed($n) && $n->operation eq 'Call';
    my $kind = $n->dispatch_kind // '';
    return $n->class_name
        if $kind eq 'method' && ($n->name // '') eq 'new' && defined $n->class_name
        && blessed($n->target) && $n->target->isa('Chalk::MOP::Sub');
    if ($kind eq 'builtin' && ($n->name // '') eq 'bless') {
        my $c = $n->inputs->[1];
        return $c->value if blessed($c) && $c->operation eq 'Constant' && ($c->const_type // '') eq 'string';
    }
    return undef;
}

# _repr_of($node) / _bound_ref($node): a node an inlined call binds to the
# caller's value (an argument) reads as THAT value's repr. A callee's `my
# ($h) = @_` is stamped Unknown, and the HashRef it holds was refused as a
# container: an element store through a reference a sub is handed.
sub _repr_of {
    my ($self, $n) = @_;
    return $self->{cache}{ 'repr:' . $n->id } if blessed($n) && exists $self->{cache}{ 'repr:' . $n->id };
    my $b = $self->{_arg_bind} && blessed($n) ? $self->{_arg_bind}{ refaddr($n) } : undef;
    # The caller's repr only where lower_value serves the caller's value as
    # it is -- a callee node nothing typed, or one used as a container; one
    # with a reading of its own is coerced to it (lower_value).
    return $b && $b->{repr} && ( ($n->stamp // 'Unknown') eq 'Unknown'
                                 || $b->{repr} =~ /Ref\z/ )
        ? $b->{repr} : $n->stamp;
}
sub _bound_ref {
    my ($self, $n) = @_;
    my $b = $self->{_arg_bind} && blessed($n) ? $self->{_arg_bind}{ refaddr($n) } : undef;
    return $b ? $b->{ref} : undef;
}

# _unwrap_ref_container($container) -> the aliased target of a `\` reference.
#
# `my $r = \@a` builds a Ref node wrapping the @a ArrayRef; in Perl \@a and @a
# share backing storage, so a store/read through the Ref must resolve to the
# SAME aggregate as the ArrayRef it wraps. The Ref node carries no repr of its
# own (it is a transparent alias), so we unwrap it to its input container. This
# is a no-op for every non-Ref container.
sub _unwrap_ref_container {
    my ($self, $container) = @_;
    return $container unless defined $container
        && $container->operation eq 'Ref';
    return $container->inputs->[0];
}

# _container_ptr($container, $kind) -> typed aggregate pointer (%Array*/%Hash*)
#
# Resolves the container's typed pointer AT THE CURRENT PROGRAM POINT:
# lower_value gives the container's value here (Family-B re-lowers
# mutable-read containers, so a reassigned ref variable yields the NEW
# aggregate's i8*), and Ref-repr containers are bitcast at the use. The old
# _arr_table/_hash_table memoized the bitcast per NODE ID, populated once
# and never invalidated — after a ref reassign every later subscript served
# the OLD aggregate's pointer (019eb6ff item 3). A bitcast is a free no-op
# cast; emitting one per use is always dominance-correct.
sub _container_ptr {
    my ($self, $container, $kind, %opt) = @_;
    $container = $self->_unwrap_ref_container($container);
    my $repr = $self->_repr_of($container) // '';
    my $v = $self->_bound_ref($container) // $self->lower_value($container);
    # A VALUE READ BY ITS TAG holding the reference (a shared lexical, a
    # merge): its payload, when the tag says so. Anything else -- undef,
    # which perl would autovivify, or another kind -- exits 255.
    #
    # A STORE AUTOVIVIFIES (opt autoviv): an undef where its value came from
    # can be written -- a variable kept in memory, an element -- becomes a
    # new aggregate there, as perl makes one. Undef anywhere else (a copy, a
    # call's value) still exits: there is nowhere to put it.
    if ($repr =~ /\A(?:Scalar|Slot)\z/ && defined $kind && $kind =~ /\A(?:Array|Hash)\z/) {
        # A READ THROUGH A REFERENCE STILL TO BE MADE (_freeze_memory_reads left
        # it where it is used) may be of this aggregate, and would then read
        # this store: `my $s = $info->{n}; f($info)` where f stores through it
        # (pvm 233 read "z" for "x").
        die "GAP: a store through a reference while a read through a reference waits to be "
          . "made -- it may read the same aggregate, after this store\n"
            if $opt{autoviv} && grep { !exists $self->{cache}{ $_->id } } values %{ $self->{_pending_tag_reads} // {} };
        my $tag = $self->_slot_tag_of($v);
        my ($ok, $typed) = ($self->_fresh, $self->_fresh);
        my ($yes, $no) = ($self->_fresh_label('cref.ok.'), $self->_fresh_label('cref.no.'));
        $self->_emit("  $ok = icmp eq i8 $tag, " . _slot_tag_value("${kind}Ref") . "  ; a ${kind} reference?");
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $ok, label %$yes, label %$no");
        $self->_new_block($no);
        my (@made, $join);
        if ($opt{autoviv} && $self->_autoviv_target($container)) {
            my ($viv, $bad) = ($self->_fresh_label('cref.viv.'), $self->_fresh_label('cref.bad.'));
            $self->_set_terminator("  br i1 " . $self->_slot_defined_bit($v) . ", label %$bad, label %$viv");
            $self->_new_block($viv);
            my $new = $kind eq 'Array' ? $self->_emit_array_of([]) : $self->_emit_empty_hash('autovivified');
            my ($raw, $s0, $s1, $s2) = map { $self->_fresh } 1 .. 4;
            $self->_emit("  $raw = ptrtoint %${kind}* $new to i64  ; autovivified");
            $self->_emit("  $s0 = insertvalue %Slot undef, i1 true, " . _slot_idx('defined'));
            $self->_emit("  $s1 = insertvalue %Slot $s0, i8 " . _slot_tag_value("${kind}Ref") . ", " . _slot_idx('tag'));
            $self->_emit("  $s2 = insertvalue %Slot $s1, i64 $raw, " . _slot_idx('payload'));
            $self->_autoviv_store($container, $s2, $raw, $kind);
            push @made, [ $new, $self->_current_block_label ];
            $join = $self->_fresh_label('cref.join.');
            $self->_set_terminator("  br label %$join");
            $self->_new_block($bad);
        }
        $self->_refuse_inside_eval("an element read through what is not a ${kind} reference");
        $self->_emit("  call void \@exit(i32 255)  ; not a ${kind} reference");
        $self->_set_terminator("  unreachable");
        $self->_new_block($yes);
        my $pl = $self->_slot_payload_of($v);
        $self->_emit("  $typed = inttoptr i64 $pl to %${kind}*  ; Scalar -> %${kind}*");
        return $typed unless @made;
        my $merged = $self->_fresh;
        push @made, [ $typed, $self->_current_block_label ];
        $self->_set_terminator("  br label %$join");
        $self->_new_block($join);
        $self->_emit("  $merged = phi %${kind}* " . join(', ', map { "[ $_->[0], %$_->[1] ]" } @made));
        return $merged;
    }
    return $v unless $repr eq "${kind}Ref";   # unboxed %Array*/%Hash* already
    my $typed = $self->_fresh;
    $self->_emit("  $typed = bitcast i8* $v to %${kind}*  ; ${kind}Ref -> ${kind}* (at use)");
    return $typed;
}

# _emit_empty_hash($what) -> %Hash*: no entries, grown on insert.
sub _emit_empty_hash {
    my ($self, $what) = @_;
    my ($hb, $hash) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $hb = call i8* \@malloc(i64 " . _sizeof_llvm_type('%Hash') . ")  ; $what: hash header");
    $self->_emit("  $hash = bitcast i8* $hb to %Hash*");
    $self->_emit("  store %Hash zeroinitializer, %Hash* $hash  ; $what: empty");
    return $hash;
}

# _autoviv_target($container) -> true when an undef read from $container can
# be replaced where it came from: a variable kept in memory, or an element of
# an array or a hash.
sub _autoviv_target {
    my ($self, $c) = @_;
    return 0 if defined $self->_bound_ref($c);   # an argument: the caller's value, copied
    return 1 if $c->operation eq 'PadAccess' && ( $c->sigil // '$' ) eq '$' && ( $c->shared || $c->is_location );
    return 0 unless $c->operation eq 'Subscript' && ( $c->can('kind') ? $c->kind // '' : '' ) =~ /\A(?:array|hash)\z/;
    return ( $self->_repr_of( $self->_unwrap_ref_container($c->inputs->[0]) ) // '' )
        =~ /\A(?:Array|ArrayRef|Hash|HashRef|Scalar|Slot)\z/ ? 1 : 0;
}

# _autoviv_store($container, $slot, $raw, $kind): write the new reference
# where $container's undef was read from (_autoviv_target).
sub _autoviv_store {
    my ($self, $c, $slot, $raw, $kind) = @_;
    if ($c->operation eq 'PadAccess') {
        $self->_emit("  store %Slot $slot, %Slot* " . $self->_location_ptr($c) . "  ; autovivified into " . $c->name);
        return;
    }
    my ($inner, $key) = $c->inputs->@[0, 1];
    if ($c->kind eq 'array') {
        my $arr = $self->_container_ptr($inner, 'Array', autoviv => 1);
        my $i   = $self->_emit_array_extend_to($arr, $self->_index_i64($key));
        my ($ep, $els, $sp) = map { $self->_fresh } 1 .. 3;
        $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2");
        $self->_emit("  $els = load %Slot*, %Slot** $ep");
        $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $els, i64 $i");
        $self->_emit("  store %Slot $slot, %Slot* $sp  ; autovivified into the element");
        return;
    }
    my $hash = $self->_container_ptr($inner, 'Hash', autoviv => 1);
    my ($kp, $kl) = $self->_str_parts($self->_hash_key_str($key));
    $self->_emit_hash_upsert($hash, $kp, $kl, 'true', _slot_tag_value("${kind}Ref"), $raw);
    return;
}

# _lower_subscript: repr-dispatch on inputs[0] container.
# Array container -> bounds-checked slot load (_lower_array_read body).
# Hash container  -> memcmp key scan (_lower_hash_read body).
# inputs[0] = container (Array or Hash), inputs[1] = index (Int) or key (Str).
sub _lower_subscript {
    my ($self, $node) = @_;

    # Memory-SSA: an element read whose memory version depends on a store under a
    # control region needs a memory-Phi at the merge (phase 2b). When the read's
    # memory input IS a proper memory-Phi over a Region (the handled 2b shape), the
    # store is control-dependent on the branch (emitted only when taken) and the
    # read loads the merged heap post-Region -- lower it normally. Otherwise (a
    # branch-guarded store with no memory-Phi reaching this read -- an unhandled
    # shape) GAP loudly rather than mislower to the wrong (pre-store) value.
    my $mem = $node->inputs->[2];
    my $mem_is_phi = defined $mem && $mem->operation eq 'Phi';
    if (defined $mem && !$mem_is_phi && $self->_has_branch_guarded_store) {
        die "GAP: element read across a branch-guarded store needs a memory-Phi "
          . "(memory-SSA phase 2b, zhi 019f33f6) -- refusing to mislower.";
    }

    # Unwrap a Ref container (`$r->[0]` as an rvalue, where $r=\@a) to its aliased
    # target ArrayRef/HashRef, mirroring the store-lvalue path and _container_ptr
    # (memory-SSA phase 2d). A Ref carries no repr of its own, so without this the
    # repr dispatch below would GAP on it; _lower_array_read/_lower_hash_read then
    # resolve the shared aggregate via _container_ptr (which also unwraps).
    my $container = $self->_unwrap_ref_container($node->inputs->[0]);
    my $container_repr = $self->_repr_of($container)
        // _require_repr($container, 'Subscript.container');
    $container_repr = 'Array' if $container_repr eq 'List' && _is_walked_list($container);   # the list made once
    # A container read by its tag: the read says which kind it is.
    if ($container_repr =~ /\A(?:Scalar|Slot)\z/ && ($node->can('kind') ? $node->kind // '' : '') =~ /\A(array|hash)\z/) {
        $container_repr = $1 eq 'array' ? 'ArrayRef' : 'HashRef';
    }

    if ($container_repr eq 'Array' || $container_repr eq 'ArrayRef') {
        return $self->_lower_array_read($node);
    }
    elsif ($container_repr eq 'Hash' || $container_repr eq 'HashRef') {
        return $self->_lower_hash_read($node);
    }
    else {
        die "GAP: Subscript container has repr=$container_repr; only Array/ArrayRef and Hash/HashRef are lowered runtime-free.";
    }
}

# _lower_array_read: bounds-checked element read.
# inputs = [Array, index :Int]. repr=Int: extract payload (in-bounds known).
# repr=Slot: return an alloca {i1,i64} — defined=true if in-bounds, false if OOB.
# The bounds-check is ALWAYS emitted (soundness). For repr=Int, the OOB path
# stores undefined into the payload (unreachable for valid in-bounds indices).
sub _lower_array_read {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;

    my $container = $node->inputs->[0];
    # Typed pointer resolved at THIS use (re-lowered for mutable-read
    # containers; bitcast for Ref reprs) — see _container_ptr.
    my $arr_ref = $self->_container_ptr($container, 'Array');
    my $idx_ref = $self->_index_i64($node->inputs->[1]);
    my $repr    = _require_repr($node, 'ArrayRead');

    # Load len and elems pointer from the Array struct.
    my $len_ptr  = $self->_fresh;
    my $elem_ptr = $self->_fresh;
    my $len      = $self->_fresh;
    my $elems    = $self->_fresh;
    $self->_emit("  $len_ptr  = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 0  ; ArrayRead: len ptr");
    $self->_emit("  $elem_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 2  ; ArrayRead: elems ptr");
    $self->_emit("  $len   = load i64, i64* $len_ptr   ; ArrayRead: load len");
    $self->_emit("  $elems = load %Slot*, %Slot** $elem_ptr  ; ArrayRead: load elems");

    # Apply perl's from-the-end adjustment: idx < 0 ? idx + len : idx. The
    # bounds check below is unsigned (icmp ult), so a still-negative adjusted
    # index (a negative OOB read, idx < -len) stays huge-unsigned and correctly
    # fails the check, landing on the OOB path -- no separate guard needed.
    my $is_neg = $self->_fresh;
    my $adj_neg = $self->_fresh;
    my $idx = $self->_fresh;
    $self->_emit("  $is_neg  = icmp slt i64 $idx_ref, 0  ; ArrayRead: index is negative?");
    $self->_emit("  $adj_neg = add i64 $idx_ref, $len     ; ArrayRead: from-the-end (idx + len)");
    $self->_emit("  $idx = select i1 $is_neg, i64 $adj_neg, i64 $idx_ref  ; ArrayRead: adjusted index");

    # Emit bounds-check: in_bounds = (idx < len).
    my $ok    = $self->_fresh;
    my $lbl_inb = $self->_fresh_label('arr_inb');
    my $lbl_oob = $self->_fresh_label('arr_oob');
    my $lbl_end = $self->_fresh_label('arr_end');
    $self->_emit("  $ok = icmp ult i64 $idx, $len  ; ArrayRead: bounds check (idx < len)");
    $self->_set_terminator("  br i1 $ok, label \%$lbl_inb, label \%$lbl_oob");
    $self->_new_block($lbl_inb);

    # In-bounds: load the WHOLE slot at elems[idx].
    #
    # One aggregate load, not a GEP+load per field. The Slot-repr merge below
    # is a single `phi %Slot`, so this arm has to supply a COMPLETE Slot --
    # tag included. Phi'ing the fields separately and reassembling in the
    # merge block would drop the STORED tag and substitute one derived from
    # this node's own repr, which is exactly the guess the tag exists to
    # remove. The narrow arms (Int/Num/Str/ptr) want only the payload, and
    # `extractvalue` off this same load gives it to them.
    my $slot_p   = $self->_fresh;
    my $slot_all = $self->_fresh;
    my $pay_val  = $self->_fresh;
    $self->_emit("  $slot_p   = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx  ; ArrayRead: slot ptr");
    $self->_emit("  $slot_all = load %Slot, %Slot* $slot_p  ; ArrayRead: load whole slot");
    $self->_emit("  $pay_val  = extractvalue %Slot $slot_all, " . _slot_idx('payload') . "  ; ArrayRead: payload");
    $self->_set_terminator("  br label \%$lbl_end");

    $self->_new_block($lbl_oob);
    # OOB: an EXPLICIT undef slot -- defined=false, tag=Undef, payload=0 --
    # built here in the arm block so the phi's incoming value is a complete
    # aggregate rather than a poison one with two fields patched in. Tag is
    # 'Undef', not 'Opaque': defined=false means the reading IS established.
    my $slot_oob = $self->_build_slot('false', '0', 'Undef', 'ArrayRead OOB');
    $self->_set_terminator("  br label \%$lbl_end");

    # ONE Slot phi, then this read's reading of it, by the STORED tag --
    # as a hash read does. Decoded by the read's stamp instead, an element
    # past the end read as an Int was 0, defined; as a Str it loaded through a
    # null %Str*; stamped Undef it was a Slot where its defined bit belonged.
    $self->_new_block($lbl_end);
    my $slot = $self->_fresh;
    $self->_emit("  $slot = phi %Slot [ $slot_all, \%$lbl_inb ], [ $slot_oob, \%$lbl_oob ]  ; ArrayRead :Slot phi");
    my $result = $self->_slot_as_reading($slot, $repr, 'ArrayRead');
    $self->{cache}{ $node->id } = $result;
    return $result;
}

# _load_array_header($array, $tag) -> ($arr_ref, $len_ptr, $elem_ptr, $len, $elems)
# Resolve the typed %Array* (at this use, via _container_ptr) and load the len
# and elems fields plus their pointers. The $tag labels the emitted comments.
# The len/elems POINTERS are returned so a mutating caller (shift/pop) can store
# an updated header back through them.
# _seed_container_repr($array): give an ArrayRef literal its container repr when
# nothing upstream committed one.
#
# _container_ptr resolves the container pointer through the repr, and the array
# often has none: `while (shift @q) { ... }` drains a queue whose value nobody
# reads, so no inference pass ever types it. An ArrayRef literal is always the
# ArrayRef repr (a boxed aggregate pointer), so the backend can supply it.
#
# UNCOMMITTED IS NOT THE SAME AS UNDEF. `Unknown` is how the producer says it
# could not type a value; it is a present answer that answers nothing. The guard
# below therefore asks whether the array COMMITTED to a repr, not whether one is
# defined -- the same distinction the loader's guards make via _is_narrowed
# (Chalk::IR::Serialize::JSON, commit d3053a2a). Spelled inline rather than
# imported: the backend does not otherwise depend on the deserializer, and one
# clause is not worth inverting that.
#
# Slice 3b of docs/plans/2026-08-24-loader-analysis-pipeline.md is what makes
# this live -- it stops dropping `Unknown` at the wire-stamp seed, so an
# ArrayRef node starts arriving with one. Under a `defined` guard the seed would
# be skipped and _container_ptr would resolve against a repr that names no
# container.
#
# The seed is a FALLBACK, never an override: a committed repr survives, since
# `Array` and `ArrayRef` take different container-pointer paths.
sub _seed_container_repr ($array) {
    my $repr = $array->stamp;
    return if defined $repr && $repr ne 'Unknown';
    return unless $array->operation eq 'ArrayLiteral';
    $array->set_stamp('ArrayRef');
    return;
}

sub _load_array_header {
    my ($self, $array, $tag) = @_;
    $self->{_need_aggregate_types} = 1;
    my $arr_ref  = $self->_container_ptr($array, 'Array');
    my $len_ptr  = $self->_fresh;
    my $elem_ptr = $self->_fresh;
    my $len      = $self->_fresh;
    my $elems    = $self->_fresh;
    $self->_emit("  $len_ptr  = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 0  ; $tag: len ptr");
    $self->_emit("  $elem_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 2  ; $tag: elems ptr");
    $self->_emit("  $len   = load i64, i64* $len_ptr    ; $tag: load len");
    $self->_emit("  $elems = load %Slot*, %Slot** $elem_ptr  ; $tag: load elems");
    return ($arr_ref, $len_ptr, $elem_ptr, $len, $elems);
}

# _lower_builtin_shift_pop: remove and return an element from a mutable %Array.
#   pop @a   -> return slot[len-1].payload, then len := len-1
#   shift @a -> return slot[0].payload, then elems := elems+1, len := len-1
# The shift front-drop advances the elems pointer by one slot (O(1), no memmove)
# and the header's len is decremented -- a later read/Length re-loads elems+len
# from the header (via _container_ptr) and observes the drained array. An empty
# array (len == 0) yields undef: represented as its defined-bit (i1 false) with a
# 0 payload, matching the ArrayRead Slot convention. Int elements only for now;
# other element reprs GAP loudly.
#
# inputs[0] is the array operand (or, when threaded as a statement effect, the
# control leads and the array is inputs[1]); resolve it by repr, not position.
# _lower_builtin_sort($node) -> $llvm_ref (an %Array* of %Slot)
#
# perl FOLDS the standard comparators into flags on the sort op, so the block
# is gone by the time a producer sees it and what remains is the DECISION.
# Without sort_cmp/sort_order three different programs are one node:
#
#   sort { $a <=> $b } (3,1,2)   perl 1
#   sort { $b <=> $a } (3,1,2)   perl 3
#   sort (3,1,2)                 perl 1   -- STRING compare, not numeric
#
# Bare `sort` defaulting to a string compare is the case that breaks ordinary
# code, not an edge case: `sort (10, 9, 100)` is `10 100 9`.
#
# The sort is an INSERTION SORT over the %Slot buffer -- O(n^2), chosen
# because the corpus sorts hash keys (2-3 elements) and a correct simple
# algorithm beats a fast one this file cannot yet test at scale. The
# comparator is the only interesting part; swapping in a better algorithm
# later changes no caller.
#
# A COPY, not in place: perl's `sort` returns a new list and leaves its
# operand alone, so sorting the operand's buffer would corrupt an array the
# program can still read.
sub _lower_builtin_sort {
    my ($self, $node) = @_;
    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;
    # The string-compare arm below emits `call @memcmp`, so the declaration is
    # this function's own requirement. It was missing and latent: the only sort
    # shape that reached lowering was `sort keys %h`, whose hash lowering sets
    # the flag on the way past. A bare `sort (10,9,100)` -- string compare over
    # a flattened literal list, touching no hash -- emitted the call with no
    # `declare`, and lli refused the module ("use of undefined value '@memcmp'").
    $self->{_need_memcmp}          = 1;

    my @elems = grep { blessed($_) } $node->inputs->@*;
    # The MEMORY version the sort reads at rides as its last input; it is
    # not an element (it was taken for one: "sort element[1] ... NO
    # representation").
    pop @elems if $node->can('memory_input') && $node->memory_input;
    die "GAP: sort expects a list operand." unless @elems;
    my $operand = $elems[0];

    my $cmp   = $node->can('sort_cmp')   ? $node->sort_cmp   : undef;
    my $order = $node->can('sort_order') ? $node->sort_order : undef;
    my $custom = !defined $cmp && $node->can('sort_cmp_sub') && blessed($node->sort_cmp_sub)
        ? $node->sort_cmp_sub : undef;
    die "GAP: sort with no folded comparator — the producer states sort_cmp "
      . "(numeric|string) and sort_order (ascending|descending); without them "
      . "`sort {\$a<=>\$b}`, `sort {\$b<=>\$a}` and a bare string `sort` are "
      . "one node and lowering would have to guess which."
        unless $custom || ( defined $cmp && defined $order );
    die "GAP: sort with a custom comparator block is not lowered (only perl's "
      . "FOLDED numeric/string comparators are); got sort_cmp='$cmp'."
        unless $custom || $cmp eq 'numeric' || $cmp eq 'string';

    my $op_repr = $operand isa Chalk::IR::Node ? ($operand->stamp // '') : '';

    # TWO OPERAND SHAPES REACH HERE, and the difference is perl's, not ours.
    # `sort keys %h` passes ONE aggregate (the keys Call, stamped List and
    # rescued to Array by the loader), while `sort {$a<=>$b} (3,1,2)` FLATTENS
    # the literal list into three scalar argument slots -- measured on the wire
    # for both, and the flattening also happens when the list is named
    # (`my @a=(3,1,2); sort @a` folds to the same three Constants).
    #
    # So a single-input aggregate is sorted where it already lives; N scalars
    # are materialised into an %Array first. Sorting reads a %Slot buffer and
    # nothing else, so once the elements are in one the two shapes converge.
    #
    # The COPY below still applies to the aggregate shape: perl's sort does not
    # mutate its operand. A buffer built here is already private, but copying it
    # too costs one memcpy and keeps a single path.
    my $src;
    if (@elems == 1 && ($op_repr eq 'Array' || $op_repr eq 'ArrayRef')) {
        $src = $self->_container_ptr($operand, 'Array');
    }
    else {
        # Every element must be typed: _emit_array_of tags each slot from the
        # element's own repr, and an untyped one would be boxed as a guess.
        # Each element is boxed with its own tag; the comparator reads it
        # by that tag (_emit_slot_out_of_order), so a string sort of numbers
        # stringifies them as perl does.
        _require_repr($elems[$_], "sort element[$_]") for 0 .. $#elems;
        $src = $self->_emit_array_of(\@elems);
    }

    # len/data of the source
    my ($slen_p, $slen, $sdat_p, $sdat) =
        ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $slen_p = getelementptr inbounds %Array, %Array* $src, i32 0, i32 0  ; sort: src len ptr");
    $self->_emit("  $slen = load i64, i64* $slen_p  ; sort: element count");
    $self->_emit("  $sdat_p = getelementptr inbounds %Array, %Array* $src, i32 0, i32 2  ; sort: src data ptr");
    $self->_emit("  $sdat = load %Slot*, %Slot** $sdat_p  ; sort: src slots");

    # Copy the buffer, then order the copy.
    my ($bytes, $raw, $slots) = ($self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $bytes = mul i64 $slen, " . _sizeof_llvm_type('%Slot') . "  ; sort: buffer bytes");
    $self->_emit("  $raw = call i8* \@malloc(i64 $bytes)  ; sort: alloc result buffer");
    $self->_emit("  $slots = bitcast i8* $raw to %Slot*  ; sort: result slots");
    my $src_i8 = $self->_fresh;
    $self->_emit("  $src_i8 = bitcast %Slot* $sdat to i8*  ; sort: src as bytes");
    $self->_emit("  call i8* \@memcpy(i8* $raw, i8* $src_i8, i64 $bytes)  ; sort: copy (perl's sort does not mutate its operand)");

    my ($arr_raw, $arr) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $arr_raw = call i8* \@malloc(i64 " . _sizeof_llvm_type('%Array') . ")  ; sort: alloc %Array header");
    $self->_emit("  $arr = bitcast i8* $arr_raw to %Array*  ; sort: %Array ptr");
    my ($alen, $acap, $adat) = ($self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $alen = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; sort: len ptr");
    $self->_emit("  $acap = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 1  ; sort: cap ptr");
    $self->_emit("  $adat = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; sort: data ptr");
    $self->_emit("  store i64 $slen, i64* $alen  ; sort: len");
    $self->_emit("  store i64 $slen, i64* $acap  ; sort: cap");
    $self->_emit("  store %Slot* $slots, %Slot** $adat  ; sort: data");

    # Insertion sort: for i in 1..len-1, bubble slot[i] down while it is out
    # of order against its predecessor.
    my $n = $self->_fresh_label('sort');
    my ($l_ohdr, $l_obody, $l_ihdr, $l_ibody, $l_swap, $l_inext, $l_onext, $l_end) =
        ("${n}_ohdr", "${n}_obody", "${n}_ihdr", "${n}_ibody",
         "${n}_swap", "${n}_inext", "${n}_onext", "${n}_end");

    my ($i_phi, $i_next, $j_phi, $j_next) =
        ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);

    my $entry = $self->_current_block_label;
    $self->_set_terminator("  br label \%$l_ohdr");

    # outer: i = 1 .. len-1
    $self->_new_block($l_ohdr);
    $self->_emit("  $i_phi = phi i64 [ 1, \%$entry ], [ $i_next, \%$l_onext ]  ; sort: i");
    my $i_more = $self->_fresh;
    $self->_emit("  $i_more = icmp slt i64 $i_phi, $slen  ; sort: i < len?");
    $self->_set_terminator("  br i1 $i_more, label \%$l_obody, label \%$l_end");

    $self->_new_block($l_obody);
    $self->_set_terminator("  br label \%$l_ihdr");

    # inner: j = i, while j > 0 and slot[j-1] out of order vs slot[j], swap
    $self->_new_block($l_ihdr);
    $self->_emit("  $j_phi = phi i64 [ $i_phi, \%$l_obody ], [ $j_next, \%$l_swap ]  ; sort: j");
    my $j_more = $self->_fresh;
    $self->_emit("  $j_more = icmp sgt i64 $j_phi, 0  ; sort: j > 0?");
    $self->_set_terminator("  br i1 $j_more, label \%$l_ibody, label \%$l_onext");

    $self->_new_block($l_ibody);
    my ($jm1, $pa, $pb) = ($self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $jm1 = sub i64 $j_phi, 1  ; sort: j-1");
    $self->_emit("  $pa = getelementptr inbounds %Slot, %Slot* $slots, i64 $jm1  ; sort: slot[j-1]");
    $self->_emit("  $pb = getelementptr inbounds %Slot, %Slot* $slots, i64 $j_phi  ; sort: slot[j]");

    my $out_of_order = $custom ? $self->_emit_sort_block_out_of_order($node, $custom, $pa, $pb)
                     : $self->_emit_slot_out_of_order($pa, $pb, $cmp, $order);
    $self->_set_terminator("  br i1 $out_of_order, label \%$l_swap, label \%$l_onext");

    # swap slot[j-1] and slot[j] as whole aggregates -- a field-wise swap that
    # forgot one field would silently pair a key with another key's payload.
    $self->_new_block($l_swap);
    my ($va, $vb) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $va = load %Slot, %Slot* $pa  ; sort: slot[j-1]");
    $self->_emit("  $vb = load %Slot, %Slot* $pb  ; sort: slot[j]");
    $self->_emit("  store %Slot $vb, %Slot* $pa  ; sort: swap");
    $self->_emit("  store %Slot $va, %Slot* $pb  ; sort: swap");
    $self->_emit("  $j_next = sub i64 $j_phi, 1  ; sort: j--");
    $self->_set_terminator("  br label \%$l_ihdr");

    $self->_new_block($l_onext);
    $self->_emit("  $i_next = add i64 $i_phi, 1  ; sort: i++");
    $self->_set_terminator("  br label \%$l_ohdr");

    $self->_new_block($l_end);

    $self->{cache}{$node->id} = $arr;
    return $arr;
}

# _emit_sort_block_out_of_order($node, $sub, $pa, $pb) -> i1: the sort's
# comparator block, inlined with its $a and $b the two slots; out of order
# when it says greater than 0 (equal ones stay, as perl's merge sort keeps
# them). A block that writes $a or $b is refused.
sub _emit_sort_block_out_of_order {
    my ($self, $node, $sub, $pa, $pb) = @_;
    my $pkg = $node->sort_package // 'main';
    my @nodes = _graph_component($sub->graph);
    die "GAP: a sort block that writes \$a or \$b is not lowered\n"
        if grep { blessed($_) && $_->operation eq 'EntryWrite' && blessed($_->inputs->[0])
                  && ( $_->inputs->[0]->symbol // '' ) =~ /\A[ab]\z/ } @nodes;
    my ($va, $vb) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $va = load %Slot, %Slot* $pa  ; sort block: \$a");
    $self->_emit("  $vb = load %Slot, %Slot* $pb  ; sort block: \$b");
    local $self->{_arg_bind} = { ($self->{_arg_bind} // {})->%* };
    for my $n (grep { blessed($_) && $_->operation eq 'EntryDef' && ( $_->package // '' ) eq $pkg } @nodes) {
        my $sym = $n->symbol // '';
        $self->{_arg_bind}{ refaddr($n) } = { ref => $sym eq 'a' ? $va : $vb, repr => 'Scalar' }
            if $sym eq 'a' || $sym eq 'b';
    }
    $self->{_call_via} = { name => $sub->name, target => $sub, args => [] };
    my $r = $self->_lower_call_direct($node);
    delete $self->{cache}{ $node->id };   # the block's value, not the sort's
    my $from = $self->{_inline_value_repr}{ $node->id } // '';
    die "GAP: a sort block whose value is a " . ( $from || 'NONE' ) . " is not lowered\n"
        unless $from =~ /\A(?:Int|Num|Boolean|Scalar|Str)\z/;
    my $num = $from eq 'Num' ? $r : $self->_emit_coercion($r, $from, 'Num', 'sort block: its answer');
    my $gt = $self->_fresh;
    $self->_emit("  $gt = fcmp ogt " . _repr_to_llvm_type('Num') . " $num, " . _repr_zero('Num') . "  ; sort block: out of order?");
    return $gt;
}

# _emit_slot_out_of_order($pa, $pb, $cmp, $order) -> i1
#
# True when the slot at $pa must move after the slot at $pb. The comparator
# is the producer's folded decision, not a guess: `numeric` reads payloads as
# i64, `string` reads them as the %Str* a Str slot boxes.
sub _emit_slot_out_of_order {
    my ($self, $pa, $pb, $cmp, $order) = @_;

    # EACH ELEMENT BY ITS OWN TAG. The raw payloads are an Int's value, a
    # Num's bits, a Str's pointer: compared as integers, a negative Num sorts
    # backwards and a Str by its address. A numeric sort reads both as Nums --
    # unless both are Ints, compared exactly, as perl's <=> does past 2**53 --
    # and a string sort stringifies each as perl does.
    my ($va, $vb) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $va = load %Slot, %Slot* $pa  ; sort: lhs");
    $self->_emit("  $vb = load %Slot, %Slot* $pb  ; sort: rhs");
    if ($cmp eq 'numeric') {
        my $int = _slot_tag_value('Int');
        my ($ta, $tb, $both, $ic, $fc, $res) = map { $self->_fresh } 1 .. 6;
        $self->_emit("  $ta = icmp eq i8 " . $self->_slot_tag_of($va) . ", $int");
        $self->_emit("  $tb = icmp eq i8 " . $self->_slot_tag_of($vb) . ", $int");
        $self->_emit("  $both = and i1 $ta, $tb  ; sort: both Ints?");
        my ($ia, $ib) = ($self->_slot_payload_of($va), $self->_slot_payload_of($vb));
        $self->_emit("  $ic = icmp " . ($order eq 'descending' ? 'slt' : 'sgt') . " i64 $ia, $ib  ; sort: Ints");
        my $na = $self->_emit_coercion($va, 'Scalar', 'Num', 'sort lhs');
        my $nb = $self->_emit_coercion($vb, 'Scalar', 'Num', 'sort rhs');
        $self->_emit("  $fc = fcmp " . ($order eq 'descending' ? 'olt' : 'ogt') . " "
            . _repr_to_llvm_type('Num') . " $na, $nb  ; sort: numbers");
        $self->_emit("  $res = select i1 $both, i1 $ic, i1 $fc  ; sort: numeric $order");
        return $res;
    }
    my ($ap, $al) = $self->_str_parts($self->_emit_coercion($va, 'Scalar', 'Str', 'sort lhs'));
    my ($bp, $bl) = $self->_str_parts($self->_emit_coercion($vb, 'Scalar', 'Str', 'sort rhs'));

    my ($shorter_c, $shorter, $mc, $ne, $len_gt, $tie) =
        ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $shorter_c = icmp slt i64 $al, $bl  ; sort: which is shorter?");
    $self->_emit("  $shorter = select i1 $shorter_c, i64 $al, i64 $bl  ; sort: compare length");
    $self->_emit("  $mc = call i32 \@memcmp(i8* nocapture readonly $ap, i8* nocapture readonly $bp, i64 $shorter)  ; sort: string compare");
    $self->_emit("  $ne = icmp ne i32 $mc, 0  ; sort: bytes differ?");

    # Equal over the shared prefix: the longer string sorts after.
    $self->_emit("  $len_gt = icmp sgt i64 $al, $bl  ; sort: lhs longer?");
    my $pred = $order eq 'descending' ? 'slt' : 'sgt';
    my $byte_gt = $self->_fresh;
    $self->_emit("  $byte_gt = icmp $pred i32 $mc, 0  ; sort: string $order");
    # The length tiebreak inverts with the order, like the byte compare does.
    # $len_gt is emitted above for the ascending case; descending needs its
    # mirror, and taking the same ref for both would sort equal-prefix strings
    # backwards in one direction.
    my $tie_gt = $len_gt;
    if ($order eq 'descending') {
        $tie_gt = $self->_fresh;
        $self->_emit("  $tie_gt = icmp slt i64 $al, $bl  ; sort: lhs shorter (descending tiebreak)");
    }
    $self->_emit("  $tie = select i1 $ne, i1 $byte_gt, i1 $tie_gt  ; sort: bytes, else length");
    return $tie;
}

# _lower_builtin_keys($node) -> $llvm_ref (an %Array* of %Slot)
#
# PERL'S KEY ORDER IS NOT REPRODUCIBLE HERE. Measured on 5.42.0, three runs
# of one program:
#
#   my %h=(b=>2,a=>1,c=>3); print join(",", keys %h)
#     b,a,c   /   b,c,a   /   a,b,c
#
# It IS made stable by PERL_HASH_SEED with PERL_PERTURB_KEYS=0 -- five runs
# of the above then agree -- so "there is no order" would be wrong. The
# reason not to reproduce it is what that stable order DEPENDS ON:
#
#   PERL_HASH_SEED=0 PERL_PERTURB_KEYS=0
#     my %h=(a=>1,b=>2,c=>3)              b,c,a
#     my %h=(c=>3,b=>2,a=>1)              b,a,c   <- same keys, different order
#     ...insert a 4th key and delete it   b,a,c   <- bucket growth changed it
#
# The order is a function of collision history and bucket splits, not of the
# key set. Reproducing it means reimplementing perl's hash function, bucket
# sizing and split thresholds bit-exactly, and pinning chalk to one perl
# build's internals -- importing an implementation where this project's job
# is to have its own.
#
# The randomisation is also a DELIBERATE SECURITY MEASURE (hardening against
# collision-flooding complexity attacks), so depending on PERL_HASH_SEED=0
# would rest chalk's correctness on a mode perl exists to let you turn off.
#
# So this emits INSERTION ORDER -- the order the entries array already holds.
# Deterministic, and a valid answer to a question perl deliberately leaves
# unordered. A program whose output depends on which order it receives is
# relying on unspecified behaviour, and every corpus use is order-independent
# (`sort keys %h`, or a `scalar(keys %h)` count).
#
# THE STAMP IS `Unknown`, NOT `List`, so a rule reading the stamp to decide
# lowerability would refuse this. What makes it lowerable is the OPERAND: a
# %Hash is { i64 count, i64 cap, %HashEntry* entries } and a %HashEntry opens
# with { i8* key_ptr, i64 key_len, ... }, so the key list is a structural read
# at known offsets rather than a typed one.
# _slot_field_ptr($slot_ptr, $field) -> a pointer to that field of a %Slot.
sub _slot_field_ptr {
    my ($self, $sp, $f) = @_;
    my $p = $self->_fresh;
    $self->_emit("  $p = getelementptr inbounds %Slot, %Slot* $sp, i32 0, i32 " . _slot_idx($f));
    return $p;
}

sub _lower_builtin_keys {
    my ($self, $node) = @_;
    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    my ($operand) = grep { blessed($_) } $node->inputs->@*;
    die "GAP: keys expects a hash operand." unless defined $operand;

    my $op_repr = $operand isa Chalk::IR::Node ? ($operand->stamp // '') : '';
    die "GAP: keys over an operand with repr=" . ($op_repr || 'NONE')
      . " — only a Hash or HashRef has a key list to read."
        unless $op_repr eq 'Hash' || $op_repr eq 'HashRef';

    my $hash = $self->_container_ptr($operand, 'Hash');

    # count = hash->count (field 0)
    my ($cnt_ptr, $cnt) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 0  ; keys: count ptr");
    $self->_emit("  $cnt = load i64, i64* $cnt_ptr  ; keys: key count");

    # IN SCALAR CONTEXT `keys` IS THE COUNT, not a list to be counted later.
    # The producer states which it is from the callsite's own OPf_WANT
    # (want=2 stamps the Call Int, want=3 stamps it List), so this reads the
    # decision rather than remaking it.
    #
    # Building the %Array either way was a type error, not a slow path: the
    # consumer of an Int-stamped Call expects an i64 and got an %Array*
    # ("'%tmp_42' defined with type '%Array*' but expected 'i64'"). Materialising
    # a list nobody asked for is also the work perl skips here.
    my $repr = $node isa Chalk::IR::Node ? ($node->stamp // '') : '';
    if ($repr eq 'Int') {
        $self->{cache}{$node->id} = $cnt;
        return $cnt;
    }

    # entries = hash->entries (field 2)
    my ($ent_ptr, $entries) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 2  ; keys: entries ptr");
    $self->_emit("  $entries = load %HashEntry*, %HashEntry** $ent_ptr  ; keys: entries");

    # Allocate the result %Array header and its slot buffer. Sized from the
    # type rather than a literal: a field added to %Slot must not silently
    # under-allocate here (the same reasoning _slot_size_bytes exists for).
    my $slot_bytes = $self->_fresh;
    $self->_emit("  $slot_bytes = mul i64 $cnt, " . _sizeof_llvm_type('%Slot') . "  ; keys: slot buffer bytes");
    my ($slot_raw, $slots) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $slot_raw = call i8* \@malloc(i64 $slot_bytes)  ; keys: alloc slot buffer");
    $self->_emit("  $slots = bitcast i8* $slot_raw to %Slot*  ; keys: slot array ptr");

    my ($arr_raw, $arr) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $arr_raw = call i8* \@malloc(i64 " . _sizeof_llvm_type('%Array') . ")  ; keys: alloc %Array header");
    $self->_emit("  $arr = bitcast i8* $arr_raw to %Array*  ; keys: %Array ptr");

    my ($alen, $acap, $adat) = ($self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $alen = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; keys: len ptr");
    $self->_emit("  $acap = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 1  ; keys: cap ptr");
    $self->_emit("  $adat = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; keys: data ptr");
    $self->_emit("  store i64 $cnt, i64* $alen  ; keys: len = key count");
    $self->_emit("  store i64 $cnt, i64* $acap  ; keys: cap = key count");
    $self->_emit("  store %Slot* $slots, %Slot** $adat  ; keys: data = slot buffer");

    # Copy each entry's key into the matching slot, in entries order.
    my $n     = $self->_fresh_label('keys');
    my $lhdr  = "${n}_hdr";
    my $lbody = "${n}_body";
    my $lend  = "${n}_end";
    my $i_phi  = $self->_fresh;
    my $i_next = $self->_fresh;

    # Capture the predecessor label BEFORE branching -- the phi names the
    # block control arrives from, which is the current block at this point.
    my $prev = $self->_current_block_label;
    $self->_set_terminator("  br label \%$lhdr");
    $self->_new_block($lhdr);
    $self->_emit("  $i_phi = phi i64 [ 0, \%$prev ], [ $i_next, \%$lbody ]  ; keys: index");
    my $more = $self->_fresh;
    $self->_emit("  $more = icmp slt i64 $i_phi, $cnt  ; keys: i < count?");
    $self->_set_terminator("  br i1 $more, label \%$lbody, label \%$lend");

    $self->_new_block($lbody);
    my ($e_p, $kp_p, $kl_p, $kp, $kl) =
        ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $e_p = getelementptr inbounds %HashEntry, %HashEntry* $entries, i64 $i_phi  ; keys: entry[i]");
    $self->_emit("  $kp_p = getelementptr inbounds %HashEntry, %HashEntry* $e_p, i32 0, i32 " . _he_idx('key_ptr') . "  ; keys: key_ptr field");
    $self->_emit("  $kl_p = getelementptr inbounds %HashEntry, %HashEntry* $e_p, i32 0, i32 " . _he_idx('key_len') . "  ; keys: key_len field");
    $self->_emit("  $kp = load i8*, i8** $kp_p  ; keys: key ptr");
    $self->_emit("  $kl = load i64, i64* $kl_p  ; keys: key len");

    # The key is a Str; a Str in a %Slot payload is a boxed %Str*, which
    # is what _box_payload emits for every other Str write.
    # VALUES ARE THE SAME WALK: each entry's value, as its slot, in the
    # order keys gives the keys.
    if (( $node->name // '' ) eq 'values') {
        my ($vdp, $vtp, $vpp, $vd, $vt, $vp, $sp) = map { $self->_fresh } 1 .. 7;
        $self->_emit("  $vdp = getelementptr inbounds %HashEntry, %HashEntry* $e_p, i32 0, i32 " . _he_idx('val_def'));
        $self->_emit("  $vtp = getelementptr inbounds %HashEntry, %HashEntry* $e_p, i32 0, i32 " . _he_idx('val_tag'));
        $self->_emit("  $vpp = getelementptr inbounds %HashEntry, %HashEntry* $e_p, i32 0, i32 " . _he_idx('val_pay'));
        $self->_emit("  $vd = load i1, i1* $vdp  ; values: defined");
        $self->_emit("  $vt = load i8, i8* $vtp  ; values: tag");
        $self->_emit("  $vp = load i64, i64* $vpp  ; values: payload");
        $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $slots, i64 $i_phi  ; values: slot[i]");
        $self->_emit("  store i1 $vd, i1* " . $self->_slot_field_ptr($sp, 'defined'));
        $self->_emit("  store i8 $vt, i8* " . $self->_slot_field_ptr($sp, 'tag'));
        $self->_emit("  store i64 $vp, i64* " . $self->_slot_field_ptr($sp, 'payload'));
        $self->_emit("  $i_next = add i64 $i_phi, 1  ; values: i++");
        $self->_set_terminator("  br label \%$lhdr");
        $self->_new_block($lend);
        $self->{cache}{$node->id} = $arr;
        return $arr;
    }
    my $key_str = $self->_set_str_len($kp, $kl);
    my $payload = $self->_box_payload($key_str, 'Str', 'keys: key');

    my ($s_p, $d_g, $t_g, $p_g) =
        ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $s_p = getelementptr inbounds %Slot, %Slot* $slots, i64 $i_phi  ; keys: slot[i]");
    $self->_emit("  $d_g = getelementptr inbounds %Slot, %Slot* $s_p, i32 0, i32 " . _slot_idx('defined') . "  ; keys: slot.defined");
    $self->_emit("  $t_g = getelementptr inbounds %Slot, %Slot* $s_p, i32 0, i32 " . _slot_idx('tag') . "  ; keys: slot.tag");
    $self->_emit("  $p_g = getelementptr inbounds %Slot, %Slot* $s_p, i32 0, i32 " . _slot_idx('payload') . "  ; keys: slot.payload");
    $self->_emit("  store i1 true, i1* $d_g  ; keys: a key is always defined");
    $self->_emit("  store i8 " . _slot_tag_value('Str') . ", i8* $t_g  ; keys: tag = Str");
    $self->_emit("  store i64 $payload, i64* $p_g  ; keys: payload = StrPair*");

    $self->_emit("  $i_next = add i64 $i_phi, 1  ; keys: i++");
    $self->_set_terminator("  br label \%$lhdr");

    $self->_new_block($lend);

    # The repr is seeded in ANALYSIS (Analysis.pm's builtin-List rule), not
    # here. It was set here first and that was too late: _require_repr runs
    # as a pre-lowering pass, so `Count(keys %h)` died on an operand with no
    # representation before this arm ever ran.
    $self->{cache}{$node->id} = $arr;
    return $arr;
}

# _lower_builtin_join($node) -> $llvm_ref (a Str)
#
# `join($sep, LIST)` is the separator interleaved with the list's elements.
# TypeLibrary declares it (join => arg_types ['Str','List'], return_type 'Str')
# and the producer stamps the Call Str, so the RESULT was never the problem --
# join simply had no arm and fell through to "cannot lower op=Call".
#
# WHAT MAKES IT LOWERABLE IS THE ARGUMENT'S ARITY, NOT ITS TYPE. The list
# argument is stamped List, which %LOWERABLE_STAMP deliberately excludes from
# the representation field: List is arity-polymorphic (Scalar, Void, Array and
# Hash all declare it as parent), so it has no single-value machine layout and
# %_REPR_NO_MACHINE_TYPE refuses it by name.
#
# But a List PRODUCED BY an ArrayLiteral has a statically known element count,
# which is a structural fact about that node rather than a property of its
# type. With the count known, join is an ordinary concat chain: no runtime
# list, no container, no length arithmetic.
#
# A list whose arity is not statically known cannot lower this way, and the
# honest answer there is a GAP. Guessing a count would be a silent wrong
# answer -- the class this file's other refusals exist to prevent.
sub _lower_builtin_join {
    my ($self, $node) = @_;

    my @inputs = grep { blessed($_) } $node->inputs->@*;
    # A join over an array reads it at a memory version, its last input --
    # not an operand (`"@r"` after a push).
    my $mem = ($node->can('memory_input') && $node->memory_input) ? pop @inputs : undef;
    die "GAP: join expects a separator and a list; got " . scalar(@inputs) . " operand(s)."
        unless @inputs >= 2;

    my ($sep_node, $list_node, @more) = @inputs;

    # Resolve the list operand to the node that actually states the arity. A
    # direct call resolves through the CALLEE'S LIST READING -- Return
    # inputs[0], never inputs[-1], which is the scalar face. A LIST OF
    # SCALARS FLATTENED INTO THE CALL -- `"@a"` over a literal arrives as
    # join($", 1, 2) -- is its own static element list.
    # One that holds an array (`"@{[sort keys %h]} z"`) flattens at run time.
    my $flatten = @more && grep { ( $_->stamp // '' ) !~ /\A(?:Int|Num|Str|Boolean)\z/ } $list_node, @more;
    # So does a range whose bounds the program computes (`"@c"` over
    # `my @c = (1 .. $n)` is a join over the Range itself).
    $flatten ||= blessed($list_node) && $list_node->operation eq 'Range'
        && grep { $_->operation ne 'Constant' } $list_node->inputs->@[0, 1];
    $flatten ||= _is_array_slice($list_node) || _is_hash_slice($list_node);
    my $elements = $flatten ? undef
        : @more ? [ $list_node, @more ]
        # A LIST READ AFTER IT WAS WRITTEN has no static elements: its
        # declaration said empty, and a push since made it 2 4 6 -- read as
        # the declaration, "@r" printed "". It is walked at run time.
        : ( blessed($mem) && $mem->operation ne 'MemStart' ) ? undef
        : $self->_static_list_elements($list_node);

    # The separator is a Str by join's signature; anything else is bridged the
    # same way an operand of any Str-context operator is. $" IS " " UNTIL A
    # PROGRAM WRITES IT: read where nothing can have, it is perl's default.
    my $default_sep = _unwritten_list_separator($sep_node);
    my $sep_ref = $self->lower_value($default_sep // $sep_node);
    my $sep_repr = $default_sep ? 'Str'
                 : ($sep_node isa Chalk::IR::Value)
                 ? $sep_node->stamp : undef;
    $sep_ref = $self->_emit_coercion($sep_ref, $sep_repr, 'Str', 'join separator')
        if defined $sep_repr && $sep_repr ne 'Str';

    # A RUNTIME-ARITY LIST LOOPS. `join(",", sort keys %h)` is the case the
    # corpus wants (references.md R11) and its element count is the hash's
    # runtime key count, so requiring a compile-time arity refused exactly the
    # program this exists for. The static path stays because it emits straight
    # -line concats with no loop when the count IS known.
    unless (defined $elements) {
        return $self->{cache}{ $node->id } = $self->_emit_join_loop(undef, $sep_ref,
            $self->_emit_flattened_array_of([ $list_node, @more ])) if $flatten;
        my $repr = $list_node isa Chalk::IR::Value
                 ? ($list_node->stamp // '') : '';
        die "GAP: join over an operand with repr=" . ($repr || 'NONE')
          . " — a runtime-arity join needs a materialised Array to walk."
            unless $repr eq 'Array' || $repr eq 'ArrayRef';
        return $self->_emit_join_loop($list_node, $sep_ref);
    }

    # An empty list joins to the empty string, and a single element joins to
    # itself -- neither uses the separator at all.
    return $self->_empty_str_ref('join: empty list') unless $elements->@*;

    my $acc;
    for my $i (0 .. $elements->$#*) {
        my $el      = $elements->[$i];
        my $el_ref  = $self->lower_value($el);
        my $el_repr = ($el isa Chalk::IR::Value)
                    ? $el->stamp : undef;
        $el_ref = $self->_emit_coercion($el_ref, $el_repr, 'Str', "join element[$i]")
            if defined $el_repr && $el_repr ne 'Str';

        if (!defined $acc) {
            $acc = $el_ref;
            next;
        }
        $acc = $self->_emit_str_append($acc, $sep_ref, "join: separator before element[$i]");
        $acc = $self->_emit_str_append($acc, $el_ref,  "join: element[$i]");
    }

    $self->{cache}{$node->id} = $acc;
    return $acc;
}

# _emit_join_loop($list_node, $sep_ref) -> $llvm_ref (a Str)
#
# join over an %Array whose length is only known at runtime. Walks the slot
# buffer accumulating `acc = acc . sep . element`, with the separator skipped
# before the first element -- which is what makes it a join rather than a
# concatenation with a trailing separator.
#
# The accumulator is a %Str carried through a phi, so its pointer and length
# travel together and a merge cannot desynchronise them (the same reason %Str
# is a first-class aggregate rather than two parallel values).
# _unwritten_list_separator($sep_node) -> a Constant " " node, or undef.
#
# `$"` read where nothing can have written it: nothing in the read's
# backward slice -- its memory version and everything that leads to it --
# stores `$"`, nor does a sub called there. (The walk once passed only the
# builtins, and an element store through a reference before "@a" refused
# the join.) The Constant belongs to no graph; it is minted once.
sub _unwritten_list_separator {
    my ($sep) = @_;
    $sep = $sep->inputs->[0] if blessed($sep) && $sep->operation eq 'Coerce';
    return undef unless blessed($sep) && $sep->operation eq 'EntryDef'
        && ($sep->can('package') ? ($sep->package // '') : '') eq 'main'
        && ($sep->can('symbol') ? ($sep->symbol // '') : '') eq '"';
    return undef if _writes_list_separator([ $sep->inputs->@* ], {});
    state $space = do {
        my $c = Chalk::IR::NodeFactory->new->make('Constant', value => ' ', const_type => 'string');
        $c->set_stamp('Str');
        $c;
    };
    return $space;
}

# _writes_list_separator(\@from, \%seen) -> true when anything reached from
# @from (inputs and control, backward; into a direct call's callee) stores $".
sub _writes_list_separator {
    my ($q, $seen) = @_;
    while (defined(my $n = shift @$q)) {
        next unless blessed($n) && !$seen->{ refaddr($n) }++;
        my $op = $n->operation;
        if ($op =~ /\A(?:EntryWrite|Assign|LocalAlias)\z/) {
            my $t = $n->inputs->[0];
            return 1 if blessed($t) && $t->operation eq 'EntryDef'
                && ($t->symbol // '') eq '"';
        }
        if ($op eq 'Call' && ($n->dispatch_kind // '') ne 'builtin') {
            my $target = $n->can('target') ? $n->target : undef;
            my $graph  = $target && $target->can('graph') ? $target->graph : undef;
            return 1 unless $graph;   # an unknown callee may write anything
            push @$q, grep { blessed($_) } $graph->nodes->@*, _control_chain_of($graph);
        }
        push @$q, grep { blessed($_) } $n->inputs->@*,
            ($n->can('control_in') ? $n->control_in : ());
    }
    return 0;
}

# _control_chain_of($graph) -> the statements on its Returns' control chains.
sub _control_chain_of {
    my ($graph) = @_;
    my @out;
    for my $r (($graph->can('returns') ? $graph->returns : [])->@*) {
        for (my $c = $r; blessed($c); $c = $c->can('control_in') ? $c->control_in : undef) {
            push @out, $c;
            last if @out > 100_000;
        }
    }
    return @out;
}

sub _emit_join_loop {
    my ($self, $list_node, $sep_ref, $arr) = @_;
    $self->{_need_aggregate_types} = 1;

    $arr //= $self->_container_ptr($list_node, 'Array');

    my ($len_p, $len, $dat_p, $slots) =
        ($self->_fresh, $self->_fresh, $self->_fresh, $self->_fresh);
    $self->_emit("  $len_p = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; join: len ptr");
    $self->_emit("  $len = load i64, i64* $len_p  ; join: element count");
    $self->_emit("  $dat_p = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; join: data ptr");
    $self->_emit("  $slots = load %Slot*, %Slot** $dat_p  ; join: slots");

    my $empty = $self->_empty_str_ref('join: accumulator seed');

    my $n = $self->_fresh_label('joinloop');
    my ($l_hdr, $l_body, $l_sep, $l_app, $l_end) =
        ("${n}_hdr", "${n}_body", "${n}_sep", "${n}_app", "${n}_end");

    # THE ACCUMULATOR LIVES IN A STACK SLOT, not a phi. Its back-edge value is
    # produced by _emit_str_append, whose SSA name does not exist until after
    # the phi would have to name it -- and a phi cannot forward-reference a
    # value this emitter has no way to pre-name. An alloca sidesteps the
    # ordering entirely; mem2reg turns it back into a phi.
    my $acc_slot = $self->_fresh;
    $self->_emit_entry("  $acc_slot = alloca %Str  ; join: accumulator slot");
    my $i_slot = $self->_fresh;
    $self->_emit_entry("  $i_slot = alloca i64  ; join: index slot");
    $self->_emit("  store i64 0, i64* $i_slot  ; join: index = 0");
    $self->_emit("  store %Str $empty, %Str* $acc_slot  ; join: accumulator starts empty");

    $self->_set_terminator("  br label \%$l_hdr");

    # The index also lives in a slot rather than a phi. _emit_str_append and
    # _emit_to_str can OPEN BLOCKS (Int->Str renders its digits in a loop), so
    # the block control leaves the body from is not $l_app and a phi naming
    # $l_app produced "Instruction does not dominate all uses". A slot has no
    # predecessor to name.
    $self->_new_block($l_hdr);
    my $i_phi = $self->_fresh;
    $self->_emit("  $i_phi = load i64, i64* $i_slot  ; join: index");
    my $acc_phi = $self->_fresh;
    $self->_emit("  $acc_phi = load %Str, %Str* $acc_slot  ; join: accumulator");
    my $more = $self->_fresh;
    $self->_emit("  $more = icmp slt i64 $i_phi, $len  ; join: i < len?");
    $self->_set_terminator("  br i1 $more, label \%$l_body, label \%$l_end");

    # The separator goes BEFORE every element except the first.
    $self->_new_block($l_body);
    my $first = $self->_fresh;
    $self->_emit("  $first = icmp eq i64 $i_phi, 0  ; join: first element?");
    $self->_set_terminator("  br i1 $first, label \%$l_app, label \%$l_sep");

    $self->_new_block($l_sep);
    my $with_sep = $self->_emit_str_append($acc_phi, $sep_ref, 'join: separator');
    $self->_emit("  store %Str $with_sep, %Str* $acc_slot  ; join: accumulator .= separator");
    $self->_set_terminator("  br label \%$l_app");

    # Read the accumulator back rather than merging the two arms with a phi:
    # the separator arm's own emission may have opened blocks, so its incoming
    # label is not $l_sep.
    $self->_new_block($l_app);
    my $base = $self->_fresh;
    $self->_emit("  $base = load %Str, %Str* $acc_slot  ; join: acc, separated");
    my $slot_p = $self->_fresh;
    $self->_emit("  $slot_p = getelementptr inbounds %Slot, %Slot* $slots, i64 $i_phi  ; join: slot[i]");
    my $slot_v = $self->_fresh;
    $self->_emit("  $slot_v = load %Slot, %Slot* $slot_p  ; join: element");
    # THE TAG DECIDES HOW THE PAYLOAD READS. _emit_to_str('Slot', ...) renders
    # the payload as an Int unconditionally, so a Str element printed as its
    # %Str POINTER: `join(",", sort keys %h)` emitted
    # "94372392710400,94372392636160" where perl prints "a,b". A slot's
    # payload is i64 bits whose interpretation lives in its tag, which is the
    # whole reason the tag exists.
    my $el_str = $self->_emit_read_slot_as($slot_v, 'Str', 'join: element',
                                           readings => [qw(Str Int Num Boolean)]);
    my $acc_next = $self->_emit_str_append($base, $el_str, 'join: element');
    $self->_emit("  store %Str $acc_next, %Str* $acc_slot  ; join: accumulator .= element");
    my $i_next = $self->_fresh;
    $self->_emit("  $i_next = add i64 $i_phi, 1  ; join: i++");
    $self->_emit("  store i64 $i_next, i64* $i_slot  ; join: index++");
    $self->_set_terminator("  br label \%$l_hdr");

    $self->_new_block($l_end);
    my $result = $self->_fresh;
    $self->_emit("  $result = load %Str, %Str* $acc_slot  ; join: result");
    return $result;
}

# _static_list_elements($node) -> \@element_nodes, or undef when the arity is
# not a compile-time fact.
#
# An ArrayLiteral states its own arity. A direct Call resolves through its
# callee's LIST reading (Return inputs[0]) -- the same slot the inliner takes,
# and never inputs[-1], which is the scalar face and would silently substitute
# one value for N.
sub _static_list_elements {
    my ($self, $node) = @_;
    return undef unless blessed($node) && $node->can('operation');

    my $op = $node->operation;
    # An array among them (`my @r = $c ? @a : @b`) is its elements, not one.
    if ($op eq 'ArrayLiteral') {
        my @in = grep { blessed($_) } $node->inputs->@*;
        return undef if grep { ( $_->stamp // '' ) =~ /\A(?:Array|List|Hash)\z/ } @in;
        return \@in;
    }

    if ($op eq 'Call' && $node->can('dispatch_kind')
            && ($node->dispatch_kind // '') eq 'direct') {
        my $target = $node->can('target') ? $node->target : undef;
        my $graph  = ($target && $target->can('graph')) ? $target->graph : undef;
        return undef unless $graph && $graph->can('returns');

        my @returns = grep {
            blessed($_) && $_->can('operation') && $_->operation eq 'Return'
        } $graph->returns->@*;
        return undef unless @returns == 1;

        # The LIST reading, explicitly. A callsite wanting the scalar face
        # would not be asking for a list at all.
        my $list_reading = $returns[0]->value();
        return undef unless blessed($list_reading);
        return $self->_static_list_elements($list_reading);
    }

    return undef;
}

# _lower_builtin_push($node) -> $llvm_ref (the new element count, Int)
#
# `push @a, LIST`: B::SoN's inputs are the array, the values, and -- the
# call being a memory version (memory_input) -- the memory it follows. Each
# value is appended through _emit_append_one, the grow-and-store a map's
# accumulator uses; an array value is appended element by element. It was
# not lowered at all: the commonest builtin refusal in the pvm corpus.
sub _lower_builtin_push {
    my ($self, $node) = @_;
    $self->{_need_aggregate_types} = 1;
    my @in = grep { blessed($_) } $node->inputs->@*;
    pop @in if $node->can('memory_input') && $node->memory_input;
    my ($array, @values) = @in;
    die "GAP: push onto a " . (($array && $array->stamp) // 'NONE')
      . " is not lowered -- only an Array\n"
        unless $array && ( ( $array->stamp // '' ) eq 'Array'
            # ...or an array field, which the object holds by reference
            || ( $array->operation eq 'FieldAccess' && ( $self->_repr_of($array) // '' ) eq 'ArrayRef' ) );
    _seed_container_repr($array) unless $array->operation eq 'FieldAccess';
    my $acc = $self->_container_ptr($array, 'Array');
    for my $v (@values) {
        # A VALUE READ BY ITS TAG (an element of an array handed in), or
        # undef, or a reference (boxed with its tag), is appended as its Slot.
        if (( $self->_repr_of($v) // '' ) =~ /\A(?:Scalar|Slot|Undef|ArrayRef|HashRef|CodeRef|ScalarRef|Object)\z/) {
            $self->{$_} = 1 for qw(_need_array_append _need_malloc_memcpy);
            my $slot = $self->_slot_of_value($v, $self->lower_value($v), 'push');
            $self->_emit("  call void \@chalk_array_push_slot(%Array* $acc, %Slot $slot)  ; push: a value by its tag");
            next;
        }
        die "GAP: push of a " . ($v->stamp // 'NONE') . " value is not lowered\n"
            unless ( $v->stamp // '' ) =~ /\A(?:Int|Num|Str|Boolean)\z/;
        $self->_emit_append_one($acc, $v);
    }
    my ($len_ptr, $len) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $len_ptr = getelementptr inbounds %Array, %Array* $acc, i32 0, i32 0  ; push: len ptr");
    $self->_emit("  $len = load i64, i64* $len_ptr  ; push: the new count");
    $self->{cache}{ $node->id } = $len;
    return $len;
}

sub _lower_builtin_shift_pop {
    my ($self, $node) = @_;
    $self->{_need_aggregate_types} = 1;

    my $name = $node->name;   # 'shift' or 'pop'
    # No fallback: the die below already rejects everything but Int, so a
    # guessed 'Int' only made the message name a repr the node never had.
    my $repr = $node->stamp;
    # A Scalar element is its whole Slot -- an @ARGV element, say -- and an
    # empty array gives an undefined one.
    die "GAP: $name element repr=" . ($repr // 'NONE (undef)')
      . " not lowered (only Int and Scalar elements yet)"
        unless defined $repr && ($repr eq 'Int' || $repr eq 'Scalar');
    # AN INT SHIFT OF AN EMPTY ARRAY IS UNDEF, which only a NUMBER reads as
    # its 0: `shift(@a) // 7` gave 0 for 7, and defined() said yes. Lowered
    # only where every value consumer reads a number (a later read taking it
    # as its memory version is no value consumer).
    if ($repr eq 'Int') {
        for my $c (grep { blessed($_) } ($node->consumers // [])->@*) {
            my $cop = $c->operation;
            # A statement it only precedes (its control), or a merge naming it
            # as a predecessor, reads no value.
            next if $cop =~ /\A(?:Region|Proj|If|Loop)\z/;
            next unless grep { blessed($_) && refaddr($_) == refaddr($node) } $c->inputs->@*;
            next if $cop =~ /\A(?:Add|Subtract|Multiply|Divide|Modulo|Negate|Num(?:Eq|Ne|Lt|Gt|Le|Ge|Cmp))\z/;
            next if $cop eq 'Coerce' && ( $c->to_repr // '' ) =~ /\A(?:Int|Num)\z/;
            my @ci = $c->inputs->@*;
            next if blessed($ci[-1]) && refaddr($ci[-1]) == refaddr($node)
                && $cop =~ /\A(?:Subscript|Count|Call|Exists|PadAccess|EntryDef|FieldAccess|Phi)\z/
                && !grep { blessed($_) && refaddr($_) == refaddr($node) } @ci[0 .. $#ci - 1];
            next if $cop eq 'Phi' && _is_memory_phi($c);
            die "GAP: $name of an Int array read by a $cop is not lowered -- an "
              . "empty array gives undef, which only a number reads as 0\n";
        }
    }

    # The array is the aggregate input. Post-load the loader has already moved the
    # leading control token to control_in (the is_stmt_effect contract), so the
    # reachable inputs are [array, memory]. Identify the array structurally: it is
    # an aggregate node (ArrayRef/HashRef op, or Array/ArrayRef repr), never the
    # memory version (a MemStart/Phi/Assign). Matching by op as well as repr is
    # robust when the array is off the value path and its repr was not inferred
    # (e.g. `while (shift @q) { ... }` where the drained value is unused).
    my ($array) = grep {
        my $op   = blessed($_) ? $_->operation : '';
        my $repr = (blessed($_) && $_->stamp) // '';
        $op eq 'ArrayLiteral' || $op eq 'HashLiteral'
            || $repr eq 'Array' || $repr eq 'ArrayRef'
    } $node->inputs->@*;
    die "GAP: $name operand is not an Array/ArrayRef" unless defined $array;
    _seed_container_repr($array);

    my ($arr_ref, $len_ptr, $elem_ptr, $len, $elems)
        = $self->_load_array_header($array, $name);

    # Empty check: len == 0 -> undef (defined=false, payload 0).
    my $empty = $self->_fresh;
    my $lbl_ne  = $self->_fresh_label("${name}_ne");
    my $lbl_mt  = $self->_fresh_label("${name}_mt");
    my $lbl_end = $self->_fresh_label("${name}_end");
    $self->_emit("  $empty = icmp eq i64 $len, 0  ; $name: array empty?");
    $self->_set_terminator("  br i1 $empty, label \%$lbl_mt, label \%$lbl_ne");

    # Non-empty: read the removed element, then update the header. pop removes the
    # last index (len-1); shift removes index 0 (the literal used directly below).
    $self->_new_block($lbl_ne);
    my $idx;
    if ($name eq 'pop') {
        $idx = $self->_fresh;
        $self->_emit("  $idx = sub i64 $len, 1  ; pop: last index (len-1)");
    }
    else {
        $idx = '0';
    }
    my $slot_p   = $self->_fresh;
    my $slot_pay = $self->_fresh;
    my $pay_val  = $self->_fresh;
    $self->_emit("  $slot_p   = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx  ; $name: slot ptr");
    if ($repr eq 'Scalar') {
        $self->_emit("  $pay_val  = load %Slot, %Slot* $slot_p  ; $name: load the slot");
    }
    else {
        my $gi_pay = _slot_idx('payload');
        $self->_emit("  $slot_pay = getelementptr inbounds %Slot, %Slot* $slot_p, i32 0, i32 $gi_pay  ; $name: payload ptr");
        $self->_emit("  $pay_val  = load i64, i64* $slot_pay  ; $name: load payload");
    }
    # Update the header: len := len-1; shift also advances elems by one slot.
    my $new_len = $self->_fresh;
    $self->_emit("  $new_len = sub i64 $len, 1  ; $name: new len");
    $self->_emit("  store i64 $new_len, i64* $len_ptr  ; $name: store new len");
    if ($name eq 'shift') {
        my $new_elems = $self->_fresh;
        $self->_emit("  $new_elems = getelementptr inbounds %Slot, %Slot* $elems, i64 1  ; shift: drop front (elems+1)");
        $self->_emit("  store %Slot* $new_elems, %Slot** $elem_ptr  ; shift: store advanced elems");
    }
    $self->_set_terminator("  br label \%$lbl_end");

    # Empty: nothing to remove.
    $self->_new_block($lbl_mt);
    my $none = $repr eq 'Scalar'
        ? $self->_build_slot('false', '0', 'Undef', "$name: empty")
        : '0';
    $self->_set_terminator("  br label \%$lbl_end");

    $self->_new_block($lbl_end);
    my $result = $self->_fresh;
    $self->_emit("  $result = phi " . ($repr eq 'Scalar' ? '%Slot' : 'i64')
        . " [ $pay_val, \%$lbl_ne ], [ $none, \%$lbl_mt ]  ; $name :$repr result");
    $self->{cache}{ $node->id } = $result;
    return $result;
}

# _lower_hash_read: linear-scan key lookup using phi-based loop counter.
# inputs = [Hash, key :Str]. repr=Int: extract payload (key found).
# repr=Slot: phi-select {defined=false, payload=0} for missing keys.
#
# Block structure:
#   pre_loop_block: load count+entries, br %hloop
#   hloop: %i = phi [0, pre_loop], [i_next, hnxt]; cond = i<count; br hchk/hmiss
#   hchk: load entry[i], len_eq check; br hcmp/hnxt
#   hcmp: memcmp; br hhit/hnxt
#   hhit: load val_def/val_pay; br hend
#   hnxt: i_next = i+1; br hloop  (back-edge)
#   hmiss: br hend
#   hend: phi result
# _hash_key_str($key_node) -> %Str: a hash key is its string. The scan
# compares bytes, so a number, an element (a Slot) or a Boolean is converted
# first -- handed over as it was, it was taken apart as a %Str and lli
# rejected the module.
sub _hash_key_str {
    my ($self, $key) = @_;
    my $ref  = $self->lower_value($key);
    my $from = $key->operation eq 'Print' ? 'Boolean' : ($self->_repr_of($key) // $key->stamp // '');
    return $ref if $from eq 'Str';
    $from = 'Scalar' if $from eq 'Slot';
    return $self->_emit_coercion($ref, $from, 'Str', 'hash key');
}

sub _lower_hash_read {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_memcmp}          = 1;

    my $container = $node->inputs->[0];
    # Typed pointer resolved at THIS use (re-lowered for mutable-read
    # containers; bitcast for Ref reprs) — see _container_ptr.
    my $hash_ref = $self->_container_ptr($container, 'Hash');
    my $repr     = _require_repr($node, 'HashRead');
    my $slot     = $self->_emit_hash_slot_of($hash_ref, $node->inputs->[1]);
    my $result = $self->_slot_as_reading($slot, $repr, 'HashRead');
    $self->{cache}{ $node->id } = $result;
    return $result;
}

# _emit_hash_slot_of($hash_ref, $key_node) -> the %Slot stored at that key
# in the %Hash*, or an undef Slot when it is missing: the key scan a read
# and a hash slice share.
sub _emit_hash_slot_of {
    my ($self, $hash_ref, $key_node) = @_;
    $self->{_need_aggregate_types} = 1;
    $self->{_need_memcmp}          = 1;
    my $lkey_ref = $self->_hash_key_str($key_node);
    # The key length drives the memcmp scan; a silently-zeroed length makes a
    # zero-length memcmp match ANY entry (spurious key match). If the key length
    # is untracked it is a TypeInference/length-tracking gap — die loudly (matches
    # the I-C loud-GAP contract), do NOT default to 0.
    my ($lkey_ptr, $lkey_len) = $self->_str_parts($lkey_ref);
    $lkey_ref = $lkey_ptr;
    defined $lkey_len
        or die "GAP: HashRead key (ref=$lkey_ref) has no tracked length — "
             . "would emit a 0-length memcmp matching any entry. Fix length tracking.";

    # Load count and entries pointer from Hash struct (in current/pre_loop block).
    my $cnt_ptr  = $self->_fresh;
    my $ent_ptr  = $self->_fresh;
    my $count    = $self->_fresh;
    my $ents     = $self->_fresh;
    $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 0  ; HashRead: count ptr");
    $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 2  ; HashRead: entries ptr");
    $self->_emit("  $count = load i64, i64* $cnt_ptr  ; HashRead: load count");
    $self->_emit("  $ents  = load %HashEntry*, %HashEntry** $ent_ptr  ; HashRead: load entries");

    # Allocate fresh block labels — all known before any block is emitted.
    my $lbl_loop = $self->_fresh_label('hloop');
    my $lbl_chk  = $self->_fresh_label('hchk');
    my $lbl_cmp  = $self->_fresh_label('hcmp');
    my $lbl_hit  = $self->_fresh_label('hhit');
    my $lbl_nxt  = $self->_fresh_label('hnxt');
    my $lbl_miss = $self->_fresh_label('hmiss');
    my $lbl_end  = $self->_fresh_label('hend');

    # Capture pre_loop label before terminating the current block.
    my $lbl_pre  = $self->_current_block_label;

    # Pre-loop -> loop header
    $self->_set_terminator("  br label \%$lbl_loop");
    $self->_new_block($lbl_loop);

    # Loop header: phi for i using pre_loop (=0) and hnxt (=i+1) predecessors.
    my $i_phi = $self->_fresh;
    my $i_next = $self->_fresh;  # defined later in hnxt; its name is known now
    $self->_emit("  $i_phi = phi i64 [ 0, \%$lbl_pre ], [ $i_next, \%$lbl_nxt ]  ; HashRead: loop counter");
    my $loop_cond = $self->_fresh;
    $self->_emit("  $loop_cond = icmp ult i64 $i_phi, $count  ; HashRead: i < count?");
    $self->_set_terminator("  br i1 $loop_cond, label \%$lbl_chk, label \%$lbl_miss");

    # hchk: load entry[i], compare key length.
    $self->_new_block($lbl_chk);
    my $ent_p   = $self->_fresh;
    my $ent_kpp = $self->_fresh;
    my $ent_klp = $self->_fresh;
    my $ent_vdp = $self->_fresh;
    my $ent_vpp = $self->_fresh;
    my $ent_kp  = $self->_fresh;
    my $ent_kl  = $self->_fresh;
    $self->_emit("  $ent_p   = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i_phi  ; HashRead: entry[$i_phi] ptr");
    $self->_emit("  $ent_kpp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 " . _he_idx('key_ptr') . "  ; HashRead: key_ptr field ptr");
    $self->_emit("  $ent_klp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 " . _he_idx('key_len') . "  ; HashRead: key_len field ptr");
    $self->_emit("  $ent_vdp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 " . _he_idx('val_def') . "  ; HashRead: val_def field ptr");
    $self->_emit("  $ent_vpp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 " . _he_idx('val_pay') . "  ; HashRead: val_pay field ptr");
    $self->_emit("  $ent_kp  = load i8*,  i8**  $ent_kpp  ; HashRead: load entry key ptr");
    $self->_emit("  $ent_kl  = load i64,  i64*  $ent_klp  ; HashRead: load entry key len");
    my $len_eq = $self->_fresh;
    $self->_emit("  $len_eq = icmp eq i64 $ent_kl, $lkey_len  ; HashRead: key-len eq?");
    $self->_set_terminator("  br i1 $len_eq, label \%$lbl_cmp, label \%$lbl_nxt");

    # hcmp: memcmp key bytes.
    $self->_new_block($lbl_cmp);
    my $cmp_res  = $self->_fresh;
    my $is_match = $self->_fresh;
    $self->_emit("  $cmp_res  = call i32 \@memcmp(i8* nocapture readonly $ent_kp, i8* nocapture readonly $lkey_ref, i64 $lkey_len)  ; HashRead: key memcmp");
    $self->_emit("  $is_match = icmp eq i32 $cmp_res, 0  ; HashRead: key match?");
    $self->_set_terminator("  br i1 $is_match, label \%$lbl_hit, label \%$lbl_nxt");

    # hhit: load value slot.
    $self->_new_block($lbl_hit);
    my $vd_val = $self->_fresh;
    my $vp_val = $self->_fresh;
    $self->_emit("  $vd_val = load i1,  i1*  $ent_vdp  ; HashRead: val defined bit");
    $self->_emit("  $vp_val = load i64, i64* $ent_vpp  ; HashRead: val payload");
    my ($vt_p, $vt_val) = ($self->_fresh, $self->_fresh);
    $self->_emit("  $vt_p = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 "
        . _he_idx('val_tag') . "  ; HashRead: val_tag field ptr");
    $self->_emit("  $vt_val = load i8, i8* $vt_p  ; HashRead: val tag");
    # The complete Slot, HERE in the arm, so the merge below is one `phi
    # %Slot`; its tag is the one stored with the value.
    my $slot_hit = $self->_fresh;
    {
        my ($s0, $s1) = ($self->_fresh, $self->_fresh);
        $self->_emit("  $s0 = insertvalue %Slot undef, i1 $vd_val, " . _slot_idx('defined') . "  ; HashRead hit: defined");
        $self->_emit("  $s1 = insertvalue %Slot $s0, i8 $vt_val, " . _slot_idx('tag') . "  ; HashRead hit: stored tag");
        $self->_emit("  $slot_hit = insertvalue %Slot $s1, i64 $vp_val, " . _slot_idx('payload') . "  ; HashRead hit: payload");
    }
    $self->_set_terminator("  br label \%$lbl_end");

    # hnxt: i++ and back-edge to loop header.
    $self->_new_block($lbl_nxt);
    # $i_next was fresh()ed earlier so its name is deterministic.
    $self->_emit("  $i_next = add i64 $i_phi, 1  ; HashRead: i++");
    $self->_set_terminator("  br label \%$lbl_loop");

    # hmiss: key not found.
    $self->_new_block($lbl_miss);
    # An EXPLICIT undef slot for this arm -- defined=false, tag=Undef,
    # payload=0 -- so the phi's incoming value is a complete aggregate, no
    # field left poison. Tag is 'Undef' rather than 'Opaque': a missing key
    # reads as undef, and that reading IS established.
    my $slot_miss = $self->_build_slot('false', '0', 'Undef', 'HashRead miss');
    $self->_set_terminator("  br label \%$lbl_end");

    # hend: ONE Slot phi, then this read's reading of it, by the stored tag.
    # Decoded instead by the read's stamp, a value of another reading was
    # garbage (an Int read as Num), and a missing key read as Str loaded
    # through a null %Str*.
    $self->_new_block($lbl_end);
    my $slot = $self->_fresh;
    $self->_emit("  $slot = phi %Slot [ $slot_hit, \%$lbl_hit ], [ $slot_miss, \%$lbl_miss ]  ; HashRead :Slot phi");
    return $slot;
}

# _lower_postfix_deref: repr-dispatch on sigil to dereference a ref value.
# sigil="@" → ArrayRef (i8*) → Array* bitcast (_lower_array_deref body).
# sigil="%" → HashRef  (i8*) → Hash*  bitcast (_lower_hash_deref body).
# sigil="$" → scalar deref (not yet in corpus; GAPs loudly).
# The input is the ref value (i8*); the output is the struct pointer.
sub _lower_postfix_deref {
    my ($self, $node) = @_;
    my $sigil = $node->sigil();

    if ($sigil eq '@') {
        return $self->_lower_array_deref($node);
    }
    elsif ($sigil eq '%') {
        return $self->_lower_hash_deref($node);
    }
    elsif ($sigil eq '$') {
        # $$r: the %Slot the reference points at, read as this node reads.
        my $ptr  = $self->_scalar_ref_target($node->inputs->[0]);
        my $slot = $self->_fresh;
        $self->_emit("  $slot = load %Slot, %Slot* $ptr  ; \$\$ref: read");
        my $repr = $node->stamp // 'Scalar';
        my $ref  = $repr =~ /\A(?:Int|Num|Str|Boolean)\z/
            ? $self->_emit_coercion($slot, 'Scalar', $repr, '$$ref') : $slot;
        $self->{cache}{ $node->id } = $ref;
        return $ref;
    }
    else {
        die "GAP: PostfixDeref sigil='$sigil' is not yet lowered runtime-free (only \$, @ and % are supported).";
    }
}

# _scalar_ref_target($ref_node) -> the %Slot* a scalar reference names.
sub _scalar_ref_target {
    my ($self, $ref_node) = @_;
    # A SCALAR HOLDING A REFERENCE: its Slot's payload, when its tag says
    # ScalarRef. Anything else is refused at run time (perl dies too: "Not a
    # SCALAR reference").
    if (($ref_node->stamp // '') =~ /\A(?:Scalar|Slot)\z/) {
        my $s   = $self->lower_value($ref_node);
        my $tag = $self->_slot_tag_of($s);
        my $ok  = $self->_fresh;
        $self->_emit("  $ok = icmp eq i8 $tag, " . _slot_tag_value('ScalarRef') . "  ; \$\$r: a scalar reference?");
        my ($yes, $no) = ($self->_fresh_label('sref.ok.'), $self->_fresh_label('sref.no.'));
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $ok, label %$yes, label %$no");
        $self->_new_block($no);
        $self->_refuse_inside_eval("a deref that dies on what is not a SCALAR reference");
        $self->_emit("  call void \@exit(i32 255)  ; not a SCALAR reference");
        $self->_set_terminator("  unreachable");
        $self->_new_block($yes);
        my $p   = $self->_slot_payload_of($s);
        my $ptr = $self->_fresh;
        $self->_emit("  $ptr = inttoptr i64 $p to %Slot*  ; Scalar -> %Slot*");
        return $ptr;
    }
    die "GAP: a scalar deref of a " . ($ref_node->stamp // 'NONE') . " is not lowered\n"
        unless ($ref_node->stamp // '') eq 'ScalarRef';
    my $r   = $self->lower_value($ref_node);
    my $ptr = $self->_fresh;
    $self->_emit("  $ptr = bitcast i8* $r to %Slot*  ; ScalarRef -> %Slot*");
    return $ptr;
}

# _lower_ref($node) -> i8*, the reference `\X` makes.
#
# A REFERENCE IS ITS REFERENT'S STORAGE. An %Array or %Hash is one heap
# object already, so `\@a` is that pointer as a ref, and writes through it
# are writes to @a. `\$x` points at $x's %Slot -- taking a reference makes a
# scalar a location (B::SoN keeps it in memory), so it has one. Anything
# else (a reference to a value, to code) is refused.
sub _lower_ref {
    my ($self, $node) = @_;
    my $x = $node->inputs->[0];
    die "GAP: a reference with no referent is not lowered\n" unless blessed($x);
    # `\$_[N]` IS TO THE CALLER'S VARIABLE, whose location the binding took in
    # the caller's frame (_arg_binding); through a copy it reached @_ (pvm
    # 203). Resolved in this frame, it was a fresh `my` of the same name and a
    # write through it was lost. Any other argument (an element, a value) is
    # refused.
    if ($x->operation eq 'Subscript' && $self->{_arg_bind}
            && (my $b = $self->{_arg_bind}{ refaddr($x) })) {
        die "GAP: a reference to an argument that is not a variable kept in memory is not lowered\n"
            unless defined $b->{loc};
        my $ref = $self->_fresh;
        $self->_emit("  $ref = bitcast %Slot* $b->{loc} to i8*  ; \\\$_[N]: the caller's variable");
        return $ref;
    }
    my $xs = $x->stamp // '';
    my ($ptr, $ty);
    if ($xs eq 'Array' || $xs eq 'Hash') {
        $ty  = $xs eq 'Array' ? '%Array*' : '%Hash*';
        $ptr = $self->_container_ptr($x, $xs);
    }
    elsif ($x->operation eq 'PadAccess' && $x->is_location) {
        # ONE LOCATION PER LEXICAL: a `my` a loop renews each pass is one
        # $x here, so every pass's \$x named the last pass's (pvm 219).
        die "GAP: a reference to a my variable a loop renews each pass is not lowered "
          . "-- chalk keeps one location per lexical\n" if $node->fresh_each_pass;
        $ty  = '%Slot*';
        $ptr = $self->_location_ptr($x);
    }
    # AN ELEMENT'S REFERENCE IS ITS SLOT in the array's buffer -- the alias a
    # foreach takes of each element it walks. Bounds-checked at run time (perl
    # would extend the array; that is refused, exit 255), and refused outright
    # for an array anything grows: a grown buffer is a new one.
    elsif ($x->operation eq 'Subscript' && ( $self->_repr_of($x->inputs->[0]) // '' ) =~ /\A(?:Array|ArrayRef)\z/) {
        my $ctr = $self->_unwrap_ref_container($x->inputs->[0]);
        die "GAP: a reference to an element of an array that may grow is not lowered\n"
            if _array_may_grow($ctr);
        $self->_refuse_inside_eval("a reference to an array element (it dies before the start)");
        my $arr = $self->_container_ptr($ctr, 'Array');
        my $i   = $self->_index_i64($x->inputs->[1]);
        my ($lp, $len, $ok, $ep, $el) = map { $self->_fresh } 1 .. 5;
        $self->_emit("  $lp = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; element ref: len ptr");
        $self->_emit("  $len = load i64, i64* $lp");
        $self->_emit("  $ok = icmp ult i64 $i, $len  ; element ref: in bounds?");
        my ($in, $out) = ($self->_fresh_label('eref.in.'), $self->_fresh_label('eref.out.'));
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $ok, label %$in, label %$out");
        $self->_new_block($out);
        $self->_emit("  call void \@exit(i32 255)  ; a reference past the end would extend the array");
        $self->_set_terminator("  unreachable");
        $self->_new_block($in);
        $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2");
        $self->_emit("  $el = load %Slot*, %Slot** $ep");
        $ptr = $self->_fresh;
        $self->_emit("  $ptr = getelementptr inbounds %Slot, %Slot* $el, i64 $i  ; element ref");
        $ty  = '%Slot*';
    }
    else {
        die "GAP: a reference to a " . $x->operation . " ($xs) is not lowered -- "
          . "only to an array, a hash, or a scalar variable\n";
    }
    # NOT CACHED: a bitcast is free, and one made inside an arm, served to a
    # use after the merge, did not dominate it.
    my $ref = $self->_fresh;
    $self->_emit("  $ref = bitcast $ty $ptr to i8*  ; \\" . ($x->can('name') ? $x->name : $xs));
    return $ref;
}

# _lower_reftype($node) -> Str, what ref() says of its operand.
#
# By the operand's repr where it is known: "ARRAY", "HASH", "SCALAR",
# "CODE", or "" for no reference. A Scalar is decided by its Slot's tag. A
# blessed object names its class, which no tag carries: refused statically,
# and a tag that turns out to be one at run time stops the program rather
# than answer "".
sub _lower_reftype {
    my ($self, $node) = @_;
    my $x  = $node->inputs->[0];
    my $xs = blessed($x) ? ($self->_repr_of($x) // '') : '';
    my %name = (ArrayRef => 'ARRAY', HashRef => 'HASH', ScalarRef => 'SCALAR', CodeRef => 'CODE');
    # ITS CLASS IS READ WHERE ref() IS LOWERED, not where it stands: a bless
    # elsewhere of this same reference (a rebless, or a bless after an
    # unblessed ref() of it) would be seen or missed by position. Refused.
    die "GAP: ref() of a reference that a bless elsewhere changes is not lowered -- "
      . "which class it reads would depend on where it is lowered\n"
        if blessed($x) && grep {
            blessed($_) && $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin'
                && ( $_->name // '' ) eq 'bless' && blessed($_->inputs->[0])
                && refaddr($_->inputs->[0]) == refaddr($x)
        } ($x->consumers // [])->@*;
    my $ref;
    # A REFERENCE MAY BE BLESSED: its class, if bless recorded one.
    if ($xs =~ /\A(?:Array|Hash|Scalar)Ref\z/) {
        my $r = $self->lower_value($x);
        my ($is, $cp, $cl) = $self->_bless_class($r);
        my ($p, $l) = $self->_str_const_parts($name{$xs}, 'ref()');
        my ($np, $nl) = map { $self->_fresh } 1 .. 2;
        $self->_emit("  $np = select i1 $is, i8* $cp, i8* $p  ; ref(): its class, or what it is");
        $self->_emit("  $nl = select i1 $is, i64 $cl, i64 $l");
        $ref = $self->_set_str_len($np, $nl);
    }
    elsif (exists $name{$xs} || $xs =~ /\A(?:Int|Num|Str|Boolean|Undef)\z/) {
        my ($p, $l) = $self->_str_const_parts($name{$xs} // '', 'ref()');
        $ref = $self->_set_str_len($p, $l);
    }
    elsif ($xs eq 'Scalar') {
        my $slot = $self->lower_value($x);
        my $tag  = $self->_slot_tag_of($slot);
        my ($p, $l) = $self->_str_const_parts('', 'ref(): none');
        for my $k (sort keys %name) {
            my ($kp, $kl) = $self->_str_const_parts($name{$k}, "ref(): $k");
            my ($is, $np, $nl) = map { $self->_fresh } 1 .. 3;
            $self->_emit("  $is = icmp eq i8 $tag, " . _slot_tag_value($k) . "  ; ref(): a $k?");
            $self->_emit("  $np = select i1 $is, i8* $kp, i8* $p");
            $self->_emit("  $nl = select i1 $is, i64 $kl, i64 $l");
            ($p, $l) = ($np, $nl);
        }
        # An array, hash or scalar reference held by tag may be blessed too:
        # its payload is the pointer bless recorded.
        {
            my ($ia, $ih, $isr, $any, $any2, $ptr, $bp, $bl) = map { $self->_fresh } 1 .. 8;
            $self->_emit("  $ia = icmp eq i8 $tag, " . _slot_tag_value('ArrayRef'));
            $self->_emit("  $ih = icmp eq i8 $tag, " . _slot_tag_value('HashRef'));
            $self->_emit("  $isr = icmp eq i8 $tag, " . _slot_tag_value('ScalarRef'));
            $self->_emit("  $any = or i1 $ia, $ih");
            $self->_emit("  $any2 = or i1 $any, $isr  ; ref(): a reference that may be blessed?");
            my $pl = $self->_slot_payload_of($slot);
            $self->_emit("  $ptr = inttoptr i64 $pl to i8*");
            my ($is, $cp, $cl) = $self->_bless_class($ptr);
            my ($both, $np, $nl) = map { $self->_fresh } 1 .. 3;
            $self->_emit("  $both = and i1 $any2, $is");
            $self->_emit("  $np = select i1 $both, i8* $cp, i8* $p  ; ref(): its class");
            $self->_emit("  $nl = select i1 $both, i64 $cl, i64 $l");
            ($p, $l) = ($np, $nl);
        }
        $self->{_need_exit} = 1;
        my ($obj, $ok, $stop) = ($self->_fresh, $self->_fresh_label('reftype_ok'), $self->_fresh_label('reftype_obj'));
        $self->_emit("  $obj = icmp eq i8 $tag, " . _slot_tag_value('Object') . "  ; ref(): an object?");
        $self->_set_terminator("  br i1 $obj, label %$stop, label %$ok");
        $self->_new_block($stop);
        $self->_emit("  call void \@exit(i32 255)  ; ref() of an object names its class: not lowered");
        $self->_set_terminator("  unreachable");
        $self->_new_block($ok);
        $ref = $self->_set_str_len($p, $l);
    }
    else {
        die "GAP: ref() of a $xs is not lowered\n";
    }
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _lower_array_deref: cast i8* ref back to %Array*.
# The input is an ArrayRef (i8*); the output is an Array* for use by Length/Subscript.
sub _lower_array_deref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;

    my $in = $node->inputs->[0];
    my $arr;
    my $in_repr = $self->_repr_of($in) // '';
    # COUNTED, `@{ undef }` is undef, not 0 (perl's rvalue deref of undef in
    # scalar context); the empty array below is only its list reading.
    # shortcut: the tag-read path below still counts a run-time undef as 0;
    # refusing it would refuse every `scalar @{ $h{k} }`. Upgrade: a Count
    # that yields a Scalar when its deref's operand may be undef.
    die "GAP: a count of \@{} over what may be undef is not lowered -- perl's is undef, not 0\n"
        if $in_repr eq 'Undef' && !$node->copy   # a copy (`my @l = @$r`) is a real, empty array
        && grep { blessed($_) && $_->operation eq 'Count' } ( $node->can('consumers') ? $node->consumers->@* : () );
    # AN UNDEF (`@{ $h{missing} }`, known missing) is an empty list.
    if ($in_repr eq 'Undef') {
        $arr = $self->_emit_array_of([]);
    }
    # A VALUE READ BY ITS TAG (`$h{k} // []` merges a Scalar and an ArrayRef
    # into a Slot): an ArrayRef is its payload, undef an empty array (perl's
    # rvalue `@{ undef }`); anything else dies in perl (exit 255).
    elsif ($in_repr =~ /\A(?:Scalar|Slot)\z/) {
        my $s   = $self->lower_value($in);
        my $tag = $self->_slot_tag_of($s);
        my ($isref, $isundef, $p, $yesp) = map { $self->_fresh } 1 .. 4;
        my ($yes, $notref, $undef, $no, $join) = map { $self->_fresh_label("aderef.$_.") } qw(ref notref undef no join);
        $self->_emit("  $isref = icmp eq i8 $tag, " . _slot_tag_value('ArrayRef') . "  ; \@{}: an array reference?");
        $self->_set_terminator("  br i1 $isref, label %$yes, label %$notref");
        $self->_new_block($yes);
        my $pl = $self->_slot_payload_of($s);
        $self->_emit("  $yesp = inttoptr i64 $pl to %Array*  ; Scalar -> %Array*");
        $self->_set_terminator("  br label %$join");
        $self->_new_block($notref);
        $self->_emit("  $isundef = icmp eq i8 $tag, " . _slot_tag_value('Undef') . "  ; \@{}: undef?");
        $self->_set_terminator("  br i1 $isundef, label %$undef, label %$no");
        $self->_new_block($no);
        $self->{_need_exit} = 1;
        $self->_refuse_inside_eval("a deref that dies on what is not an ARRAY reference");
        $self->_emit("  call void \@exit(i32 255)  ; not an ARRAY reference");
        $self->_set_terminator("  unreachable");
        $self->_new_block($undef);
        my $empty = $self->_emit_array_of([]);
        my $from_undef = $self->_current_block_label;
        $self->_set_terminator("  br label %$join");
        $self->_new_block($join);
        $arr = $self->_fresh;
        $self->_emit("  $arr = phi %Array* [ $yesp, %$yes ], [ $empty, %$from_undef ]  ; \@{}: the array");
    }
    else {
        my $ref_val = $self->lower_value($in);
        $arr = $self->_fresh;
        $self->_emit("  $arr = bitcast i8* $ref_val to %Array*  ; ArrayDeref: i8* ref -> Array*");
    }
    $arr = $self->_emit_aggregate_copy($arr, 'Array') if $node->copy;
    $self->{cache}{ $node->id } = $arr;
    return $arr;
}

# _emit_aggregate_copy($ptr, 'Array'|'Hash') -> a new %Array*/%Hash* holding
# what $ptr does: a new header and the live slots or entries copied. Both
# headers are { i64 count, i64 cap, buffer }, so one copy serves.
sub _emit_aggregate_copy {
    my ($self, $src, $kind) = @_;
    $self->{_need_malloc_memcpy} = 1;
    my $ty   = "%$kind";
    my $elem = $kind eq 'Array' ? '%Slot' : '%HashEntry';
    my ($np, $n, $bp, $buf, $bytes, $nb, $nbuf, $raw, $hdr, $new) = map { $self->_fresh } 1 .. 10;
    $self->_emit("  $np = getelementptr inbounds $ty, $ty* $src, i32 0, i32 0  ; copy: count ptr");
    $self->_emit("  $n = load i64, i64* $np  ; copy: count");
    $self->_emit("  $bp = getelementptr inbounds $ty, $ty* $src, i32 0, i32 2  ; copy: buffer ptr");
    $self->_emit("  $buf = load $elem*, $elem** $bp  ; copy: buffer");
    $self->_emit("  $bytes = mul i64 $n, " . _sizeof_llvm_type($elem) . "  ; copy: live bytes");
    $self->_emit("  $nb = add i64 $bytes, 1  ; copy: never malloc(0)");
    $self->_emit("  $nbuf = call i8* \@malloc(i64 $nb)  ; copy: new buffer");
    $self->_emit("  $raw = bitcast $elem* $buf to i8*");
    $self->_emit("  call i8* \@memcpy(i8* $nbuf, i8* $raw, i64 $bytes)  ; copy: the elements");
    $self->_emit("  $hdr = call i8* \@malloc(i64 " . _sizeof_llvm_type($ty) . ")  ; copy: new header");
    $self->_emit("  $new = bitcast i8* $hdr to $ty*");
    my ($f0, $f1, $f2, $tb) = map { $self->_fresh } 1 .. 4;
    $self->_emit("  $f0 = getelementptr inbounds $ty, $ty* $new, i32 0, i32 0");
    $self->_emit("  store i64 $n, i64* $f0  ; copy: count");
    $self->_emit("  $f1 = getelementptr inbounds $ty, $ty* $new, i32 0, i32 1");
    $self->_emit("  store i64 $n, i64* $f1  ; copy: cap");
    $self->_emit("  $f2 = getelementptr inbounds $ty, $ty* $new, i32 0, i32 2");
    $self->_emit("  $tb = bitcast i8* $nbuf to $elem*");
    $self->_emit("  store $elem* $tb, $elem** $f2  ; copy: buffer");
    return $new;
}

# _lower_hash_deref: cast i8* ref back to %Hash*.
sub _lower_hash_deref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;

    my $in = $node->inputs->[0];
    my $hash;
    # AN UNDEF (`%{ $h{missing} }`, known missing) is an empty hash.
    my $empty_hash = sub {
        my ($raw, $empty, $c0, $c1, $c2) = map { $self->_fresh } 1 .. 5;
        $self->{_need_malloc_memcpy} = 1;
        $self->_emit("  $raw = call i8* \@malloc(i64 " . _sizeof_llvm_type('%Hash') . ")  ; %{ undef }: an empty hash");
        $self->_emit("  $empty = bitcast i8* $raw to %Hash*");
        $self->_emit("  $c0 = getelementptr inbounds %Hash, %Hash* $empty, i32 0, i32 0");
        $self->_emit("  store i64 0, i64* $c0  ; count=0");
        $self->_emit("  $c1 = getelementptr inbounds %Hash, %Hash* $empty, i32 0, i32 1");
        $self->_emit("  store i64 0, i64* $c1  ; cap=0");
        $self->_emit("  $c2 = getelementptr inbounds %Hash, %Hash* $empty, i32 0, i32 2");
        $self->_emit("  store %HashEntry* null, %HashEntry** $c2  ; no entries");
        return $empty;
    };
    if (( $self->_repr_of($in) // '' ) eq 'Undef') {
        $hash = $empty_hash->();
    }
    # A VALUE READ BY ITS TAG (an object's field, `$h{m} // $h{n}`): a
    # HashRef is its payload, undef an empty hash (perl's rvalue `%{ undef }`),
    # anything else dies in perl (exit 255) -- as _lower_array_deref.
    elsif (( $self->_repr_of($in) // '' ) =~ /\A(?:Scalar|Slot)\z/) {
        my $s   = $self->lower_value($in);
        my $tag = $self->_slot_tag_of($s);
        my ($isref, $isundef, $yesp) = map { $self->_fresh } 1 .. 3;
        my ($yes, $notref, $undef, $no, $join) = map { $self->_fresh_label("hderef.$_.") } qw(ref notref undef no join);
        $self->_emit("  $isref = icmp eq i8 $tag, " . _slot_tag_value('HashRef') . "  ; %{}: a hash reference?");
        $self->_set_terminator("  br i1 $isref, label %$yes, label %$notref");
        $self->_new_block($yes);
        my $pl = $self->_slot_payload_of($s);
        $self->_emit("  $yesp = inttoptr i64 $pl to %Hash*  ; Scalar -> %Hash*");
        $self->_set_terminator("  br label %$join");
        $self->_new_block($notref);
        $self->_emit("  $isundef = icmp eq i8 $tag, " . _slot_tag_value('Undef') . "  ; %{}: undef?");
        $self->_set_terminator("  br i1 $isundef, label %$undef, label %$no");
        $self->_new_block($no);
        $self->{_need_exit} = 1;
        $self->_refuse_inside_eval("a deref that dies on what is not a HASH reference");
        $self->_emit("  call void \@exit(i32 255)  ; not a HASH reference");
        $self->_set_terminator("  unreachable");
        $self->_new_block($undef);
        my $empty = $empty_hash->();
        $self->_set_terminator("  br label %$join");
        $self->_new_block($join);
        $hash = $self->_fresh;
        $self->_emit("  $hash = phi %Hash* [ $yesp, %$yes ], [ $empty, %$undef ]  ; %{}: the hash");
    }
    else {
        my $ref_val = $self->lower_value($in);
        $hash = $self->_fresh;
        $self->_emit("  $hash = bitcast i8* $ref_val to %Hash*  ; HashDeref: i8* ref -> Hash*");
    }
    $hash = $self->_emit_aggregate_copy($hash, 'Hash') if $node->copy;
    $self->{cache}{ $node->id } = $hash;
    return $hash;
}

# ---------------------------------------------------------------------------
# MOP / class object lowering (G5: feature-class static vtables + object structs)
# ---------------------------------------------------------------------------

# _lower_call_new($node) -> $llvm_ref
#
# _store_field_payload($val_ref, $repr, $pay_gep, $pname) -> $stored_ref
#
# Store a lowered value into an object field's i64 payload slot, boxing per repr.
# The single owner of the slot-payload store dispatch, shared across the :param
# binding path, the default-value path, and the FieldAccess-lvalue assign path so
# every write boxes a given repr identically (019f4512): Str -> malloc a %Str,
# store ptr+len, ptrtoint to i64; Boolean -> zext i1 to i64; ArrayRef/HashRef ->
# ptrtoint i8* to i64; Int -> identity. The Str length is read from
# _str_len_table (keyed by the value's SSA ref), falling back to a runtime strlen
# when the length is not compile-time tracked. Caller has already emitted the
# defined-bit store and resolved $pay_gep.
#
# Returns the SSA ref that represents the field's value at this program point:
# the original i8* string ref for Str, or the boxed i64 payload for everything
# else. Callers that use the assign expression as a value (FieldAccess-lvalue)
# cache this; the :param / default callers ignore it.
# _box_payload($val_ref, $repr, $what) -> $i64_ref
#
# The one rule for putting a value into a %Slot's i64 payload. The i64 is a
# machine WORD: it carries an Int directly, a Boolean zero-extended, a Num
# bitcast, and anything wider as a POINTER to a heap box.
#
# Every optional-value cell in the backend is this shape -- an array element,
# an object field, and a hash entry's inlined (val_def, val_pay) pair -- so
# they share this rule rather than each deciding for themselves. They used to
# decide separately, and the ones that were not exercised fell behind: a field
# could hold a Str (boxed into a %Str) while an array element could not,
# so `my @a = ("hi")` -- unremarkable Perl -- could not be represented.
#
# $what labels the emitted IR ("field 'n'", "ArrayRef elem[0]").
sub _box_payload {
    my ($self, $val_ref, $repr, $what) = @_;

    my $ref = $self->_fresh;
    if ($repr eq 'Str') {
        # A Str is a (ptr, len) PAIR and does not fit in one word, so box it
        # into a heap %Str and carry the pointer. The length must come from
        # the length table; strlen would be wrong for a string with an embedded
        # NUL and is only a fallback for an untracked pointer.
        my ($str_ptr, $len_ref) = $self->_str_parts($val_ref);
        my $pair_raw = $self->_fresh;
        my $pair_ptr = $self->_fresh;
        my $pair_bytes = _sizeof_llvm_type('%Str');
        $self->_emit("  $pair_raw = call i8* \@malloc(i64 $pair_bytes)  ; alloc StrPair ($pair_bytes bytes) for $what");
        $self->_emit("  $pair_ptr = bitcast i8* $pair_raw to %Str*  ; typed StrPair ptr");
        my $pp_gep = $self->_fresh;
        $self->_emit("  $pp_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
        $self->_emit("  store i8* $str_ptr, i8** $pp_gep  ; store str ptr");
        my $pl_gep = $self->_fresh;
        $self->_emit("  $pl_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 1  ; StrPair.len");
        my $len_val = $len_ref;
        unless (defined $len_val) {
            $len_val = $self->_fresh;
            $self->_emit("  $len_val = call i64 \@strlen(i8* $str_ptr)  ; strlen for $what");
        }
        $self->_emit("  store i64 $len_val, i64* $pl_gep  ; store str len");
        # ENC IS WRITTEN, NOT LEFT AS MALLOC GARBAGE. It has no reader yet, so
        # skipping it is invisible today and becomes a heisenbug the moment one
        # lands -- in the reader, not here. 0 is the ASCII/UTF-8 default the
        # field list documents; a boxed Str whose encoding was never decided is
        # exactly the value that default is for.
        my $pe_gep = $self->_fresh;
        $self->_emit("  $pe_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 "
                   . _str_idx('enc') . "  ; %Str.enc");
        $self->_emit("  store i32 " . _str_enc('utf8') . ", i32* $pe_gep  ; store str enc (utf8)");
        $self->_emit("  $ref = ptrtoint %Str* $pair_ptr to i64  ; boxed %Str -> i64 payload for $what");
        $self->{_need_str_type} = 1;
        $self->{_need_malloc_memcpy} = 1;
        return $ref;
    }
    if ($repr eq 'Num') {
        # A double is exactly one word: reinterpret its bits rather than boxing.
        # The read side bitcasts back, so no precision is lost.
        my $num_ty = _repr_to_llvm_type($repr);
        $self->_emit("  $ref = bitcast $num_ty $val_ref to i64  ; Num -> i64 payload for $what");
        return $ref;
    }
    if ($repr eq 'Boolean') {
        $self->_emit("  $ref = zext i1 $val_ref to i64  ; Boolean -> i64 payload for $what");
        return $ref;
    }
    if ($repr eq 'ArrayRef' || $repr eq 'HashRef' || $repr eq 'CodeRef' || $repr eq 'ScalarRef'
            || $repr eq 'Object') {
        $self->_emit("  $ref = ptrtoint i8* $val_ref to i64  ; $repr ptr -> i64 payload for $what");
        return $ref;
    }
    # An Int IS the payload word — no conversion, and no instruction.
    return $val_ref if $repr eq 'Int';

    die "GAP: $what has repr=$repr, which has no i64 payload encoding "
      . "(Int, Boolean, Num, Str and ref types are boxed) — refusing to emit "
      . "invalid IR.";
}

# _field_store_is_coherent($field_repr, $value_repr) -> bool
#
# The i64 field payload holds ONE of two kinds of thing, and store and read must
# agree on which:
#
#   DIRECT -- the value itself in the 64 bits: Int (identity), Boolean (zext).
#   BOXED  -- a POINTER stored via ptrtoint: Str (a StrPair*), ArrayRef/HashRef
#             (an i8*).
#
# _store_field_payload picks by the VALUE's repr; _lower_field_access_in_method
# reads by the FieldAccess NODE's repr. When those disagree about the KIND, the
# read `inttoptr`s an integer or uses an address as a number -- the segfault
# this check exists to prevent.
#
# This is a T2 question and only a T2 question: GIVEN THESE TWO ENCODINGS, IS
# THIS STORE COHERENT? It is deliberately NOT subtyping. `Str <: Scalar` holds
# in the type lattice, yet storing a StrPair* into a Scalar-declared field is
# incoherent, because a Scalar-declared read loads a bare i64. Subtyping is the
# wrong tool here; agreement of interpretation is the right one.
#
# `Scalar` is the un-narrowed cell: its payload is a plain i64, so it accepts
# any DIRECT value (this is what makes Int-into-Scalar legal, and it is the
# whole 9-case `classes` regression) and refuses every BOXED one.
sub _field_store_is_coherent {
    my ($field_repr, $value_repr) = @_;

    # No declaration, nothing to disagree with.
    return true if !defined $field_repr;
    return true if $field_repr eq $value_repr;

    my %BOXED  = map { $_ => 1 } qw(Str ArrayRef HashRef);
    my %DIRECT = map { $_ => 1 } qw(Int Boolean);

    # The general cell reads as a bare i64, so it holds any direct value.
    return $DIRECT{$value_repr} ? true : false if $field_repr eq 'Scalar';

    # Otherwise the two must name the SAME encoding, and the equality check
    # above already covered that: distinct boxed kinds bitcast differently on
    # read, and a direct value read as boxed (or the reverse) misreads the bits.
    return false;
}

sub _store_field_payload {
    my ($self, $val_ref, $repr, $pay_gep, $pname) = @_;

    if ($repr eq 'Str') {
        my ($str_ptr, $len_ref) = $self->_str_parts($val_ref);
        my $pair_raw = $self->_fresh;
        my $pair_ptr = $self->_fresh;
        my $pair_bytes = _sizeof_llvm_type('%Str');
        $self->_emit("  $pair_raw = call i8* \@malloc(i64 $pair_bytes)  ; alloc StrPair ($pair_bytes bytes) for field '$pname'");
        $self->_emit("  $pair_ptr = bitcast i8* $pair_raw to %Str*  ; typed StrPair ptr");
        my $pp_gep = $self->_fresh;
        $self->_emit("  $pp_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
        $self->_emit("  store i8* $str_ptr, i8** $pp_gep  ; store str ptr");
        my $pl_gep = $self->_fresh;
        $self->_emit("  $pl_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 1  ; StrPair.len");
        my $len_val = defined $len_ref ? $len_ref : 'zeroinitializer';
        if ($len_val eq 'zeroinitializer') {
            $len_val = $self->_fresh;
            $self->_emit("  $len_val = call i64 \@strlen(i8* $str_ptr)  ; strlen for Str field '$pname'");
        }
        $self->_emit("  store i64 $len_val, i64* $pl_gep  ; store str len");
        # enc, for the same reason as the sibling boxing site above: an
        # uninitialised field whose reader is coming is a heisenbug scheduled
        # for the day the reader lands.
        my $fe_gep = $self->_fresh;
        $self->_emit("  $fe_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 "
                   . _str_idx('enc') . "  ; %Str.enc");
        $self->_emit("  store i32 " . _str_enc('utf8') . ", i32* $fe_gep  ; store str enc (utf8)");
        my $pair_as_i64 = $self->_fresh;
        $self->_emit("  $pair_as_i64 = ptrtoint %Str* $pair_ptr to i64  ; boxed %Str -> i64 payload");
        $self->_emit("  store i64 $pair_as_i64, i64* $pay_gep  ; field '$pname' Str payload = StrPair*");
        $self->{_need_str_type} = 1;
        return $val_ref;
    }

    my $pay_i64 = $self->_fresh;
    if ($repr eq 'Boolean') {
        $self->_emit("  $pay_i64 = zext i1 $val_ref to i64  ; Boolean->i64 for field '$pname'");
    } elsif ($repr eq 'Array' || $repr eq 'Hash') {
        # AN AGGREGATE FIELD'S DEFAULT: the field holds a reference to it.
        $self->_emit("  $pay_i64 = ptrtoint %${repr}* $val_ref to i64  ; $repr -> its reference for field '$pname'");
    } elsif ($repr eq 'ArrayRef' || $repr eq 'HashRef') {
        # Pointer-repr value: ptrtoint before storing into the i64 payload,
        # mirroring the array/hash element-store branches. A bare
        # `add i64 0, <ptr>` would be invalid IR.
        $self->_emit("  $pay_i64 = ptrtoint i8* $val_ref to i64  ; $repr ptr -> i64 for field '$pname'");
    } elsif ($repr eq 'Int') {
        $self->_emit("  $pay_i64 = add i64 0, $val_ref  ; identity: Int->i64 for field '$pname'");
    } elsif ($repr eq 'Num') {
        # REINTERPRET the bits into the cell; do NOT convert. `fptosi` would
        # truncate 1.5 to 1 and silently lose the value -- the payload is a
        # 64-bit box, not an integer the number is being coerced to.
        #
        # The machine type comes from %_REPR_LLVM_TYPE rather than being named
        # here: what Num encodes AS is that table's decision and revisable per
        # context, so a second literal at this site would be a parallel
        # authority that could drift. Only the KIND of move -- a
        # reinterpretation -- is fixed here.
        my $num_ty = _repr_to_llvm_type($repr);
        $self->_emit("  $pay_i64 = bitcast $num_ty $val_ref to i64  ; $repr bits -> i64 payload for field '$pname'");
    } else {
        die "GAP: field '$pname' value repr=$repr cannot be stored in an i64 "
          . "payload (only Int/Num/Boolean/Str/ArrayRef/HashRef are lowered) — "
          . "refusing to emit invalid IR.";
    }
    $self->_emit("  store i64 $pay_i64, i64* $pay_gep  ; field '$pname' payload");
    return $pay_i64;
}

# _lower_runtime_dispatch($node, $obj) -> %Slot, or undef where it does not
# apply: a method on a blessed reference whose class is known only at run
# time. The candidates are the packages whose sub of that name the program
# declares; the class the bless table holds for the invocant picks one, and
# that sub is inlined in its arm, the invocant its first argument. No match
# stops the program (exit 255). Refused where a class could inherit or
# AUTOLOAD (another sub would run), or a `class` declares the method.
sub _lower_runtime_dispatch {
    my ($self, $node, $obj) = @_;
    my $mop = $self->{mop} or return undef;
    my $name = $node->name // return undef;
    my @classes = $mop->classes;
    my @cands = map { my $c = $_; map { [ $c->name, $_ ] } grep { $_->name eq $name } $c->subs } @classes;
    return undef unless @cands;
    die "GAP: a method ('$name') on a run-time class where a class inherits or has AUTOLOAD is not lowered\n"
        if grep { defined $_->superclass || defined $_->parent_name || grep { $_->name eq 'AUTOLOAD' } $_->subs } @classes;
    die "GAP: a method ('$name') on a run-time class that a `class` also declares is not lowered\n"
        if grep { $_->find_method($name) } @classes;
    # EVERY CLASS THE PROGRAM BLESSES INTO HAS IT, or an object of one would
    # reach no arm -- where perl dies naming the file and line, which nothing
    # here knows. A bless into a run-time class is into a class some `->new`
    # names.
    {
        my %has = map { $_->[0] => 1 } @cands;
        my (%into, $runtime);
        for my $n (@PROGRAM) {
            if ($n->operation eq 'Call' && ( $n->dispatch_kind // '' ) eq 'builtin' && ( $n->name // '' ) eq 'bless') {
                my $c = $n->inputs->[1];
                if (blessed($c) && $c->operation eq 'Constant' && ( $c->const_type // '' ) eq 'string') { $into{ $c->value } = 1 }
                else { $runtime = 1 }
            }
        }
        if ($runtime) {
            $into{ $_->class_name } = 1 for grep {
                $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'method'
                && ( $_->name // '' ) eq 'new' && defined $_->class_name
            } @PROGRAM;
        }
        my @lacking = grep { !$has{$_} } sort keys %into;
        die "GAP: a method ('$name') on a run-time class that a class this program blesses into "
          . "(@lacking) does not have is not lowered -- perl's death there names the file and line\n"
            if @lacking;
    }
    my $rs = $self->_repr_of($obj) // $obj->stamp // '';
    # AN INLINED ARGUMENT is the caller's value: its element read is the
    # caller's, read there (the callee's `$_[0]` has no array of its own).
    my $root = $obj;
    for (1 .. 32) {
        my $b = $self->{_arg_bind} ? $self->{_arg_bind}{ refaddr($root) } : undef;
        last unless $b && blessed($b->{node});
        $root = $b->{node};
    }
    my $ref;
    if ($rs =~ /\A(?:Hash|Array|Scalar)Ref\z/) { $ref = $self->lower_value($obj) }
    elsif ($rs eq 'Scalar' || ( $rs eq 'Object' && $root->operation eq 'Subscript' )) {
        # An element stamped Object is read as its Slot, by its tag.
        my $slot = $rs eq 'Scalar' ? $self->lower_value($obj) : $self->_subscript_slot($root);
        my ($tag, $ok) = ($self->_slot_tag_of($slot), $self->_fresh);
        my $pl = $self->_slot_payload_of($slot);
        my @is = map { my $t = $self->_fresh; $self->_emit("  $t = icmp eq i8 $tag, " . _slot_tag_value($_)); $t } qw(HashRef ArrayRef ScalarRef);
        $self->_emit("  $ok = or i1 $is[0], $is[1]");
        my $ok2 = $self->_fresh;
        $self->_emit("  $ok2 = or i1 $ok, $is[2]  ; dispatch: a reference?");
        my ($no, $yes) = map { $self->_fresh_label("dispatch.$_.") } qw(notref ref);
        $self->{_need_exit} = 1;
        $self->_set_terminator("  br i1 $ok2, label %$yes, label %$no");
        $self->_new_block($no);
        $self->_emit("  call void \@exit(i32 255)  ; a method on what is not a blessed reference");
        $self->_set_terminator("  unreachable");
        $self->_new_block($yes);
        $ref = $self->_fresh;
        $self->_emit("  $ref = inttoptr i64 $pl to i8*  ; dispatch: the invocant");
    }
    else { return undef }
    my ($is, $cp, $cl) = $self->_bless_class($ref);
    my @args = grep { blessed($_) } $node->inputs->@*;
    pop @args if $node->can('memory_input') && $node->memory_input;
    my $end = $self->_fresh_label('dispatch.end.');
    my @in;
    for my $cand (@cands) {
        my ($cname, $sub) = @$cand;
        my ($p, $l) = $self->_str_const_parts($cname, 'dispatch: a class');
        my ($leq, $m, $meq, $both, $hit) = map { $self->_fresh } 1 .. 5;
        my ($arm, $next) = map { $self->_fresh_label("dispatch.$_.") } qw(arm next);
        $self->{_need_memcmp} = 1;
        $self->_emit("  $leq = icmp eq i64 $cl, $l");
        my ($cmpl) = $self->_fresh_label('dispatch.cmp.');
        $self->_set_terminator("  br i1 $leq, label %$cmpl, label %$next");
        $self->_new_block($cmpl);
        $self->_emit("  $m = call i32 \@memcmp(i8* $cp, i8* $p, i64 $l)  ; dispatch: is it $cname?");
        $self->_emit("  $meq = icmp eq i32 $m, 0");
        $self->_emit("  $hit = and i1 $meq, $is");
        $self->_set_terminator("  br i1 $hit, label %$arm, label %$next");
        $self->_new_block($arm);
        my $v = do {
            local $self->{cache} = { $self->{cache}->%* };
            $self->{_call_via} = { name => "${cname}::$name", target => $sub, args => [@args] };
            my $r = $self->_lower_call_direct($node);
            my $from = $self->{_inline_value_repr}{ $node->id } // '';
            die "GAP: a method ('$name') on a run-time class whose ${cname}::$name returns a list is not lowered\n"
                if $from =~ /\A(?:Array|List|Hash)\z/;
            $from eq 'Scalar' ? $r
              : $from eq 'Undef' ? $self->_build_slot('false', '0', 'Undef', 'dispatch: undef')
              : $self->_emit_coercion($r, $from, 'Scalar', "dispatch: ${cname}::$name");
        };
        push @in, "[ $v, %" . $self->_current_block_label . " ]";
        $self->_set_terminator("  br label %$end");
        $self->_new_block($next);
    }
    $self->{_need_exit} = 1;
    $self->_emit("  call void \@exit(i32 255)  ; dispatch: no package of this program has the method");
    $self->_set_terminator("  unreachable");
    $self->_new_block($end);
    my $res = $self->_fresh;
    $self->_emit("  $res = phi %Slot " . join(', ', @in) . "  ; dispatch: its value");
    # READ AS THE CALL IS TYPED: Analysis may have typed it from a sub's
    # return (a Str), and its consumers read that.
    my $st = $node->stamp // 'Unknown';
    if ($st eq 'Unknown') { $node->set_stamp('Scalar'); $st = 'Scalar' }
    if ($st ne 'Scalar') {
        die "GAP: a method ('$name') on a run-time class read as a $st is not lowered\n"
            unless _keeps_value('Scalar', $st);
        $res = $self->_emit_coercion($res, 'Scalar', $st, "dispatch: read as $st");
    }
    $self->{_inline_value_repr}{ $node->id } = $st;
    return $self->{cache}{ $node->id } = $res;
}

# _lower_method_on_non_object($node, $obj) -> the call's value, or undef when
# its invocant may be an object. perl dies on a method called on undef or a
# plain value. Statically so, it always dies; a Scalar is read by its tag at
# run time, and one holding a reference -- an object would dispatch on its
# run-time class -- stops the program (exit 255). The die is a branch to its
# eval, and only where nothing reads $@: perl's message names the file and
# line, which nothing here knows.
sub _lower_method_on_non_object {
    my ($self, $node, $obj) = @_;
    return undef unless blessed($obj);
    my $rs = $obj->operation eq 'Print' ? 'Boolean' : ( $self->_repr_of($obj) // $obj->stamp // '' );
    my $location = $obj->operation eq 'PadAccess' && $obj->is_location;
    my $plain = $rs =~ /\A(?:Int|Num|Str|Boolean|Undef)\z/;
    return undef unless $plain || $rs eq 'Scalar' || ( $rs eq 'Unknown' && $location );
    my $name = $node->name;
    my $f = ($self->{_eval_frames} // [])->[-1];
    if (!$f || $READS_ERROR
            || ( defined $node->eval_id && ( $f->{region}->eval_id // '' ) ne $node->eval_id )) {
        # Possibly an object, it is the dispatch that is refused.
        return undef unless $plain;
        die "GAP: a method ('$name') called on a plain value dies, and its message "
          . "(naming the file and line) would be seen -- not lowered\n";
    }
    my $die = sub {
        $self->_store_eval_error($self->_set_str_len($self->_str_const_parts(
            "Can't call method \"$name\" on what is not an object\n", 'method on a non-object')));
        # What was made before the first die dominates the join: only what
        # comes after it may not.
        $f->{cached_at_first_die} //= { map { $_ => 1 } keys %{ $self->{cache} } };
        $f->{dies}++;
        $self->_set_terminator("  br label %$f->{catch}  ; a method on a non-object: caught by its eval");
    };
    if ($plain) {
        $self->lower_value($obj);
        $die->();
    }
    else {
        my $slot;
        if ($rs eq 'Scalar') { $slot = $self->lower_value($obj) }
        else {
            $slot = $self->_fresh;
            $self->_emit("  $slot = load %Slot, %Slot* " . $self->_location_ptr($obj) . "  ; the invocant");
        }
        my $tag = $self->_slot_tag_of($slot);
        my ($is_plain) = $self->_fresh;
        my ($dies, $obj_l) = map { $self->_fresh_label("nonobj.$_.") } qw(dies object);
        $self->_emit("  $is_plain = icmp ule i8 $tag, " . _slot_tag_value('Boolean') . "  ; not a reference?");
        $self->_set_terminator("  br i1 $is_plain, label %$dies, label %$obj_l");
        $self->_new_block($obj_l);
        $self->{_need_exit} = 1;
        $self->_emit("  call void \@exit(i32 255)  ; a method on an object of a run-time class is not lowered");
        $self->_set_terminator("  unreachable");
        $self->_new_block($dies);
        $die->();
    }
    $self->_new_block($self->_fresh_label('nonobj.after.'));
    return $self->{cache}{ $node->id } = $self->_build_slot('false', '0', 'Undef', 'after a die: unreached');
}

# Lowers a Call(dispatch_kind='method', name='new') node.
# This is the canonical form of the New node: malloc + vtable bind + :param binding.
# Inputs are the :param values; the class rides as the class_name attribute.
sub _lower_call_new {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    # MOP-direct shape: inputs are ONLY the :param values — class structure
    # is registry context named by the class_name attribute, never an input.
    my $param_names = $node->can('param_names') ? ($node->param_names // []) : [];
    my $class_name  = $node->class_name
        // die "LLVM MOP: Call(new) has no class_name — the constructor must "
             . "name its statically-known class (019eb42a MOP-direct contract).";
    my $param_vals  = [ ($node->inputs // [])->@* ];

    # Verify the class is registered
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: Call(new) references undeclared class '$class_name'";

    # malloc the object
    my $raw     = $self->_fresh;
    my $obj_ref = $self->_fresh;
    $self->_emit("  $raw     = call i8* \@malloc(i64 ptrtoint (%${class_name}.obj* getelementptr (%${class_name}.obj, %${class_name}.obj* null, i64 1) to i64))  ; Call(new) $class_name: sizeof");
    $self->_emit("  $obj_ref = bitcast i8* $raw to %${class_name}.obj*  ; Call(new) $class_name: typed ptr");

    # Store vtable pointer
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 0  ; vtable ptr slot");
    $self->_emit("  store %${class_name}.vt* \@${class_name}__vtable, %${class_name}.vt** $vt_gep  ; store vtable");

    # Bind :param fields
    my $fields = $reg->{fields} // [];
    for my $i (0 .. $#$param_names) {
        my $pname   = $param_names->[$i];
        my $pval    = $param_vals->[$i];
        # Bind by the bare :param key; fall back to the (possibly sigil-
        # prefixed) field name for native callers that pass bare param_names.
        my ($finfo) = grep {
            ($_->{param_name} // '') eq $pname || ($_->{name} // '') eq $pname
        } @$fields;
        unless (defined $finfo) {
            die "LLVM MOP: Call(new) $class_name: no :param field named '$pname' in class registry";
        }
        my $fidx = $finfo->{field_index};
        my $slot_idx = $fidx + 1;
        # An object field IS a %Slot cell. Its subfield indices come from
        # _slot_idx, never a literal: a field added to @_SLOT_FIELDS must
        # not silently re-aim these GEPs at the wrong bytes.
        my ($fi_def, $fi_tag, $fi_pay) =
            (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
        my $repr = defined $pval ? _require_repr($pval, 'Call(new).:param.field') : 'Int';
        # The payload is STORED using the constructor argument's repr but READ
        # back using the field's DECLARED repr (the FieldAccess path). If they
        # disagree the read misinterprets the stored bits (an Int stored where a
        # Str field's StrPair* is expected inttoptrs to garbage and segfaults),
        # so refuse loudly rather than emit crashing IR (zhi 019f378f).
        # THIS GUARD ASKS A T2 QUESTION AND MUST NOT ASK A T1 ONE
        # (perigrin, 2026-08-29).
        #
        # The tempting reasoning is "Int <: Scalar, so permit the store". That
        # is a TYPE relation, and it is not what a store site may decide on. The
        # equally tempting counter-reasoning — "an Int field is i64 (8 bytes), a
        # Scalar field is %Slot (16 bytes), so the shapes differ" — is WORSE: it
        # asserts a LAYOUT as though it followed from the type. It does not, and
        # here it is not even true. Measured: `%Box.obj = type { %Box.vt*,
        # %Slot }` — every field is ALREADY a %Slot whatever its declared repr,
        # the store writes the defined bit and payload separately, and
        # `field_repr` governs how the payload is INTERPRETED on read, not the
        # cell's shape.
        #
        # The general point, which is why this comment is long: statements of
        # the form "type X is N bytes" OVER-DECIDE. They fix an encoding that
        # T1 must be free to leave open — if T1's `Scalar` were bound to a
        # 16-byte cell, T1 could neither narrow it later without the encoding
        # going wrong, nor leave it unnarrowed without paying for a box. T1's
        # answer stays A TYPE; T2 decides what it costs, and an SV*-based target
        # would decide differently.
        #
        # So the question this site may ask is T2's: GIVEN THESE TWO ENCODINGS,
        # IS THIS STORE COHERENT? The hazard it exists for is a payload written
        # under one interpretation and read under another — the `inttoptr`
        # segfault below. `$field_repr ne $repr` is a crude proxy for that, and
        # it currently refuses stores that are in fact coherent (Int into the
        # general cell). Narrowing it to compare INTERPRETATIONS is T2 work and
        # wants the ref case checked first: `Box->new(v => [1,2])` is legal and
        # the payload is i64.
        #
        # Measured 2026-08-29: 9 corpus `classes` cases block here after the
        # producer correctly widened `:param` fields to Scalar (9d23bda).
        my $field_repr = $finfo->{field_repr};
        die "GAP: Call(new) $class_name field '$pname' declared repr=$field_repr "
          . "but constructor argument repr=$repr — the payload would be written "
          . "under one interpretation and read under another."
            unless _field_store_is_coherent($field_repr, $repr);
        my $val_ref = $self->lower_value($pval);

        my $def_gep = $self->_fresh;
        $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_def  ; field[$fidx] defined bit");
        $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' defined=true");
        my $tag_gep = $self->_fresh;
        my $tag_nm  = _slot_tag_for_repr($repr);
        $self->_emit("  $tag_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_tag  ; field[$fidx] tag");
        $self->_emit("  store i8 " . _slot_tag_value($tag_nm) . ", i8* $tag_gep  ; field '$pname' tag=$tag_nm");

        my $pay_gep = $self->_fresh;
        $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_pay  ; field[$fidx] payload");

        $self->_store_field_payload($val_ref, $repr, $pay_gep, $pname);
    }

    # Store default/uninit fields not provided as :param. Match the same
    # namespace the bind loop used: a field is "provided" if either its bare
    # param_name or its (sigil-prefixed) name appears in param_names.
    for my $finfo (@$fields) {
        my $pname = $finfo->{name} // '';
        my $fkey  = $finfo->{param_name} // '';
        next if grep { $_ eq $fkey || $_ eq $pname } @$param_names;
        my $fidx     = $finfo->{field_index};
        my $slot_idx = $fidx + 1;
        # An object field IS a %Slot cell. Its subfield indices come from
        # _slot_idx, never a literal: a field added to @_SLOT_FIELDS must
        # not silently re-aim these GEPs at the wrong bytes.
        my ($fi_def, $fi_tag, $fi_pay) =
            (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
        if ($finfo->{has_default}) {
            my $def_node = $finfo->{default_node};
            # has_default promises a default value node. If it is missing the MOP
            # is ill-formed: silently storing 0 reads at runtime identically to a
            # real default of 0, so a malformed IR would look like a miscompile
            # (this cost a full false-miscompile chase during 2c recon). Refuse
            # loudly instead (zhi 019f378f).
            die "LLVM MOP: field '$pname' has has_default=true but no default "
              . "value node — ill-formed MOP." unless defined $def_node;
            my $def_repr = _require_repr($def_node, 'Call(new).default.field');
            # A DEFAULT IS MADE ANEW for each object, as perl evaluates it: served
            # from the cache, a second `new` shared the first one's hash (5252
            # for 52u1; `field $r = {}` 5151 for 51u0).
            {
                my @q = ($def_node);
                my %seen;
                while (my $n = shift @q) {
                    next unless blessed($n) && !$seen{ refaddr($n) }++;
                    next if $n->operation eq 'Constant';
                    delete $self->{cache}{ $n->id };
                    push @q, $n->inputs->@*;
                }
            }
            my $def_ref  = $self->lower_value($def_node);
            my $def_gep = $self->_fresh;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_def  ; default field[$fidx] defined");
            $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' default defined=true");
            my $tag_gep = $self->_fresh;
            my $tag_nm  = _slot_tag_for_repr($def_repr =~ s{\A(Array|Hash)\z}{${1}Ref}r);
            $self->_emit("  $tag_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_tag  ; default field[$fidx] tag");
            $self->_emit("  store i8 " . _slot_tag_value($tag_nm) . ", i8* $tag_gep  ; field '$pname' default tag=$tag_nm");

            my $pay_gep = $self->_fresh;
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_pay  ; default field[$fidx] payload");
            # Box the default the same way a :param value is (Str -> StrPair,
            # Boolean -> zext, else identity) via the shared payload-store helper.
            $self->_store_field_payload($def_ref, $def_repr, $pay_gep, $pname);
        } elsif ($pname =~ /\A([%@])/) {
            # AN AGGREGATE FIELD starts as an empty hash or array of its own.
            my $kind = $1 eq '%' ? 'Hash' : 'Array';
            my $new  = $kind eq 'Hash' ? $self->_emit_empty_hash("field '$pname'") : $self->_emit_array_of([]);
            my ($def_gep, $tag_gep, $pay_gep, $raw) = map { $self->_fresh } 1 .. 4;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_def");
            $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' defined");
            $self->_emit("  $tag_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_tag");
            $self->_emit("  store i8 " . _slot_tag_value("${kind}Ref") . ", i8* $tag_gep  ; field '$pname' tag=${kind}Ref");
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_pay");
            $self->_emit("  $raw = ptrtoint %${kind}* $new to i64");
            $self->_emit("  store i64 $raw, i64* $pay_gep  ; field '$pname' = an empty \L$kind\E of its own");
        } else {
            my $def_gep = $self->_fresh;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_def  ; uninit field[$fidx] defined");
            $self->_emit("  store i1 false, i1* $def_gep  ; field '$pname' not initialized");
            # defined=false, so the reading IS established: the cell is undef.
            # That is Undef, not Opaque -- Opaque means no reading was determined.
            my $tag_gep = $self->_fresh;
            $self->_emit("  $tag_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_tag  ; uninit field[$fidx] tag");
            $self->_emit("  store i8 " . _slot_tag_value('Undef') . ", i8* $tag_gep  ; field '$pname' tag=Undef");

            my $pay_gep = $self->_fresh;
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 $fi_pay  ; uninit field[$fidx] payload");
            $self->_emit("  store i64 0, i64* $pay_gep  ; field '$pname' payload=0");
        }
    }

    # ADJUST blocks: call the per-class @Cls__ADJUST function (emitted once
    # by _emit_class_registry_ir in its own fresh context). Lowering the
    # bodies inline here shared this context's value cache across
    # constructions — the second new of the same class cache-hit the body's
    # statement nodes and skipped its stores (review I6).
    my $adjusts = $reg->{adjusts} // [];
    if (grep { @{ $_->{body_nodes} // [] } } @$adjusts) {
        $self->_refuse_inside_eval("a constructor that runs ADJUST");
        $self->_emit("  call void \@${class_name}__ADJUST(i8* $raw)  ; run ADJUST blocks");
    }

    # Return the raw i8* pointer (Object repr)
    my $result = $self->_fresh;
    $self->_emit("  $result = bitcast %${class_name}.obj* $obj_ref to i8*  ; Call(new) $class_name: -> Object (i8*)");
    $self->{cache}{ $node->id } = $result;
    return $result;
}

# _lower_call_method($node) -> $llvm_ref
#
# Lowers a Call(dispatch_kind='method') node.
# When name='new': routes to the constructor lowering (_lower_call_new).
# Otherwise: vtable-dispatch (same logic as the former _lower_method_call).
# Inputs: the :param values for name='new'; inputs[0] = invocant for regular
# method calls. The class rides as the class_name attribute (MOP-direct).
# _copy_out_written_args($name, \@idx, \@args, $array): `$_[N] = ...` IS A
# STORE TO THE CALLER'S ARGUMENT. The callee wrote the array the call built
# for @_; each written element is stored back here, after the inline, to the
# argument it aliases -- a variable kept in memory, or an element. A literal
# is read-only in perl (it dies), and a temporary keeps no store; the first
# is refused, the second needs nothing.
sub _copy_out_written_args {
    my ($self, $name, $written, $args, $arr) = @_;
    for my $i (@$written) {
        die "GAP: direct call to '$name': callee writes \$_[$i] past the "
          . scalar(@$args) . " argument(s) passed -- that grows \@_, which "
          . "is not lowered.\n" if $i > $#$args;
        my $arg = $args->[$i];
        my $op  = $arg->operation;
        die "GAP: direct call to '$name': callee writes \$_[$i], a literal -- "
          . "perl dies (a read-only value); that is not lowered.\n"
            if $op eq 'Constant';
        my $lvalue = ( $op eq 'PadAccess' && $arg->is_location )
                  || ( $op eq 'Subscript' && blessed($arg->inputs->[0])
                       && $arg->inputs->[0]->operation ne 'ArgsSource' );
        die "GAP: direct call to '$name': callee writes \$_[$i], whose argument "
          . "is a $op this does not store back to.\n"
            unless $lvalue || $op =~ /\A(?:Add|Subtract|Multiply|Concat|Call)\z/;
        next unless $lvalue;
        my ($ep, $elems, $sp, $slot) = map { $self->_fresh } 1 .. 4;
        $self->_emit("  $ep = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; \@_ elems ptr");
        $self->_emit("  $elems = load %Slot*, %Slot** $ep  ; \@_ elems");
        $self->_emit("  $sp = getelementptr inbounds %Slot, %Slot* $elems, i64 $i  ; \$_[$i]");
        $self->_emit("  $slot = load %Slot, %Slot* $sp  ; \$_[$i] after the call");
        my $f  = Chalk::IR::NodeFactory->new;
        my $ph = $f->make('Constant', value => "\0copy-out:$i:" . refaddr($arg), const_type => 'string');
        $ph->set_stamp('Scalar');
        local $self->{_arg_bind} = { ($self->{_arg_bind} // {})->%*,
                                     refaddr($ph) => { ref => $slot, repr => 'Scalar' } };
        my $store = $f->make('Assign', inputs => [ $arg, $ph ]);
        $store->set_stamp('Scalar');
        $self->_lower_assign($store);
    }
}

# _lower_call_direct($node) -> $llvm_ref
#
# Lower a direct named-sub call (dispatch_kind='direct'). The loader resolved
# the callee to its metaobject (target). The callee is inlined at the call
# site: the caller's Call inputs are its arguments, and the callee's single
# Return value subgraph is lowered in the current context.
#
# No-argument callee (F1): inline the result subgraph directly; nothing from
# this context leaks in.
#
# Argument-passing callee (F5): the caller's Call inputs are the arguments, and
# the callee reads its Nth positional argument via a `shift @_` (a
# Call(builtin,shift) over EntryDef(*,_)). Since the callee is INLINED (not
# a real call frame), each such arg-read is bound by SSA substitution to the
# caller's already-lowered argument ref — this is runtime-free inlining, not a
# call ABI. Only the single-positional-`shift` shape is sound: two `shift`s
# hash-cons to one node (their ordering is lost), and `my ($a,$b)=@_` /
# `$_[N]` do not connect to the args in the graph — those GAP loudly rather
# than miscompile.

sub _lower_call_direct {
    my ($self, $node) = @_;

    # AN INDIRECT CALL RESOLVED to a sub (_lower_call_indirect) is lowered as
    # a direct one of it: its name, metaobject and arguments ride here, taken
    # at once so a call inside the inlined body does not see them.
    my $via = delete $self->{_call_via};
    my $name  = $via ? $via->{name} : $node->name;
    die "GAP: direct call to '$name' as `&$name`, which shares its caller's \@_, is not lowered\n"
        if $node->can('shares_args') && $node->shares_args;
    # A CALL IN AN EVAL'S BODY is caught by that eval: inlined with it not
    # open as a branch (in an arm, a loop body), the callee's die would leave
    # the program -- or reach another eval's end.
    {
        my $f = ($self->{_eval_frames} // [])->[-1];
        die "GAP: a call in a block eval that is not lowered as a branch (in an arm or "
          . "a loop body) is not lowered -- the callee's die would not be caught\n"
            if $node->can('eval_id') && defined $node->eval_id
            && !($f && ($f->{region}->eval_id // '') eq $node->eval_id);
    }

    # Inlining is the only direct-call mechanism, so a self- or mutually-
    # recursive callee has no terminating lowering: we inline the body, which
    # contains the same Call, which inlines again. Without this guard the
    # compiler does not fail — it NEVER RETURNS (measured: `Deep recursion on
    # _lower_inlined_effects_then_value`, then a hang). A non-terminating
    # compiler violates GAP-not-miscompile more seriously than a wrong answer
    # does, because no gate can catch it.
    #
    # The frame is local-scoped so it unwinds with the inline (same pattern as
    # _arg_bind below), which keeps a sub called twice at DIFFERENT call sites
    # legal — only re-entering a callee already on the inline stack is a cycle.
    # Real `define`+`call` emission removes the need for this guard by giving
    # recursion a terminating lowering; until then it GAPs loudly.
    die "GAP: direct call to '$name' is recursive — inlining is the only "
      . "direct-call mechanism and cannot terminate on a cycle. Real "
      . "define+call emission is required to lower this."
        if $self->{_inlining} && $self->{_inlining}{$name};
    local $self->{_inlining} = { ($self->{_inlining} // {})->%*, $name => 1 };
    # A FORMAT'S BODY is what `write` runs: its formlines print (_lower_formline).
    local $self->{_in_format} = 1 if $name =~ /::__FORMAT__:/;

    # Through the METAOBJECT, not a bare graph. `target` is a MOP::Sub handle,
    # so the callee's graph AND its metadata (params, uses_args, return type)
    # are reachable from one place -- which is the whole point of Chalk keeping
    # a MOP alongside the graph rather than dissolving declarations into it.
    my $target = $via ? $via->{target} : $node->can('target') ? $node->target : undef;
    my $graph  = $target && $target->can('graph') ? $target->graph : undef;
    die "GAP: direct call to '$name' has no resolved callee — the loader could "
      . "not resolve the sub name to a metaobject (an unknown or builtin sub)."
        unless defined $graph;
    # `defined` is NOT enough on its own: MOP::Sub's `graph` field defaults to a
    # fresh EMPTY graph rather than undef, so a metaobject declared without a
    # body yields a defined-but-empty graph here. Inlining that emits nothing
    # and returns whatever happens to be on hand — a silent wrong answer where
    # a refusal belongs. The loader now refuses to build such a metaobject; this
    # is the consumer-side half of that invariant.
    die "GAP: direct call to '$name': the callee metaobject carries an EMPTY "
      . "graph (no Return) — it was declared without a body."
        unless $graph->returns && $graph->returns->@*;

    # A SUB NO ONE DEFINES runs its package's AUTOLOAD (Analysis), which finds
    # the name it was called by in $AUTOLOAD: perl stores it there first.
    if (!$via && $node->can('autoloads') && defined(my $full = $node->autoloads)) {
        my ($pkg) = $full =~ /\A(.*)::[^:]+\z/;
        die "GAP: direct call to '$name' runs AUTOLOAD from inside AUTOLOAD -- "
          . "inlining cannot terminate on that cycle\n"
            if $self->{_inlining}{"${pkg}::AUTOLOAD"};
        $self->{_inlining}{"${pkg}::AUTOLOAD"} = 1;
        my ($p, $l) = $self->_str_const_parts($full, 'AUTOLOAD');
        my $slot = $self->_emit_coercion($self->_str_value($p, len => $l), 'Str', 'Scalar', 'store to $AUTOLOAD');
        $self->_emit("  store %Slot $slot, %Slot* " . $self->_pkg_slot_ptr($pkg, 'AUTOLOAD')
            . "  ; \$${pkg}::AUTOLOAD = \"$full\"");
    }

    my @returns = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } $graph->returns->@*;
    die "GAP: direct call to '$name': callee graph has "
      . scalar(@returns) . " Returns — exactly one is required to inline."
        if @returns != 1;

    # WHICH READING THIS CALLSITE TAKES IS ITS OWN CONTEXT'S ANSWER. A
    # list-returning callee carries two -- inputs[0] all N values, inputs[1]
    # the scalar face -- because it is compiled once and cannot see its
    # caller. Taking value() unconditionally is right for every list callsite
    # and wrong for every scalar one, which is why a fixture with only
    # list-context calls cannot tell the two apart.
    #
    # An undef want is a REAL state (perl leaves the slot empty for a call in
    # last-operand position), and return_reading_for_want reads it as the list
    # reading rather than as scalar -- see its comment for why that is the
    # sound default.
    my $want  = ($node && $node->can(q{want})) ? $node->want : undef;
    my $value = Chalk::IR::Analysis::return_reading_for_want($returns[0], $want);
    die "GAP: direct call to '$name': callee Return has no value input."
        unless defined $value;

    # A pure callee's Return.control_in is Start (pure pad/data work sits off
    # the control chain); an effectful callee's is a Print/Assign/store or a
    # loop/branch Region. A STRAIGHT-LINE effect chain (Print -> ... -> Start,
    # no Region/Loop/If/Assign) is threaded in program order by
    # _collect_straight_line_effect_chain below (Slice B Commit 2-print). Any
    # other shape -- a loop, a branch, a store -- goes through
    # _lower_inlined_structure.
    my $control_in = $returns[0]->control_in;
    # A CALLEE THAT BRANCHES, LOOPS OR STORES is inlined whole: its control
    # structure is lowered in place by _lower_inlined_structure, as a method
    # body's is. A straight line of prints and calls keeps the lighter path.
    my $structured = !_is_straight_line_effect_chain($control_in);
    my @effect_chain = $structured ? ()
        : $self->_collect_straight_line_effect_chain($control_in, $name);
    # THE CALL HAS THE CALLER'S TYPE. The callee's value is lowered at its
    # own repr, and the caller reads the call at the call's: g's `$_[0] * 2`
    # is an Int, the call to it was stamped Num, and the i64 went where a
    # double was wanted -- lli rejected the module. Reconciled here, once.
    # A CALL IN VOID CONTEXT HAS NO VALUE TO REACH ITS CALLER. Its effects
    # are inlined; its value is not lowered -- a sub ending in an if makes
    # that value inside an arm, and refusing it refused every statement call
    # to such a sub. Nothing reads the call, so its ref is a placeholder.
    # ...but a FORMAT'S last line is its value: it prints (_lower_formline).
    my $void = ($want // '') eq 'void'
        && $name !~ /::__FORMAT__:/;
    my $inline = sub {
        my $ref = $structured
            ? $self->_lower_inlined_structure($returns[0], $void ? undef : $value)
            : $self->_lower_inlined_effects_then_value(\@effect_chain, $void ? undef : $value);
        return '0' if $void;
        my $from = $value->operation eq 'Print' ? 'Boolean' : ($self->{_inlined_value_repr} // $value->stamp // '');
        # What the inlined value IS, for a list that flattens it
        # (_emit_flattened_array_of): an Array, or one scalar.
        $self->{_inline_value_repr}{ $node->id } = $from;
        # A CALL NOTHING TYPED RETURNS WHAT ITS CALLEE DOES. A sub returning
        # a shared lexical returns a Scalar (that lexical's Slot); the call to
        # it, stamped Unknown, is that Scalar -- this call node is this call
        # site's own, so saying so is no one else's business.
        # A reference too: a package method returning its blessed `$self`.
        $node->set_stamp($from)
            if ( $node->stamp // 'Unknown' ) eq 'Unknown'
            && $from =~ /\A(?:Scalar|Int|Num|Str|Boolean|ArrayRef|HashRef|CodeRef|ScalarRef)\z/;
        # A SCALAR-CONTEXT CALL STAMPED AS A LIST reads its callee's scalar
        # reading, which is what was lowered: `sub g { return }` gives undef
        # there, and the call stamped List was "always defined" (backlog
        # 7cbb3220).
        $node->set_stamp($from)
            if ($want // '') eq 'scalar'
            && ( $node->stamp // '' ) =~ /\A(?:List|Array)\z/
            && $from =~ /\A(?:Int|Num|Str|Boolean|Undef|Scalar)\z/;
        my $to   = $node->stamp // '';
        # Between SCALAR readings only: a list callee's Array value is what a
        # List-stamped call already reads, and has no arrow to coerce along.
        state %scalar = map { $_ => 1 } qw(Int Num Str Boolean Scalar Slot Undef);
        if ($scalar{$from} && $scalar{$to} && $from ne $to) {
            die "GAP: call $name: the callee's value is a $from but the call "
              . "reads a $to -- that coercion would not keep the value.\n"
                unless _keeps_value($from, $to);
            $ref = $self->_emit_coercion($ref, $from, $to, "call $name result");
        }
        # A REFERENCE where the call is a Scalar is boxed into the Slot that
        # holds it: a method returning its blessed `$self` handed back the bare
        # pointer, and the next call read it as a %Slot (invalid IR).
        elsif ($from =~ /\A(?:ArrayRef|HashRef|CodeRef|ScalarRef)\z/ && $to =~ /\A(?:Scalar|Slot)\z/) {
            $ref = $self->_slot_of_value($value, $ref, "call $name result");
        }
        return $ref;
    };

    # A trailing VOID statement-effect attaches on Return.inputs[1..] rather
    # than control_in (see Chalk::IR::Serialize::JSON's _control_chain_nodes,
    # JSON.pm:983-997, for the seed predicate this mirrors): a void method
    # call is not the return value, so the loader keeps it as an extra Return
    # input alongside the value. The control_in check above does not see it
    # (that Return's own control_in can still be Start), and unguarded it
    # would ALSO mis-select the trailing effect as the return value (inputs's
    # LAST element, above). GAP loudly rather than drop or mis-select it.
    my @inputs = $returns[0]->inputs->@*;
    my @trailing_effects = grep {
        blessed($_) && $_->can('control_in') && defined $_->control_in
    } @inputs[ 1 .. $#inputs ];
    die "GAP: direct call to '$name': callee has effect(s) carried as extra "
      . "Return inputs (a trailing void statement-effect) that inlining "
      . "does not yet thread in program order."
        if @trailing_effects;

    my @args = $via ? $via->{args}->@* : $node->inputs->@*;

    # A CLOSURE READS WHAT IT CAPTURED as it is when it runs: each CellRead of
    # its graph is the load of the variable it names, in the frame that made
    # it -- inlined here, as the call is made while that frame runs. One that
    # writes a capture is refused.
    local $self->{_arg_bind} = { ($self->{_arg_bind} // {})->%* };
    $self->_bind_captures($graph, $name, $via ? $via->{anon} : undef);

    # No-argument callee: thread its straight-line effect chain (if any), then
    # inline the result subgraph. Memoize under the CALLER Call node's id
    # (Context.pm ~353's cache-hit check) so a Call reached twice — once as a
    # statement via process_control_node, once as the Return's value via
    # lower_value, both the SAME node — inlines the callee once instead of
    # re-running the effect chain and result subgraph a second time.
    # A SIGNATURE CALLED WITH NOTHING takes its defaults: the binding below
    # does that, and here its parameters stayed unbound (pvm 102).
    my @no_arg_reads = @args ? () : eval { $self->_collect_positional_arg_reads($graph, $name) };
    unless (@args || ( !$@ && $self->{_args_signature} && @no_arg_reads )) {
        # @_ READ AS A LIST with nothing passed is an empty list: `"c[@_]"`
        # called as `c()` reached ArgsSource unbound and refused.
        my @reads = eval { $self->_collect_positional_arg_reads($graph, $name) };
        local $self->{_arg_bind} = { ($self->{_arg_bind} // {})->%* };
        if (!$@ && !@reads && (my $aa = $self->{_args_read_as_a_list})) {
            $self->{_arg_bind}{ refaddr($aa) } = { ref => $self->_emit_array_of([]), repr => 'Array' };
        }
        my $ref = $inline->();
        $self->{cache}{ $node->id } = $ref;
        return $ref;
    }

    # Argument-passing callee: bind the callee's positional arg-reads to the
    # caller's argument values. Find the callee's `shift @_` reads first (this
    # validates the shape and GAPs loudly on any @_ access that inlining cannot
    # bind soundly), then lower the caller's args in this context.
    my @arg_reads = $self->_collect_positional_arg_reads($graph, $name);
    my $args_array = $self->{_args_read_as_a_list};
    my $written    = $self->{_args_written};
    my $signature  = $self->{_args_signature};
    my $slurpy     = $self->{_args_slurpy};
    # A SIGNATURE CHECKS ITS ARITY: too many, or too few for a parameter with
    # no default, and perl dies. A parameter the body never reads is not in
    # the graph, so it cannot be shown to have a default: it counts as
    # mandatory, which refuses rather than guesses.
    if ($signature) {
        my @declared = @{ $target->params // [] };
        # An UNNAMED parameter (`$` in `($, $phi)`) is not in `params`; the
        # signature's count is every positional one.
        my $sig = $target->can('signature') ? $target->signature : undef;
        @declared = map { "\$p$_" } 1 .. $sig->{mandatory}
            if ref $sig eq 'HASH' && ( $sig->{kind} // '' ) eq 'declared' && !$sig->{slurpy}
                && ( $sig->{mandatory} // 0 ) > @declared;
        # AN ANONYMOUS SUB'S DECLARED LIST IS NOT ON THE WIRE (its metaobject is
        # built from the graph, with `@_` for a placeholder): only the
        # parameters it reads are known, so only those are checked.
        my $unknown = @declared == 1 && $declared[0] eq '@_';
        @declared = map { "\$p$_" } 0 .. ( @arg_reads ? (sort { $b <=> $a } map { $_->index } @arg_reads)[0] : -1 )
            if $unknown;
        die "GAP: direct call to '$name': a signature with a slurpy parameter is not lowered\n"
            if grep { /\A[@%]/ } @declared;
        die "GAP: direct call to '$name' passes " . scalar(@args) . " argument(s) to a "
          . "signature of " . scalar(@declared) . " -- perl dies (Too many arguments).\n"
            if @args > @declared && !$unknown;
        my %read = map { $_->index => $_ } grep { blessed($_) } @arg_reads;
        for my $i (scalar(@args) .. $#declared) {
            die "GAP: direct call to '$name' passes " . scalar(@args) . " argument(s), too few "
              . "for its signature -- perl dies (Too few arguments).\n"
                unless $read{$i} && defined $read{$i}->default_when
                    # A DEFAULT THAT RUNS CODE (`$x = g()`) is the body's: an if on
                    # how many arguments @_ holds. The declared signature says the
                    # position is optional.
                    or ref $sig eq 'HASH' && ( $sig->{kind} // '' ) eq 'declared'
                        && defined $sig->{mandatory}   # every scalar; the last `optional` default
                        && $i >= $sig->{mandatory} - ( $sig->{optional} // 0 );
        }
        for my $i (0 .. $#args) {
            die "GAP: direct call to '$name': a signature default applied when the argument is "
              . $read{$i}->default_when . " is not lowered\n"
                if $read{$i} && ( $read{$i}->default_when // 'absent' ) ne 'absent';
        }
    }
    # @_ READ AS A LIST is one argument per element: an argument that is
    # itself a list would flatten, which this does not build.
    if ($args_array) {
        for my $a (@args) {
            die "GAP: direct call to '$name': an argument stamped "
              . ( $a->stamp // 'NONE' ) . " flattens into \@_, which inlining "
              . "does not build.\n"
                unless ( $a->stamp // '' ) =~ /\A(?:Int|Num|Str|Boolean|Scalar|Undef|ArrayRef|HashRef|CodeRef|ScalarRef|Object)\z/;
        }
    }

    # A CODE REFERENCE PASSED is not lowered as a value: bound to its
    # AnonSub, it is what an indirect call in the callee runs.
    die "GAP: direct call to '$name': a code reference in an \@_ read as a list is not lowered\n"
        if $args_array && grep { blessed($_) && $_->operation eq 'AnonSub' } @args;
    my @arg_refs = map { $_->operation eq 'AnonSub' ? undef : $self->lower_value($_) } @args;

    # Push the arg-binding frame (refaddr-keyed; see lower_value), inline the
    # callee's effect chain + result subgraph, then tear the frame down. Nested
    # inlined calls each add their own callee's arg-reads to the shared frame —
    # the refaddr keys are per-node, so an inner callee's shift never shadows
    # an outer's.
    local $self->{_arg_bind} = { ($self->{_arg_bind} // {})->%* };
    # Bind the REF AND THE REPR. The callee's arg-read carries the callee's
    # own stamp -- a `$_[0]` Subscript is `Scalar`, because @_ is an array of
    # Slots and nothing in the callee narrows it. Substituting only the value
    # left that Scalar stamp on a node now holding the caller's `i64`, so the
    # surrounding Coerce[Scalar -> Num] emitted a %Slot tag dispatch against a
    # bare integer: "'%tmp_1' defined with type 'i64' but expected '%Slot'".
    # The repr is what every consumer uses to decide how to READ the value, so
    # rebinding one without the other is a type lie.
    # AN ARGUMENT NOT PASSED is undef -- or, for a signature, its default,
    # lowered once the passed ones are bound (it may read them). Extras are
    # passed and not read.
    my @defaulted;
    for my $i (0 .. $#arg_reads) {
        my $r = $arg_reads[$i];
        next unless blessed($r);
        if ($signature) {
            my $k = $r->index;
            if ($k < @args) { $self->{_arg_bind}{ refaddr($r) } = $self->_arg_binding($args[$k], $arg_refs[$k]) }
            else              { push @defaulted, $r }
        }
        elsif ($i < @args) {
            $self->{_arg_bind}{ refaddr($r) } = $self->_arg_binding($args[$i], $arg_refs[$i]);
        }
        else {
            $self->{_arg_bind}{ refaddr($r) } =
                { ref => $self->_build_slot('false', '0', 'Undef', "$name: argument $i not passed"), repr => 'Scalar' };
        }
    }
    # The slurpy array is the arguments past the scalars -- every read of it
    # in the callee, whichever memory version, is that one array.
    if ($slurpy) {
        my @rest = @args[ scalar(@arg_reads) .. $#args ];
        my $arr  = $self->_emit_array_of(\@rest);
        for my $n (_graph_component($graph)) {
            next unless blessed($n) && $n->operation eq 'PadAccess'
                && ( $n->sigil // '' ) eq '@' && ( $n->symbol // '' ) eq ( $slurpy->symbol // '' );
            $self->{_arg_bind}{ refaddr($n) } = { ref => $arr, repr => 'Array' };
        }
    }
    # A DEFAULT IS THE CALLEE'S, lowered in this frame: taken after the
    # snapshot below, `$x * 3` made for one call served the next (f() then
    # f(4) gave 4/6 for 4/12).
    my %cache_before = $self->{cache}->%*;
    for my $r (@defaulted) {
        my $d = $r->inputs->[0];
        # No default of its own: the body tests @_ and runs it (see the arity
        # check); the parameter is not read when it is not passed.
        unless (blessed($d)) {
            $self->{_arg_bind}{ refaddr($r) } = { ref => $self->_build_slot('false', '0', 'Undef', "$name: not passed"), repr => 'Scalar' };
            next;
        }
        $self->{_arg_bind}{ refaddr($r) } = { ref => $self->lower_value($d), repr => $d->stamp };
    }
    my $args_arr = $args_array ? $self->_emit_array_of(\@args) : undef;
    $self->{_arg_bind}{ refaddr($args_array) } = { ref => $args_arr, repr => 'Array' }
        if $args_array;

    # The callee's body nodes must NOT outlive this inline frame in the value
    # cache. The callee graph is ONE object shared by every call site (measured:
    # both `Call#2` and `Call#3` in `f(1)+f(2)` hold the same callee graph
    # refaddr, and its Multiply node has a single id and a single refaddr), so
    # a cache keyed on node id serves site 2 whatever site 1 computed --
    # with site 1's ARGUMENT baked in. That is F14/F15/F16: `f(1)+f(2)` emitted
    # exactly ONE `mul` and printed 4 where perl prints 6.
    #
    # refaddr keying does not fix this, unlike _arg_bind's collision: there the
    # keys were per-node and merely needed to be unique across graphs, whereas
    # here the callee node objects are LITERALLY IDENTICAL between sites. What
    # varies is the frame, so the frame is what the scoping must follow.
    #
    # Snapshot-and-restore rather than a fresh empty cache: the caller's own
    # already-lowered nodes stay visible to the inlined body (its arg refs were
    # lowered in this context, above), and entries the callee added are dropped
    # on the way out. Mirrors _arg_bind's local-scoped frame directly above.
    #
    # `f(3)+f(3)` passed before this fix by coincidence -- one cached
    # computation happens to be right for both sites -- which is why the corpus
    # case insists the arguments DIFFER.
    my $ref = $inline->();
    $self->{cache}->%* = %cache_before;
    $self->_copy_out_written_args($name, $written, \@args, $args_arr) if $written;

    # Memoize under the caller Call node's id, same reasoning as the
    # no-argument path above: this Call can be reached a second time as the
    # Return's value after already running as a statement effect. Written
    # AFTER the restore above -- it is a caller-side entry and must survive.
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _collect_straight_line_effect_chain($control_in, $name) -> @chain (newest-first)
#
# Collects the callee Return's control_in effect chain for Slice B Commit
# 2-print. Returns the chain in DISCOVERY order (newest-first, i.e. the order
# control_in walking naturally produces — the same order the top-level driver
# collects it in before reversing, LLVM.pm ~911-933). An empty list means a
# pure callee (control_in undef or Start): nothing to thread.
#
# GAPs loudly — the existing Commit 1 behavior — unless every node on the
# chain is a straight-line Print. Only Print is measured/verified for
# cross-graph inline splicing (Slice B Commit 2-print's scope); any other
# statement-effect (Assign/store, RegexSubst, a nested Call, ...) or a
# Region/Loop/If (the parked loop-store shape, memory-SSA re-entrancy — a
# separate slice) keeps GAPping rather than attempt an unverified lowering.
sub _collect_straight_line_effect_chain {
    my ($self, $control_in, $name) = @_;

    my @chain;
    my $c = $control_in;
    while (defined $c) {
        die "GAP: direct call to '$name': callee has effect(s) on its control "
          . "chain (print/store/...) that inlining does not yet thread in "
          . "program order."
            unless blessed($c) && $c->can('operation');

        my $op = $c->operation;
        last if $op eq 'Start';

        die "GAP: direct call to '$name': callee has effect(s) on its control "
          . "chain (print/store/...) that inlining does not yet thread in "
          . "program order."
            unless $op eq 'Print' || $op eq 'Call';

        # WHY `Call` IS HERE. This filter was written 2026-08-01 listing the
        # effect shapes verified at that time, when a callee's chain held
        # Print/Assign/Region. Two days later perl5-son 40d8f8b landed R1.0 --
        # "every Call is a control-chain effect, void or not" -- and a
        # `shift @_` became a control-chain node on EVERY argument-taking sub.
        # The list was complete when written and was made incomplete by a
        # change in the other repo, silently: refusing looks like correct
        # conservatism, so nothing failed loudly while it refused the commonest
        # shape in the language.
        #
        # The hazard it was built for is NOT what kept it narrow. That was the
        # id-keyed cache collision (a callee Print#N served a caller Print#N's
        # ref, silently dropping the effect), and the same commit fixed it with
        # a fresh cache for the chain drive. `_lower_inlined_effects_then_value`
        # is nine lines and inspects no op: fresh cache, fresh mut-read memo,
        # process_control_node over whatever it is handed. The fix was never
        # Print-specific; only this list was.
        #
        # Region/Loop/If still GAP below -- that is the parked memory-SSA
        # re-entrant slice, a real remaining concern rather than an unmeasured
        # one.

        push @chain, $c;
        $c = $c->can('control_in') ? $c->control_in : undef;
    }
    return @chain;
}

# _keeps_value($from, $to) -> bool
#
# Does coercing a $from value to $to keep it, so that reading it back gives
# what perl would? Used where the inliner reconciles a callee's reading with
# its caller's -- a call's result, a bound argument -- and nowhere a program
# itself asks for the conversion. A number made a Str and read back as a
# number is NOT kept: `g(1/3) * 3` through a Str-stamped call gave
# 0.999999999999999 for 1, and a big integer came back as 9.00719925474099e+15
# (review of e1a15d3a). Widening to a Num, boxing into a Slot, unboxing one,
# and numifying a Str (perl's own reading) are kept.
my %KEEPS = (
    Int     => { map { $_ => 1 } qw(Num Scalar Slot) },
    Boolean => { map { $_ => 1 } qw(Int Num Scalar Slot) },
    Num     => { map { $_ => 1 } qw(Scalar Slot) },
    Str     => { map { $_ => 1 } qw(Num Scalar Slot) },
    Undef   => { map { $_ => 1 } qw(Scalar Slot) },
    # A reference boxes by its tag into a value read by its tag.
    ( map { $_ => { Scalar => 1, Slot => 1 } } qw(ArrayRef HashRef ScalarRef CodeRef) ),
    Scalar  => { map { $_ => 1 } qw(Int Num Str Boolean Slot) },
    Slot    => { map { $_ => 1 } qw(Int Num Str Boolean Scalar) },
);
sub _keeps_value {
    my ($from, $to) = @_;
    return 1 if $from eq $to;
    return $KEEPS{$from} && $KEEPS{$from}{$to} ? 1 : 0;
}

# _is_straight_line_effect_chain($control_in) -> bool
#
# Is the callee's control chain prints and calls back to Start, and nothing
# else? That is what _collect_straight_line_effect_chain threads; anything
# else is inlined by _lower_inlined_structure.
sub _is_straight_line_effect_chain {
    my ($c) = @_;
    while (blessed($c) && $c->can('operation')) {
        my $op = $c->operation;
        return 1 if $op eq 'Start';
        return 0 unless $op eq 'Print' || $op eq 'Call';
        $c = $c->can('control_in') ? $c->control_in : undef;
    }
    return !defined $c;
}

# _lower_inlined_structure($return, $value) -> $llvm_ref
#
# INLINE A WHOLE CALLEE: its ifs, loops and stores, lowered in place through
# the same _process_control_chain a method body or the main program goes
# through, with the callee's own Elaborate plan placing its merge phis. The
# straight-line path took prints alone, and a callee that branched, looped or
# stored was refused -- 106 pvm corpus cases.
#
# EVERY TABLE KEYED BY NODE ID IS THE CALLEE'S FOR THE DURATION. Each graph
# numbers its nodes from its own factory, so a callee node can share an id
# with an unrelated caller node (see _lower_inlined_effects_then_value below);
# the cache, the merge plan, and every per-node side table are swapped for
# the callee's and restored on the way out. The var_table starts EMPTY: the
# arguments reach the body through _arg_bind, not the table, and a copy of the
# caller's let a callee VarDecl#1 read the caller's VarDecl#1 (8 for 10).
# The value is lowered inside the same frame: it is the callee's node, and a
# Phi at its merge is only in the callee's plan.
sub _lower_inlined_structure {
    my ($self, $return, $value) = @_;

    # A VALUE MADE INSIDE AN ARM HAS NO MERGE. A sub ending in `if ($n) {
    # print "x" }` returns that if's value -- B::SoN spells it And($n, Print)
    # or a ternary over the arms' prints -- and the print's result exists only
    # in its arm: served past the merge, lli rejected the module. An effect
    # the value reads must be on the callee's main chain; a Phi is the merge
    # that makes an arm's value legal, so the walk stops there.
    my %on_chain;
    for (my $c = $return->control_in; blessed($c); ) {
        last if $on_chain{ refaddr($c) }++;
        $c = ($c->operation eq 'Region' && $c->can('head') && blessed($c->head))
           ? $c->head
           : ($c->can('control_in') ? $c->control_in : undef);
    }
    # A PHI IS THAT MERGE only when its Region is on the main chain: a nested
    # if's merge sits inside an outer arm, and its phi does not dominate the
    # outer one (pvm subroutines.md, a nested if ending a sub: LLI_FAIL). A
    # merge phi's own effect inputs are its arms' values, boxed in by
    # _coerce_arm; anything deeper is walked like the rest.
    my $arm_value = "GAP: an inlined sub's value is made inside one of its arms "
                  . "(an if as its last statement) -- that value has no merge to "
                  . "reach the caller through.\n";
    # Below an on-chain merge phi, an arm's value is lowered in its own arm --
    # effects and all -- so only a further merge there needs checking.
    # MADE IN AN ARM means its control leads back to an arm's Proj before it
    # reaches the main chain. An effect with no control at all -- a call the
    # producer floats -- is no arm's, and refusing it refused 33 corpus cases
    # for nothing. A loop's phi is lowered with its body, before the
    # back-edge, wherever that loop sits; an if's merge inside an arm is not.
    my $in_an_arm = sub ($n) {
        for (my $c = $n->can('control_in') ? $n->control_in : undef; blessed($c); ) {
            return 0 if $on_chain{ refaddr($c) };
            return 1 if $c->operation eq 'Proj';
            $c = ($c->operation eq 'Region' && $c->can('head') && blessed($c->head))
               ? $c->head
               : ($c->can('control_in') ? $c->control_in : undef);
        }
        return 0;
    };
    my @q = defined $value ? ([$value, 0]) : ();
    my %seen;
    while (defined(my $e = shift @q)) {
        my ($n, $in_arm) = @$e;
        next unless blessed($n) && !$seen{ refaddr($n) . "/$in_arm" }++;
        if ($n->operation eq 'Phi') {
            my $r = $n->can('region') ? $n->region : undef;
            # In an arm, an if's merge -- or a loop's exit, the loop being in
            # that arm too -- is lowered there, before the value that reads it.
            die $arm_value
                unless blessed($r) && ( $on_chain{ refaddr($r) } || $r->operation eq 'Loop'
                    || ( $in_arm && $r->can('head') && blessed($r->head)
                         && $r->head->operation =~ /\A(?:If|Loop)\z/ ) );
            # A LOOP ON THE MAIN CHAIN carries its phi in its header, which
            # dominates what follows the loop; its back-edge is the body's,
            # lowered with it, ifs and all. Only the first value comes from
            # outside. Walked into the back-edge, an if's merge in the body
            # refused 19 corpus cases.
            if ($r->operation eq 'Loop' && $on_chain{ refaddr($r) }) {
                push @q, [ $n->inputs->[0], $in_arm ];
                next;
            }
            push @q, map { [$_, 1] } $n->inputs->@*;
            next;
        }
        die $arm_value if !$in_arm && $n->is_fixed && !$on_chain{ refaddr($n) }
            && $in_an_arm->($n);
        push @q, map { [$_, $in_arm] } $n->inputs->@*;
    }
    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($return);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($return, $dom);
    local $self->{elab}                  = $elab;
    local $self->{elab_phi_by_block}     = _index_elab_phis($elab);
    local $self->{cache}                 = {};
    local $self->{_past_a_died_eval}     = {};   # keyed by id, as {cache} is
    local $self->{var_table}             = {};
    local $self->{_mut_read_memo}        = {};
    local $self->{_frozen_reads}         = {};
    local $self->{_env_defined}          = {};
    local $self->{_undef_payload}        = {};
    local $self->{_undef_defined_bit}    = {};
    local $self->{_phi_to_vd}            = {};
    local $self->{_regex_captures}       = {};
    local $self->{_phi_forcing}          = {};
    local $self->{_vd_repr}              = {};
    local $self->{_unwind_emitted}       = {};
    local $self->{_empty_arrays}         = {};
    local $self->{_local_slots}          = {};
    local $self->{_graph_entry_idx}      = $self->{current_idx};
    local $self->{_branch_guarded_store} = 0;
    local $self->{_loop_ctx_stack}       = [];
    local $self->{_jump_merges}          = {};
    Chalk::Target::LLVM::_process_control_chain($self, $return);
    my $ref = defined $value ? $self->lower_value($value) : undef;
    # Its type as this lowering held it -- a merge typed by THESE arguments
    # (_repr_of) -- read before the callee's cache goes.
    $self->{_inlined_value_repr} = defined $value ? $self->_repr_of($value) : undef;
    return $ref;
}

# _lower_inlined_effects_then_value(\@effect_chain, $value) -> $llvm_ref
#
# Threads a callee's straight-line effect chain (oldest-first; @effect_chain
# is newest-first per _collect_straight_line_effect_chain, so this reverses
# it) through process_control_node INSIDE the arg-bind frame, splicing the
# callee's effects into the caller's control chain in program order, then
# lowers the Return value.
#
# CROSS-GRAPH CACHE COLLISION (load-bearing): lower_value's cache is keyed by
# the node's STRING id (Context.pm ~341), but each graph numbers its nodes
# from its OWN factory (NodeFactory.pm counter), so a callee Print#N can
# collide with an unrelated caller Print#N. Since the effect-emitting subs
# (_lower_print et al) write `$self->{cache}{$node->id} = ...` directly
# (there is no shared setter to intercept), the ONLY safe way to guarantee a
# callee's effect is never served from — or silently folded into — the
# caller's cache is to swap the ENTIRE cache to a fresh hash for the duration
# of the chain drive (mirrors _arg_bind's existing local-scoped-frame
# pattern). This also gives the correct TWO-CALL-SITE behavior for free: each
# inline gets its own fresh cache, so a callee inlined twice re-lowers (and
# re-emits) its effect both times rather than being served a stale cached ref.
#
# PRECONDITION for the parked Commit 2-loop-store slice (load-bearing): the
# fresh cache is scoped to the effect drive only; $value is then lowered under
# the RESTORED caller cache. So a value node ALSO referenced by an effect (e.g.
# `sub f { print $x; $x }`) is lowered TWICE — once under the fresh cache, once
# under the caller cache. This is safe ONLY because every value node the
# Print-only chain admits is either (a) pure and idempotent to re-lower (a
# double-lower recomputes byte-identical bytes; only the $value copy is wired
# into the return — a redundant emit, e.g. Concat leaks one malloc, but NOT a
# miscompile), or (b) a no-emit PadAccess. An EFFECTFUL or memory-reading value
# node re-lowered here WOULD double-emit its effect (a real miscompile). Those
# are excluded today by Call's per-call identity (never hash-consed,
# NodeFactory.pm) and the Print-only guard in _collect_straight_line_effect_chain
# (a store/nested-call on the chain GAPs). WIDENING that guard (the parked
# loop-store slice: admitting a Region/store/nested Call) MUST re-establish this
# invariant — scope the cache swap to cover $value too, or prove the shared node
# stays pure — or it silently reintroduces the double-effect miscompile.
#
# CROSS-GRAPH MUT-READ-MEMO COLLISION (git-zhi 019fbe27, load-bearing): a
# SECOND, independent id-keyed cache — $self->{_mut_read_memo}
# (_reads_mutable_location's memo, Context.pm ~276-303) — has the exact same
# cross-graph collision hazard as {cache} above, but is NOT covered by the
# {cache} swap: it is a pure structural classification (does this node read a
# mutable location), computed once and reused for the REST OF THIS LOWERING,
# independent of any given cache generation. A callee PURE node (e.g. an Add
# referenced twice) can collide, by id, with an unrelated CALLER
# mutable-read node (PadAccess/Subscript/FieldAccess/EntryDef); whichever
# is classified first wins the memo entry for that id. If the callee's node
# is classified PURE first, the caller's same-id mutable-read node later
# inherits that stale PURE answer, so lower_value's cache-bypass check
# (Context.pm ~353) wrongly treats it as cacheable and serves a stale
# pre-mutation value — the same stale-value miscompile class {cache}
# isolation guards against, just via the OTHER id-keyed table. Unlike
# {cache}, this hazard spans BOTH the effect-chain drive and the $value
# lowering (a callee's pure subexpression can be looked up twice, and thus
# memoized, in either), so the isolation must wrap the ENTIRE callee-node
# lowering span here, not just the narrower effect-drive cache swap above.
sub _lower_inlined_effects_then_value {
    my ($self, $effect_chain, $value) = @_;

    local $self->{_mut_read_memo} = {};

    # THE VALUE IS LOWERED IN THE SAME FRAME AS THE EFFECTS. Lowered under
    # the caller's cache, a Call the effect chain had already run -- `return
    # 5 + f(1)`, `$l[h()]` -- missed its memo and was lowered, and run, a
    # second time: `print "x"` printed twice (review of 4e1e9969). This is the
    # invariant the PRECONDITION above asked to be re-established.
    local $self->{cache}         = {};
    local $self->{_past_a_died_eval} = {};   # keyed by id, as {cache} is
    local $self->{_frozen_reads} = {};   # keyed by id, as {cache} is
    local $self->{_empty_arrays} = {};   # the callee's `my @a`, fresh per call
    local $self->{_local_slots}  = {};   # and its `my $x` kept in memory
    local $self->{_graph_entry_idx} = $self->{current_idx};
    # READS AT ENTRY ARE TAKEN AT ENTRY, as _process_control_chain takes them:
    # a `join(sort keys %h)` at the callee's MemStart, lowered at its use
    # after a call that writes %h, read the write.
    my ($memstart) = grep { defined } map { $self->_find_memstart($_) }
        grep { blessed($_) } ($value, $effect_chain->@*);
    # Only reads this callee reaches: a MemStart shared across graphs (an
    # older wire) has every graph's reads for consumers.
    if (defined $memstart) {
        my (%in, @q);
        @q = grep { blessed($_) } ($value, $effect_chain->@*);
        while (defined(my $n = shift @q)) {
            next if $in{ refaddr($n) }++;
            push @q, grep { blessed($_) } $n->inputs->@*;
        }
        $self->_freeze_memory_reads($memstart, \%in);
    }
    $self->process_control_node($_) for reverse $effect_chain->@*;
    my $ref = defined $value ? $self->lower_value($value) : undef;
    # Its type as this lowering held it -- a merge typed by THESE arguments
    # (_repr_of) -- read before the callee's cache goes.
    $self->{_inlined_value_repr} = defined $value ? $self->_repr_of($value) : undef;
    return $ref;
}

# _is_args_array($node) -> bool
#
# Is this EntryDef the ARGUMENT ARRAY `@_`, as opposed to the scalar `$_`?
#
# `@_` has its OWN NODE KIND now, so this is one operation check. It was a
# name test (`var_name eq '_'`), which could not tell `@_` from the scalar `$_`
# -- a `$_` node walked into the @_ handling and was reported as "a list
# assignment `my (...) = @_`" on a source containing none: a correct refusal
# with a wrong diagnosis. A sigil check fixed that; a separate node kind means
# the two cannot be confused even in principle.
sub _is_args_array {
    my ($node) = @_;
    return $node->operation eq 'ArgsSource';
}

# _graph_component($graph) -> @nodes
#
# EVERY NODE OF A CALLEE, not its membership. Graph::nodes walks data edges,
# and an if's condition hangs off the If, which is reached by control: in
# `sub f { my $n = shift; if ($n) {...} }` the shift is read only by the
# condition, so membership never held it and the arguments went unbound
# ("reads 0 positional argument(s)").
#
# BACKWARD from what membership holds -- inputs, control_in, a Region's head
# -- and FORWARD only from a control node to what it controls (an If's or a
# Loop's Projs, the statements a Proj or Region heads). Following every
# consumer walked out of the callee through any node another graph shared:
# the coercion passes once minted one Coerce for two graphs, and g's walk
# counted f's shift as its own (review of 4e1e9969).
sub _graph_component {
    my ($graph) = @_;
    my (%seen, @out);
    my @q = grep { blessed($_) } $graph->nodes->@*;
    while (defined(my $n = shift @q)) {
        next if $seen{ refaddr($n) }++;
        push @out, $n;
        my $op = $n->operation;
        push @q, grep { blessed($_) } (
            $n->inputs->@*,
            ($n->can('control_in') ? $n->control_in : ()),
            ($n->can('head')       ? $n->head       : ()),
        );
        # @_ IS READ BY WHAT CONSUMES IT, and a `my (...) = @_` is consumed by
        # nothing: the walk reaches it from @_, or from a target it assigns.
        # Only the list assignment: an @_ hash-consed across graphs (an older
        # wire) has every sub's reads for consumers, and they are not ours.
        push @q, grep { blessed($_) && $_->operation eq 'Assign' } ($n->consumers // [])->@*
            if $op eq 'ArgsSource' && $n->can('consumers');
        push @q, grep {
            blessed($_) && $_->operation eq 'Assign'
                && blessed($_->inputs->[-1]) && _is_args_array($_->inputs->[-1])
        } ($n->consumers // [])->@*
            if $op eq 'PadAccess' && $n->can('consumers');
        next unless $op =~ /\A(?:If|Loop|Proj|Region)\z/ && $n->can('consumers');
        push @q, grep {
            blessed($_) && (
                $_->operation eq 'Proj'
                || ( $_->can('control_in') && blessed($_->control_in)
                     && refaddr($_->control_in) == refaddr($n) ) )
        } ($n->consumers // [])->@*;
    }
    return @out;
}

# _collect_positional_arg_reads($graph, $name) -> @shift_nodes
#
# Find the callee graph's positional argument reads: Call(builtin, shift) nodes
# whose operand is EntryDef(*, _) (i.e. `shift @_`). Returns them in graph
# order. Dies (loud GAP) on any OTHER access to @_ that inlining cannot bind:
# a `pop @_`, a list assignment `my (...) = @_`, or a `$_[N]` subscript — those
# shapes do not carry the positional binding the caller's args need.
sub _collect_positional_arg_reads {
    my ($self, $graph, $name) = @_;

    my @shifts;
    my @list_assigns; # `my (...) = @_`
    my %subscripts;   # index => the $_[index] Subscript node
    my %params;       # index => the Parameter node (a DECLARED signature)
    my $args_array;   # @_ itself, when the callee reads it as a list
    $self->{_args_read_as_a_list} = undef;
    my (%written, $written_src);   # `$_[N] = ...`: N => 1, and @_
    $self->{_args_written} = undef;
    $self->{_args_signature} = 0;
    $self->{_args_slurpy}    = undef;
    for my $n (_graph_component($graph)) {
        next unless blessed($n);
        my $op = $n->operation;

        # A DECLARED PARAMETER. Its index IS its position, so this needs no
        # recovery at all -- which is the point. `shift @_` and `$_[N]` both
        # cap at ONE argument here, for reasons that do not apply: multiple
        # shifts hash-cons to a single node and lose their order, and the
        # subscript path was written for the single-arg case. A Parameter
        # carries its own index, so N of them order themselves.
        if ($op eq 'Parameter') {
            $params{ $n->index } = $n;
            next;
        }

        # `shift @_` / `pop @_`: the arg-read we can bind (shift only).
        if ($op eq 'Call' && $n->can('dispatch_kind')
                && ($n->dispatch_kind // '') eq 'builtin'
                && defined $n->name && ($n->name eq 'shift' || $n->name eq 'pop')) {
            my ($operand) = grep { blessed($_) } $n->inputs->@*;
            next unless defined $operand && _is_args_array($operand);
            die "GAP: direct call to '$name': callee reads \@_ via `pop` — only "
              . "positional `shift \@_` argument binding is inlined (`pop \@_` "
              . "reads from the end, which inlining does not model)."
                if $n->name eq 'pop';
            push @shifts, $n;
        }
        # `my (...) = @_`: an Assign whose last input is @_ and whose others
        # are its targets, in order -- each target IS its argument's position.
        elsif ($op eq 'Assign' && @{ $n->inputs } >= 2
                && blessed($n->inputs->[-1]) && _is_args_array($n->inputs->[-1])) {
            # `my @p = @_` is a copy of the list, not a position.
            my @t = $n->inputs->@[ 0 .. $#{ $n->inputs } - 1 ];
            next if @t == 1 && blessed($t[0]) && $t[0]->operation eq 'PadAccess'
                && ( $t[0]->sigil // '' ) eq '@';
            push @list_assigns, $n;
        }
        # `$_[N]`: a positional subscript on @_, i.e. Subscript(ArgsSource,
        # Constant(N), Mem). Bindable: the caller's Nth argument substitutes for
        # the whole Subscript node during inlining (keyed by refaddr, like a
        # `shift @_`). Collected by index so a single `$_[0]` reader binds arg 0.
        #
        # The container used to be a string Constant("_") -- the array spelled
        # as its own NAME, which is why this test read a literal.
        elsif ($op eq 'Subscript') {
            my @in = grep { blessed($_) } $n->inputs->@*;
            my ($container, $index) = @in;
            next unless defined $container
                && $container->operation eq 'ArgsSource';
            next unless defined $index && $index->operation eq 'Constant'
                && $index->can('value') && defined $index->value
                && $index->value =~ /^\d+$/;
            $subscripts{ $index->value } = $n;
        }
        # `my (...) = @_`: @_ accessed as an aggregate. The producer does not
        # connect the list-assign to the caller's args in the graph, so inlining
        # cannot bind it — GAP loudly rather than miscompile.
        elsif ($op eq 'ArgsSource') {
            # Two consumers ARE bindable and are handled above: a `shift @_`
            # Call, and a `$_[N]` Subscript. Anything else (a list-assign, a
            # deref) is an @_ shape inlining cannot bind.
            #
            # The Subscript exemption is new with the ArgsSource node: `$_[0]`
            # used to reach @_ through a string Constant("_") container, so it
            # never arrived here at all. Now that every spelling of @_ names the
            # same node, this guard sees them all -- and must not refuse the one
            # the arg binder already knows how to handle.
            my @other = grep {
                blessed($_)
                    && !( $_->operation eq 'Call'
                        && $_->can('dispatch_kind')
                        && ($_->dispatch_kind // '') eq 'builtin'
                        && defined $_->name && $_->name eq 'shift' )
                    && $_->operation ne 'Subscript'
                    && !( $_->operation eq 'Assign'
                          && refaddr($_->inputs->[-1] // 0) == refaddr($n) )
            } $n->consumers->@*;
            # READ AS A LIST -- counted, walked, joined, copied -- @_ is an
            # array of the call's arguments, built at the call (see
            # _lower_call_direct). Only reads: a copy cannot carry a write
            # back to the caller's variable, nor a shift out of the list.
            if (@other) {
                for my $c (@other) {
                    my $cop = $c->operation;
                    # Counted, tested, or copied into a hash: reads.
                    next if $cop =~ /\A(?:Count|Exists|HashLiteral)\z/;
                    # Read as a number or a truth: its count.
                    next if $cop eq 'Coerce' && ( $c->to_repr // '' ) =~ /\A(?:Int|Num|Str|Boolean)\z/;
                    next if $cop eq 'Call' && ( $c->dispatch_kind // '' ) eq 'builtin'
                        && ( $c->name // '' ) =~ /\A(?:join|sort|reverse)\z/;
                    next if $cop eq 'Assign' && blessed($c->inputs->[0])
                        && refaddr($c->inputs->[-1]) == refaddr($n)
                        && $c->inputs->[0]->operation eq 'PadAccess'
                        && ( $c->inputs->[0]->sigil // '' ) eq '@';
                    die "GAP: direct call to '$name': callee hands \@_ to a $cop"
                      . ( $cop eq 'Call' ? ' ' . ( $c->name // '?' ) : '' )
                      . " -- inlining reads \@_ as a list of the arguments, and "
                      . "that may write it.\n";
                }
                $args_array = $n;
            }
            # A WRITE THROUGH AN ELEMENT reaches the caller's variable, which
            # a copy cannot: `$_[0] = 9` is refused whatever else reads @_. So
            # is one through a reference to it -- the alias a foreach takes of
            # an iterator it hands to a call -- found by following the
            # reference through what passes it on to a store's target.
            for my $sub (grep { blessed($_) && $_->operation eq 'Subscript' } $n->consumers->@*) {
                my @q = ($sub);
                my %seen;
                while (defined(my $v = shift @q)) {
                    next if $seen{ refaddr($v) }++;
                    for my $u (($v->consumers // [])->@*) {
                        next unless blessed($u);
                        my $uop = $u->operation;
                        # A STORE TO `$_[N]` ITSELF, N a constant, is written back
                        # to the caller's argument after the inline (copy-out,
                        # _lower_call_direct). One through a reference is not.
                        if ($uop eq 'Assign' && refaddr($v) == refaddr($sub)
                                && refaddr($u->inputs->[0] // 0) == refaddr($v)) {
                            my $ix = $sub->inputs->[1];
                            if (blessed($ix) && $ix->operation eq 'Constant'
                                    && ($ix->value // '') =~ /\A\d+\z/) {
                                $written{ $ix->value } = 1;
                                $written_src = $n;
                                next;
                            }
                        }
                        die "GAP: direct call to '$name': callee writes \$_[N] -- an "
                          . "alias of the caller's argument, which inlining does not "
                          . "write back.\n"
                            if ( $uop eq 'Assign' && refaddr($u->inputs->[0] // 0) == refaddr($v) )
                            || $uop eq 'LocalAlias';
                        push @q, $u if $uop =~ /\A(?:Ref|TernaryExpr|PostfixDeref)\z/;
                    }
                }
            }
        }
    }

    # @_ WRITTEN is read as the array it is: every `$_[N]` reads the array the
    # call builds, which the callee's stores change, and the call copies the
    # written elements back. A positional binding would read the value from
    # before the store.
    if (%written) {
        die "GAP: direct call to '$name': callee writes \@_ and binds it by "
          . "`shift` or `my (...) = \@_` -- only `\$_[N]` reads see its stores.\n"
            if @shifts || @list_assigns || %params;
        $self->{_args_written} = [ sort { $a <=> $b } keys %written ];
        $self->{_args_read_as_a_list} = $written_src;
        return ();
    }

    if ($args_array) {
        die "GAP: direct call to '$name': callee shifts \@_ and reads it as a "
          . "list -- the list after a shift is not the call's arguments.\n"
            if @shifts;
        $self->{_args_read_as_a_list} = $args_array;
    }

    # A DECLARED SIGNATURE WINS, and it is not capped at one argument. The
    # parameters are returned in index order, so the caller's positional
    # binding (arg_reads[$i] <- arg_refs[$i]) lines up by construction.
    $self->{_args_signature} = %params ? 1 : 0;
    if (%params) {
        die "GAP: direct call to '$name': callee mixes declared signature "
          . "parameters with `shift \@_` / `\$_[N]` positional reads."
            if @shifts || %subscripts;

        # BY INDEX, holes and all: a hole is a parameter the body never
        # reads (`($, $phi)`), and each read one keeps its own position.
        my ($max) = sort { $b <=> $a } keys %params;
        return map { $params{$_} } 0 .. $max;
    }

    # ONE POSITIONAL STYLE PER CALLEE: shifts, `$_[N]`, or one `my (...) =
    # @_`. Mixed, which read takes which argument depends on order the graph
    # does not carry, so it is refused rather than guessed.
    die "GAP: direct call to '$name': callee mixes `shift \@_`, `\$_[N]` and "
      . "`my (...) = \@_` positional reads -- inlining binds one style per callee."
        if (@shifts ? 1 : 0) + (%subscripts ? 1 : 0) + (@list_assigns ? 1 : 0) > 1;

    # `my ($a, $b) = @_`: the targets, in order, are the arguments. A slurpy
    # target (`@rest`, `%args`) takes all that remain and is no one position.
    if (@list_assigns) {
        die "GAP: direct call to '$name': callee assigns \@_ to a list "
          . scalar(@list_assigns) . " times -- inlining binds one."
            if @list_assigns > 1;
        my @inputs  = $list_assigns[0]->inputs->@*;
        my @targets = @inputs[ 0 .. $#inputs - 1 ];
        # A SLURPY ARRAY LAST takes every argument after the scalars: bound by
        # the call to an array of them (_lower_call_direct, _args_slurpy).
        if (@targets && blessed($targets[-1]) && $targets[-1]->operation eq 'PadAccess'
                && ( $targets[-1]->sigil // '' ) eq '@') {
            $self->{_args_slurpy} = pop @targets;
        }
        for my $t (@targets) {
            die "GAP: direct call to '$name': callee's `my (...) = \@_` has a "
              . "slurpy target -- an array or hash takes every remaining "
              . "argument, which inlining does not bind."
                unless blessed($t) && $t->operation eq 'PadAccess'
                    && ( $t->can('sigil') ? ($t->sigil // '$') : '$' ) eq '$';
        }
        return @targets;
    }

    # `$_[N]`: bound by index, which must run from 0 with no hole -- a
    # positional binding past a hole would shift every later argument.
    if (%subscripts) {
        # BY INDEX, holes and all: a method reads `$_[1]` and never its
        # invocant. A hole is a position nothing reads (undef here).
        my ($max) = sort { $b <=> $a } keys %subscripts;
        return map { $subscripts{$_} } 0 .. $max;
    }

    # SHIFTS ARE ORDERED BY THEIR MEMORY. Each `shift @_` takes the shift
    # before it as its memory input -- that chain IS their order, so several
    # bind as surely as one. (They were said to hash-cons and lose it; they do
    # not.) A chain that does not cover every shift -- one under a branch --
    # has no single order and is refused.
    return @shifts if @shifts <= 1;
    my %is_shift = map { refaddr($_) => $_ } @shifts;
    my ($first) = grep {
        my $m = $_->inputs->[1];
        !( blessed($m) && $is_shift{ refaddr($m) } )
    } @shifts;
    my @ordered;
    my %next = map {
        my $m = $_->inputs->[1];
        ( blessed($m) && $is_shift{ refaddr($m) } ) ? ( refaddr($m) => $_ ) : ()
    } @shifts;
    for (my $c = $first; defined $c; $c = $next{ refaddr($c) }) {
        push @ordered, $c;
        last if @ordered > @shifts;
    }
    die "GAP: direct call to '$name': callee's " . scalar(@shifts)
      . " `shift \@_` reads do not form one memory chain -- their order is not "
      . "in the graph (a shift under a branch?)."
        unless @ordered == @shifts
            && scalar(grep { !blessed($_->inputs->[1]) || !$is_shift{ refaddr($_->inputs->[1]) } } @shifts) == 1;
    return @ordered;
}

sub _lower_call_method {
    my ($self, $node) = @_;

    my $method_name = $node->name;

    # A PACKAGE'S `new` IS ITS SUB, which blesses what it builds: a `class`
    # constructor's object struct was allocated in its place, and the sub
    # (and its bless) never ran.
    return $self->_lower_call_direct($node)
        if blessed($node->target) && $node->target->isa('Chalk::MOP::Sub');

    # Route constructor calls to the construction lowering.
    if ($method_name eq 'new') {
        return $self->_lower_call_new($node);
    }
    my $obj_node    = $node->inputs->[0];
    # AN INVOCANT THE CALL SITE MADE: a sub's parameter, inlined, is the
    # caller's argument -- a `C->new(...)` or a bless into a literal class --
    # whose class is static there. The method is that class's sub, for this
    # lowering only: the Call is shared by every site that inlines the sub.
    if (!defined $node->class_name && defined(my $cls = $self->_static_class_of($obj_node))) {
        my $mop = $self->{mop};
        my $c   = $mop ? $mop->for_class($cls) : undef;
        my ($sub) = $c ? grep { $_->name eq $method_name } $c->subs : ();
        die "GAP: method '$method_name' of class $cls (passed in) is not a package sub of "
          . "it -- inherited or a `class` method, not lowered\n" unless $sub;
        my $was = $node->target;
        $node->set_target($sub);
        my $ref = eval { $self->_lower_call_direct($node) };
        my $err = $@;
        $node->set_target($was);
        die $err if $err;
        return $ref;
    }
    # A METHOD ON WHAT IS NOT AN OBJECT dies (`state $n` with no feature is
    # `$n->state`).
    if (!defined $node->class_name) {
        my $r = $self->_lower_method_on_non_object($node, $obj_node);
        return $r if defined $r;
        $r = $self->_lower_runtime_dispatch($node, $obj_node);
        return $r if defined $r;
    }
    # MOP-direct shape: the class rides as the class_name attribute.
    my $class_name  = $node->class_name
        // die "GAP: LLVM MOP: Call(method) '$method_name' has no class_name — "
             . "method dispatch must name its statically-known class "
             . "(019eb42a MOP-direct contract).";
    # A PACKAGE SUB CALLED AS A METHOD (see _attach_call_targets) is a direct
    # call with the invocant as its first argument -- inlined like any other.
    return $self->_lower_call_direct($node)
        if blessed($node->target) && $node->target->isa('Chalk::MOP::Sub');

    $self->_refuse_inside_eval("a call to method '$method_name'");
    my $result_repr = _require_repr($node, 'Call(method)');

    # Verify class and method are in the registry
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: Call(method) '$method_name' on undeclared class '$class_name' — "
             . "the class is not in the sealed MOP handed to lower(). Cannot emit vtable slot.";

    my $methods = $reg->{methods} // [];
    my ($minfo) = grep { ($_->{name} // '') eq $method_name } @$methods;
    unless (defined $minfo) {
        die "LLVM MOP: Call(method) '$method_name' is absent from class '$class_name' vtable — "
          . "available methods: [" . join(', ', map { $_->{name} // '?' } @$methods) . "]. "
          . "Cannot emit vtable dispatch to a non-existent slot.";
    }

    # ABI cross-check: the call site is cast per the NODE's repr while the
    # vtable function was DEFINED per the registry's return_repr. The i8*
    # fn-ptr bitcast means lli ACCEPTS a mismatch — the silent-garbage
    # channel (branch-review I4). Die loudly instead.
    #
    # THIS IS A T2 CHECK, NOT A T1 ONE (perigrin, 2026-08-28). Both operands are
    # REPRESENTATIONS — `_repr_to_llvm_type` inputs, Int => i64 vs Num =>
    # double. The vtable ABI is a property of the LOWERING GRAPH: it names the
    # machine slot an indirect call reads through, not the Perl type of the
    # method. So the `ne` below is an ENCODING coherence test and its wording
    # ("disagrees") should not be read as a type conflict.
    #
    # The distinction is load-bearing because Int <: Num in the lattice
    # (%PARENT: Int => 'Num'; join(Int,Num) = Num). A node stamped Num where the
    # ABI says Int is therefore SOUND on the type axis — the join moved up, and
    # an Int value IS a Num. What is unsound is reading i64 bits through a
    # double slot, which is why this fires. Measured 2026-08-28: corpus R15
    # printed 1.48219693752374e-323 for perl's 3, i.e. i64 3's bits as a double.
    #
    # I hypothesised twice that a missing `sitofp` at THIS boundary was a real
    # chalk-side gap. FALSIFIED by measurement, 2026-08-28 — recorded because a
    # negative result that is not written down gets re-derived.
    #
    # Probe: `class Box { field $v :param :reader = 0; method half { $v / 2 } }`
    # — a Num-returning method and an Int-returning `:reader` on ONE vtable, on
    # a truthful wire. It lowers, and `lli` matches perl exactly (3.5 / 7). The
    # emitted module shows why:
    #
    #   define internal double @Box__half(i8* %self)
    #   define internal i64    @Box__v(i8* %self)
    #   @Box__vtable = { ..., i8* bitcast (double (i8*)* @Box__half to i8*),
    #                         i8* bitcast (i64    (i8*)* @Box__v    to i8*) }
    #
    # EACH METHOD IS DEFINED AT ITS OWN RETURN TYPE, and the vtable bitcasts
    # each function pointer separately — there is no shared slot type for an
    # Int and a Num to collide in. The `sitofp`s in that module sit INSIDE
    # `Box::half`, promoting the Int field read for the divide, which is where
    # a coercion belongs.
    #
    # So this guard fires only when the NODE's repr disagrees with the
    # REGISTRY's, and both derive from the same wire: on a truthful wire they
    # agree by construction. The 6 failures that prompted the hypothesis were
    # downstream of a FABRICATED stamp (producer 1f1dd43 typed a Call from its
    # caller's requirement), not of a missing cast.
    my $abi_repr = $minfo->{return_repr}
        // die "GAP: Call(method) '$method_name' — class '$class_name' vtable "
             . "entry has NO return_repr, so the call site's ABI cast cannot be "
             . "cross-checked. Guessing one would cast a $result_repr result "
             . "through a fabricated ABI. Fix the MOP so the method declares "
             . "its return repr.";
    # THE TWO NO LONGER DERIVE FROM ONE SOURCE, so equality is the wrong test.
    # The comment above says they "agree by construction" on a truthful wire --
    # true when both came from the producer, and false since chalk's own T1
    # narrows a Call from whole-program evidence the wire does not carry. A
    # `:param` field is honestly `Scalar` on the wire and provably `Int` from
    # its construction sites; the node knows more than the ABI, which is
    # REFINEMENT, not disagreement.
    #
    # Refusing it was correct while nothing could bridge the two. Something can
    # now: `Int <: Scalar`, the callee returns the `%Slot` its body was emitted
    # at, and the unbox below reads that cell at the node's repr. So the test
    # is whether the node REFINES the ABI, and only an unrelated pair is still
    # a defect worth refusing.
    #
    # TWO EARLIER ATTEMPTS FIXED THIS FROM THE WRONG END (both reverted): they
    # narrowed the CALLEE to match the node -- first the vtable entry, then the
    # metaobject -- and emitted 4622382067542392832 for perl's 11, which is
    # 11.0's bits read as an i64. The callee has ONE body at ONE machine type;
    # it is the CALL that must meet it, and the refinement is honoured after.
    if ($result_repr ne $abi_repr
            && !Chalk::Grammar::Perl::TypeLibrary::is_subtype($result_repr, $abi_repr)) {
        die "GAP: Call(method) '$method_name' node repr=$result_repr disagrees "
          . "with class '$class_name' vtable ABI return_repr=$abi_repr — "
          . "neither refines the other, so a mismatched indirect call would be "
          . "silently wrong.";
    }

    my $slot_idx = $minfo->{vtable_slot};

    # Lower the object to get the raw pointer
    my $obj_raw = $self->lower_value($obj_node);

    # Load vtable pointer
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; Call(method) $method_name: typed obj");
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 0  ; vtable ptr slot");
    my $vt_ptr = $self->_fresh;
    $self->_emit("  $vt_ptr = load %${class_name}.vt*, %${class_name}.vt** $vt_gep  ; load vtable ptr");

    # Load opaque fn ptr from vtable slot
    my $fn_slot_llvm = 1 + $slot_idx;
    my $fn_gep = $self->_fresh;
    $self->_emit("  $fn_gep = getelementptr inbounds %${class_name}.vt, %${class_name}.vt* $vt_ptr, i64 0, i32 $fn_slot_llvm  ; method '$method_name' fn ptr slot");
    my $opaque_fn = $self->_fresh;
    $self->_emit("  $opaque_fn = load i8*, i8** $fn_gep  ; load opaque fn ptr for '$method_name'");

    # Cast to actual fn-ptr type and call
    # AT THE ABI. `$result_repr` (the node's, possibly refined) named this type
    # until 2026-09-01, so a node narrowed to Int cast a `%Slot (i8*)` callee to
    # `i64 (i8*)` and called it at the wrong type.
    # THE ARGUMENTS. `$node->inputs` is [invocant, arg0, arg1, ...], and the
    # callee's formals came from its own Parameter nodes -- two independent
    # readings of the same signature, so a disagreement between them is a real
    # defect and refused rather than papered over. Passing the wrong count
    # through a bitcast fn pointer is not a diagnosable error at run time; it
    # is stack garbage read as a value.
    my $param_reprs = $minfo->{param_reprs} // [];
    my @arg_nodes   = @{ $node->inputs }[ 1 .. $#{ $node->inputs } ];
    if (@arg_nodes != @$param_reprs) {
        die "GAP: Call(method) '$method_name' passes " . scalar(@arg_nodes)
          . " argument(s) but '$class_name'::$method_name declares "
          . scalar(@$param_reprs) . " -- the emitted call would read stack "
          . "garbage for the missing one.";
    }

    my @call_args;
    for my $i (0 .. $#arg_nodes) {
        my $want = $param_reprs->[$i];
        my $got  = $arg_nodes[$i]->stamp // '';
        # AT THE CALLEE'S TYPE, for the same reason the return is: the body is
        # emitted once, at one machine type. A caller that knows a narrower
        # type still has to hand over the declared one.
        my $ref = $self->lower_value($arg_nodes[$i]);
        # _emit_coercion is the shipped arrow between two reprs, the same one
        # an explicit Coerce node lowers through. It refuses a pair it cannot
        # bridge, which is the right answer here: calling at the wrong machine
        # type is not diagnosable at run time.
        $ref = $self->_emit_coercion($ref, $got, $want,
                                     "Call(method) $method_name arg $i")
            if $got ne $want;
        push @call_args,
             Chalk::Target::LLVM::_method_fn_llvm_ret_type($want) . " $ref";
    }
    my $arg_text = join(', ', "i8* $obj_raw", @call_args);

    my $fn_type  = _method_fn_type($abi_repr, $param_reprs);
    my $typed_fn = $self->_fresh;
    $self->_emit("  $typed_fn = bitcast i8* $opaque_fn to $fn_type*  ; cast to typed fn ptr");

    my $result = $self->_fresh;

    # THE CALL MUST MATCH THE FN-POINTER CAST, which was made at $abi_repr just
    # above. This arm keyed on $result_repr -- the NODE's repr -- so a method
    # whose vtable ABI is %Slot, called at a site the loader narrowed to Str,
    # emitted a %Str-returning call through a %Slot-returning pointer and lli
    # refused ("defined with type '%Slot (i8*)*' but expected '%Str (i8*)*'").
    #
    # Same class as the bug the comment above this cast records (a node
    # narrowed to Int casting a %Slot callee to `i64 (i8*)`), reached through
    # the other operand: there the CAST followed the node, here the CALL did.
    # The ABI is the authority for both, and a refinement is honoured by
    # unboxing at the boundary -- which the else-branch below already does.
    if ($result_repr eq 'Str' && $abi_repr eq 'Str') {
        $self->{_need_str_type} = 1;
        $self->_emit("  $result = call %Str $typed_fn($arg_text)  ; Call(method) $method_name -> StrPair");
        my $str_ptr = $self->_fresh;
        my $str_len = $self->_fresh;
        $self->_emit("  $str_ptr = extractvalue %Str $result, 0  ; Call(method) $method_name result ptr");
        $self->_emit("  $str_len = extractvalue %Str $result, 1  ; Call(method) $method_name result len");
        $str_ptr = $self->_set_str_len($str_ptr, $str_len);
        $self->{cache}{ $node->id } = $str_ptr;
        return $str_ptr;
    }
    else {
        # The call's return type MUST match the typed fn pointer's return type
        # ($fn_type, cast above from $result_repr), or lli rejects the module. Str
        # (%Str) was handled above; the same repr->LLVM-return-type authority
        # that DEFINED each method (_method_fn_llvm_ret_type) names the type here,
        # so call and definition can never disagree (and an unsupported repr dies
        # there once, not in a parallel inline table).
        my $ret_ty = Chalk::Target::LLVM::_method_fn_llvm_ret_type($abi_repr);
        $self->_emit("  $result = call $ret_ty $typed_fn($arg_text)  ; Call(method) $method_name -> $ret_ty");
        # THE CALL IS AT THE ABI; THE NODE MAY KNOW MORE. When the vtable
        # declares Scalar the callee returns %Slot, but this node's repr may
        # have been refined to something narrower -- Int <: Scalar. Consumers
        # read the cached ref AT THE NODE'S REPR, so the payload is unpacked
        # here rather than caching a %Slot where an i64 is expected. The
        # refinement is honoured at the boundary, not by calling at the
        # narrower type: the callee has ONE emitted body at ONE machine type.
        if ($abi_repr eq 'Scalar' && ($node->stamp // '') ne 'Scalar') {
            my $pay = $self->_fresh;
            my $mi_pay = _slot_idx('payload');
            $self->_emit("  $pay = extractvalue %Slot $result, $mi_pay  ; Call(method) $method_name: Slot payload -> "
                       . ($node->stamp // '?'));

            # A STR PAYLOAD IS A POINTER TO THE BOXED STR, not the value.
            # Every other narrowed reading (Int, Num, Boolean) IS the payload
            # word, so returning it directly was right for them and silently
            # wrong here -- the consumer would read a heap address as a string.
            # Unpacked the same way the field read does: one encoding, read the
            # same way wherever it is met.
            if (($node->stamp // '') eq 'Str') {
                $self->{_need_str_type} = 1;
                my $pair = $self->_fresh;
                $self->_emit("  $pair = inttoptr i64 $pay to %Str*  ; Call(method) $method_name: payload -> %Str*");
                my $pg = $self->_fresh;
                $self->_emit("  $pg = getelementptr inbounds %Str, %Str* $pair, i64 0, i32 " . _str_idx('ptr') . "  ; %Str.ptr");
                my $sp = $self->_fresh;
                $self->_emit("  $sp = load i8*, i8** $pg  ; load str ptr");
                my $lg = $self->_fresh;
                $self->_emit("  $lg = getelementptr inbounds %Str, %Str* $pair, i64 0, i32 " . _str_idx('len') . "  ; %Str.len");
                my $sl = $self->_fresh;
                $self->_emit("  $sl = load i64, i64* $lg  ; load str len");
                $sp = $self->_set_str_len($sp, $sl);
                $self->{cache}{ $node->id } = $sp;
                return $sp;
            }
            # A BOOLEAN IS AN i1, the payload an i64: a method returning
            # print's 1 handed its consumer the word where a bit was wanted.
            if (($node->stamp // '') eq 'Boolean') {
                my $bit = $self->_fresh;
                $self->_emit("  $bit = icmp ne i64 $pay, 0  ; Call(method) $method_name: payload -> i1");
                $pay = $bit;
            }

            $self->{cache}{ $node->id } = $pay;
            return $pay;
        }
        $self->{cache}{ $node->id } = $result;
        return $result;
    }
}

# _lower_ref_of_object($node) -> $llvm_ref (Str: ptr to class-name string)
#
# Lowers ref($obj) where obj has repr=Object. Returns the class-name string
# pointer (i8*) and tracks the compile-time-known length in _str_len_table.
sub _lower_ref_of_object {
    my ($self, $node) = @_;

    my $obj_node = $node->inputs->[0];

    # Walk obj_node back to the constructing Call(new) for its class_name.
    my $class_name = _infer_class_name_from_obj($obj_node);
    my $name_len   = length($class_name);  # compile-time known ASCII length

    # Load vtable from obj, load class-name ptr from vtable slot 0.
    # This is the runtime-verifiable path (load from actual vtable).
    my $obj_raw = $self->lower_value($obj_node);
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; ref(obj): typed obj");
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 0  ; vtable ptr slot");
    my $vt_ptr = $self->_fresh;
    $self->_emit("  $vt_ptr = load %${class_name}.vt*, %${class_name}.vt** $vt_gep  ; load vtable");
    my $cn_gep = $self->_fresh;
    $self->_emit("  $cn_gep = getelementptr inbounds %${class_name}.vt, %${class_name}.vt* $vt_ptr, i64 0, i32 0  ; class-name ptr slot");
    my $cn_ptr = $self->_fresh;
    $self->_emit("  $cn_ptr = load i8*, i8** $cn_gep  ; load class-name ptr");

    # Track the compile-time-known length for the Str output epilogue
    $cn_ptr = $self->_set_str_len($cn_ptr, $name_len);
    $self->{cache}{ $node->id } = $cn_ptr;
    return $cn_ptr;
}

# ---------------------------------------------------------------------------
# Regex sub-compiler (G6): lower a literal pattern to a runtime-free matcher.
#
# The pattern is a compile-time-known literal string (RegexMatch->pattern), so
# the matcher is emitted as straight-line LLVM with NO libperl / perl regex
# engine. The subject rides on the G3 Str representation (i8* ptr + a length
# tracked in _str_len_table).
#
# Emission style (per the G6 spike): a shared outer "try each start offset"
# slide loop wrapping a straight-line per-pattern inner recognizer. For T0 the
# recognizer is an unrolled literal byte comparison; later tranches grow the
# recognizer (anchors collapse the slide loop, classes/quantifiers/captures
# extend the inner body) without changing this scaffold.
# ---------------------------------------------------------------------------

# _compile_regex_pattern($pattern, $flags) -> \%compiled
#
# Parse a literal regex pattern into the compiled form the emitter consumes:
# a sequence of one-byte ATOMS plus anchor flags. Atom kinds:
#   { kind => 'lit',   byte => $ord }                  — exact byte
#   { kind => 'class', neg => 0|1, ranges => [[lo,hi],...] }
#                                                      — byte in (or not in)
#                                                        any of the ranges
#                                                        (singles are [b,b])
#   { kind => 'any' }                                  — . (any byte but \n)
# Shorthands \d \w \s (and \D \W \S) desugar to classes; a backslash escape
# of a metachar (\. \[ \$ ...) is a literal byte. T3 adds per-atom quantifiers.
# Byte escapes the G6 sub-compiler resolves (regex-language escapes).
my %REGEX_ESCAPE_BYTE = (
    t => 0x09, n => 0x0A, r => 0x0D, f => 0x0C, a => 0x07, e => 0x1B, '0' => 0x00,
);

# _regex_escape_byte(\@chars, $idx, $pattern) -> ($byte, $consumed)
#
# Resolve a backslash escape; $idx is the char AFTER the backslash. Returns
# the byte value and how many pattern chars were consumed (1, or 3 for \xHH).
# Escaped punctuation is the literal byte; \t \n \r \f \a \e \0 map to their
# control bytes; \xHH parses two hex digits. Assertion and unknown
# ALPHANUMERIC escapes (\b \B \A \z \Z \G \p \N \c ...) DIE LOUDLY — perl
# reserves them, so matching the literal letter would be a silent miscompile.
sub _regex_escape_byte {
    my ($chars, $idx, $pattern) = @_;
    my $e = $chars->[$idx];
    if ($e !~ /[A-Za-z0-9]/) {
        return (ord($e), 1);                # \. \[ \$ \\ \/ ...
    }
    if (exists $REGEX_ESCAPE_BYTE{$e}) {
        return ($REGEX_ESCAPE_BYTE{$e}, 1); # \t \n \r \f \a \e \0
    }
    if ($e eq 'x') {
        my $hex = join '', grep { defined } @{$chars}[ $idx + 1, $idx + 2 ];
        die "malformed \\x escape in regex pattern '$pattern' "
          . "(need two hex digits)" unless $hex =~ /^[0-9A-Fa-f]{2}$/;
        return (hex($hex), 3);
    }
    die "GAP: regex escape \\$e in pattern '$pattern' not supported by the G6 "
      . "sub-compiler (assertions \\b \\B \\A \\z \\Z \\G and classes \\p \\N "
      . "are pending tranches — refusing to silently match a literal '$e')";
}

sub _compile_regex_pattern {
    my ($pattern, $flags) = @_;

    # No flag is implemented yet; silently ignoring one (e.g. /i compiling a
    # case-sensitive matcher, /x treating whitespace as literal atoms) would
    # be a silent miscompile. One gate here covers m//, qr//, and s///.
    die "GAP: regex flags '$flags' not yet supported by the G6 sub-compiler"
        if length($flags // '');

    # T1 anchors: a leading ^ anchors the match at offset 0; a trailing $
    # anchors the match end at the subject length (or before a final newline,
    # perl semantics). They are not literal bytes. A trailing escaped \$ is a
    # literal dollar — the $ is an anchor only when preceded by an EVEN run of
    # backslashes (\\$ = escaped backslash THEN anchor; \$ = literal dollar).
    my $anchored_start = 0;
    my $anchored_end   = 0;
    if ($pattern =~ /^\^/) {
        $anchored_start = 1;
        $pattern =~ s/^\^//;
    }
    if ($pattern =~ /(\\*)\$$/ && length($1) % 2 == 0) {
        $anchored_end = 1;
        $pattern =~ s/\$$//;
    }

    # Shorthand class definitions (byte ranges).
    my %SHORTHAND = (
        d => [ [ord('0'), ord('9')] ],
        w => [ [ord('0'), ord('9')], [ord('A'), ord('Z')], [ord('a'), ord('z')],
               [ord('_'), ord('_')] ],
        s => [ [0x09, 0x0D], [ord(' '), ord(' ')] ],   # \t \n \v \f \r space
    );

    my @atoms;
    my @paren_stack;   # open-group cap indices (undef = non-capturing)
    my $ngroups = 0;   # capture group counter
    my @chars = split //, $pattern;
    my $i = 0;
    while ($i <= $#chars) {
        my $c = $chars[$i];

        if ($c eq '\\') {
            # Escape: shorthand class, byte escape, or literal punctuation.
            my $e = $chars[ $i + 1 ]
                // die "regex pattern '$pattern' ends with a bare backslash";
            if ($e =~ /^[dwsDWS]$/) {
                push @atoms, {
                    kind   => 'class',
                    neg    => ($e =~ /[DWS]/) ? 1 : 0,
                    ranges => $SHORTHAND{ lc $e },
                };
                $i += 2;
                next;
            }
            my ($byte, $used) = _regex_escape_byte(\@chars, $i + 1, $pattern);
            push @atoms, { kind => 'lit', byte => $byte };
            $i += 1 + $used;
            next;
        }

        if ($c eq '[') {
            # Character class: [^? ... ] with ranges and escapes.
            my $j   = $i + 1;
            my $neg = 0;
            if (($chars[$j] // '') eq '^') { $neg = 1; $j++ }
            my @ranges;
            my $first = 1;   # a ] as the FIRST member is a literal ]
            while ($j <= $#chars) {
                my $cc = $chars[$j];
                last if $cc eq ']' && !$first;
                $first = 0;
                # Shorthand expansion inside the class: [\d_] etc.
                if ($cc eq '\\') {
                    my $e = $chars[ $j + 1 ]
                        // die "regex class in '$pattern' ends with a bare backslash";
                    if ($e =~ /^[dwsDWS]$/) {
                        die "GAP: regex class shorthand \\$e inside [...] not yet supported "
                          . "in pattern '$pattern'" if $e =~ /[DWS]/;
                        push @ranges, $SHORTHAND{ lc $e }->@*;
                        $j += 2;
                        next;
                    }
                }
                # One endpoint: a plain char or a resolved escape byte.
                my ($lo, $lo_used);
                if ($cc eq '\\') {
                    ($lo, $lo_used) = _regex_escape_byte(\@chars, $j + 1, $pattern);
                    $lo_used += 1;   # the backslash itself
                }
                else {
                    ($lo, $lo_used) = (ord($cc), 1);
                }
                my $k = $j + $lo_used;
                # Range lo-hi (a dash that is not the last member)?
                if (($chars[$k] // '') eq '-' && ($chars[ $k + 1 ] // ']') ne ']') {
                    my ($hi, $hi_used);
                    if ($chars[ $k + 1 ] eq '\\') {
                        ($hi, $hi_used) = _regex_escape_byte(\@chars, $k + 2, $pattern);
                        $hi_used += 1;
                    }
                    else {
                        ($hi, $hi_used) = (ord($chars[ $k + 1 ]), 1);
                    }
                    # Perl rejects a descending range at compile time; matching
                    # nothing silently would be a miscompile.
                    die "invalid [] range (lo > hi) in regex pattern '$pattern'"
                        if $lo > $hi;
                    push @ranges, [ $lo, $hi ];
                    $j = $k + 1 + $hi_used;
                    next;
                }
                push @ranges, [ $lo, $lo ];
                $j = $k;
            }
            die "unterminated character class in regex pattern '$pattern'"
                unless ($chars[$j] // '') eq ']';
            push @atoms, { kind => 'class', neg => $neg, ranges => \@ranges };
            $i = $j + 1;
            next;
        }

        if ($c eq '.') {
            push @atoms, { kind => 'any' };
            $i++;
            next;
        }

        # Capture groups (T4): zero-width gopen/gclose markers around the
        # enclosed atoms. (?:...) is non-capturing (markers with cap undef —
        # transparent without alternation, but tracked so ')' pairs up).
        # Quantified groups ((ab)+) are a pending tranche.
        if ($c eq '(') {
            my $cap;
            if (($chars[$i+1] // '') eq '?' && ($chars[$i+2] // '') eq ':') {
                $cap = undef;     # non-capturing
                $i += 3;
            }
            elsif (($chars[$i+1] // '') eq '?') {
                die "GAP: regex (?...) construct (lookaround/modifier/code) in "
                  . "pattern '$pattern' not supported";
            }
            else {
                $cap = ++$ngroups;
                $i++;
            }
            push @atoms, { kind => 'gopen', cap => $cap };
            push @paren_stack, $cap;
            next;
        }
        if ($c eq ')') {
            die "unbalanced ')' in regex pattern '$pattern'"
                unless @paren_stack;
            my $cap = pop @paren_stack;
            push @atoms, { kind => 'gclose', cap => $cap };
            $i++;
            next;
        }

        # Quantifiers (T3): attach {min,max} to the PRECEDING atom. max undef
        # = unbounded. A quantifier with no preceding atom is malformed.
        # A `{` THAT OPENS NO COUNT ({n} {n,} {n,m} {,m}) is a literal brace,
        # as perl reads it: `m{a{b}c}` was refused as malformed (pvm 379).
        # Blanks may stand by the braces and the comma (perl 5.34).
        my $count_re = qr/^\{[ \t]*(?:(\d+)[ \t]*(,[ \t]*(\d*))?|,[ \t]*(\d+))[ \t]*\}/;
        if ($c =~ /[*+?]/ || ( $c eq '{' && join('', @chars[ $i .. $#chars ]) =~ $count_re )) {
            die "regex quantifier '$c' with no preceding atom in pattern '$pattern'"
                unless @atoms;
            my $atom = $atoms[-1];
            die "GAP: quantified group (...)$c in pattern '$pattern' not yet "
              . "supported by the G6 sub-compiler (tranche pending)"
                if $atom->{kind} eq 'gclose';
            die "GAP: regex quantifier '$c' directly after '(' in pattern '$pattern'"
                if $atom->{kind} eq 'gopen';
            die "GAP: double quantifier on one atom in pattern '$pattern' "
              . "(non-greedy *? +? ?? not yet supported)"
                if exists $atom->{min};
            if ($c eq '*') { $atom->{min} = 0; $atom->{max} = undef; $i++; next }
            if ($c eq '+') { $atom->{min} = 1; $atom->{max} = undef; $i++; next }
            if ($c eq '?') { $atom->{min} = 0; $atom->{max} = 1;     $i++; next }
            # {n} {n,} {n,m}
            my $rest = join '', @chars[ $i .. $#chars ];
            if ($rest =~ $count_re) {
                # {,m} is {0,m}
                my ($n, $has_comma, $m) = defined $4 ? (0, 1, $4) : ($1, defined $2, $3);
                $atom->{min} = 0 + $n;
                $atom->{max} = $has_comma ? (length($m // '') ? 0 + $m : undef) : 0 + $n;
                die "regex {n,m} with m < n in pattern '$pattern'"
                    if defined $atom->{max} && $atom->{max} < $atom->{min};
                $i += length($&);
                next;
            }
            die "malformed regex counted quantifier near '"
              . substr($rest, 0, 8) . "' in pattern '$pattern'";
        }

        # Unsupported metachars die loudly rather than silently matching as
        # literals (alternation arrives in T5). Mid-pattern ^/$ are perl
        # ASSERTIONS (usually unmatchable without /m) — matching them as
        # literal bytes would silently diverge.
        # (A lone `}` is a literal brace, as perl reads it.)
        if ($c =~ /[|^\$]/) {
            die "GAP: regex metachar '$c' in pattern '$pattern' not yet supported "
              . "by the G6 sub-compiler (tranche pending; mid-pattern ^/\$ are "
              . "assertions, not literals)";
        }

        push @atoms, { kind => 'lit', byte => ord($c) };
        $i++;
    }

    die "unbalanced '(' in regex pattern '$pattern'" if @paren_stack;

    return {
        atoms          => \@atoms,
        anchored_start => $anchored_start,
        anchored_end   => $anchored_end,
        ngroups        => $ngroups,
    };
}

# _emit_atom_predicate($self, $atom, $byte_ref, $label) -> $i1_ref
#
# Emit the LLVM predicate for one atom against an already-loaded subject byte.
# Returns the i1 SSA ref that is true iff the byte satisfies the atom.
sub _emit_atom_predicate {
    my ($self, $atom, $byte_ref, $label) = @_;

    if ($atom->{kind} eq 'lit') {
        my $eq = $self->_fresh;
        my $ch = $atom->{byte} >= 0x20 && $atom->{byte} <= 0x7e ? chr($atom->{byte}) : sprintf('\\x%02x', $atom->{byte});
        $self->_emit("  $eq = icmp eq i8 $byte_ref, $atom->{byte}  ; $label: byte == '$ch'?");
        return $eq;
    }

    if ($atom->{kind} eq 'any') {
        # Perl . matches any byte except newline (no /s in the supported slice).
        my $ne = $self->_fresh;
        $self->_emit("  $ne = icmp ne i8 $byte_ref, 10  ; $label: . (any byte but \\n)");
        return $ne;
    }

    if ($atom->{kind} eq 'class') {
        # OR over ranges: (b >= lo && b <= hi) || ...
        my $acc;
        for my $r ($atom->{ranges}->@*) {
            my ($lo, $hi) = @$r;
            my $in;
            if ($lo == $hi) {
                $in = $self->_fresh;
                $self->_emit("  $in = icmp eq i8 $byte_ref, $lo  ; $label: class member $lo");
            }
            else {
                my $ge = $self->_fresh;
                my $le = $self->_fresh;
                $in = $self->_fresh;
                $self->_emit("  $ge = icmp uge i8 $byte_ref, $lo  ; $label: class range lo");
                $self->_emit("  $le = icmp ule i8 $byte_ref, $hi  ; $label: class range hi");
                $self->_emit("  $in = and i1 $ge, $le  ; $label: in [$lo-$hi]?");
            }
            if (!defined $acc) {
                $acc = $in;
            }
            else {
                my $or = $self->_fresh;
                $self->_emit("  $or = or i1 $acc, $in  ; $label: class union");
                $acc = $or;
            }
        }
        # Empty class [] matches nothing.
        if (!defined $acc) {
            $acc = $self->_fresh;
            $self->_emit("  $acc = add i1 false, false  ; $label: empty class never matches");
        }
        if ($atom->{neg}) {
            my $not = $self->_fresh;
            $self->_emit("  $not = xor i1 $acc, true  ; $label: negated class");
            return $not;
        }
        return $acc;
    }

    die "G6 internal: unknown regex atom kind '$atom->{kind}'";
}

# _emit_regex_seq($self, \@atoms, $idx, $pos_ref, \%ctx)
#
# Position-threaded recursive emission of atoms[$idx..]. $pos_ref is the SSA
# value of the current subject position. %ctx carries subj_ptr/subj_len/
# hit_lbl/fail_lbl/anch_e; fail_lbl is the CURRENT backtrack target (the
# innermost enclosing backoff decrementer, or the slide-advance block at the
# top level). Each atom is emitted exactly once; a quantified atom wraps the
# continuation (the recursive call) in a backoff loop, giving correct greedy
# backtracking via runtime loop structure rather than code duplication.
#
# Emission contract: called with a current open block; every path it emits
# ends in a terminator (br to hit/fail or into its own loop structure).
sub _emit_regex_seq {
    my ($self, $atoms, $idx, $pos_ref, $ctx) = @_;

    # Base: end of pattern. Record the whole-match end position (group 0),
    # check the end anchor, then hit. Perl's $ matches at the end of the
    # subject OR immediately before a FINAL newline ("foo\n" =~ /foo$/ is
    # true), so the anchor check is pos==len, or pos==len-1 with subj[pos]
    # being a newline (the load is branch-guarded: pos==len-1 implies
    # in-bounds).
    if ($idx > $#$atoms) {
        $ctx->{caps}{m0e} = $pos_ref;
        if ($ctx->{anch_e}) {
            my $lbl_chknl = $self->_fresh_label('rxenl');
            my $lbl_ldnl  = $self->_fresh_label('rxeld');
            my $at_end = $self->_fresh;
            $self->_emit("  $at_end = icmp eq i64 $pos_ref, $ctx->{subj_len}  ; RegexMatch \$: match ends at len?");
            $self->_set_terminator("  br i1 $at_end, label \%$ctx->{hit_lbl}, label \%$lbl_chknl");

            $self->_new_block($lbl_chknl);
            my $lenm1 = $self->_fresh;
            $self->_emit("  $lenm1 = sub i64 $ctx->{subj_len}, 1  ; RegexMatch \$: len-1");
            my $is_pre = $self->_fresh;
            $self->_emit("  $is_pre = icmp eq i64 $pos_ref, $lenm1  ; RegexMatch \$: just before the last byte?");
            $self->_set_terminator("  br i1 $is_pre, label \%$lbl_ldnl, label \%$ctx->{fail_lbl}");

            $self->_new_block($lbl_ldnl);
            my $gep = $self->_fresh;
            $self->_emit("  $gep = getelementptr inbounds i8, i8* $ctx->{subj_ptr}, i64 $pos_ref  ; RegexMatch \$: last byte ptr");
            my $byte = $self->_fresh;
            $self->_emit("  $byte = load i8, i8* $gep  ; RegexMatch \$: last byte");
            my $is_nl = $self->_fresh;
            $self->_emit("  $is_nl = icmp eq i8 $byte, 10  ; RegexMatch \$: final newline?");
            $self->_set_terminator("  br i1 $is_nl, label \%$ctx->{hit_lbl}, label \%$ctx->{fail_lbl}");
        }
        else {
            $self->_set_terminator("  br label \%$ctx->{hit_lbl}");
        }
        return;
    }

    my $atom  = $atoms->[$idx];

    # Capture-group boundary markers (T4): zero-width — record the current
    # position SSA as the group's start/end and continue. The records go into
    # the SHARED $ctx->{caps} hashref (ctx is shallow-copied at backoff
    # boundaries; the caps ref is shared by all copies). The recorded refs
    # dominate the recursion base (the linear chain), so they are valid at the
    # hit edge; on a backtracked retry the same SSA names hold the values of
    # the CURRENT (ultimately successful) attempt.
    if ($atom->{kind} eq 'gopen' || $atom->{kind} eq 'gclose') {
        if (defined $atom->{cap}) {
            my $slot = $atom->{kind} eq 'gopen' ? 's' : 'e';
            $ctx->{caps}{$slot}[ $atom->{cap} ] = $pos_ref;
        }
        $self->_emit_regex_seq($atoms, $idx + 1, $pos_ref, $ctx);
        return;
    }

    my $quant = exists $atom->{min};

    if (!$quant) {
        # Plain atom: bounds-check, load, predicate, advance position by one.
        my $lbl_ld = $self->_fresh_label('rxa');
        my $lbl_nx = $self->_fresh_label('rxn');
        my $inb = $self->_fresh;
        $self->_emit("  $inb = icmp ult i64 $pos_ref, $ctx->{subj_len}  ; RegexMatch atom[$idx]: in bounds?");
        $self->_set_terminator("  br i1 $inb, label \%$lbl_ld, label \%$ctx->{fail_lbl}");

        $self->_new_block($lbl_ld);
        my $gep = $self->_fresh;
        $self->_emit("  $gep = getelementptr inbounds i8, i8* $ctx->{subj_ptr}, i64 $pos_ref  ; RegexMatch atom[$idx]: byte ptr");
        my $byte = $self->_fresh;
        $self->_emit("  $byte = load i8, i8* $gep  ; RegexMatch atom[$idx]: subject byte");
        my $ok = $self->_emit_atom_predicate($atom, $byte, "RegexMatch atom[$idx]");
        my $pos_next = $self->_fresh;
        $self->_emit("  $pos_next = add i64 $pos_ref, 1  ; RegexMatch atom[$idx]: advance");
        $self->_set_terminator("  br i1 $ok, label \%$lbl_nx, label \%$ctx->{fail_lbl}");

        $self->_new_block($lbl_nx);
        $self->_emit_regex_seq($atoms, $idx + 1, $pos_next, $ctx);
        return;
    }

    # Quantified atom {min,max} (max undef = unbounded): greedy-consume loop
    # counts how many bytes the atom can take from $pos_ref, then a backoff
    # loop tries the continuation at count c = greedy, greedy-1, ..., min.
    my ($min, $max) = ($atom->{min}, $atom->{max});

    my $lbl_cur   = $self->_current_block_label;
    my $lbl_ghead = $self->_fresh_label('rxgh');   # greedy header (cnt phi)
    my $lbl_gtest = $self->_fresh_label('rxgt');   # greedy predicate test
    my $lbl_gbody = $self->_fresh_label('rxgb');   # greedy increment
    my $lbl_gdone = $self->_fresh_label('rxgd');   # greedy done
    my $lbl_bhead = $self->_fresh_label('rxbh');   # backoff header (c phi)
    my $lbl_bbody = $self->_fresh_label('rxbb');   # backoff continuation
    my $lbl_bdec  = $self->_fresh_label('rxbd');   # backoff decrement
    my $cnt_next  = $self->_fresh;                 # forward ref for ghead phi
    my $c_dec     = $self->_fresh;                 # forward ref for bhead phi

    $self->_set_terminator("  br label \%$lbl_ghead");

    # Greedy header: how many consumed so far; can we take one more?
    $self->_new_block($lbl_ghead);
    my $cnt = $self->_fresh;
    $self->_emit("  $cnt = phi i64 [ 0, \%$lbl_cur ], [ $cnt_next, \%$lbl_gbody ]  ; RegexMatch q[$idx]: greedy count");
    my $posg = $self->_fresh;
    $self->_emit("  $posg = add i64 $pos_ref, $cnt  ; RegexMatch q[$idx]: greedy pos");
    my $inb = $self->_fresh;
    $self->_emit("  $inb = icmp ult i64 $posg, $ctx->{subj_len}  ; RegexMatch q[$idx]: in bounds?");
    my $more = $inb;
    if (defined $max) {
        my $ltmax = $self->_fresh;
        $self->_emit("  $ltmax = icmp ult i64 $cnt, $max  ; RegexMatch q[$idx]: below max $max?");
        my $and = $self->_fresh;
        $self->_emit("  $and = and i1 $inb, $ltmax  ; RegexMatch q[$idx]: may consume more?");
        $more = $and;
    }
    $self->_set_terminator("  br i1 $more, label \%$lbl_gtest, label \%$lbl_gdone");

    # Greedy test: does the atom match at posg?
    $self->_new_block($lbl_gtest);
    my $gep = $self->_fresh;
    $self->_emit("  $gep = getelementptr inbounds i8, i8* $ctx->{subj_ptr}, i64 $posg  ; RegexMatch q[$idx]: byte ptr");
    my $byte = $self->_fresh;
    $self->_emit("  $byte = load i8, i8* $gep  ; RegexMatch q[$idx]: subject byte");
    my $ok = $self->_emit_atom_predicate($atom, $byte, "RegexMatch q[$idx]");
    $self->_set_terminator("  br i1 $ok, label \%$lbl_gbody, label \%$lbl_gdone");

    # Greedy body: consume one and loop.
    $self->_new_block($lbl_gbody);
    $self->_emit("  $cnt_next = add i64 $cnt, 1  ; RegexMatch q[$idx]: consume");
    $self->_set_terminator("  br label \%$lbl_ghead");

    # Greedy done: enter the backoff loop with c = greedy count.
    $self->_new_block($lbl_gdone);
    $self->_set_terminator("  br label \%$lbl_bhead");

    # Backoff header: try the continuation at count c; give up below min.
    $self->_new_block($lbl_bhead);
    my $c = $self->_fresh;
    $self->_emit("  $c = phi i64 [ $cnt, \%$lbl_gdone ], [ $c_dec, \%$lbl_bdec ]  ; RegexMatch q[$idx]: backoff count");
    my $ge_min = $self->_fresh;
    $self->_emit("  $ge_min = icmp sge i64 $c, $min  ; RegexMatch q[$idx]: count >= min $min?");
    $self->_set_terminator("  br i1 $ge_min, label \%$lbl_bbody, label \%$ctx->{fail_lbl}");

    # Backoff body: the continuation at pos + c; its fail target is the
    # decrementer (back off one and retry), NOT the outer fail.
    $self->_new_block($lbl_bbody);
    my $posb = $self->_fresh;
    $self->_emit("  $posb = add i64 $pos_ref, $c  ; RegexMatch q[$idx]: continuation pos");
    my %inner_ctx = ( $ctx->%*, fail_lbl => $lbl_bdec );
    $self->_emit_regex_seq($atoms, $idx + 1, $posb, \%inner_ctx);

    # Backoff decrement: one fewer repetition, retry.
    $self->_new_block($lbl_bdec);
    $self->_emit("  $c_dec = sub i64 $c, 1  ; RegexMatch q[$idx]: back off");
    $self->_set_terminator("  br label \%$lbl_bhead");
    return;
}

# _emit_regex_matcher($self, $subj_ptr, $subj_len, $compiled, $tag) -> \%match
#
# Emit the full matcher (slide loop + position-threaded recognizer + end
# merge) for an already-compiled pattern. Returns the END-block SSA values:
#   matched — i1 (did the pattern match anywhere?)
#   m0s/m0e — i64 whole-match start/end offsets (0 on miss)
#   cap_s/cap_e — arrayrefs (1-based) of i64 capture-group offsets (0 on miss)
# Captures are plain SSA offset pairs into the subject buffer — no struct is
# materialized (a %MatchResult ABI is only needed at a function boundary,
# i.e. a future qr//-as-function; per the G6 scope decision it is not built).
sub _emit_regex_matcher {
    my ($self, $subj_ptr, $subj_len, $compiled, $tag) = @_;
    $tag //= 'RegexMatch';

    my @atoms    = $compiled->{atoms}->@*;
    my $anch_s   = $compiled->{anchored_start};
    my $anch_e   = $compiled->{anchored_end};
    my $ngroups  = $compiled->{ngroups} // 0;

    # Minimum bytes the pattern can match (sum of per-atom min counts;
    # zero-width group markers contribute nothing). Drives the slide-loop
    # room check; quantified atoms may consume more.
    my $min_len = 0;
    for my $a (@atoms) {
        next if $a->{kind} eq 'gopen' || $a->{kind} eq 'gclose';
        $min_len += ($a->{min} // 1);
    }

    # Empty pattern (possibly with anchors). The $ anchor's position honors
    # perl's final-newline rule: the effective end position is len-1 when the
    # last byte is a newline, else len (so s/$/X/ inserts BEFORE a trailing
    # newline, and /^$/ matches "\n").
    if (scalar @atoms == 0) {
        if ($anch_e) {
            # endpos = (len > 0 && subj[len-1] == '\n') ? len-1 : len
            my $lbl_pre   = $self->_current_block_label;
            my $lbl_ld    = $self->_fresh_label('rxeep');
            my $lbl_merge = $self->_fresh_label('rxeem');
            my $nonempty  = $self->_fresh;
            $self->_emit("  $nonempty = icmp ugt i64 $subj_len, 0  ; $tag: non-empty subject?");
            $self->_set_terminator("  br i1 $nonempty, label \%$lbl_ld, label \%$lbl_merge");

            $self->_new_block($lbl_ld);
            my $lenm1 = $self->_fresh;
            $self->_emit("  $lenm1 = sub i64 $subj_len, 1  ; $tag: len-1");
            my $gep = $self->_fresh;
            $self->_emit("  $gep = getelementptr inbounds i8, i8* $subj_ptr, i64 $lenm1  ; $tag: last byte ptr");
            my $byte = $self->_fresh;
            $self->_emit("  $byte = load i8, i8* $gep  ; $tag: last byte");
            my $is_nl = $self->_fresh;
            $self->_emit("  $is_nl = icmp eq i8 $byte, 10  ; $tag: trailing newline?");
            my $end_ld = $self->_fresh;
            $self->_emit("  $end_ld = select i1 $is_nl, i64 $lenm1, i64 $subj_len  ; $tag: \$ position");
            $self->_set_terminator("  br label \%$lbl_merge");

            $self->_new_block($lbl_merge);
            my $endpos = $self->_fresh;
            $self->_emit("  $endpos = phi i64 [ $end_ld, \%$lbl_ld ], [ 0, \%$lbl_pre ]  ; $tag: effective end (len==0 -> 0)");

            my $r = $self->_fresh;
            if ($anch_s) {
                # /^$/ matches iff the effective end is offset 0.
                $self->_emit("  $r = icmp eq i64 $endpos, 0  ; $tag /^\$/: empty (or lone-newline) subject?");
            }
            else {
                # /$/ always matches, at the effective end position.
                $self->_emit("  $r = add i1 true, false  ; $tag /\$/: always matches at the end");
            }
            my $m0 = $anch_s ? '0' : $endpos;
            return { matched => $r, m0s => $m0, m0e => $m0, cap_s => [], cap_e => [] };
        }

        # //, /^/ — match unconditionally at offset 0.
        my $r = $self->_fresh;
        $self->_emit("  $r = add i1 true, false  ; $tag: empty pattern always matches");
        return { matched => $r, m0s => '0', m0e => '0', cap_s => [], cap_e => [] };
    }

    # Slide loop: for start in 0 .. (len - min_len), try the pattern at start.
    my $lbl_pre   = $self->_current_block_label;
    my $lbl_head  = $self->_fresh_label('rxhead');
    my $lbl_try   = $self->_fresh_label('rxtry');
    my $lbl_cont  = $self->_fresh_label('rxcont');
    my $lbl_hit   = $self->_fresh_label('rxhit');
    my $lbl_miss  = $self->_fresh_label('rxmiss');
    my $lbl_end   = $self->_fresh_label('rxend');
    my $start_next = $self->_fresh;

    $self->_set_terminator("  br label \%$lbl_head");

    # Header: start phi + room check (start + min_len <= len).
    # With a start anchor (^), there is no back-edge from the continue block
    # (a failed try goes straight to miss), so the phi has only the entry edge.
    $self->_new_block($lbl_head);
    my $start = $self->_fresh;
    if ($anch_s) {
        $self->_emit("  $start = phi i64 [ 0, \%$lbl_pre ]  ; $tag ^: anchored at offset 0");
    }
    else {
        $self->_emit("  $start = phi i64 [ 0, \%$lbl_pre ], [ $start_next, \%$lbl_cont ]  ; $tag: slide start");
    }
    my $min_end = $self->_fresh;
    $self->_emit("  $min_end = add i64 $start, $min_len  ; $tag: start + min pattern length");
    my $room = $self->_fresh;
    $self->_emit("  $room = icmp sle i64 $min_end, $subj_len  ; $tag: room for pattern?");
    $self->_set_terminator("  br i1 $room, label \%$lbl_try, label \%$lbl_miss");

    # Try: position-threaded recursive emission of the atom sequence. Each
    # atom's code is emitted once; quantified atoms emit a greedy-consume loop
    # plus a backoff loop whose body holds the continuation, so backtracking
    # happens via loop structure at runtime (fail targets thread to the
    # innermost enclosing backoff; the outermost fail target is the slide
    # advance). The end-anchor check lives in the recursion base (pos == len).
    # The caps hashref is SHARED across the recursion's ctx copies; the seq
    # records group-boundary position SSA refs + the whole-match end into it.
    my %caps = ( s => [], e => [], m0e => undef );
    $self->_new_block($lbl_try);
    $self->_emit_regex_seq(\@atoms, 0, $start, {
        subj_ptr => $subj_ptr,
        subj_len => $subj_len,
        hit_lbl  => $lbl_hit,
        fail_lbl => $lbl_cont,
        anch_e   => $anch_e,
        caps     => \%caps,
    });

    # Continue: advance the start offset (or stop, if start-anchored).
    $self->_new_block($lbl_cont);
    $self->_emit("  $start_next = add i64 $start, 1  ; $tag: next start");
    if ($anch_s) {
        # Start anchor (^): only offset 0 is tried — a failed try means no match.
        $self->_set_terminator("  br label \%$lbl_miss");
    }
    else {
        $self->_set_terminator("  br label \%$lbl_head");
    }

    # Hit / miss feed the end-block phis.
    $self->_new_block($lbl_hit);
    $self->_set_terminator("  br label \%$lbl_end");
    $self->_new_block($lbl_miss);
    $self->_set_terminator("  br label \%$lbl_end");

    # End merge: matched + the whole-match and capture-group offsets. All the
    # recorded refs dominate the hit edge; miss feeds 0 sentinels (consumers
    # must guard on matched — perl leaves $N undef on a failed match).
    $self->_new_block($lbl_end);
    my $matched = $self->_fresh;
    $self->_emit("  $matched = phi i1 [ true, \%$lbl_hit ], [ false, \%$lbl_miss ]  ; $tag: matched?");
    my $m0s = $self->_fresh;
    $self->_emit("  $m0s = phi i64 [ $start, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: match start");
    my $m0e = $self->_fresh;
    $self->_emit("  $m0e = phi i64 [ $caps{m0e}, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: match end");
    my (@cap_s, @cap_e);
    for my $g (1 .. $ngroups) {
        my ($s_ref, $e_ref) = ($caps{s}[$g], $caps{e}[$g]);
        die "G6 internal: capture group $g has no recorded boundaries"
            unless defined $s_ref && defined $e_ref;
        my $sp = $self->_fresh;
        $self->_emit("  $sp = phi i64 [ $s_ref, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: \$$g start");
        my $ep = $self->_fresh;
        $self->_emit("  $ep = phi i64 [ $e_ref, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: \$$g end");
        $cap_s[$g] = $sp;
        $cap_e[$g] = $ep;
    }

    return { matched => $matched, m0s => $m0s, m0e => $m0e,
             cap_s => \@cap_s, cap_e => \@cap_e };
}

# _lower_regex_match($node) -> $llvm_ref (i1 matched?)
sub _lower_regex_match {
    my ($self, $node) = @_;

    my $subj_node = $node->inputs->[0];
    my $repr      = _require_repr($node, 'RegexMatch');

    # Lower the subject to its i8* pointer and obtain its byte length.
    my ($subj_ptr, $subj_len_tracked) = $self->_str_parts($self->lower_value($subj_node));
    my $subj_len  = $subj_len_tracked
        // die "GAP: RegexMatch subject (ref=$subj_ptr) has no tracked length — "
             . "the matcher needs the subject's byte length.";

    # A SCALAR m//g matches from the variable's pos() and leaves pos() at the
    # end of the match, or undef on a miss (pvm 388).
    my $flags = $node->flags // '';
    if ($flags =~ s/g//g) {
        die "GAP: m//g in list context is not lowered\n" unless $repr eq 'Boolean';
        die "GAP: m//g on what is not a `my` variable assigned in the program is not lowered "
          . "-- its pos() belongs to what it aliases\n"
            unless $subj_node->operation eq 'PadAccess' && $self->_pos_var_ok($subj_node);
        my $compiled = _compile_regex_pattern($node->pattern, $flags);
        die "GAP: m//g whose pattern is anchored at the start is not lowered\n"
            if $compiled->{anchored_start};
        die "GAP: m//g whose pattern can match the empty string is not lowered\n"
            unless grep { $_->{kind} =~ /\A(?:lit|class|any)\z/ && ( $_->{min} // 1 ) > 0 }
                   $compiled->{atoms}->@*;
        my $cell = $self->_pos_cell($subj_node);
        my ($p, $neg, $p0, $over, $start, $rp, $rl) = map { $self->_fresh } 1 .. 7;
        $self->_emit("  $p = load i64, i64* $cell  ; m//g: pos()");
        $self->_emit("  $neg = icmp slt i64 $p, 0");
        $self->_emit("  $p0 = select i1 $neg, i64 0, i64 $p  ; m//g: from the start when pos() is undef");
        $self->_emit("  $over = icmp sgt i64 $p0, $subj_len");
        $self->_emit("  $start = select i1 $over, i64 $subj_len, i64 $p0");
        $self->_emit("  $rp = getelementptr inbounds i8, i8* $subj_ptr, i64 $start");
        $self->_emit("  $rl = sub i64 $subj_len, $start  ; m//g: what is left");
        my $match = $self->_emit_regex_matcher($rp, $rl, $compiled, 'RegexMatch /g');
        my ($end, $new) = map { $self->_fresh } 1 .. 2;
        $self->_emit("  $end = add i64 $start, $match->{m0e}");
        $self->_emit("  $new = select i1 $match->{matched}, i64 $end, i64 -1  ; m//g: pos() after");
        $self->_emit("  store i64 $new, i64* $cell");
        $match->{subj_ptr} = $rp;
        $self->{_regex_captures}{ $node->id } = $match;
        return $self->{cache}{ $node->id } = $match->{matched};
    }

    my $compiled = _compile_regex_pattern($node->pattern, $node->flags);
    my $match    = $self->_emit_regex_matcher($subj_ptr, $subj_len, $compiled, 'RegexMatch');

    # Record the capture offsets for downstream consumers (G7's $N magic vars
    # read these as graph-edge side data; s/// consumes them directly).
    # subj_ptr rides along so a RegexCapture can materialize the $N view.
    $match->{subj_ptr} = $subj_ptr;
    $self->{_regex_captures}{ $node->id } = $match;

    $self->{cache}{ $node->id } = $match->{matched};
    return $match->{matched};
}

# _pos_cell($var) -> the i64* that holds the pos() of a `my` variable: -1 for
# undef. One per variable, keyed as handle cells are (the subs inlined around
# it, its pad slot and name).
sub _pos_cell {
    my ($self, $v) = @_;
    my $key = join(',', sort keys %{ $self->{_inlining} // {} }) . '|' . ( $v->targ // '' ) . $v->name;
    return $self->{_pos_cells}{$key} //= do {
        my $c = $self->_fresh;
        $self->_emit_entry("  $c = alloca i64  ; pos(" . $v->name . ")");
        $self->_emit_entry("  store i64 -1, i64* $c  ; pos() undef");
        $c;
    };
}

# _pos_var_ok($var): a variable whose pos() is kept here -- one the program
# assigns (not a foreach alias, whose pos() is its element's), which nothing
# but an assignment or s/// changes (those clear pos(); tr, chomp, chop and
# the like would have to as well).
sub _pos_var_ok {
    my ($self, $v) = @_;
    my $name = $v->name;
    return $self->{_pos_var_ok}{$name} //= do {
        my @p = @PROGRAM;
        my $assigned = grep { $_->operation eq 'Assign' && blessed($_->inputs->[0])
            && $_->inputs->[0]->operation eq 'PadAccess' && $_->inputs->[0]->name eq $name } @p;
        my $other = grep { $_->operation =~ /\A(?:Transliterate|Chomp|ChompValue|Chop|CompoundAssign|Increment|Decrement)\z/
            && grep { blessed($_) && $_->operation eq 'PadAccess' && $_->name eq $name } $_->inputs->@* } @p;
        $assigned && !$other ? 1 : 0;
    };
}

# _lower_pos($node) -> %Slot: pos($var), undef or the offset its last m//g
# ended at.
sub _lower_pos {
    my ($self, $node) = @_;
    my ($v) = grep { blessed($_) } $node->inputs->@*;
    die "GAP: pos() of what is not a variable a scalar m//g matches is not lowered\n"
        unless blessed($v) && $v->operation eq 'PadAccess' && $POS_VARS{ $v->name } && $self->_pos_var_ok($v);
    my ($p, $def) = map { $self->_fresh } 1 .. 2;
    $self->_emit("  $p = load i64, i64* " . $self->_pos_cell($v) . "  ; pos()");
    $self->_emit("  $def = icmp sge i64 $p, 0");
    my ($s0, $s1, $s2) = map { $self->_fresh } 1 .. 3;
    $self->{_need_aggregate_types} = 1;
    $self->_emit("  $s0 = insertvalue %Slot undef, i1 $def, " . _slot_idx('defined'));
    $self->_emit("  $s1 = insertvalue %Slot $s0, i8 " . _slot_tag_value('Int') . ", " . _slot_idx('tag'));
    $self->_emit("  $s2 = insertvalue %Slot $s1, i64 $p, " . _slot_idx('payload'));
    my $to = $self->_repr_of($node) // $node->stamp // 'Scalar';
    return $self->{cache}{ $node->id } = $to =~ /\A(?:Scalar|Slot|Unknown)\z/ ? $s2
        : $self->_emit_coercion($s2, 'Scalar', $to, 'pos()');
}

# _lower_match_apply($node) -> $llvm_ref (i1 matched?)
#
# Lowers Match (=~ applying a compiled-regex VALUE): inputs[0] = subject Str,
# inputs[1] = the qr// value. A qr// literal is a Constant(const_type='regex')
# with :Regex repr — its pattern is compile-time known, so the application
# inlines the same matcher RegexMatch uses. A qr value that cannot be resolved
# statically (e.g. flowing through vars/containers the resolver cannot walk)
# is a loud GAP — a matcher-function ABI is only built if that need is real.
sub _lower_match_apply {
    my ($self, $node) = @_;

    my $subj_node = $node->inputs->[0];
    my $qr_node   = $node->inputs->[1];
    my $repr      = _require_repr($node, 'Match');

    my $qr_op = $qr_node->can('operation') ? $qr_node->operation : '';
    # A CONSTANT STRING is the pattern perl compiles it to (`/$p/` with $p
    # folded to "b", pvm 384).
    unless ($qr_op eq 'Constant'
        && $qr_node->can('const_type')
        && ($qr_node->const_type // '') =~ /\A(?:regex|string)\z/)
    {
        my $why = ($qr_op eq 'Constant')
            ? "a string-valued =~ rhs (perl treats it as a pattern) is not yet "
            . "wired — it IS statically resolvable, just an unimplemented form"
            : "a runtime-computed pattern would need a matcher-fn ABI";
        die "GAP: Match rhs (op=$qr_op) is not a qr// literal "
          . "(Constant const_type='regex') — $why.";
    }
    my $pattern = $qr_node->value;
    # ...WITH THE MATCH'S FLAGS, which only B::SoN's Match carries for a
    # string: unsent, `/$p/i` matched case-sensitive (0 for perl's 1).
    # A qr// CARRIES ITS OWN FLAGS: dropped by the loader, `"a" =~ qr/A/i`
    # matched case-sensitive (0 for perl's 1).
    my $flags = $qr_node->can('flags') ? $qr_node->flags // '' : '';
    if (($qr_node->const_type // '') eq 'string') {
        $flags = $node->can('flags') ? $node->flags : undef;
        die "GAP: a match against a string pattern whose flags were not sent is not lowered\n"
            unless defined $flags;
    }

    my ($subj_ptr, $subj_len_tracked) = $self->_str_parts($self->lower_value($subj_node));
    my $subj_len = $subj_len_tracked
        // die "GAP: Match subject (ref=$subj_ptr) has no tracked length — "
             . "the matcher needs the subject's byte length.";

    my $compiled = _compile_regex_pattern($pattern, $flags);
    my $match    = $self->_emit_regex_matcher($subj_ptr, $subj_len, $compiled, 'Match(qr)');

    $match->{subj_ptr} = $subj_ptr;
    $self->{_regex_captures}{ $node->id } = $match;
    $self->{cache}{ $node->id } = $match->{matched};
    return $match->{matched};
}

# _lower_regex_capture($node) -> $llvm_ref (i8* NUL-terminated copy)
#
# Lowers RegexCapture ($N): inputs[0] is the RegexMatch/Match node whose
# lowering recorded its capture offsets in _regex_captures. The captured
# bytes are COPIED into a fresh NUL-terminated buffer (malloc len+1 +
# memcpy + NUL), upholding the backend-wide invariant that EVERY Str SSA
# value is NUL-terminated: length tracking is lost at phi merges, and the
# fallbacks (epilogue printf %s, strlen) assume NUL — a zero-copy view into
# the subject violated that and printed the subject tail when a capture
# crossed an if/else merge (branch-review C4). Zero-copy views can return
# when the Str representation carries explicit lengths end-to-end.
#
# On a failed match the offsets are the 0 sentinels, so the copy is the
# empty string; perl yields undef there — the realistic lib/ idiom guards
# $N behind the match (matched ? $1 : ...), and the undef face is a tracked
# follow-up alongside the L3 Undef-rep composition.
sub _lower_regex_capture {
    my ($self, $node) = @_;

    my $repr       = _require_repr($node, 'RegexCapture');
    die "GAP: RegexCapture has repr=$repr; \$N capture values are Str"
        unless $repr eq 'Str';
    my $match_node = $node->inputs->[0];
    my $n          = $node->n;

    # Lower the match first (idempotent via the value cache); its lowering
    # records the capture offsets keyed by the match node's id.
    $self->lower_value($match_node);
    my $rec = $self->{_regex_captures}{ $match_node->id };
    unless (defined $rec) {
        my $mop = $match_node->can('operation') ? $match_node->operation : '?';
        die "GAP: RegexCapture input (op=$mop) is not a regex match node — "
          . "\$$n is a slot of a match result; only RegexMatch/Match produce one.";
    }
    my ($s_ref, $e_ref) = ($rec->{cap_s}[$n], $rec->{cap_e}[$n]);
    unless (defined $s_ref && defined $e_ref) {
        my $have = $#{ $rec->{cap_s} };
        $have = 0 if $have < 0;
        die "RegexCapture \$$n out of range — the pattern has $have capture "
          . "group(s) (\$& / group 0 is a tracked follow-up).";
    }

    $self->{_need_malloc_memcpy} = 1;

    my $src = $self->_fresh;
    $self->_emit("  $src = getelementptr inbounds i8, i8* $rec->{subj_ptr}, i64 $s_ref  ; RegexCapture: \$$n source");
    my $len = $self->_fresh;
    $self->_emit("  $len = sub i64 $e_ref, $s_ref  ; RegexCapture: \$$n length");
    my $alloc = $self->_fresh;
    $self->_emit("  $alloc = add i64 $len, 1  ; RegexCapture: +1 for NUL");
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $alloc)  ; RegexCapture: \$$n buffer");
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $src, i64 $len)  ; RegexCapture: copy \$$n");
    my $nul = $self->_fresh;
    $self->_emit("  $nul = getelementptr inbounds i8, i8* $buf, i64 $len  ; RegexCapture: NUL slot");
    $self->_emit("  store i8 0, i8* $nul  ; RegexCapture: NUL-terminate");

    $buf = $self->_set_str_len($buf, $len);
    $self->{cache}{ $node->id } = $buf;
    return $buf;
}

# _lower_env_read($node) -> $llvm_ref (i8* value string)
#
# Lowers EnvRead: a getenv(key) call against host process state. A missing
# key reads as the EMPTY string, which is how perl prints its undef; its
# defined bit is kept in {_env_defined} for `//` and `defined`
# (_env_defined_bit). The value length is a runtime strlen, tracked in
# _str_len_table.
sub _lower_env_read {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'EnvRead');
    die "GAP: EnvRead has repr=$repr; %ENV values are Str" unless $repr eq 'Str';
    my $key  = $node->key;
    $self->{_need_getenv} = 1;

    # Key as a per-node module global (same symbol-prefix + byte-length rule as
    # @str_const_N/@rxs_lit_N, owned by _module_global_name).
    my ($kname, undef, $ktotal) = $self->_module_global_name('env_key', $key);
    my $kptr = $self->_fresh;
    $self->_emit("  $kptr = getelementptr inbounds [$ktotal x i8], [$ktotal x i8]* $kname, i64 0, i64 0  ; EnvRead: key \"$key\"");

    # Empty-string fallback: the content is identical for every EnvRead, so
    # share ONE @env_empty global across all EnvRead nodes in this context
    # instead of emitting a symbol-unique @env_empty_N per node.
    my $ename = $self->{_env_empty_global} //= do {
        my ($n) = $self->_module_global_name('env_empty', '');
        $n;
    };
    my $eptr = $self->_fresh;
    $self->_emit("  $eptr = getelementptr inbounds [1 x i8], [1 x i8]* $ename, i64 0, i64 0  ; EnvRead: empty fallback");

    my $raw = $self->_fresh;
    $self->_emit("  $raw = call i8* \@getenv(i8* $kptr)  ; EnvRead: getenv(\"$key\")");
    my $isnull = $self->_fresh;
    $self->_emit("  $isnull = icmp eq i8* $raw, null  ; EnvRead: key unset?");
    # THE KEY'S DEFINEDNESS, kept for `//` and `defined`: an unset key prints
    # as the empty string below, but it is undef to them -- read as defined,
    # `$ENV{N} // 3` was "" and a loop bounded by it never ran.
    my $isset = $self->_fresh;
    $self->_emit("  $isset = icmp ne i8* $raw, null  ; EnvRead: key set (its defined bit)");
    $self->{_env_defined}{ $node->id } = $isset;
    my $val = $self->_fresh;
    $self->_emit("  $val = select i1 $isnull, i8* $eptr, i8* $raw  ; EnvRead: value (empty if unset)");
    my $len = $self->_fresh;
    $self->_emit("  $len = call i64 \@strlen(i8* $val)  ; EnvRead: value length");

    $val = $self->_set_str_len($val, $len);
    $self->{cache}{ $node->id } = $val;
    return $val;
}

# _lower_stash_access($node) -> $llvm_ref, the read as its own repr
#
# A package scalar read (`our $g`): load its %Slot (_pkg_slot_name) and unbox
# it to this read's reading. A mutable-location read (EntryDef is in
# %MUTABLE_READ_OPS): one at a memory version is frozen there
# (_freeze_memory_reads); the entry definition re-lowers at each use.
sub _lower_stash_access {
    my ($self, $node) = @_;
    return $self->_argv_array($node)
        if ($node->sigil // '') eq '@' && $node->symbol eq 'ARGV'
        && ($node->package // 'main') eq 'main';
    my $repr = _require_repr($node, 'EntryDef');
    die "GAP: a package variable " . ($node->sigil // '?') . $node->symbol
      . " that is not a scalar is not lowered\n" unless ($node->sigil // '$') eq '$';
    my $g    = $self->_pkg_slot_ptr($node->package, $node->symbol);
    my $slot = $self->_fresh;
    $self->_emit("  $slot = load %Slot, %Slot* $g  ; read package scalar \$"
        . $node->package . '::' . $node->symbol);
    my $ref = $repr eq 'Undef'                          ? $self->_slot_defined_bit($slot)
            : $repr =~ /\A(?:Int|Num|Str|Boolean)\z/  ? $self->_emit_coercion($slot, 'Scalar', $repr,
                                                              'package scalar ' . $node->symbol)
            : $repr eq 'Scalar'                         ? $slot
            : die "GAP: EntryDef repr=$repr is not lowered\n";
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _argv_array($node) -> the %Array* that is @ARGV
#
# @ARGV IS THE PROGRAM'S ARGUMENTS: argv[1..] as Strs, built ONCE in main's
# entry block (by @chalk_argv_array) and shared by every read, so a shift
# from it is seen by what follows. Only main has argv.
sub _argv_array {
    my ($self, $node) = @_;
    die "GAP: \@ARGV read outside the main program is not lowered\n"
        if $self->{_in_method_body};
    unless (defined $self->{_argv_ref}) {
        $self->{_need_argv}            = 1;
        $self->{_need_aggregate_types} = 1;
        $self->{_need_malloc_memcpy}   = 1;
        my $ref = $self->_fresh;
        $self->_emit_entry("  $ref = call %Array* \@chalk_argv_array(i32 %argc, i8** %argv)  ; \@ARGV");
        $self->{_argv_ref} = $ref;
    }
    return $self->{cache}{ $node->id } = $self->{_argv_ref};
}

# _emit_argv_helper() -> the IR text of @chalk_argv_array(argc, argv): an
# %Array of argv[1..argc-1], each a defined %Slot holding a boxed %Str. The
# Slot's field order and the Str tag come from the tables every other Slot
# is built from.
sub _emit_argv_helper {
    my ($d, $t, $p) = (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
    my $str = _slot_tag_value('Str');
    return <<"END_HELPER";
define internal %Array* \@chalk_argv_array(i32 %argc, i8** %argv) {
entry:
  %n32 = sub i32 %argc, 1
  %n = sext i32 %n32 to i64
  %slot_sz = ptrtoint %Slot* getelementptr (%Slot, %Slot* null, i64 1) to i64
  %n1 = add i64 %n, 1
  %bytes = mul i64 %n1, %slot_sz
  %buf = call i8* \@malloc(i64 %bytes)
  %slots = bitcast i8* %buf to %Slot*
  br label %loop
loop:
  %i = phi i64 [ 0, %entry ], [ %i1, %body ]
  %more = icmp slt i64 %i, %n
  br i1 %more, label %body, label %done
body:
  %ai = add i64 %i, 1
  %pp = getelementptr inbounds i8*, i8** %argv, i64 %ai
  %ptr = load i8*, i8** %pp
  %len = call i64 \@strlen(i8* %ptr)
  %sbuf = call i8* \@malloc(i64 ptrtoint (%Str* getelementptr (%Str, %Str* null, i64 1) to i64))
  %sp = bitcast i8* %sbuf to %Str*
  %sp0 = getelementptr inbounds %Str, %Str* %sp, i64 0, i32 0
  store i8* %ptr, i8** %sp0
  %sp1 = getelementptr inbounds %Str, %Str* %sp, i64 0, i32 1
  store i64 %len, i64* %sp1
  %sp2 = getelementptr inbounds %Str, %Str* %sp, i64 0, i32 2
  store i32 0, i32* %sp2
  %pay = ptrtoint %Str* %sp to i64
  %s0 = insertvalue %Slot undef, i1 true, $d
  %s1 = insertvalue %Slot %s0, i8 $str, $t
  %s2 = insertvalue %Slot %s1, i64 %pay, $p
  %slot = getelementptr inbounds %Slot, %Slot* %slots, i64 %i
  store %Slot %s2, %Slot* %slot
  %i1 = add i64 %i, 1
  br label %loop
done:
  %abuf = call i8* \@malloc(i64 ptrtoint (%Array* getelementptr (%Array, %Array* null, i64 1) to i64))
  %arr = bitcast i8* %abuf to %Array*
  %a0 = getelementptr inbounds %Array, %Array* %arr, i32 0, i32 0
  store i64 %n, i64* %a0
  %a1 = getelementptr inbounds %Array, %Array* %arr, i32 0, i32 1
  store i64 %n, i64* %a1
  %a2 = getelementptr inbounds %Array, %Array* %arr, i32 0, i32 2
  store %Slot* %slots, %Slot** %a2
  ret %Array* %arr
}
END_HELPER
}

# _store_package_scalar($target, $value_node, $value_ref) -> $value_ref
#
# Box a value into a package scalar's %Slot -- the store an EntryWrite and an
# Assign to an EntryDef both are.
sub _store_package_scalar {
    my ($self, $target, $value, $ref) = @_;
    die "GAP: a store to the package variable " . ($target->sigil // '?') . $target->symbol
      . " that is not a scalar is not lowered\n" unless ($target->sigil // '$') eq '$';
    my $from = $value->operation eq 'Print' ? 'Boolean' : ($value->stamp // '');
    ($ref, $from) = $self->_miss_kept($value, $ref, $from);
    my $boxed = $from =~ /\A(?:Scalar|Slot)\z/ ? $ref
              : $from eq 'Undef' ? $self->_build_slot('false', '0', 'Undef', 'store to $' . $target->symbol)
              : $from =~ /\A(?:Int|Num|Str|Boolean)\z/
                  ? $self->_emit_coercion($ref, $from, 'Scalar', 'store to $' . $target->symbol)
              : die "GAP: a store to package scalar \$" . $target->symbol
                  . " of a $from value is not lowered\n";
    $self->_emit("  store %Slot $boxed, %Slot* " . $self->_pkg_slot_ptr($target->package, $target->symbol)
        . "  ; store package scalar \$" . $target->package . '::' . $target->symbol);
    return $ref;
}

# _lower_entry_write($node): EntryWrite(target, value, memory) -- a package
# scalar stored through memory, where another graph (a sub) or a later
# version reads it.
sub _lower_entry_write {
    my ($self, $node) = @_;
    my ($target, $value) = grep { blessed($_) } $node->inputs->@[0, 1];
    die "GAP: an EntryWrite whose target is not an EntryDef is not lowered\n"
        unless blessed($target) && $target->operation eq 'EntryDef' && blessed($value);
    # `*name = sub { ... }` that Analysis bound statically: every call of the
    # name already runs that sub, so the assignment has nothing left to do.
    return $self->{cache}{ $node->id } = '0'
        if $value->operation eq 'AnonSub' && $value->glob_bound;
    my $ref = $self->_store_package_scalar($target, $value, $self->lower_value($value));
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _parse_subst_replacement($replacement, $ngroups) -> \@segments
#
# Split an s/// replacement into literal runs and $N capture references.
# Each segment is { kind => 'lit', text => ... } or { kind => 'cap', n => N }.
# A backslash escapes the next char to a literal; $& $` $' and $N beyond the
# pattern's group count die loudly as GAPs.
sub _parse_subst_replacement {
    my ($repl, $ngroups) = @_;
    my @segs;
    my $lit = '';
    my @chars = split //, $repl;
    my $i = 0;
    my $flush = sub {
        push @segs, { kind => 'lit', text => $lit } if length $lit;
        $lit = '';
    };
    while ($i <= $#chars) {
        my $c = $chars[$i];
        if ($c eq '\\' && $i < $#chars) {
            my $e = $chars[ $i + 1 ];
            # The replacement contract is COOKED BYTES: the parser resolves
            # double-quotish escapes (\t, \n, \x..) before constructing the
            # node; only \$ and \\ are substitution-level escapes here. An
            # alphanumeric escape reaching this point would silently become
            # the literal letter — die loudly instead.
            die "GAP: s/// replacement escape \\$e not supported (the parser "
              . "resolves double-quotish escapes; only \\\$ and punctuation "
              . "escapes are handled here)" if $e =~ /[A-Za-z0-9]/;
            $lit .= $e;
            $i += 2;
            next;
        }
        if ($c eq '$' && $i < $#chars) {
            my $n = $chars[ $i + 1 ];
            if ($n =~ /^[1-9]$/) {
                # Perl reads the LONGEST digit run ($12 = group 12, not $1."2");
                # multi-digit groups are beyond the supported slice — die rather
                # than silently splitting into $1 . "2".
                die "GAP: s/// replacement multi-digit capture ref \$$n$chars[$i+2] "
                  . "not supported (perl reads it as one group number)"
                    if ($chars[ $i + 2 ] // '') =~ /^\d$/;
                die "GAP: s/// replacement references \$$n but the pattern has "
                  . "only $ngroups capture group(s)" if $n > $ngroups;
                $flush->();
                push @segs, { kind => 'cap', n => 0 + $n };
                $i += 2;
                next;
            }
            die "GAP: s/// replacement \$$n not supported (only \$1..\$9 capture refs)";
        }
        $lit .= $c;
        $i++;
    }
    $flush->();
    return \@segs;
}

# _lower_regex_subst($node) -> $llvm_ref (i8* result string)
#
# Lowers s///: run the matcher, then splice — result = prefix [0,m0s) +
# replacement (literal segments + $N captured slices) + suffix [m0e,len).
# A failed match returns the subject unchanged. First match only (/g is a
# tracked follow-up). The result length is a runtime value tracked in
# _str_len_table (the Str epilogue prints via "%.*s").
sub _lower_regex_subst {
    my ($self, $node) = @_;

    my $subj_node = $node->inputs->[0];
    my $repr      = _require_repr($node, 'RegexSubst');

    # AN EMPTY PATTERN is perl's last successful one, which is not tracked --
    # and B::SoN sends `s/$p/X/` this way, $p's value in the replacement
    # (printed "babcb" for perl's "aXcb").
    die "GAP: s/// with an empty pattern (the last pattern that matched, or one "
      . "interpolated at run time) is not lowered\n"
        if ( $node->pattern // '' ) eq '';

    # A COMPUTED REPLACEMENT arrives as an operand between the subject and
    # the memory version, the `replacement` field then "": B::SoN computes it
    # in the arm of the match (captures, or the /e expression) and merges it
    # with undef. In the matched block it is that arm's value, spliced in.
    my @rest = grep { blessed($_) } @{ $node->inputs }[ 1 .. $#{ $node->inputs } ];
    my $repl_node = ( @rest && !_is_memory_version($rest[0]) ) ? shift @rest : undef;
    die "GAP: s/// with more than one computed replacement operand is not lowered\n"
        if @rest > 1 || ( @rest == 1 && !_is_memory_version($rest[0]) );

    # /e is the producer's to compute; with the value here, it is spent.
    my $flags = $node->flags // '';
    $flags =~ s/e//g if $repl_node;
    my $global = $flags =~ s/g//g;
    die "GAP: s///$flags flags not yet supported by the G6 sub-compiler"
        if length $flags;

    # s/// READS ITS SUBJECT AS A STRING: a Scalar (a location's Slot) is
    # read as one, by its tag. Taken apart as a %Str, lli rejected it.
    my $subj_ref = $self->lower_value($subj_node);
    $subj_ref = $self->_emit_coercion($subj_ref, 'Scalar', 'Str', 's/// subject')
        if ( $subj_node->stamp // '' ) eq 'Scalar';
    my ($subj_ptr, $subj_len_tracked) = $self->_str_parts($subj_ref);
    my $subj_len  = $subj_len_tracked
        // die "GAP: RegexSubst subject (ref=$subj_ptr) has no tracked length — "
             . "the matcher needs the subject's byte length.";

    # A REPLACEMENT MADE PER MATCH (/ge) is a graph of its own, not lowered
    # here: dropped, the replacement was "".
    die "GAP: s/// whose replacement is computed per match (/ge) is not lowered\n"
        if defined $node->replacement_body;
    my $compiled = _compile_regex_pattern($node->pattern, $flags);
    my $segs     = $repl_node ? [ { kind => 'val' } ]
                 : _parse_subst_replacement($node->replacement // '', $compiled->{ngroups} // 0);

    if ($global) {
        # A COMPUTED REPLACEMENT is made once by B::SoN, not once per match.
        die "GAP: s///g with a computed replacement (/e, or one made per match) is not lowered\n"
            if $repl_node || defined $node->replacement_body;
        # PERL STEPS OVER AN EMPTY MATCH by rules of its own, and ^ matches
        # only at the start: neither is this loop's.
        die "GAP: s///g whose pattern is anchored at the start is not lowered\n"
            if $compiled->{anchored_start};
        die "GAP: s///g whose pattern can match the empty string is not lowered\n"
            unless grep { $_->{kind} =~ /\A(?:lit|class|any)\z/ && ( $_->{min} // 1 ) > 0 }
                   $compiled->{atoms}->@*;
        return $self->_lower_regex_subst_g($node, $subj_node, $subj_ptr, $subj_len, $compiled, $segs);
    }

    my $match = $self->_emit_regex_matcher($subj_ptr, $subj_len, $compiled, 'RegexSubst');
    # s///'s count: one, or none.
    my $one = $self->_fresh;
    $self->_emit("  $one = zext i1 $match->{matched} to i64  ; s///: how many replaced");
    $self->{_subst_count}{ $node->id } = $one;

    $self->{_need_malloc_memcpy} = 1;

    my $lbl_pre  = $self->_current_block_label;
    my $lbl_do   = $self->_fresh_label('rxsdo');
    my $lbl_done = $self->_fresh_label('rxsdn');
    $self->_set_terminator("  br i1 $match->{matched}, label \%$lbl_do, label \%$lbl_done");

    # Matched: build the spliced string.
    $self->_new_block($lbl_do);
    my $m0len = $self->_fresh;
    $self->_emit("  $m0len = sub i64 $match->{m0e}, $match->{m0s}  ; RegexSubst: matched length");

    # Replacement length: compile-time literal bytes + runtime capture lengths.
    my $lit_total = 0;
    $lit_total += length($_->{text}) for grep { $_->{kind} eq 'lit' } @$segs;
    my $repl_len = $lit_total;   # SSA ref or constant
    for my $seg (grep { $_->{kind} eq 'val' } @$segs) {
        # Defined here: the match took the arm that computed it.
        my $v    = $self->lower_value($repl_node);
        my $from = $self->_repr_of($repl_node) // '';
        $v = $self->_emit_coercion($v, $from, 'Str', 's/// computed replacement') if $from ne 'Str';
        my ($vp, $vl) = $self->_str_parts($v);
        die "GAP: s/// computed replacement has no tracked length\n" unless defined $vl;
        @$seg{qw(ptr len_ref)} = ($vp, $vl);
        my $acc = $self->_fresh;
        $self->_emit("  $acc = add i64 $repl_len, $vl  ; RegexSubst: + computed replacement");
        $repl_len = $acc;
    }
    for my $seg (grep { $_->{kind} eq 'cap' } @$segs) {
        my $n = $seg->{n};
        my $clen = $self->_fresh;
        $self->_emit("  $clen = sub i64 $match->{cap_e}[$n], $match->{cap_s}[$n]  ; RegexSubst: \$$n length");
        $seg->{len_ref} = $clen;
        my $acc = $self->_fresh;
        $self->_emit("  $acc = add i64 $repl_len, $clen  ; RegexSubst: replacement length so far");
        $repl_len = $acc;
    }

    my $keep = $self->_fresh;
    $self->_emit("  $keep = sub i64 $subj_len, $m0len  ; RegexSubst: bytes kept from subject");
    my $new_len = $self->_fresh;
    $self->_emit("  $new_len = add i64 $keep, $repl_len  ; RegexSubst: result length");
    my $alloc = $self->_fresh;
    $self->_emit("  $alloc = add i64 $new_len, 1  ; RegexSubst: +1 for NUL");
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $alloc)  ; RegexSubst: result buffer");

    # Prefix [0, m0s).
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $subj_ptr, i64 $match->{m0s})  ; RegexSubst: prefix");
    my $cursor = $match->{m0s};   # dest offset after the prefix

    # Replacement segments.
    for my $seg (@$segs) {
        my $dest = $self->_fresh;
        $self->_emit("  $dest = getelementptr inbounds i8, i8* $buf, i64 $cursor  ; RegexSubst: dest cursor");
        if ($seg->{kind} eq 'lit') {
            my $text = $seg->{text};
            # Same symbol-prefix + byte-length rule as @str_const_N (I1) — the
            # byte length is the memcpy size below, so it must count bytes.
            my ($gname, $blen, $total) = $self->_module_global_name('rxs_lit', $text);
            my $src = $self->_fresh;
            $self->_emit("  $src = getelementptr inbounds [$total x i8], [$total x i8]* $gname, i64 0, i64 0  ; RegexSubst: literal segment");
            $self->_emit("  call i8* \@memcpy(i8* $dest, i8* $src, i64 $blen)  ; RegexSubst: copy literal");
            my $next = $self->_fresh;
            $self->_emit("  $next = add i64 $cursor, $blen  ; RegexSubst: advance cursor");
            $cursor = $next;
        }
        elsif ($seg->{kind} eq 'val') {
            $self->_emit("  call i8* \@memcpy(i8* $dest, i8* $seg->{ptr}, i64 $seg->{len_ref})  ; RegexSubst: copy computed replacement");
            my $next = $self->_fresh;
            $self->_emit("  $next = add i64 $cursor, $seg->{len_ref}  ; RegexSubst: advance cursor");
            $cursor = $next;
        }
        else {
            my $n = $seg->{n};
            my $src = $self->_fresh;
            $self->_emit("  $src = getelementptr inbounds i8, i8* $subj_ptr, i64 $match->{cap_s}[$n]  ; RegexSubst: \$$n source");
            $self->_emit("  call i8* \@memcpy(i8* $dest, i8* $src, i64 $seg->{len_ref})  ; RegexSubst: copy \$$n");
            my $next = $self->_fresh;
            $self->_emit("  $next = add i64 $cursor, $seg->{len_ref}  ; RegexSubst: advance cursor");
            $cursor = $next;
        }
    }

    # Suffix [m0e, len) + NUL terminator.
    my $sfx_dest = $self->_fresh;
    $self->_emit("  $sfx_dest = getelementptr inbounds i8, i8* $buf, i64 $cursor  ; RegexSubst: suffix dest");
    my $sfx_src = $self->_fresh;
    $self->_emit("  $sfx_src = getelementptr inbounds i8, i8* $subj_ptr, i64 $match->{m0e}  ; RegexSubst: suffix source");
    my $sfx_len = $self->_fresh;
    $self->_emit("  $sfx_len = sub i64 $subj_len, $match->{m0e}  ; RegexSubst: suffix length");
    $self->_emit("  call i8* \@memcpy(i8* $sfx_dest, i8* $sfx_src, i64 $sfx_len)  ; RegexSubst: suffix");
    my $nul_ptr = $self->_fresh;
    $self->_emit("  $nul_ptr = getelementptr inbounds i8, i8* $buf, i64 $new_len  ; RegexSubst: NUL slot");
    $self->_emit("  store i8 0, i8* $nul_ptr  ; RegexSubst: NUL-terminate");
    # The matched path ends in the block current NOW: reading a computed
    # replacement by its tag opens blocks of its own.
    my $lbl_do_end = $self->_current_block_label;
    $self->_set_terminator("  br label \%$lbl_done");

    # Merge: spliced buffer on match, the original subject otherwise.
    $self->_new_block($lbl_done);
    my $res = $self->_fresh;
    $self->_emit("  $res = phi i8* [ $buf, \%$lbl_do_end ], [ $subj_ptr, \%$lbl_pre ]  ; RegexSubst: result");
    my $res_len = $self->_fresh;
    $self->_emit("  $res_len = phi i64 [ $new_len, \%$lbl_do_end ], [ $subj_len, \%$lbl_pre ]  ; RegexSubst: result length");

    $res = $self->_set_str_len($res, $res_len);
    # A LOCATION'S s/// IS STORED BACK: the RegexSubst is its next memory
    # version, and the read after it is frozen there -- at the slot.
    if ($subj_node->operation eq 'PadAccess' && $subj_node->is_location) {
        my $boxed = $self->_emit_coercion($res, 'Str', 'Scalar', 's/// store-back');
        $self->_emit("  store i64 -1, i64* " . $self->_pos_cell($subj_node) . "  ; s/// clears pos()")
            if $POS_VARS{ $subj_node->name };
        $self->_emit("  store %Slot $boxed, %Slot* " . $self->_location_ptr($subj_node)
            . "  ; s/// stores lexical " . $subj_node->name);
    }
    $self->{cache}{ $node->id } = $res;
    return $res;
}

# _lower_regex_subst_g(...) -> %Str: s///g. Every match, left to right: the
# text before it and its replacement are appended, and the next search starts
# where it ended; the rest of the subject closes the result. Counted for
# RegexSubstCount. (The pattern consumes at least one byte and is not
# anchored: the caller refuses the others.)
sub _lower_regex_subst_g {
    my ($self, $node, $subj_node, $sp, $sl, $compiled, $segs) = @_;
    $self->{_need_malloc_memcpy} = 1;
    my $acc0 = $self->_empty_str_ref('s///g: so far');
    my $from = $self->_current_block_label;
    my ($head, $hit, $latch, $tail) = map { $self->_fresh_label("rxsg.$_.") } qw(head hit latch tail);
    my ($acc, $off, $cnt, $acc_n, $off_n, $cnt_n, $rp, $rl) = map { $self->_fresh } 1 .. 8;
    $self->_set_terminator("  br label %$head");
    $self->_new_block($head);
    $self->_emit("  $acc = phi %Str [ $acc0, %$from ], [ $acc_n, %$latch ]  ; s///g: the result so far");
    $self->_emit("  $off = phi i64 [ 0, %$from ], [ $off_n, %$latch ]  ; s///g: where the search starts");
    $self->_emit("  $cnt = phi i64 [ 0, %$from ], [ $cnt_n, %$latch ]  ; s///g: how many replaced");
    $self->_emit("  $rp = getelementptr inbounds i8, i8* $sp, i64 $off");
    $self->_emit("  $rl = sub i64 $sl, $off  ; s///g: what is left");
    my $m = $self->_emit_regex_matcher($rp, $rl, $compiled, 's///g');
    $self->_set_terminator("  br i1 $m->{matched}, label %$hit, label %$tail");

    $self->_new_block($hit);
    my $a = $self->_emit_str_append($acc, $self->_set_str_len($rp, $m->{m0s}), 's///g: before the match');
    for my $seg (@$segs) {
        if ($seg->{kind} eq 'lit') {
            $a = $self->_emit_str_append($a, $self->_set_str_len($self->_str_const_parts($seg->{text}, 's///g: replacement')), 's///g');
            next;
        }
        my $n = $seg->{n};
        my ($cp, $clen) = map { $self->_fresh } 1 .. 2;
        $self->_emit("  $cp = getelementptr inbounds i8, i8* $rp, i64 $m->{cap_s}[$n]  ; s///g: \$$n");
        $self->_emit("  $clen = sub i64 $m->{cap_e}[$n], $m->{cap_s}[$n]");
        $a = $self->_emit_str_append($a, $self->_set_str_len($cp, $clen), 's///g: a capture');
    }
    $self->_emit("  $acc_n = select i1 true, %Str $a, %Str $a");
    $self->_emit("  $off_n = add i64 $off, $m->{m0e}  ; s///g: past the match");
    $self->_emit("  $cnt_n = add i64 $cnt, 1");
    $self->_set_terminator("  br label %$latch");
    $self->_new_block($latch);
    $self->_set_terminator("  br label %$head");

    $self->_new_block($tail);
    my $res = $self->_emit_str_append($acc, $self->_set_str_len($rp, $rl), 's///g: the rest');
    $self->{_subst_count}{ $node->id } = $cnt;
    if ($subj_node->operation eq 'PadAccess' && $subj_node->is_location) {
        my $boxed = $self->_emit_coercion($res, 'Str', 'Scalar', 's///g store-back');
        $self->_emit("  store i64 -1, i64* " . $self->_pos_cell($subj_node) . "  ; s///g clears pos()")
            if $POS_VARS{ $subj_node->name };
        $self->_emit("  store %Slot $boxed, %Slot* " . $self->_location_ptr($subj_node)
            . "  ; s///g stores lexical " . $subj_node->name);
    }
    return $self->{cache}{ $node->id } = $res;
}

# _lower_regex_subst_count($node): what s/// yields -- how many it replaced,
# or "" when none (perl's false).
sub _lower_regex_subst_count {
    my ($self, $node) = @_;
    my ($subst) = grep { blessed($_) } $node->inputs->@*;
    $self->lower_value($subst);
    my $cnt = $self->{_subst_count}{ $subst->id }
        // die "GAP: the count of an s/// not lowered here is not lowered\n";
    my $to = $node->stamp // 'Str';
    return $self->{cache}{ $node->id } = $cnt if $to eq 'Int';
    die "GAP: an s/// count read as a $to is not lowered\n" unless $to eq 'Str';
    my ($np, $nl) = $self->_str_parts($self->_emit_int_to_str($cnt));
    my ($ep) = $self->_str_const_parts('', 's///: none replaced');
    my ($none, $p, $l) = map { $self->_fresh } 1 .. 3;
    $self->_emit("  $none = icmp eq i64 $cnt, 0");
    $self->_emit("  $p = select i1 $none, i8* $ep, i8* $np");
    $self->_emit("  $l = select i1 $none, i64 0, i64 $nl");
    return $self->{cache}{ $node->id } = $self->_set_str_len($p, $l);
}

# _lower_print($node) -> $llvm_ref (an i1 1, Boolean repr)
#
# A control-pinned statement effect: emit each list argument to stdout in order,
# then yield print's boolean 1 (perl's print returns a genuine Boolean). The loader
# already split the leading control token off inputs, so inputs are exactly the
# printed values. Each argument is emitted by its representation:
#   Str  -> printf("%.*s", (i32)len, ptr)  — exactly len bytes, embedded-NUL safe;
#           the length comes from the compile-time/runtime _str_len_table.
#   Int  -> printf("%d", (i32)val)         — the i64 value truncated to i32,
#           mirroring the Int return epilogue.
# Any other repr is an honest GAP (Num/Boolean/aggregate print is not wired). The
# output is emitted BEFORE the return-value epilogue because it lands in @main's
# control-chain instructions, which precede the epilogue printf.
sub _lower_print {
    my ($self, $node) = @_;

    my @args = $node->inputs->@*;
    if ($node->can('has_filehandle') && $node->has_filehandle) {
        my $fh = shift @args;
        unless (blessed($fh) && $fh->operation eq 'Constant' && ( $fh->value // '' ) eq 'STDOUT') {
            return $self->_lower_print_to_handle($node, $fh, @args)
                if blessed($fh) && $fh->operation eq 'PadAccess';
            die "GAP: print to the handle "
              . ( blessed($fh) && $fh->can('value') ? ( $fh->value // '?' ) : '?' ) . " is not lowered\n";
        }
    }
    # A PROGRAM THAT SELECTS A HANDLE prints where it says: to STDOUT when
    # none is selected, else into the selected handle.
    my ($sel_join, $sel_r, $sel_from);
    if ($SELECTS && !( $node->can('has_filehandle') && $node->has_filehandle )) {
        $self->{_need_select} = 1;
        my @strs = $self->_print_strs(@args);
        my ($sel, $none) = map { $self->_fresh } 1 .. 2;
        my ($out, $tofh) = map { $self->_fresh_label("print.$_.") } qw(stdout tofh);
        $sel_join = $self->_fresh_label('print.join.');
        $self->_emit("  $sel = load i8*, i8** \@chalk_selected  ; print: the selected handle");
        $self->_emit("  $none = icmp eq i8* $sel, null");
        $self->_set_terminator("  br i1 $none, label %$out, label %$tofh");
        $self->_new_block($tofh);
        $sel_r = $self->_emit_handle_write($sel, @strs);
        $sel_from = $self->_current_block_label;
        $self->_set_terminator("  br label %$sel_join");
        $self->_new_block($out);
    }
    for my $arg (@args) {
        next unless defined $arg;
        my $repr = $arg->stamp;
        my $ref  = $self->_print_arg($arg);

        if (defined $repr && $repr eq 'Str') {
            my ($str_ptr, $len) = $self->_str_parts($ref);
            $ref = $str_ptr;
            die "Print of a Str arg whose length is not tracked in "
              . "_str_len_table — cannot emit exactly-len bytes."
                unless defined $len;
            # printf's %.*s precision arg is i32. A literal length passes through;
            # an SSA (i64) length is truncated to i32.
            my $len32 = ($len =~ /\A\d+\z/) ? $len : do {
                my $t = $self->_fresh;
                $self->_emit("  $t = trunc i64 $len to i32  ; Print: Str length -> i32");
                $t;
            };
            $self->{_need_print_str_fmt} = 1;
            my $fp = $self->_fresh;
            $self->_emit("  $fp = getelementptr inbounds [5 x i8], [5 x i8]* \@fmt_print_str, i64 0, i64 0  ; Print: %.*s fmt");
            $self->_emit("  call i32 (i8*, ...) \@printf(i8* $fp, i32 $len32, i8* $ref)  ; Print: emit Str arg");
        }
        else {
            # Print's signature is Print(Str...). Anything else must arrive
            # through an explicit coercion -- the producer wraps a non-Str
            # argument in a Stringify -- rather than Print carrying a case per
            # representation.
            #
            # It used to lower Int here as well, with printf %lld, while
            # Stringify separately knew how to render an Int. Two places knew
            # about the same conversion, so teaching Print a new type (Boolean,
            # Num, Slot) meant teaching both. Now only the coercion learns a
            # type and this stays one operator over one representation.
            die "GAP: Print of a "
              . (defined $repr ? $repr : 'representation-less')
              . " arg — Print takes Str, so this needs a Coerce(X -> Str) "
              . "(the producer inserts one for a stamped non-Str argument).";
        }
    }

    # print returns a genuine boolean 1. Materialize an i1 1 runtime-opaquely so
    # the value-context read (`my $ok = print ...`) tags Bool:1. alloca/store/load
    # keeps it opaque to the optimizer, matching the Undef/Boolean constant pattern.
    my $slot = $self->_fresh;
    $self->_emit("  $slot = alloca i1  ; Print: return-value slot");
    $self->_emit("  store i1 1, i1* $slot  ; Print: yields boolean 1");
    my $ref = $self->_fresh;
    $self->_emit("  $ref = load i1, i1* $slot  ; Print: read boolean 1");
    if ($sel_join) {
        my $out_end = $self->_current_block_label;
        $self->_set_terminator("  br label %$sel_join");
        $self->_new_block($sel_join);
        my $r = $self->_fresh;
        $self->_emit("  $r = phi i1 [ $ref, %$out_end ], [ $sel_r, %$sel_from ]  ; print: wrote?");
        $ref = $r;
    }
    $self->{cache}{ $node->id } = $ref;
    return $ref;
}

# _lower_print_to_handle($node, $fh, @args) -> i1: `print $out LIST` onto
# an in-memory write handle appends each value to its scalar; true. A closed
# or read handle writes nothing; false.
sub _lower_print_to_handle {
    my ($self, $node, $fh, @args) = @_;
    my @strs = $self->_print_strs(@args);
    my $cell = $self->_handle_cell($fh);
    my $h = $self->_fresh;
    $self->_emit("  $h = load i8*, i8** $cell  ; print: the handle");
    return $self->{cache}{ $node->id } = $self->_emit_handle_write($h, @strs);
}

# _print_strs(@args) -> each printed value, lowered: Print takes Str.
sub _print_strs {
    my ($self, @args) = @_;
    return map {
        my $r = ( $_->stamp // '' );
        die "GAP: Print of a $r arg to a handle -- Print takes Str\n" unless $r eq 'Str';
        $self->_print_arg($_);
    } grep { blessed($_) } @args;
}

# _print_arg($arg) -> its Str. A LIST MADE AT RUN TIME (a readline's lines)
# reaches print as one Coerce[List->Str]: its elements, one after another --
# read as an aggregate's scalar it printed their count.
sub _print_arg {
    my ($self, $arg) = @_;
    # ...ONE B::SoN CALLED A LIST: one Analysis narrowed from Unknown (a sub's
    # value, `print scalar(ff())`) is its scalar reading, the count (pvm 228).
    if ($arg->operation eq 'Coerce' && ( $arg->wire_from // $arg->from_repr // '' ) =~ /\A(?:List|Array)\z/
            && ( $arg->to_repr // '' ) eq 'Str'
            && ( $self->_repr_of($arg->inputs->[0]) // '' ) =~ /\A(?:Array|List)\z/) {
        return $self->{cache}{ $arg->id } //= $self->_emit_join_loop($arg->inputs->[0], $self->_empty_str_ref('print: no separator'));
    }
    return $self->lower_value($arg);
}

# _lower_select($node) -> i8*: `select(FH)` makes FH the handle a bare print
# writes to and is the one it replaces -- a handle a later select can take
# back (null for STDOUT). Its value has no other use here.
sub _lower_select {
    my ($self, $node) = @_;
    die "GAP: select in a program with classes is not lowered -- a method body would not see it\n"
        if grep { $_ ne 'main' } keys %{ $self->{class_registry} // {} };
    die "GAP: select whose result is used other than by another select is not lowered\n"
        if grep { my $c = $_; blessed($c) && !( $c->operation eq 'Call' && ( $c->name // '' ) eq 'select' )
                  && grep { blessed($_) && refaddr($_) == refaddr($node) } $c->inputs->@* }
            ($node->consumers // [])->@*;
    my ($fh) = grep { blessed($_) } $node->inputs->@*;
    die "GAP: select() with no handle is not lowered\n" unless $fh;
    my $h;
    if ($fh->operation eq 'Constant' && ( $fh->value // '' ) eq 'STDOUT') { $h = 'null' }
    elsif ($fh->operation eq 'Call' && ( $fh->name // '' ) eq 'select') { $h = $self->lower_value($fh) }
    elsif ($fh->operation eq 'PadAccess') {
        $h = $self->_fresh;
        $self->_emit("  $h = load i8*, i8** " . $self->_handle_cell($fh) . "  ; select: the handle");
    }
    else { die "GAP: select of a " . $fh->operation . " is not lowered -- only of a `my \$fh`, STDOUT, or what a select returned\n" }
    $self->{_need_select} = 1;
    my $prev = $self->_fresh;
    $self->_emit("  $prev = load i8*, i8** \@chalk_selected  ; select: the one it replaces");
    $self->_emit("  store i8* $h, i8** \@chalk_selected  ; select");
    return $self->{cache}{ $node->id } = $prev;
}

# _lower_sselect($node): four-argument select with no handles and no wait
# finds none ready: 0.
sub _lower_sselect {
    my ($self, $node) = @_;
    my @in = $node->inputs->@*;
    die "GAP: four-argument select on handles, or with a wait, is not lowered\n"
        unless @in == 4 && !grep { !blessed($_) || $_->operation ne 'Constant' || ( $_->const_type // '' ) ne 'undef' } @in[0 .. 2]
        and blessed($in[3]) && $in[3]->operation eq 'Constant' && ( $in[3]->value // '' ) eq '0';
    return $self->{cache}{ $node->id } = '0';
}

# _emit_handle_write($h, @strs) -> i1: append each Str to the scalar the
# handle at $h writes; false, writing nothing, when it is closed or a read
# handle.
sub _emit_handle_write {
    my ($self, $h, @strs) = @_;
    my ($open, $t, $ok) = map { $self->_fresh } 1 .. 3;
    my ($chk, $write, $join) = map { $self->_fresh_label("printfh.$_.") } qw(chk write join);
    my $from = $self->_current_block_label;
    $self->_emit("  $open = icmp ne i8* $h, null");
    $self->_set_terminator("  br i1 $open, label %$chk, label %$join");
    $self->_new_block($chk);
    $self->_emit("  $t = load i8*, i8** " . $self->_handle_field($h, 3) . "  ; print: the scalar it writes");
    $self->_emit("  $ok = icmp ne i8* $t, null");
    my $chk_end = $self->_current_block_label;
    $self->_set_terminator("  br i1 $ok, label %$write, label %$join");
    $self->_new_block($write);
    my $tp = $self->_fresh;
    $self->_emit("  $tp = bitcast i8* $t to %Slot*");
    for my $str (@strs) {
        my $old = $self->_fresh;
        $self->_emit("  $old = load %Slot, %Slot* $tp  ; print: what it holds");
        my $cat = $self->_emit_str_append($self->_emit_coercion($old, 'Scalar', 'Str', 'print: its string'),
            $str, 'print to a handle');
        my $boxed = $self->_emit_coercion($cat, 'Str', 'Scalar', 'print: appended');
        $self->_emit("  store %Slot $boxed, %Slot* $tp  ; print: appended");
    }
    my $write_end = $self->_current_block_label;
    $self->_set_terminator("  br label %$join");
    $self->_new_block($join);
    my $r = $self->_fresh;
    $self->_emit("  $r = phi i1 [ 0, %$from ], [ 0, %$chk_end ], [ 1, %$write_end ]  ; print: wrote?");
    return $r;
}

# _lower_field_access_in_method($node) -> $llvm_ref
#
# Lowers a FieldAccess node when inside a method body context.
# Reads from %self at the field's struct offset.
# For Str fields: payload is a StrPair* (as i64); returns the string ptr.
sub _lower_field_access_in_method {
    my ($self, $node) = @_;

    my $field_index = $node->field_index;
    my $class_name  = $self->{_method_class_name}
        or die "LLVM MOP: FieldAccess in method body but _method_class_name not set";
    my $repr        = _require_repr($node, 'FieldAccess(method)');

    my $slot_idx  = $field_index + 1;
    # An object field IS a %Slot cell. Its subfield indices come from
    # _slot_idx, never a literal: a field added to @_SLOT_FIELDS must
    # not silently re-aim these GEPs at the wrong bytes.
    my ($fi_def, $fi_tag, $fi_pay) =
        (_slot_idx('defined'), _slot_idx('tag'), _slot_idx('payload'));
    my $obj_raw   = $self->{_method_self_name} // '%self';
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; FieldAccess: typed self");
    my $pay_gep   = $self->_fresh;
    $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 $fi_pay  ; field[$field_index] payload");
    my $pay       = $self->_fresh;
    $self->_emit("  $pay = load i64, i64* $pay_gep  ; load field[$field_index] payload");

    if ($repr eq 'Str') {
        # Payload is a StrPair* (as i64) — cast and extract {ptr, len}
        $self->{_need_str_type} = 1;
        my $pair_ptr = $self->_fresh;
        $self->_emit("  $pair_ptr = inttoptr i64 $pay to %Str*  ; payload -> StrPair*");
        my $pp_gep = $self->_fresh;
        $self->_emit("  $pp_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
        my $sp = $self->_fresh;
        $self->_emit("  $sp = load i8*, i8** $pp_gep  ; load str ptr");
        my $lp_gep = $self->_fresh;
        $self->_emit("  $lp_gep = getelementptr inbounds %Str, %Str* $pair_ptr, i64 0, i32 1  ; StrPair.len");
        my $sl = $self->_fresh;
        $self->_emit("  $sl = load i64, i64* $lp_gep  ; load str len");
        $sp = $self->_set_str_len($sp, $sl);
        $self->{cache}{ $node->id } = $sp;
        return $sp;
    }
    elsif ($repr eq 'ArrayRef' || $repr eq 'HashRef') {
        # An aggregate-ref field: the payload i64 is a boxed i8* (the store side
        # does `ptrtoint i8* -> i64`; _store_field_payload). Read is the mirror:
        # inttoptr i64 -> i8*. _container_ptr then bitcasts this i8* to %Array*/
        # %Hash* at the use (it keys on repr eq "${kind}Ref"), so a `$items->[0]`
        # / `scalar $items->@*` / a foreach over the field lowers (zhi 019f61ad).
        my $ptr = $self->_fresh;
        $self->_emit("  $ptr = inttoptr i64 $pay to i8*  ; $repr payload -> i8*");
        $self->{cache}{ $node->id } = $ptr;
        return $ptr;
    }
    else {
        # SCALAR READINGS GO THROUGH THE TAG. "Int: payload is i64 directly"
        # stood here, and it is only true when the cell was WRITTEN as an Int.
        # A field is a %Slot, and every store site tags it: `$n += 1` on a
        # `:param` field writes tag=Num with `bitcast double -> i64`, so reading
        # the payload as an i64 hands back the double's BITS. Measured on corpus
        # method-call: 4622382067542392832, which is exactly
        # unpack('q', pack('d', 11.0)).
        #
        # perigrin's rule: boxing and unboxing a Slot MUST consult the type tag.
        # The write half already did; this is the read half. _emit_read_slot_as
        # is the same dispatch _lower_coerce_from_slot uses -- a defined-bit
        # guard, one arm per tag, an undef path for anything unreadable -- so
        # the two halves share one mechanism rather than agreeing by discipline.
        #
        # It wants the whole cell, not the payload word, so load the aggregate.
        my $slot_gep = $self->_fresh;
        $self->_emit("  $slot_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx  ; field[$field_index] cell");
        my $slot = $self->_fresh;
        $self->_emit("  $slot = load %Slot, %Slot* $slot_gep  ; load field[$field_index] cell");

        # THE STR ARM IS BACK, because the reason it was dropped is gone.
        #
        # It was excluded because the Str arm GEPs the boxed-Str type while a
        # method body is lowered BEFORE the prologue that declared it, so the
        # type appeared after its first use and lli refused the module. That
        # was a property of %StrPair being declared CONDITIONALLY, on a
        # pre-scan that asked which methods return Str. %Str is declared
        # unconditionally, and since the collapse there is only %Str -- so the
        # ordering hazard this narrowing worked around no longer exists.
        #
        # DROPPING THE ARM WAS NOT SAFE, which is what forced the collapse.
        # Measured on `field $s :param = "hi"; method get { $s }`: the
        # constructor boxes "hi" onto the heap and stores the pointer, the tag
        # is written Str, and the read then tested only Int/Num/Boolean -- so
        # the cell fell to the undef arm and the program printed an empty line
        # where perl prints `hi`. The old comment said the undef arm "answers
        # honestly"; it does for a Str cell reaching an INT-typed read, and it
        # does not for a Str cell reaching a Scalar-typed read, which is this
        # case.
        my $val = $self->_emit_read_slot_as($slot, $repr,
            "FieldAccess(method) field[$field_index] -> $repr");
        $self->{cache}{ $node->id } = $val;
        return $val;
    }
}

# _infer_class_name_from_obj($obj_node) -> $class_name
#
# Walks the obj_node back to find the statically-known class name. Supports:
# - Call(dispatch_kind='method', name='new') via its class_name attribute
# - Other cases: die loudly (cannot infer class name)
sub _infer_class_name_from_obj {
    my ($obj_node) = @_;
    return undef unless defined $obj_node;
    my $op = $obj_node->can('operation') ? $obj_node->operation : '';
    # Call(dispatch_kind='method', name='new') is the canonical construction form.
    if ($op eq 'Call' && $obj_node->can('dispatch_kind')
        && ($obj_node->dispatch_kind // '') eq 'method'
        && ($obj_node->name // '') eq 'new')
    {
        return $obj_node->class_name
            // die "LLVM MOP: Call(new) has no class_name — cannot infer the "
                 . "constructed class (019eb42a MOP-direct contract).";
    }
    # PadAccess to a variable holding a constructed object — walk inputs
    if ($op eq 'PadAccess') {
        # Not yet supported in MOP: die to trigger diagnostic
        die "LLVM MOP: cannot infer class name from PadAccess — "
          . "method body self-reference via var not yet supported";
    }
    die "LLVM MOP: cannot infer class name from op=$op — expected Call(new) or PadAccess";
}

1;
