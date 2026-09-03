# ABOUTME: Runs the loader's type-inference passes over a decoded graph set.
# ABOUTME: Consumes graphs + class metadata; produces a typed graph set and the MOP.
use 5.42.0;
use utf8;

package Chalk::IR::Analysis;

use Scalar::Util qw(blessed refaddr);

use Chalk::IR::Value;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Coerce;             # _insert_str_coercions builds these
use Chalk::Grammar::Perl::TypeLibrary;   # is_subtype / join_types: the lattice

# NOTE: no `use Chalk::IR::Serialize::JSON` here, and none is needed. The passes
# below used to live in that module and were called back into it from here,
# which made the two modules mutually dependent -- a load cycle that only a
# runtime `require` at the call site could break. Moving the bodies here
# dissolves it: the loader decodes, this module analyses, and nothing points
# back. That the cycle existed at all was the code saying the earlier split was
# a file boundary rather than a real one.

# WHY THIS IS A SEPARATE MODULE
#
# These passes were previously called from inside
# Chalk::IR::Serialize::JSON::from_json. They are not deserialization: every
# one of them takes GRAPHS (plus class metadata or the MOP) and none touches
# the JSON. An earlier audit described the arrangement as "an
# iterate-to-fixpoint dataflow analysis smeared across a deserializer".
#
# Extracting them makes the phase boundary explicit: from_json decodes, this
# runs the analysis. The move was verified to be safe before it was attempted:
# no pass mutates the decoded JSON, there is no file-scoped mutable state, and
# nothing reads $data in an order-dependent way. See
# docs/plans/2026-08-24-loader-analysis-pipeline.md, slice 1.
#
# THE PASS ORDER BELOW IS LOAD-BEARING AND IS PRESERVED VERBATIM from the
# original. The comments moved with it. Several orderings encode a fixpoint
# dependency (a caller's type is only knowable once its callee is typed), and
# the sequence was arrived at incrementally against the corpus gate. Do not
# reorder without re-running it.
#
# SCOPE (docs/plans/2026-08-24-loader-analysis-pipeline.md): the loader's job
# is a well-typed Chalk IR and nothing else. These passes currently assign
# REPRESENTATIONS; under the plan they move to the type axis, and the
# vocabulary translation becomes the lowering pass's job. This module is where
# that change will happen.

# run($graphs, $classes) -> \%graphs
#
# $graphs  — hashref of name => Chalk::IR::Graph, freshly deserialized
# $classes — the decoded `classes` section of the wire, or undef
#
# Returns the same graph set (mutated in place, as the passes have always
# done), and nothing else. The MOP is not a second return slot: every graph
# carries it on $g->mop, so a caller reaches it through an edge.
# _ctor_arg_reprs(\%graphs) -> ("class\0param_name" => repr, ...)
# Scan every graph for Call(new) nodes; each binds param_names[i] to inputs[i],
# so it records the repr of the argument passed for each named :param. First
# first construction wins (//=). Two safety constraints the review flagged:
#   (1) DETERMINISM: iterate graphs in a stable (sorted-key) order, so a class
#       constructed more than once with divergent arg reprs resolves the same
#       way every run (the determinism constraint).
#   (2) SAFE REPRS ONLY: infer a field type only for reprs the :param-binding +
#       field-read path actually lowers (Int, Str — proven by field-basic/A5).
#       A Num-looking literal (3.0) whose value is integer would mis-type the
#       field Num and lower into malformed IR (i64 value into a double slot);
#       the constant-DEFAULT path GAPs loudly on Num, so the inference must not
#       be LESS safe. Anything but Int/Str stays uninferred (an honest GAP,
#       exactly as before this inference existed).
my %_INFERABLE_FIELD_REPR = (Int => 1, Str => 1);




# _propagate_computed_reprs(\%graphs) — fixpoint-propagate representations onto
# computed nodes whose inputs are now typed (e.g. a FieldAccess stamped from its
# field type feeds an Add). Mirrors the producer's result-stamp rules so a field
# read flowing into arithmetic carries a repr to the method body root.
my %_COMPUTED_REPR = (
    # A Phi (control-flow value merge) and a TernaryExpr carry the JOIN of their
    # arm reprs -- a merge of two Ints is Int, an Int|Str widens to Str -- the
    # same rule _make_ternary uses. An early-return merged into single-exit
    # (`return X if C`, `E // return X`) reaches the backend as a Region+Phi over
    # the exit values, which the backend cannot lower without an explicit repr.
    # DefinedOr (`$a // $b`) is the same kind of merge: it yields ONE of its two
    # operands, so its repr is their join, exactly as a TernaryExpr's is. It was
    # missing here, so `$a // $b` reached the backend with no representation --
    # invisible while its only consumer was the return epilogue (which reads the
    # repr from elsewhere), and surfacing the moment a Str context needed to
    # coerce it: "Print of a representation-less arg".
    Phi => 'join', TernaryExpr => 'join', DefinedOr => 'join',
    # And (&&) / Or (||) RETURN ONE OF THEIR OPERANDS (`$a && $b` is $a or $b, not
    # a fresh boolean), so the result repr is the JOIN of the operands -- the same
    # rule Phi and TernaryExpr use, because all three are merges of operands.
    #
    # This was 'same' (require the two reprs to agree, yield that repr) because
    # the backend's merge phi is ONE instruction needing ONE machine type, and a
    # mismatched pair could not be lowered at all. It can now: the backend
    # bridges a non-conforming ARM with a coercion to the node's repr, so the
    # join is what tells it WHICH type to bridge to. Measured, 'join' is a strict
    # superset of 'same' here -- it types Boolean&&Boolean -> Boolean and Int&&Int -> Int
    # exactly as before, and additionally types Int&&Str -> Str and
    # Int&&Num -> Num, which 'same' left untyped.
    #
    # Boolean mixed with a chain member (Int&&Boolean, Boolean&&Str) still joins to undef
    # -- Boolean is a sibling of the Int <: Num <: Str chain under Scalar, not a
    # point on it -- and stays a loud GAP, as it did under 'same'.
    And => 'join', Or => 'join',
    Add => 'join', Subtract => 'join', Multiply => 'join', Negate => 'join',
    Divide => 'Num', Power => 'Num', Modulo => 'Int',
    BitAnd => 'Int', BitOr => 'Int', BitXor => 'Int',
    LeftShift => 'Int', RightShift => 'Int', Complement => 'Int',
    Concat => 'Str', Length => 'Int', Count => 'Int',
    # ref($x) reads the type/class name of a reference -- always a Str,
    # regardless of the operand (ref($obj) -> class name, ref([...]) -> "ARRAY").
    RefType => 'Str',
    # Predicates are always Boolean. Defined/Not gate an early-return guard
    # (`E // return X` lowers to If(Not(Defined(E)))); the backend needs an
    # explicit Boolean repr on the If condition to emit an i1 branch.
    (map { $_ => 'Boolean' } qw(
        NumEq NumLt NumGt NumLe NumGe NumNe StrEq StrLt StrGt StrLe StrGe StrNe
        Defined Not)),
    NumCmp => 'Int', StrCmp => 'Int',
);

# Nodes whose OWN repr is fixed by their kind (RC1). A RegexMatch result is a
# boolean whatever it matched.
#
# ArrayLiteral/HashLiteral ARE NOT HERE, and the reason is the whole point of
# the 2026-08-31 producer rename. The op used to be called `ArrayRef`, and this
# table read `ArrayRef => 'ArrayRef'` -- the op name used AS the type. That is
# only correct when the constructor is named for the thing it produces, and it
# is not: one `ArrayLiteral` builds BOTH `[1,2,3]` (a genuine reference,
# stamp=ArrayRef) and `my @a = (10,20,30)` (a plain array, stamp=Array). Seeding
# from the op name stamped every lexical array as a reference.
#
# The producer already sends the right answer on the wire, so there is nothing
# to seed: the literal's repr is whatever its stamp says. The same conflation
# cost 37 corpus spec blocks and one wrong fix of mine on the consumer side, and
# it died loudly in the producer's own code the moment the two strings differed.
my %_SEED_REPR = (
    RegexMatch => 'Boolean',
);

# _insert_str_coercions(\%graphs) — wrap a non-Str operand of a Str-context
# operator in a Coerce(X -> Str).
#
# Print(Str...) and StrEq/StrNe(Str, Str) take Str; a non-Str operand is bridged
# by a coercion rather than the operator learning a representation. The producer
# does this at its build site, but only for an operand that carries a STAMP
# there. A call's return type is not known until the loader resolves the callee
# (`say($c->get)`), so the producer sees an unstamped operand and correctly
# declines to guess — leaving it to arrive here typed.
#
# Runs after every repr fixpoint, the first point the operand's representation
# is known. Idempotent: an operand already produced by a Coerce is skipped, so a
# graph loaded twice does not stack coercions.
# Nodes whose OWN contract fixes an operand repr, independent of any source
# signature. `Print(Str...)` is the standing example: the IR node lowers ONE
# representation and every argument position is Str, while the source builtin
# `print` is variadic over `List` because perl flattens a LIST into it. Those are
# two different claims about two different things -- see the `print @a` case in
# t/corpus/mdtest/statements.md -- so the node contract is stated HERE, on the
# node, and is not sought in TypeLibrary's builtin table.
#
# Everything else asks the signature. This hash exists for genuine node-level
# contracts only; an entry that merely restates a source signature belongs in
# TypeLibrary instead.
my %_NODE_OPERAND_REPR = (Print => 'Str');


# The scalar representations a value can be CONVERTED to, keyed by source repr.
# WHICH COERCIONS EXIST IS A FACT ABOUT PERL, and this table states it. It is
# T1: it models the language, and it must be derivable from perl's behaviour
# alone. Measured on 5.42.0 -- every one of the 16 pairs admitted here is a
# conversion perl performs, and the 4 excluded all share a target, because
# perl has no operation producing undef from a value.
#
# IT MUST NOT BE DEFINED BY WHAT ANY TARGET CAN LOWER. This comment used to
# open "Mirrors the arms _lower_coerce implements (Context.pm)", which made a
# type-system fact answerable by one backend: a target with a missing arm
# would have deleted a legal conversion from the language model, and a second
# target would have had no say at all.
#
# T1 is the CHECKER -- it establishes a well-formed IR and a program as
# type-safe as it can be made, the way TypeScript's checker does. Each T2 is
# a FUNCTOR into a different category: LLVM's machine types today, and a Perl
# target (TypeScript-to-JavaScript) is the obvious second.
#
# AND AN SV IS NOT A TYPE, which is the whole reason this layer exists. An SV
# carries flags for WHICH SLOTS ARE CURRENTLY POPULATED -- IOK, NOK, POK --
# not what the value IS, and they change as the value is used. Measured with
# Devel::Peek on 5.42.0:
#
#     my $x = "5";        SV = PV     FLAGS = (POK, IsCOW, pPOK)
#     my $y = $x + 0;     SV = PVIV   FLAGS = (IOK, POK, IsCOW, pIOK, pPOK)
#
# Same SV, same value, different answer -- reading it numerically populated a
# second slot. So "what type is this SV" has no stable answer at runtime;
# there is a bag of cached interpretations instead. Chalk decides the type
# BEFORE lowering precisely so a target does not have to ask that question,
# and so the answer cannot change underneath it.
#
# A functor into a category that is not total over the source NEED NOT BE
# TOTAL -- we map the arrows we can map. So a coercion this target cannot
# lower is a PARTIALITY to be named, not a defect in T1, and T1 does not get
# edited down to fit it (perigrin, 2026-09-02).
#
# The relationship is still checked -- t/bootstrap/ir/every-legal-coercion-is-
# lowered.t asks the backend, pair by pair, whether each legal coercion has an
# implementation -- but a failure there is a HOLE IN THE TARGET, to be fixed
# in T2, never by editing this table down to fit.
#
# Aggregates (Array/Hash/ArrayRef/HashRef/CodeRef) are deliberately ABSENT: no
# conversion from an aggregate to a scalar repr is defined, so an aggregate in a
# scalar position is a type error to REPORT, not a coercion to invent.
#
# EVERY KEY HERE IS A LATTICE TYPE, and that is a rule rather than an accident.
# This table is T1 -- it reasons about the TYPE axis. `Slot` had a row here
# (Slot => { Str => 1 }) and should never have: `Slot` is not a Chalk type. It
# has no parent, no children and no membership rule; it names the
# { i1 defined, i8 tag, i64 payload } cell that the TYPE `Scalar` encodes as.
# Naming it here was T2 vocabulary leaking into a T1 table, which is the exact
# confusion the functor exists to remove.
#
# The row was also unreachable: measured across every fixture in
# t/bootstrap/ir/data/, `_coercion_exists` is called with `Int` and nothing
# else -- `Slot` never appears as a source, because nothing in lib/ stamps it
# and the wire never carries it (the loader drops a Slot stamp on sight, see
# Serialize/JSON.pm). So removing it changes no behaviour; it removes a claim
# that a repr can be a coercion SOURCE at the type layer.
#
# Pinned by t/bootstrap/ir/no-repr-names-at-t1.t, which fails if a
# representation name reappears in live T1 code.
my %_COERCIBLE_TO = (
    Int   => { Num => 1, Str => 1, Boolean => 1 },
    Num   => { Int => 1, Str => 1, Boolean => 1 },
    # Str -> Int was MISSING while the backend implemented it
    # (Context.pm:2858). perl reads the string as a number and then truncates
    # toward zero -- `int("3.9abc")` is 3 -- so it is Str->Num composed with
    # Num->Int, both of which were already here. Its absence meant the loader
    # declined to insert the Coerce and the operand GAPped downstream for a
    # conversion that works.
    #
    # IT WENT STALE RATHER THAN BEING WRONG WHEN WRITTEN, which is the point.
    # This table was authored 2026-08-26 (f92c6869) and was accurate then. The
    # backend GAINED the Str->Int arm on 2026-08-31 (91d50c1b), added for the
    # %Slot tag dispatch -- reading a cell as Int has to enumerate the Str tag,
    # because the cell may hold one. Nothing linked the two, so one side moved
    # and the other did not. Two days, and the only symptom was a GAP that
    # blamed the wrong layer.
    #
    # Pinned by t/bootstrap/ir/every-legal-coercion-is-lowered.t.
    Str   => { Num => 1, Int => 1, Boolean => 1 },
    Boolean  => { Int => 1, Num => 1, Str => 1 },
    Undef => { Int => 1, Num => 1, Str => 1, Boolean => 1 },

    # SCALAR HAS A TRUTH VALUE, and this row was missing entirely -- Scalar
    # appeared nowhere as a coercion SOURCE, so `_coercion_exists('Scalar',
    # 'Boolean')` was false and `&&`/`||` over a tagged cell refused for want
    # of a conversion T1 said did not exist.
    #
    # It exists. Measured on 5.42.0 across one witness per branch of Scalar --
    # Int, Num, Str, Undef, Boolean and a reference, including the pairs a
    # naive reading gets wrong ("0" is false, "00" is TRUE, "" is false, a ref
    # is true): every inhabitant produces a boolean, and NONE dies doing it.
    # perl's truthiness is total.
    #
    # THE ARGUMENT IS COMPOSITIONAL, which is why only this one target is
    # added. Scalar is the JOIN of the single-value types; every member
    # individually coerces to Boolean (see the four rows above), so the join
    # does too. It is NOT added for Int/Num/Str: narrowing a tagged cell to a
    # specific reading is a different question -- which reading? -- and the
    # honest answer there is still the tag dispatch, not a coercion row.
    #
    # AND IT IS NOT SUBTYPING. Scalar is the PARENT of Str on the lattice;
    # `Scalar <: Boolean` would invert the hierarchy. A coercion says a
    # conversion is DEFINED, not that one type contains the other -- the
    # distinction this table's own header insists on, and the one that
    # `ArrayRef -> Num` (legal, lossy, not a subtype) exists to illustrate.
    # Pinned by t/bootstrap/ir/scalar-has-a-truth-value.t.
    Scalar => { Boolean => 1 },
);

# hydrate($graphs, $classes) -> \%graphs
#
# THE LOADER'S HALF. Replays the wire's raw `classes` records into a sealed MOP
# and attaches it to every graph. This is the only half that needs the raw
# section, and the three field-inference passes run here, BEFORE the seal, for
# a structural reason: field types must land on the records while they are
# still mutable, because MOP::Field has no type setter. They infer ONTO THE
# RECORDS -- construction, not inference over graphs.
sub hydrate ($class, $graphs, $classes = undef) {
    my %graphs = %$graphs;

    # A MOP always exists: a program with no classes still has `main`. The
    # replay below used to be skipped entirely when the wire sent
    # `classes: undef`, which made the MOP an edge that existed for some
    # programs and not others. Normalised once, here, so every pass below sees
    # a hash.
    $classes = {} unless ref $classes eq q{HASH};

    # NO EARLY RESOLVE. This used to run here, BEFORE _attach_call_targets
    # below, so every direct Call reached it with `target` still undef and fell
    # back to the graph-name hash -- measured, exactly once per call, 18 times
    # over the corpus. That fallback was the whole reason the name read
    # survived: the comment in _resolve_direct_calls said it retires "when
    # _attach_call_targets can precede the first resolve", and this call was
    # what stopped it.
    #
    # Measured: deleting it moves nothing (205/205/207/218 before and after).
    # The fixpoint's resolve below does the same work WITH targets attached, so
    # the early pass only ever produced answers the later one recomputes.

    # 4c: a `classes` section (from B::SoN) is replayed into a sealed MOP. Field
    # types must be inferred onto the raw records BEFORE the MOP is sealed, so
    # each declared field carries its type (the backend reads it from the MOP).
    # With an empty $classes the field-inference passes write nothing (their
    # write loops are classes-keyed) and _replay_classes builds the MOP
    # holding just the ADJUST-seeded `main`.

    # A :param field's type comes from the constructor argument.
    _infer_param_field_types($classes, \%graphs);
    # Stamp the field reads that are already typed, then propagate so an
    # ADJUST expression over them (`$val * 2`) carries a repr.
    _stamp_field_access_reprs($classes, \%graphs);
    _seed_and_propagate_reprs(\%graphs);
    # RETIRE THE VACUOUS WIDENINGS FIRST, because the inference below reads a
    # STORED VALUE'S repr and that reading is final -- it is written onto the
    # raw field record, and _replay_classes seals the MOP over it a few lines
    # down. There is no later pass that can move a field's type.
    #
    # Measured on classes.md `adjust`: the ADJUST body is
    # `Multiply(Coerce[Scalar -> Num](FieldAccess(0) :Int), Constant(2) :Int)`.
    # The stamp above already narrowed the field read to Int, which leaves the
    # producer's Coerce converting an Int to a supertype nothing asked for --
    # exactly the vacuous widening _narrow_unknown_coercions was taught to
    # retire. Without the retirement here, Multiply joins to Num, $double is
    # sealed `type: Num`, and `Call(double)` inherits Num where the spec pins
    # Int. The retirement only ever moves a stamp DOWN, so running it earlier
    # cannot widen anything a later pass would have to undo.
    _narrow_unknown_coercions(\%graphs);
    # An ADJUST-only field (no :param, no default) is typed from the value an
    # ADJUST stores into it (Assign(FieldAccess-lvalue, value)). Re-stamp the
    # now-typed field reads (the accessor body's FieldAccess) after.
    if (_infer_field_types_from_stores($classes, \%graphs)) {
        _stamp_field_access_reprs($classes, \%graphs);
    }

    my $mop = _replay_classes($classes, \%graphs);

    # The MOP rides on the IR (spec §6). Every graph in this run points at the
    # SAME sealed MOP, so a transform holding one graph reaches the whole
    # program through an edge instead of a graph-set passed alongside it.
    # Attached here, the first point the MOP is sealed.
    $_->set_mop($mop) for values %graphs;
    # The reverse direction of the same edge (T1 spec §6): a graph reaches the
    # MOP, and the MOP reaches every graph in the unit. Attached HERE, in the
    # loader, so it survives the T1 split -- T1 receives one graph and can
    # still reach its siblings without being handed a set.
    $mop->register_graphs(\%graphs);
    # THE HYDRATION HALF ENDS HERE. Everything above replays the wire's raw
    # `classes` records into a sealed MOP and attaches it to every graph --
    # deserialization, reproducing what the frontend sent. Everything below
    # infers types, and reads the MOP through its protocol rather than the
    # records it was built from (a25cae08), which is what lets the two
    # separate at all.
    return \%graphs;
}

# infer($graphs) -> \%graphs
#
# T1'S HALF. Needs only graphs and the MOP edge they carry -- no raw `classes`
# section, which is why it can run after the seal and, in due course, from a
# single graph's MOP registry rather than a set.
#
# ORDERED, NOT INTERLEAVED (perigrin, 2026-08-31): hydration completes, then
# inference runs and reads the result repeatedly. Reading class structure many
# times is inference doing its job against a finished model, not the two being
# entangled.
sub infer ($class, $graphs) {
    my %graphs = $graphs->%*;
    my ($mop) = grep { defined } map { $_->mop } values %graphs;
    return $graphs unless defined $mop;

    # Attach each resolved direct Call's callee METAOBJECT as soon as the
    # MOP exists. This used to run at the very end of from_json, on the
    # belief that the repr fixpoint below needed to precede it -- measured
    # wrong: _replay_classes seals the MOP ~30 lines BEFORE the direct-call
    # fixpoint, so the metaobject is available to it.
    _attach_call_targets(\%graphs, $mop);

    # Universal repr-inference: seed aggregate/regex reprs and fixpoint-propagate
    # through computed + aggregate-read nodes for EVERY graph (class or not).
    # The backend requires a repr on these nodes to lower them (RC1).
    _seed_and_propagate_reprs(\%graphs);

    # Stamp method Calls from the callee's return_repr, then re-propagate: a Call
    # newly types nodes a computed expression consumes (Add over a method-Call
    # result), which the next propagation resolves. This is a FIXPOINT: a method
    # whose BODY consumes a call (`method use_it { $self->a() + 1 }`) has no
    # return_repr until its internal call is stamped AND its body root re-derived,
    # so a caller of use_it can only be stamped on a LATER pass. Loop stamp +
    # propagate until a pass stamps nothing new (zhi 019f5e57). Bounded by the
    # finite number of Call nodes; a graph with no method Calls converges in one
    # pass (stamped==0 immediately).
    while (_stamp_method_call_reprs(\%graphs, $mop) > 0) {
        _seed_and_propagate_reprs(\%graphs);
    }

    # Direct-call argument binding (F5): a callee's `shift @_` arg-read is typed
    # from the caller's argument repr, then the callee body (and the Call result)
    # re-derive. Fixpoint: a callee reached through a chain is typed once the
    # outer call's arg is known on a prior pass. After seeding, the Call's own
    # result repr is picked up from the callee Return via _resolve_direct_calls'
    # stamp logic, which we re-run to catch calls newly resolvable this pass.
    while (_seed_direct_call_arg_reprs(\%graphs) > 0) {
        _seed_and_propagate_reprs(\%graphs);

        # RETIRE VACUOUS WIDENINGS BEFORE THE CALL IS STAMPED FROM THE CALLEE.
        # The seeding above narrows the callee's argument read (Scalar -> Int),
        # which can leave the producer's Coerce[Scalar -> Num] a no-op over a
        # value already narrower than its target. _resolve_direct_calls stamps
        # the Call from the callee's RETURN, so if that retirement waits until
        # the pass at the end of run(), the callee body settles to Int AFTER
        # every callsite has already taken Num -- measured exactly that way:
        # `Multiply :Int` in main::f with `Call :Num` in the driver, one link
        # apart and both derived from the same edge.
        #
        # The pass is idempotent (it only rebuilds a Coerce whose operand is
        # narrower than its own from_repr, and only retires one whose operand
        # already satisfies the consumer), so running it here does not conflict
        # with the call at the end of run() that narrows what
        # _insert_str_coercions adds later.
        _narrow_unknown_coercions(\%graphs);

        _resolve_direct_calls(\%graphs);

        # A NARROWED BODY MUST CARRY ITS SIGNATURE WITH IT. The method-Call
        # fixpoint above ran BEFORE this one, so a method whose body narrows
        # here (its arg read seeded, its vacuous Coerce retired) was already
        # stamped from the wider reading -- and Target::LLVM emits the callee's
        # signature from the metaobject's return_type while emitting the BODY
        # from the graph. Measured when this was missing: `Counter__inc`
        # emitted `define internal double` over a body whose Add had become
        # i64, and lli refused with "'%tmp_44' defined with type 'i64' but
        # expected 'double'". The two halves of one function disagreed.
        #
        # _stamp_method_call_reprs already reconciles wire against graph and
        # calls set_return_type with the narrower; set_return_type itself only
        # ever narrows and dies on a widening. So re-running it here cannot
        # weaken a type -- it only lets the metaobject catch up to a body this
        # loop just refined.
        _stamp_method_call_reprs(\%graphs, $mop);
    }
    # The loop stamps a Call's result repr in _resolve_direct_calls AFTER the
    # pass's _seed_and_propagate_reprs already ran, so a consumer of the call
    # result (an `$x = foo(5)` Assign) is still untyped when the loop exits. Run
    # one final propagation so the now-stamped Calls flow into their consumers.
    _seed_and_propagate_reprs(\%graphs);

    # 1d: attach the callee METAOBJECT to each resolved direct Call.
    #
    # Call.pm documents `target` as "a MOP::Method/Sub handle ... so codegen can
    # read the callee's graph/params/return-type directly without going through
    # the symbol table at emit time". That is the MOP-shaped contract, and the
    # B::SoN path did not meet it: it set a bare
    # Chalk::IR::Graph, whose own comment explains why -- "a top-level sub is not
    # a MOP class method, so it rides here."
    #
    # Under everything-is-a-class that premise is gone: a file-level sub is a sub
    # of class `main`, and 1a/1b give it a real MOP::Sub. So the callee handle is
    # now available and the flat-graph fallback is no longer the only option.
    #
    # Runs HERE, after _replay_classes has sealed the MOP -- the earlier
    # _resolve_direct_calls passes are part of the repr fixpoint and run before
    # any metaobject exists.

    # Str-context coercions the PRODUCER could not insert. Print(Str...) and
    # StrEq/StrNe(Str, Str) take Str, and the producer wraps a non-Str operand
    # in a Coerce(X -> Str) at its build site -- but only when the operand
    # carries a STAMP there. A method or direct call has no return type until
    # the loader resolves the callee (`say($c->get)`), so the producer sees an
    # unstamped operand, correctly declines to guess, and the operand arrives
    # here typed Int with no coercion in front of it.
    #
    # Runs last, after every repr fixpoint above, because that is the first
    # point the operand's representation is actually known.
    _insert_str_coercions(\%graphs);

    # NARROW the Unknowns. The producer writes from_repr 'Unknown' for a Coerce
    # whose operand it could not type -- honestly, since a direct call's result
    # is not typable until the callee's graph exists. By here every repr
    # fixpoint has run and the operand usually IS typed, so the Coerce can be
    # rebuilt against the narrowed type. Runs last, after _insert_str_coercions,
    # so a coercion inserted there is narrowed too.
    _narrow_unknown_coercions(\%graphs);

    # RECONCILE THE SIGNATURES WITH THE BODIES ONE LAST TIME. The pass above
    # can narrow a METHOD's body -- retiring a vacuous widening inside
    # `method inc { $n += 1 }` moves its Return value from Num to Int -- and it
    # runs after the method-Call fixpoint near the top of run(). Target::LLVM
    # emits a method's SIGNATURE from the metaobject's return_type and its BODY
    # from the graph, so a body narrowed here without a matching signature
    # emits two halves of one function that disagree.
    #
    # Measured when this was missing: `define internal double @Counter__inc`
    # over a body whose Add had become i64, and lli refused the module with
    # "'%tmp_44' defined with type 'i64' but expected 'double'". That is a
    # REFUSAL, not a miscompile -- but the same disagreement one step earlier
    # is how 11.0's bits get read as an i64, which is precisely what
    # ir/call-at-the-abi-unbox-at-the-node.t was written to catch.
    #
    # set_return_type only ever narrows and dies on a widening, so this cannot
    # weaken a type another pass established; it lets the metaobject catch up.
    _stamp_method_call_reprs(\%graphs, $mop);

    # AND ONE MORE NARROWING, because the reconciliation above can move a
    # method Call down (Num -> Int) and everything derived from it with it.
    # A Coerce minted by _insert_str_coercions was stamped from the operand as
    # it stood BEFORE that move, so `Coerce[Num -> Str]` can end up reading an
    # Int. It lowers correctly either way -- _lower_coerce reads the operand's
    # live representation and treats from_repr as a fallback -- but the node
    # misdescribes itself, and the corpus shape leg reads the node.
    #
    # Both passes only ever narrow, so this pair converges rather than
    # oscillating: the second call can only act on what the re-stamp moved,
    # and the re-stamp can only move a stamp DOWN a finite lattice.
    _narrow_unknown_coercions(\%graphs);

    # THE EXIT INVARIANT -- NOT YET ENFORCED. See
    # _assert_value_nodes_are_typed below for why it is off and what has to
    # happen before it can be turned on.
    #
    # _assert_value_nodes_are_typed(\%graphs);

    # The graph set IS the result. $mop is not returned alongside it -- it was
    # attached to every graph above, so a caller wanting the MOP asks a graph
    # for it rather than destructuring a second slot.
    return \%graphs;
}

# run($graphs, $classes) -> \%graphs
#
# THE COMPOSITION, kept so the ~49 existing callers do not move in this commit:
# hydrate-then-infer and nothing else. A caller wanting only a faithful
# reproduction of the wire calls hydrate; T1 calls infer.
sub run ($class, $graphs, $classes = undef) {
    $class->hydrate($graphs, $classes);
    return $class->infer($graphs);
}


# _assert_value_nodes_are_typed($graphs)
#
# THE INVARIANT: a Chalk::IR::Value node has a stamp after analysis. A control
# node does not, and must not -- it defines no value, so there is no type for
# it to carry and asking is a category error.
#
# WHY THIS IS CHECKED HERE rather than in Chalk::IR::Value's ADJUST (which is
# how the PRODUCER enforces the same rule, perl5-son SoN::IR::Value): chalk's
# loader constructs every node first (Serialize/JSON.pm:158) and assigns types
# afterwards (:181 and the passes above). An ADJUST would fire on every node
# before any pass had a chance to type it. The producer can use ADJUST because
# it builds a node only once it knows the value; chalk cannot.
#
# WHY IT MATTERS. Once this holds, `defined $node->representation` STOPS
# DISCRIMINATING for value nodes -- it is always true. The nine guards in the
# loader that use it as "already decided" are then asking a question with a
# fixed answer, and must be re-expressed as `_is_narrowed` (committed to
# something, versus still Unknown).
#
# ============================================================================
# CURRENTLY DISABLED. THE INVARIANT DOES NOT HOLD YET -- and turning this on is
# how we found that out, which is the point of writing it before relying on it.
#
# Enabling it drops the corpus gate 218 -> 200, with 18 cases failing.
#
# THE KIND BREAKDOWN THAT WAS RECORDED HERE WAS WRONG, and the way it was wrong
# is worth keeping. It read:
#
#     Phi 21, ArgsSource 18, PadAccess 12, Call 6, Ref 3
#
# Those counts came from loading whole producer JSON files, which carry the
# producer's OWN internals (B::GV::SAFENAME, B::SoN::_cv_is_user_code,
# Exporter::Heavy, ...) alongside the program under test. They described perl's
# guts, not Chalk's corpus. A follow-up census scoped the way the corpus gate
# scopes -- ProgramRunner's not_package= exclusion list -- found:
#
#     PadAccess   3 of 3   (ALL of them; closed, see _stamp_field_access_reprs)
#     ArgsSource  1 of 1   (the `shift @_` read in a sub with args)
#
# Two kinds, not five. `Phi`, `Call` and `Ref` do not appear in user code at
# all at this sample size. And the cascade that breakdown implied does not
# exist: the DOWNSTREAM count (untyped node with an untyped input) is ZERO --
# every untyped node is its own root, so there is no single hole to find whose
# closure fixes the rest.
#
# An even earlier 7-program census suggested the invariant already held. It did
# not. Between them the lesson is the same twice: a sample that is not scoped
# the way the gate is scoped will mislead in whichever direction it happens to
# be unrepresentative.
#
# MEASURED AGAINST THE FULL 218-CASE CORPUS (2026-08-25), which is what the
# eight-program caveat above asked for. Sixteen untyped Value nodes in total:
#
#     Phi          7   DOWNSTREAM   main::__PROGRAM__
#     ArgsSource   6   root         main::f, main::id
#     Call         2   root         main::__PROGRAM__
#     Ref          1   root         main::__PROGRAM__
#
# So the real work was NINE root nodes in three kinds. The seven Phis are all
# downstream -- untyped because their inputs are -- and should resolve when the
# roots do rather than needing rules of their own.
#
# ARGSSOURCE IS CLOSED (perl5-son 714ec0e), taking 6 of the 9 roots with it.
# Re-measured after: SIXTEEN -> TEN untyped, THREE roots left (Call 2, Ref 1),
# and ArgsSource does not appear at all.
#
# The fix was to stamp `@_` as `Array` at the producer. It defaulted to
# `Unknown`, which claims inference FAILED when nothing had ever asked: `@_` is
# an array of scalars structurally, for every sub, with no inference required.
# (`List` would be one level too wide -- that is the flattening notion, and the
# backend refuses it as signature vocabulary.)
#
# An earlier note here argued AGAINST stamping it, on two grounds. Both were
# wrong, and the record is kept because the reasoning is the reusable part:
#
#   - "Array[Scalar] does not lower, so the stamp is useless." True about the
#     ELEMENT, irrelevant to the CONTAINER. %Array* has had a machine encoding
#     all along, and nothing reads ArgsSource as a value -- `shift` and `$_[0]`
#     mint their own nodes, typed from the callsite. Only `my @a = @_` needs
#     the element type, and that shape stays a GAP.
#   - "It would paper over the real defect: a parameter read should not route
#     through @_ as a MEMORY READ (Parameter.pm)." That defect is real and
#     already fixed for the case it covers -- a signature sub mints Parameter
#     nodes and has no ArgsSource at all. `shift` is not that case: it MUTATES
#     the list, which is a genuine array operation, so ArgsSource is the right
#     node there and typing it is not papering over anything.
#
# THIS IS A REAL GAP IN THE LOADER'S TYPING, not a bad assertion. Each of the
# five is a node that DEFINES a value and reaches lowering with no type, which
# is exactly the GIGO condition the analysis pipeline exists to remove
# (docs/plans/2026-08-24-loader-analysis-pipeline.md). `PadAccess` in a
# `:reader` accessor body is the clearest instance: `Pair::left` returns a pad
# read that nothing types.
#
# TO ENABLE: close the three remaining roots, or narrow the assertion to the
# kinds that are genuinely covered and widen it as each is fixed. PadAccess and
# ArgsSource are closed. Call (2) and Ref (1) are unexamined, and the 7 Phis
# should follow from them without rules of their own -- worth re-measuring
# rather than assuming, since every census this session has corrected the one
# before it.
#
# Do NOT enable it by weakening it to "warn" -- a contract nothing enforces is
# the state this function was written to end.
# ============================================================================
sub _assert_value_nodes_are_typed ($graphs) {
    my @untyped;
    for my $gname (sort keys %$graphs) {
        my $g = $graphs->{$gname} or next;
        for my $node ($g->nodes->@*) {
            next unless $node isa Chalk::IR::Value;
            next if defined $node->stamp;
            push @untyped, sprintf('%s in %s (%s)',
                $node->operation, $gname, $node->id);
            last if @untyped >= 5;   # naming five is enough to diagnose
        }
        last if @untyped >= 5;
    }
    return unless @untyped;

    die "IR: analysis finished with untyped Value node(s) -- every node that "
      . "DEFINES a value must carry a type by the end of the pipeline, so "
      . "lowering can rely on it: @untyped\n";
}

# _is_narrowed($repr) — has this node COMMITTED to a representation?
#
# Not the same question as `defined $repr`, and the difference is the whole
# reason this exists. `Unknown` is how the producer says it could not type a
# value; it is a present answer that answers nothing. A pass asking "was this
# already decided, so I should leave it alone?" must say no to it.
#
# The two spellings agree today only because the wire-stamp seed below gates on
# %LOWERABLE_STAMP, which drops `Unknown` and leaves the field undef. That gate
# is removed in slice 3b (docs/plans/2026-08-24-loader-analysis-pipeline.md),
# at which point `defined` would start reading the producer's admission of
# ignorance as a committed type -- silently, since every such guard would just
# stop doing its work. The measured casualty is the OOB->Slot fix below: it
# would stop firing and corpus R9 would miscompile.
#
# The producer draws the same line (perl5-son FromOptree.pm:3100). It holds a
# Stamp object and so tests `$stamp->type ne 'Unknown'`; this field holds a
# plain string, so the test is against the string. If the field ever becomes a
# Stamp here too, this is the one site that changes.
# `Scalar` IS REFINABLE, and is excluded for the same reason `Unknown` is
# (2026-08-29). Both are answers that commit to nothing: `Unknown` is the
# lattice top, `Scalar` the top of the SCALAR SPINE -- what the join yields when
# nothing narrower was proven. A guard asking "was this already decided, so
# leave it alone?" must say no to both.
#
# This became live rather than theoretical when the producer started shipping
# `Scalar` for every un-narrowable Subscript (perl5-son 8c15e32: a subscript
# reads ONE slot, and one slot holds a scalar). Before that nothing produced a
# `Scalar` stamp, which is why Phase 3's G5 measured ZERO instances of the
# hazard and could not reproduce it. With it treated as committed, the three
# fixpoint guards (:1150, :1249, :1826) skip such a node PERMANENTLY and it can
# never reach `Int` even where the graph proves it.
#
# TERMINATION IS PRESERVED, which matters because this sub is the fixpoint's
# latch (pinned by ir/propagate-fixpoint-terminates.t, and Phase 3 proved that
# loosening it to "re-stamp whenever something changed" hangs the loop). The
# exemption is not that loosening: a refinement from `Scalar` is strictly
# DOWNWARD along a finite spine -- Scalar -> Str -> Num -> Int, at most three
# steps -- and every landing point IS a commitment, so the node stops being
# revisited. Pinned by ir/scalar-is-refinable.t.
sub _is_narrowed ($repr) {
    return false if !defined $repr;
    return false if $repr eq 'Unknown' || $repr eq 'Scalar';
    return true;
}

# -----------------------------------------------------------------------
# _resolve_direct_calls(\%graphs) — attach each direct sub call's callee graph.
# A Call with dispatch_kind='direct' names its callee (fully-qualified, e.g.
# main::foo); resolve that name against the loaded graph set and stash the graph
# so the Call's repr can be stamped from the callee's Return value. Calls
# whose name has no matching graph (builtins, unresolved) are left as-is.
# _all_graph_nodes($g) -> ($g->nodes PLUS control-chain nodes), deduped by id.
# $g->nodes walks inputs from the returns' value only, so a Call embedded in an
# if CONDITION (`if (($x = foo(1)) == 1)`) -- reached via control_in, not the
# Return value chain -- is absent. The call-stamping passes must see it to type
# the Call result (and thus the `$x = foo(1)` Assign consuming it).
sub _all_graph_nodes ($g) {
    my %seen;
    my @out;
    for my $n ($g->nodes->@*, _control_chain_nodes($g)) {
        next unless blessed($n);
        push @out, $n unless $seen{ $n->id }++;
    }
    return @out;
}

# _attach_call_targets(\%graphs, $mop, $classes) — give each resolved direct Call its
# callee METAOBJECT.
#
# The MOP is Chalk's deliberate divergence from classic Sea of Nodes: a flat
# graph dissolves declarations into itself, while Chalk keeps metaobjects
# alongside so a consumer can ASK rather than pattern-match. Every sub-level
# scan in this file exists because the B::SoN path skipped that layer.
#
# Keyed by the callee's fully-qualified name (`main::f`), which is how the
# producer names the graph and how declare_sub records the metaobject.
sub _attach_call_targets ($graphs, $mop) {
    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && $node->can('set_target')
                && !defined $node->target;

            my $kind = $node->dispatch_kind // '';

            # METHOD dispatch. The Call already knows its statically-resolved
            # class; the method itself is found by asking the CLASS, whose
            # find_method walks the superclass chain -- so an inherited call
            # lands on the DECLARING class's metaobject. Chalk::MOP::find_method
            # would answer too, but by scanning `values %classes` in hash order
            # and returning the first name match: a guess, not a resolution.
            #
            # `new` is the backend-synthesized constructor -- no metaobject
            # exists for it -- and a `:reader` accessor is synthesized too. Both
            # are legitimately target-less; only a genuine method resolves here.
            if ($kind eq 'method') {
                my $cls = defined $node->class_name
                    ? $mop->for_class($node->class_name) : undef;
                my $m = $cls ? $cls->find_method($node->name // '') : undef;
                $node->set_target($m) if $m;
                next;
            }

            next unless $kind eq 'direct';

            my ($cls_name, $sub_name) = ($node->name // '') =~ /^(.*)::([^:]+)$/;
            my $cls = defined $cls_name ? $mop->for_class($cls_name) : undef;
            my ($sub) = $cls
                ? (grep { $_->name eq $sub_name } $cls->subs)
                : ();

            if ($sub) {
                $node->set_target($sub);
                next;
            }

            # NO METAOBJECT. That is fine for a genuinely unresolvable callee (a
            # builtin, or a package outside the emission filter) -- those have no
            # graph either, and the backend's own GAP names them.
            #
            # But a callee with a resolved GRAPH and no metaobject is a
            # DISAGREEMENT between the two halves of the wire, and it is
            # reachable: the producer writes $graphs->{$full_name}
            # UNCONDITIONALLY and only then calls _record_sub, which returns
            # early for a `method` CV and for a `:reader` accessor. Measured --
            # `Widget::go($w)` on a class method gives rg=SET, target=UNDEF.
            #
            # The backend now resolves THROUGH the metaobject, so this would
            # surface there as "an unknown or builtin sub" -- actively wrong,
            # since the sub is neither. Say what is really true, here, where both
            # facts are in hand.
            # NO METAOBJECT. Quiet for a callee that is not the program's own
            # code -- a builtin, or an ambient module sub perl loaded along the
            # way (Carp::ret_summary and friends have a graph but deliberately
            # no sub record: B::SoN keys that on CV->FILE eq $0). Those simply
            # are not callable here, and the backend's own GAP says so.
            #
            # LOUD when the class IS in the MOP but the sub is not: that is a
            # genuine disagreement between the two halves of the wire, and it is
            # reachable -- the producer writes the graph unconditionally, then
            # _record_sub returns early for a `method` CV and for a `:reader`
            # accessor. Measured: `Widget::go($w)` on a class method gives a
            # graph with no metaobject. Resolving through the metaobject would
            # otherwise report "an unknown or builtin sub", which is wrong.
            die "GAP: direct call to '" . ($node->name // '?') . "' names class "
              . "'$cls_name', which IS in the MOP, but no sub '$sub_name' is "
              . "recorded on it. A `method` or `:reader` CV is emitted as a "
              . "graph but deliberately not recorded as a sub "
              . "(B::SoN::_record_sub's early returns), so it cannot be called "
              . "in sub form."
                #
                # `$mop->was_declared` is load-bearing: Chalk::MOP's
                # ADJUST seeds class `main` on EVERY load, so its presence in
                # the MOP is NOT evidence the wire declared it. Without this,
                # a wire carrying subs and no `classes` key (the two are
                # independent) made every top-level sub call look like a class
                # contradicting itself, and the loader died on a program shape
                # it had loaded a commit earlier. Only a class the wire
                # actually DECLARED can contradict itself.
                if $cls
                && $mop->was_declared($cls_name)
                && exists $graphs->{ $node->name // '' };
        }
    }
    return;
}

# return_reading_for_want($return, $want) -> the input a callsite takes
#
# A list-returning sub carries TWO readings, because it is compiled once and
# cannot see its caller's context: perl leaves entersub's context slot empty
# for a call in last-operand position, which is the same fact that makes
# `wantarray` a runtime function.
#
#   Return inputs[0]   the LIST reading: all N values
#   Return inputs[1]   the SCALAR reading, or absent
#
# The producer has already applied the collapse rule, so the whole job here is
# picking the slot. THE RULE IS NOT "last element" AND NOT "count" -- measured
# against perl 5.42.0:
#
#   sub lit { return (10,20,30) }             my $s = lit()  -> 30
#   sub agg { my @a=(10,20,30); return @a }   my $s = agg()  ->  3
#   sub mix { my @x=(10,20); return (99,@x) } my $s = mix()  ->  2
#
# `mix` discriminates: the last ELEMENT of the flattened list is 20 where perl
# says 2. It is the comma operator's rule -- the last OPERAND read in scalar
# context, recursively -- and getting it wrong here would be a well-formed
# graph computing a wrong number.
#
# AN UNDEF $want IS A REAL STATE, NOT MISSING DATA. It means perl left the
# context slot empty (the last-operand case, whose context arrives at runtime
# from the caller's frame), so it must not be read as "scalar". The LIST
# reading is the sound default: it carries all N values, so nothing a later
# collapse needs has been discarded.
#
# A callee with only ONE reading answers every context from it -- `return @a`
# needs no second face, because the container already answers both readings
# (its scalar reading is its length).
sub return_reading_for_want ($return, $want) {
    return undef unless defined $return;

    my $list_reading = $return->value();

    return $list_reading unless defined $want && $want eq 'scalar';

    my $scalar_reading = $return->can('scalar_value')
        ? $return->scalar_value()
        : undef;

    return defined $scalar_reading ? $scalar_reading : $list_reading;
}

sub _resolve_direct_calls ($graphs) {
    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && ($node->dispatch_kind // '') eq 'direct';
            # THE EDGE FIRST. `target` is the callee metaobject and it holds
            # the callee graph -- the same object the name lookup returns
            # (asserted by refaddr in ir/resolve-direct-calls-reads-the-edge.t),
            # reached without the Map<String,Graph> the T1 contract retires.
            #
            # The name read stays as the PRE-MOP BOOTSTRAP, and only that.
            # `run` calls this pass twice; the first call precedes
            # _attach_call_targets (which cannot run before _replay_classes
            # seals the MOP), so at that call every direct Call has `target`
            # undef. Measured: that first pass is where most direct-call result
            # stamps come from, and ir/llvm-class-sub-define.t fails without
            # it. The name read retires when _attach_call_targets can precede
            # the first resolve.
            my $callee
                = ( $node->can('target')
                    && $node->target
                    && $node->target->can('graph')
                    && $node->target->graph )
                or next;

            # Stamp the Call's repr from the callee's Return value, so the
            # backend and the shape contract see the call result's type. The
            # callee's single Return input[-1] is its result value.
            # THE CALLEE'S RETURN IS THE AUTHORITATIVE SOURCE for a direct
            # call's type, so this runs even when the Call already carries a
            # stamp -- but only ever to move it DOWN the lattice, to a strict
            # subtype of what it holds.
            #
            # An `unless (_is_narrowed(...))` guard here froze the FIRST answer.
            # This pass runs inside a fixpoint whose earlier rounds narrow the
            # callee's own body (a `shift @_` read seeded from the callsite,
            # then a vacuous Coerce retired above it), so the first round stamps
            # from a callee that has not settled yet. Measured on F5's fixture:
            # main::f's body reached `Add :Int` while its one callsite still
            # read `Call :Num`, one link apart, both derived from the same
            # retired edge -- and the corpus specs for nine cases pin the Int.
            #
            # DOWNWARD ONLY, and that is what keeps this from being the
            # "preempt a source" mistake. A Call is not typed by its consumer
            # here; it is typed by its own callee, which the type rules already
            # name as its authority. Refusing to move sideways or up means a
            # callee that legitimately widens (a second callsite forcing a join)
            # cannot be silently overwritten by a stale narrower reading.
            my ($ret) = grep {
                blessed($_) && $_->can('operation')
                    && $_->operation eq 'Return'
            } $callee->returns->@*;
            # ->value() is inputs[0]. Reading [-1] stamped every
            # list-returning sub's callsites from its SCALAR face --
            # the same bug bson hit in _graph_return_type (7b26a89).
            my $val = $ret ? $ret->value() : undef;
            if ($val && _is_narrowed($val->representation)) {
                my $have = $node->representation;
                my $want = $val->representation;
                $node->set_representation($want)
                    if !_is_narrowed($have)
                    || ($have ne $want
                        && Chalk::Grammar::Perl::TypeLibrary::is_subtype($want, $have));
            }
        }
    }
    return;
}

# -----------------------------------------------------------------------
# _seed_direct_call_arg_reprs(\%graphs) -> count of nodes newly stamped.
#
# A callee compiled in isolation reads its Nth positional argument via a
# `shift @_` (Call(builtin,shift) over ArgsSource), which has no type on
# its own -- so an expression over it (`shift + 1`) stays untyped and the
# backend's NO-REPR guard would fire. The type is known at the CALL site: it is
# the argument's repr. Stamp the callee's single `shift @_` read with the
# resolved call's argument repr so the universal propagation carries the type
# into the callee body (and then to the Call result via _resolve_direct_calls'
# return-value stamp). Only the sound single-`shift`, single-argument shape is
# seeded (the backend inlines exactly that shape; other @_ shapes GAP there).
# Run inside the repr fixpoint: a callee-of-a-callee is typed once its own
# callee's shift is stamped on a prior pass.
# _arg_is_self_call($arg, $callee) -> bool. Is this argument the RESULT of a
# direct call into $callee itself? Then its repr is $callee's own return type,
# not an independent measurement of what a caller passes in, and seeding
# $callee's argument read from it closes a cycle. `f(f(1))` is the shape.
#
# Compared by graph identity (refaddr), not by name: the callee handle is the
# one the loader resolved for both Calls, so the same sub is the same object.
sub _arg_is_self_call ($arg, $callee) {
    return false unless blessed($arg) && $arg->operation eq 'Call';
    return false unless $arg->can('dispatch_kind')
        && ($arg->dispatch_kind // '') eq 'direct';
    return false unless $arg->can('target') && $arg->target;
    my $arg_callee = $arg->target->graph or return false;
    return refaddr($arg_callee) == refaddr($callee) ? true : false;
}

sub _seed_direct_call_arg_reprs ($graphs) {
    my $stamped = 0;

    # GATHER, then stamp. The callee's argument read is ONE node shared by
    # every callsite, so it can carry only one stamp and that stamp has to be
    # true of every value that reaches it. Stamping inline made it whichever
    # callsite the walk happened to reach first: measured on
    # `sub g { my $x = shift; return $x } g(1); g("hello")`, source order
    # alone selected between two different wrong answers -- the reversed order
    # stamped the read `Int` and left the Str-argument Call carrying an Int
    # stamp, which is the unsound direction.
    #
    # So the sweep below only COLLECTS: read node => the reprs arriving at it,
    # keyed by refaddr because the read is a shared singleton reached through
    # `$node->target->graph`. The join and the single stamp happen after.
    #
    # TERMINATION. `_is_narrowed` is this fixpoint's termination latch (pinned
    # by ir/is-narrowed-guards.t and ir/propagate-fixpoint-terminates.t), and
    # loosening it to "re-stamp whenever something changed" is what hangs the
    # loop. What replaces it here is not looser: the existing stamp is folded
    # INTO the join, so a stamp only ever moves UP the lattice, and the
    # lattice is finite with `Unknown` at the top. A node can therefore be
    # re-stamped only finitely often, and `$stamped` counts only real moves.
    my %pending;    # refaddr(read) => { node => $n, reprs => [...], self => [...] }

    # $self_arm marks an arm whose repr is NOT an independent measurement: the
    # argument at that callsite is a direct Call into the very callee whose
    # argument read we are seeding, so its stamp IS that callee's return type,
    # which this seed is in the middle of deriving. See the join below.
    my $collect = sub ($read, $repr, $self_arm = false) {
        my $slot = $pending{ refaddr($read) }
            //= { node => $read, reprs => [], self => [] };
        push $slot->{ $self_arm ? 'self' : 'reprs' }->@*, $repr;
        return;
    };

    for my $gname (sort keys $graphs->%*) {
        for my $node (_all_graph_nodes($graphs->{$gname})) {
            next unless $node->operation eq 'Call'
                && $node->can('dispatch_kind')
                && ($node->dispatch_kind // '') eq 'direct'
                && $node->can('target') && $node->target;
            my @args = grep { blessed($_) } $node->inputs->@*;
            next unless @args;

            # Find the callee's single positional argument read: either a
            # `shift @_` (Call builtin shift over ArgsSource) or a `$_[0]`
            # subscript (Subscript over Constant("_") at index 0). Both bind the
            # first argument; stamp whichever the callee uses.
            my $callee = $node->target->graph;

            # A DECLARED SIGNATURE stamps by INDEX, and is not capped at one
            # argument the way the `shift @_` / `$_[0]` recovery paths below
            # are. Those cap at one because multiple shifts hash-cons to a
            # single node and lose their order; a Parameter carries its index,
            # so parameter N pairs with argument N by construction.
            my %params;
            for my $n ($callee->nodes->@*) {
                next unless blessed($n) && $n->operation eq 'Parameter';
                $params{ $n->index } = $n;
            }
            if (%params) {
                for my $i ( sort { $a <=> $b } keys %params ) {
                    # A parameter with no matching argument is an arity
                    # mismatch; leave it untyped and let the backend GAP
                    # against the operation that needed a type, rather than
                    # guessing here.
                    my $arg = $args[$i] or next;
                    my $repr = $arg->representation // next;
                    $collect->( $params{$i}, $repr,
                        _arg_is_self_call( $arg, $callee ) );
                }
                next;
            }

            my @reads = grep {
                my $n = $_;
                blessed($n) && $n->operation eq 'Call'
                    && $n->can('dispatch_kind')
                    && ($n->dispatch_kind // '') eq 'builtin'
                    && defined $n->name && $n->name eq 'shift'
                    && do {
                        my ($op) = grep { blessed($_) } $n->inputs->@*;
                        $op && $op->operation eq 'ArgsSource';
                    };
            } $callee->nodes->@*;
            unless (@reads) {
                # `$_[0]`: Subscript(ArgsSource, Constant(0), Mem).
                #
                # The container used to be a string Constant("_") -- the array
                # spelled as its own NAME -- so this had to match a literal.
                # With @_ as a node kind the container is simply that node.
                @reads = grep {
                    my $n = $_;
                    blessed($n) && $n->operation eq 'Subscript' && do {
                        my ($c, $i) = grep { blessed($_) } $n->inputs->@*;
                        $c && $c->operation eq 'ArgsSource'
                            && $i && $i->operation eq 'Constant' && $i->can('value')
                            && defined $i->value && $i->value eq '0';
                    };
                } $callee->nodes->@*;
            }
            next unless @reads == 1 && @args == 1;

            my $arg_repr = $args[0]->representation // next;
            $collect->( $reads[0], $arg_repr,
                _arg_is_self_call( $args[0], $callee ) );
        }
    }

    # JOIN, then stamp once. The read's existing stamp joins in as another
    # arm, so this is monotone: the answer is always a supertype of what was
    # there. `_join_repr` is the lattice authority (TypeLibrary::join_types
    # folded), which is what makes `Int` and `Str` arrive at `Str` rather than
    # at whichever the walk saw first.
    #
    # Sorted by node id so the traversal order of `%pending` cannot reach the
    # output -- determinism, and the thing the order-independence assertion in
    # ir/direct-call-args-join-all-callsites.t pins.
    for my $slot (
        sort { $a->{node}->id cmp $b->{node}->id } values %pending )
    {
        my $read = $slot->{node};
        my $existing = $read->representation;

        # A SELF-REFERENTIAL ARM IS NOT A SECOND CALLER'S MEASUREMENT. In
        # `f(f(1))` both callsites bind the SAME read: the inner passes
        # Constant(1) :Int, the outer passes the inner Call, whose stamp is
        # f's own return type. Joining them makes the read a function of
        # itself -- the outer arm is Num (the producer's honest widening of
        # an unresolved return), join(Int, Num) = Num, the body stays Num, the
        # inner Call is stamped Num from that body, and the next round joins
        # the same Num. The cycle is stable at the pessimistic answer and
        # nothing in the loop can descend out of it. Measured on subs.md F15:
        # every pass held `Call :Num  Call :Num  shift :Num`.
        #
        # So a self arm is DEFERRED, not dropped: it is used only when it is
        # the sole evidence (a genuinely recursive `sub f { f($n) }`, where
        # there is no independent caller and the widened reading is the only
        # honest answer). Once an independent arm exists, the read settles from
        # it, the body re-derives, and _resolve_direct_calls carries the
        # narrowed return to BOTH Calls -- the inner and the outer alike, which
        # is why the outer never needed its own arm.
        #
        # SOUNDNESS. Dropping an arm is the direction that could under-widen,
        # so it is worth being exact about why it cannot here: the omitted arm
        # is not a value flowing in from outside, it is this read's own answer
        # travelling around a cycle. Whatever the read settles to, the callee
        # returns a function of it, and that is what the outer call passes
        # back in -- so the arm is subsumed by the fixpoint rather than
        # ignored by it. The stamp is still checked against the callee on the
        # next round, and `_resolve_direct_calls` will only ever move a Call
        # DOWN, so an arm that genuinely demanded a wider read would leave the
        # Call unable to narrow rather than silently narrowing it.
        #
        # This is still FORWARD inference: the read is typed from its callers'
        # arguments, exactly as before. All that changed is which arms count as
        # a caller's independent argument.
        my @arms = $slot->{reprs}->@*;
        @arms = $slot->{self}->@* unless @arms;

        # TWO QUESTIONS, TWO OPERATORS. Both arms went through _join_repr,
        # which is right for one of them and wrong for the other.
        #
        #   ACROSS CALLSITES -- join. The read is ONE node shared by every
        #   caller, so its stamp must be true of all of them: `g(1); g("hello")`
        #   makes it Str, and anything narrower is unsound for one caller.
        #
        #   AGAINST THE PRIOR STAMP -- meet. That is not a caller. `Scalar` on
        #   a `shift @_` read records that NOTHING NARROWED IT YET, and
        #   join(Scalar, Int) = Scalar, so an absence of evidence outranked a
        #   measurement. The read never moved; the producer's
        #   Coerce[Scalar -> Num] stood; Add(Num, Int) joined to Num; and
        #   `sub f { my $x = shift; $x + 1 }` called once as f(10) returned Num
        #   where the corpus spec says Int. Int <: Num and the only call is
        #   f(Int), so f : Int -> Int (perigrin).
        my $from_sites = _join_repr(@arms);
        next unless defined $from_sites;

        # TERMINATION, and why this does not oscillate. The old comment named
        # folding $existing into the JOIN as this fixpoint's latch: stamps only
        # climb, the lattice is finite, so a node re-stamps finitely often.
        # Meeting descends instead, and mixing directions is how a fixpoint
        # alternates -- so the descent needs its own argument, not the absence
        # of the old one.
        #
        # It is BackwardInference's, already in the tree: fold the node's own
        # stamp INTO the meet, "so a later round cannot move the stamp
        # SIDEWAYS between two incomparable types and the loop need never
        # settle". `meet` is monotone downward over a finite lattice, `None` is
        # its bottom, and the `eq` guard below still refuses a no-op re-stamp,
        # so `$stamped` counts only real moves.
        my $narrowed = defined $existing
            ? Chalk::Grammar::Perl::TypeLibrary::meet_types($existing, $from_sites)
            : $from_sites;

        # `None` means the two are unrelated -- the prior stamp and the
        # callsites disagree with neither refining the other. That is a real
        # defect somewhere upstream, not something to paper over by picking
        # one; leave the stamp alone and let the backend GAP on whatever
        # consumes it.
        next unless defined $narrowed && $narrowed ne 'None';
        my $joined = $narrowed;

        # Only a real move counts. `$stamped` drives the caller's `while`, so
        # returning a nonzero for a no-op re-stamp is what would spin it.
        next if defined $existing && $existing eq $joined;
        $read->set_representation($joined);
        $stamped++;
    }

    return $stamped;
}

# _coercion_exists($from, $to) -> bool. Is this conversion defined at all?
sub _coercion_exists ($from, $to) {
    return false if !defined $from || !defined $to;
    return ($_COERCIBLE_TO{$from} && $_COERCIBLE_TO{$from}{$to}) ? true : false;
}

# _required_operand_repr($op, $position) -> repr, or undef for "no opinion".
#
# The node's own contract first, then the source signature. A position with no
# answer is left alone: a missed coercion GAPs loudly downstream, whereas a
# guessed one is a silent wrong answer.
sub _required_operand_repr ($op, $position) {
    return $_NODE_OPERAND_REPR{$op}
        if exists $_NODE_OPERAND_REPR{$op};
    return Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op($op, $position);
}

sub _insert_str_coercions ($graphs) {
    my $inserted = 0;
    # Its own factory: _deserialize_graph's is per-graph and not retained, and a
    # node's identity is its content hash, so nodes minted here are consistent
    # with the ones already in the graph.
    my $factory = Chalk::IR::NodeFactory->new();
    for my $name (sort keys %$graphs) {
        my $g = $graphs->{$name} or next;
        for my $node (_all_graph_nodes($g)) {
            next unless $node->can('operation');
            my $op = $node->operation;
            my $inputs = $node->inputs // next;
            for my $i (0 .. $inputs->$#*) {
                # Asked PER POSITION, because signatures are per position --
                # `substr(Str, Num, Num)` wants different types at different
                # operands, which a whole-node flag cannot express.
                my $want = _required_operand_repr($op, $i) // next;

                my $in = $inputs->[$i];
                next unless defined $in && ref $in && ref($in) ne 'ARRAY';
                next unless $in->can('representation');
                my $repr = $in->representation;
                # undef repr: nothing established a type, so a coercion here
                # would be the guess the producer already declined to make.
                # The backend reports it against the operator, which names the
                # node that actually needs a type.
                next unless defined $repr;
                next if $repr eq $want;
                next if $in->isa('Chalk::IR::Node::Coerce');

                # A position that accepts a SET takes this repr as-is.
                next if Chalk::Grammar::Perl::TypeLibrary::accepts_operand_repr($op, $repr);

                # A COERCION IS A CONVERSION, NOT A SUBSUMPTION. Whether one
                # exists is a question about the PAIR -- is this conversion
                # defined? -- and NOT a question about the lattice. Int->Str is
                # legitimate because stringification is defined for an Int, not
                # because Int <: Str; Boolean->Str is equally legitimate even
                # though Boolean is a SIBLING of Str under Scalar and no subtype
                # relation holds in either direction.
                #
                # Keying this on subtyping was wrong twice over, both measured:
                # requiring `is_subtype($repr, $want)` un-lowered six cases
                # whose Boolean/Slot operands print perfectly well, and exempting
                # Str wholesale then un-lowered eight more by stringifying the
                # ArrayRef operand of `scalar @a`.
                #
                # The defined pairs are the ones _lower_coerce implements
                # (Context.pm _lower_coerce): Int<->Num, anything->Boolean,
                # Boolean->Num/Int, Undef->Int/Num, scalars->Str, Str->Num/Boolean.
                # Aggregates appear in NONE of them -- an ArrayRef reaching a
                # scalar position is a type error to report, not a missing
                # conversion to invent.
                next unless _coercion_exists($repr, $want);

                my $c = $factory->make('Coerce',
                    inputs    => [$in],
                    from_repr => $repr,
                    to_repr   => $want,
                );
                $c->set_representation($want);
                $inputs->[$i] = $c;
                $inserted++;
            }
        }
    }
    return $inserted;
}

# _narrow_unknown_coercions(\%graphs) -> count of Coerce nodes narrowed.
#
# A Coerce carrying from_repr 'Unknown' is a coercion whose SOURCE type was not
# determined when the node was built. 'Unknown' is the pessimistic top type
# (TypeScript's `unknown`, not its `any`): it holds any value but obliges the
# holder to NARROW it before use. This is that narrowing.
#
# The producer writes it for an unstamped operand, which is honest at its stage
# -- a direct call's result cannot be typed while the callee's graph may not
# exist yet. By the time this runs every repr fixpoint has completed and the
# operand usually carries a concrete repr, so the Coerce is REBUILT against it.
#
# Rebuilt, not mutated: from_repr is part of Coerce's content_hash (per
# typed-ir-representation.md, Coerce[Str->Num](x) and Coerce[Int->Num](x) are
# distinct nodes), so narrowing changes the node's IDENTITY. Mutating in place
# would leave a node whose hash no longer matches its contents, which breaks
# hash-consing. The consumer's input slot is repointed and the old Coerce is
# removed from its operand's consumer list, so no orphan is left listed as a
# reader of a node it no longer reads.
#
# An Unknown that CANNOT be narrowed is left alone deliberately: the backend
# then reports it as an inference failure naming the operand, which is the
# whole point of distinguishing Unknown from Scalar. A Scalar GAP means "this
# scalar type is not lowered"; an Unknown GAP means "nothing ever typed this".
sub _narrow_unknown_coercions ($graphs) {
    my $narrowed = 0;
    my $factory  = Chalk::IR::NodeFactory->new();
    my @stale;      # consumers whose stamp was derived from a retired coercion

    for my $name (sort keys %$graphs) {
        my $g = $graphs->{$name} or next;
        for my $node (_all_graph_nodes($g)) {
            my $inputs = ($node->can('inputs') ? $node->inputs : undef) or next;

            for my $i (0 .. $inputs->$#*) {
                my $c = $inputs->[$i];
                # NOT just 'Unknown'. `Scalar` is equally un-narrowed -- the
                # top of the scalar spine, which has no single machine reading
                # -- and the producer emits Coerce[Scalar -> Num] directly for
                # a :param field's :reader. Narrowing only Unknown left every
                # such node to die in the backend for want of a Scalar arm.
                # _is_narrowed states the rule; both callers now use it.
                next unless blessed($c) && $c->isa('Chalk::IR::Node::Coerce');

                my $operand = ($c->inputs // [])->[0];
                next unless blessed($operand) && $operand->can('representation');
                my $repr = $operand->representation;

                # A STALE `from_repr` IS ALSO UN-NARROWED, even when it names a
                # real type. The gate here used to be `!_is_narrowed(from_repr)`
                # -- Unknown or Scalar only -- which is right for the case that
                # named this pass, but it skips a Coerce whose from_repr was
                # accurate when the producer wrote it and has since been
                # OUTRUN by its own operand. Measured on classes.md field-attrs:
                # the operand narrowed Num -> Int when the vacuous widenings
                # below it were retired, leaving `Coerce[Num -> Str]` reading an
                # Int. It lowers correctly (_lower_coerce reads the operand's
                # live representation and treats from_repr as a fallback), so
                # this is not a miscompile -- but the node then MISDESCRIBES
                # itself, and the corpus shape leg reads the node, so the spec's
                # `Coerce(Int -> Str)` could not match.
                #
                # Rebuilding is the same operation either way: mint a Coerce
                # whose from_repr is what the operand actually is.
                next if _is_narrowed($c->from_repr)
                    && defined $repr
                    && $repr eq $c->from_repr;

                # Still untyped: leave the Unknown in place so the backend can
                # report it. Narrowing to a guess here would recreate exactly
                # the bug this replaced.
                #
                # `Scalar` IS AN ANSWER HERE, though `_is_narrowed` says
                # otherwise -- and the difference matters. That predicate is a
                # FIXPOINT TERMINATION LATCH: it asks "could this stamp still
                # move?", and Scalar could, so it answers false. This site asks
                # a different question -- "do we know what the operand is?" --
                # and for a tagged cell we do: Scalar is a measured type with a
                # machine encoding (%Slot) and real coercions out of it
                # (Scalar -> Boolean, added when && over a tagged cell was
                # unblocked).
                #
                # Measured on logical.md L5d: the And's operand is Scalar and
                # its Coerce kept `from_repr=Unknown`, so the node MISDESCRIBED
                # itself and the corpus spec could not match. Not a miscompile
                # -- _lower_coerce reads the operand's live representation and
                # treats from_repr as a fallback -- but a node whose recorded
                # type disagrees with its operand is exactly what the shape leg
                # exists to catch.
                next unless _is_narrowed($repr)
                         || (defined $repr && $repr eq 'Scalar');

                # The operand is ALREADY the target type: the coercion is an
                # identity edge and the consumer can read the operand directly.
                #
                # ALSO RETIRED: a VACUOUS WIDENING. Once the operand narrows to
                # a SUBTYPE of the target and the consumer requires no
                # particular type at this position, the coercion converts a
                # value to a supertype nothing asked for -- and the result is
                # not merely redundant, it is WRONG on the type axis, because
                # the widened repr propagates. Measured on
                # `sub f { my $x = shift; $x * 2 }; f(10)`: the producer cannot
                # type `shift @_` so it emits Coerce[Scalar -> Num];
                # _seed_direct_call_arg_reprs then narrows the read to Int and
                # this pass rebuilt the node as Coerce[Int -> Num], leaving the
                # TARGET alone. Multiply(Num, Int) then joined to Num and every
                # callsite of f inherited Num where the corpus specs pin Int --
                # nine shape failures from one surviving edge (commit 92ffe890
                # diagnosed this and deferred it as "the functor's identity law,
                # unenforced").
                #
                # ONLY when the consumer requires nothing. Arithmetic is
                # polymorphic over the numeric spine -- Multiply/Add ask for no
                # particular operand type, so Multiply(Int, Int) is legal and
                # yields Int. `Concat` DOES require Str, and there the coercion
                # is load-bearing: dropping it would hand the backend an Int
                # where it emits a string operation. _required_operand_repr is
                # the authority for that distinction and is already how
                # _insert_str_coercions decides to ADD one; retiring one is the
                # same question asked in the other direction.
                my $required = _required_operand_repr($node->operation, $i);
                my $vacuous  = !defined $required
                    && $repr ne $c->to_repr
                    && Chalk::Grammar::Perl::TypeLibrary::is_subtype($repr, $c->to_repr);

                if ($repr eq $c->to_repr || $vacuous) {
                    $inputs->[$i] = $operand;
                    $c->remove_consumer($node) if $c->can('remove_consumer');
                    $operand->remove_consumer($c) if $operand->can('remove_consumer');

                    # A VACUOUS WIDENING'S CONSUMER IS NOW STALE. The producer
                    # computed Multiply's `Num` by joining ITS OPERANDS -- one
                    # of which was the coercion just retired. Dropping the edge
                    # without clearing the stamp leaves the widened answer
                    # standing over narrowed inputs, which is the whole defect
                    # one link further down: `Multiply :Num <- [Int, Int]`.
                    #
                    # Cleared, not recomputed here: `_propagate_computed_reprs`
                    # owns the join rule (`Multiply => 'join'`) and is the one
                    # place that knows it. This pass only invalidates; the
                    # re-propagation below derives the new answer. Restricted to
                    # the vacuous case -- an identity edge ($repr eq to_repr)
                    # changes no type, so its consumer's stamp is still true.
                    if ($vacuous && $node->can('set_representation')) {
                        push @stale, $node;
                    }

                    $narrowed++;
                    next;
                }

                my $new = $factory->make('Coerce',
                    inputs    => [$operand],
                    from_repr => $repr,
                    to_repr   => $c->to_repr,
                );
                $new->set_representation($c->to_repr);

                $inputs->[$i] = $new;
                # The old Coerce no longer reads the operand.
                $operand->remove_consumer($c) if $operand->can('remove_consumer');
                $narrowed++;
            }
        }
    }

    # RE-DERIVE what the retirements invalidated. Clearing the stamp is safe
    # only because the join rule can recompute it from the operands that
    # remain; a node whose repr cannot be re-derived would be left worse off
    # than before, so this runs the same propagation the loader already
    # trusts rather than inventing an answer here.
    if (@stale) {
        $_->set_representation(undef) for @stale;
        _propagate_computed_reprs($graphs);
    }

    return $narrowed;
}

sub _ctor_arg_reprs ($graphs) {
    my %map;
    for my $key (sort keys %$graphs) {
        my $g = $graphs->{$key};
        for my $node ($g->nodes->@*) {
            next unless $node->operation eq 'Call'
                && ($node->name // '') eq 'new'
                && $node->can('param_names');
            my $class = $node->class_name // next;
            my $pn    = $node->param_names // next;
            my @args  = $node->inputs->@*;
            for my $i (0 .. $#$pn) {
                my $arg  = $args[$i] or next;
                my $repr = blessed($arg) ? $arg->representation : undef;
                next unless defined $repr && $_INFERABLE_FIELD_REPR{$repr};

                # JOIN over every construction site, never the first one.
                # `//=` stood here, so the answer depended on the order
                # `sort keys %$graphs` happened to produce. Measured on
                # `Holder->new(v => 42)` and `Holder->new(v => "hello")` in one
                # program: source order alone selected `Str` (correct, the join)
                # or `Int` (WRONG -- a Str is stored into a field stamped Int).
                #
                # This is legitimate BECAUSE chalk is ahead-of-time (perigrin):
                # every construction site is in the program graph, so a join
                # over all of them is true of every value the field can hold.
                # It is the same discipline `_seed_direct_call_arg_reprs`
                # already applies to sub arguments, whose comment records the
                # identical measurement for `g(1); g("hello")`.
                my $k = "$class\0" . $pn->[$i];
                $map{$k} = defined $map{$k} ? _join_repr($map{$k}, $repr) : $repr;
            }
        }
    }
    return %map;
}

# _replay_classes($classes, \%graphs) — rebuild a sealed Chalk::MOP from the
# declarative class section, wiring each method to its loaded graph. Parents are
# declared before children so `superclass =>` can reference the parent's class.
sub _replay_classes ($classes, $graphs) {
    require Chalk::MOP;

    # Field types are inferred onto the raw records before this point (ctor-arg
    # and ADJUST-store passes in from_json), so declare_field below sees them.

    my $mop = Chalk::MOP->new;

    for my $name (_classes_in_parent_order($classes)) {
        my $cd     = $classes->{$name};
        my $parent = $cd->{parent};
        my $super  = (defined $parent && length $parent)
            ? $mop->for_class($parent)
            : undef;

        my $cls = $mop->declare_class($name,
            (defined $super  ? (superclass  => $super)  : ()),
            (defined $parent ? (parent_name => $parent) : ()),
        );
        # Recorded so a post-seal pass can tell a DECLARED class from the
        # `main` Chalk::MOP seeds unconditionally.
        $mop->mark_declared($name);

        for my $f (($cd->{fields} // [])->@*) {
            my $vname = $f->{name} // '$?';
            my @attrs;
            push @attrs, ':param'  if $f->{is_param};
            push @attrs, ':reader' if $f->{is_reader};
            my $is_reader = $f->{is_reader} ? true : false;

            # A field default (4c-1b) rides as a graph-ref whose Return value is
            # the default Constant; wire it as default_value + has_default. The
            # field type (inferred from the default) becomes the field repr.
            my ($default_node, $has_default);
            if (defined $f->{default_ref}
                && (my $dg = $graphs->{ $f->{default_ref} })) {
                my ($dret) = $dg->returns->@*;
                $default_node = $dret ? $dret->inputs->[0] : undef;
                $has_default  = defined $default_node;
            }

            my $field_type = $f->{type};

            # A field's DECLARED type types its own default expression.
            #
            # The default lives in a separate graph (`Bag::__DEFAULT_0`) that no
            # forward pass can type on its own when the value is an AGGREGATE
            # literal: measured on the pinned producer, the `[10,20,30]` of
            # `field $items = [10,20,30]` arrives `ArrayLiteral :Unknown`, while
            # the identical `[10,20,30]` in an ordinary graph arrives
            # `ArrayLiteral :ArrayRef`. That difference is not a producer bug and
            # %_SEED_REPR must not paper over it: ONE ArrayLiteral op builds both
            # `[1,2,3]` (a reference) and `my @a = (1,2,3)` (a plain array), so
            # the op name does not name the type (see the note at %_SEED_REPR).
            #
            # In a field default the ambiguity is ALREADY RESOLVED, and not by
            # inference -- the field record on the wire carries `type` before
            # either graph is walked. Carrying it down is forward inference from
            # a declaration onto its initializer, which is why it is sound where
            # stamping the CONSTRUCTION SITE is not: that would be typing a value
            # by its consumer.
            #
            # FILL A HOLE, NEVER PREEMPT A SOURCE. Only an unnarrowed default is
            # stamped. A `field $n = 0` default arrives `Constant :Int` -- which
            # is strictly better than that field's own weaker wire type `Scalar`
            # -- and overwriting it would swap an i64 for a %Slot. A type-sound
            # stamp is still a wrong stamp when it was never derived from
            # anything.
            #
            # Without this the default node reaches Target::LLVM with no
            # representation and _require_repr reports it as
            # "Call(new).default.field" (zhi 019f61ad).
            if (defined $field_type
                    && defined $default_node
                    && $default_node->can('set_representation')
                    && !_is_narrowed($default_node->representation)) {
                $default_node->set_representation($field_type);
            }

            $cls->declare_field($vname,
                sigil      => substr($vname, 0, 1),
                param_name => $f->{param_name},
                attributes => \@attrs,
                is_reader  => $is_reader,
                (defined $field_type ? (type => $field_type) : ()),
                ($has_default
                    ? (default_value => $default_node, has_default => true)
                    : ()),
            );
        }

        my $methods = $cd->{methods} // {};
        # The producer DECLARES each method's return type in the
        # method_return_types sibling map; the loader CARRIES it, exactly as
        # declare_sub below carries a sub's. A wire without the entry
        # predates the declaration and arrives as `Unknown` -- the lattice
        # top -- never as undef. `Unknown` is a real type meaning
        # "inference has not determined this"; undef is an ABSENCE, and an
        # absence forces every downstream consumer to invent its own meaning.
        my $wire_rts = $cd->{method_return_types} // {};
        for my $mname (sort keys %$methods) {
            # NOT declare_sub's die-on-missing-graph rule, deliberately.
            # An agentic review proposed mirroring it here on symmetry
            # grounds; MEASURED, that regresses a passing test. Real producer
            # wire declares methods whose graph is legitimately absent from
            # the loaded set (SoN::FromOptree::StackSim::merge), and
            # call-target-is-a-metaobject.t asserts the loader keeps going and
            # reports the disagreement at the CALL rather than aborting the
            # whole load. Subs and methods differ here: a sub is recorded only
            # after translate() succeeds, so its absence really is a
            # contradiction; a method's is not.
            my $graph = $graphs->{ $methods->{$mname} };
            $cls->declare_method($mname,
                (defined $graph ? (graph => $graph) : ()),
                return_type => ($wire_rts->{$mname} // 'Unknown'),
            );
        }

        # Subs (1b): a `sub` is not a `method` -- it carries no implicit
        # invocant -- so it replays into a MOP::Sub rather than a MOP::Method.
        # The wire distinguishes them at the producer (CvFLAGS & CVf_METHOD).
        #
        # This is the metadata channel that lets consumers STOP recovering
        # sub-level facts by scanning the graph: uses_args in particular cannot
        # be derived reliably, since `@_` has three IR spellings and vanishes
        # entirely for `my ($a,$b) = @_`.
        my $subs = $cd->{subs} // {};
        for my $sname (sort keys %$subs) {
            my $sd  = $subs->{$sname};
            my $key = $sd->{graph} // '';
            # REFUSE a record whose graph is missing rather than declaring a
            # graph-less MOP::Sub. MOP::Sub's `graph` field defaults to a fresh
            # EMPTY Chalk::IR::Graph, not undef, so a consumer's `defined`
            # check cannot tell "no body" from "a body" -- it would inline
            # nothing and silently produce a wrong answer. The producer records
            # a sub only after its translate() succeeds, so a missing graph
            # means the wire and the graph set disagree; say so loudly.
            my $graph = $graphs->{$key}
                or die "GAP: class '$name' declares sub '$sname' with graph key "
                     . "'$key', which is not in the loaded graph set.";
            # The producer DECLARES the return type; the loader CARRIES it. A
            # wire without the field predates the declaration and arrives as
            # `Unknown` -- the lattice top -- never as undef. `Unknown` is a
            # real type meaning "inference has not determined this"; undef is
            # an ABSENCE, and an absence forces every downstream consumer to
            # invent its own meaning for it.
            $cls->declare_sub($sname,
                graph       => $graph,
                params      => ($sd->{params} // []),
                uses_args   => ($sd->{uses_args} ? true : false),
                return_type => ($sd->{return_type} // 'Unknown'),
            );
        }

        # ADJUST blocks (4c-1b): each rides as a graph-ref; replay via
        # declare_adjust with the loaded graph.
        for my $aref (($cd->{adjusts} // [])->@*) {
            my $ag = $graphs->{$aref} or next;
            $cls->declare_adjust(graph => $ag);
        }
    }

    $mop->seal;

    # FieldAccess reprs are stamped by from_json's pre-seal pass (before
    # _replay_classes is called), and _mop->seal / class replay does not create
    # new FieldAccess nodes or re-type fields, so a tail re-stamp here is
    # redundant (idempotent) -- removed in the 019f4625 cleanup pass. The
    # universal repr pass (_seed_and_propagate_reprs) and method-Call stamping
    # run afterward in from_json as before.

    return $mop;
}

# _join_repr(@reprs) -> the least upper bound of the arms on the type lattice.
#
# A left fold of TypeLibrary::join_types, which is the lattice authority. This
# routine holds no widening order of its own: it was first `%_REPR_RANK = (Int
# => 0, Num => 1, Str => 2)` (the Int <: Num <: Str chain re-encoded as
# integers) and then a scan for an arm that is a supertype of all the others.
# Both were a second copy of something TypeLibrary already states, and both
# were PARTIAL -- they could only answer with a type an arm already named, so a
# pair whose LUB is neither arm came back undef. `Undef` and `Int` are siblings
# under `Scalar`: the lattice joins them at Scalar, the arm-scan said undef, and
# downstream read that as "inference failed" when it was the join that could not
# express the answer.
#
# The fold is TOTAL: every pair of lattice elements has a join, bottoming out at
# `Unknown` for elements sharing no ancestor (Slot with anything else). Note
# what that means for the callers -- `Unknown` is now a RESULT, not just an
# input, and it ABSORBS (join_types:309), so an arm inference could not type
# makes the whole merge Unknown rather than being discarded in favour of the
# known arm. That is deliberate (spec section 10): typing a merge from one arm
# when the other is unknown is a guess about the unknown one.
#
# Returns undef ONLY for the empty arm list. No arms is not a join with an
# answer; every other input has one.
sub _join_repr (@reprs) {
    return undef unless @reprs;

    my $acc = shift @reprs;
    $acc = Chalk::Grammar::Perl::TypeLibrary::join_types($acc, $_) for @reprs;
    return $acc;
}

# _seed_and_propagate_reprs(\%graphs) — the universal repr pass (runs for EVERY
# graph, class or not). Seeds aggregate/regex node reprs, then fixpoint-
# propagates through computed nodes and aggregate reads (Subscript) until no
# more reprs can be derived.
sub _seed_and_propagate_reprs ($graphs) {
    for my $g (values %$graphs) {
        # Seed over $g->nodes PLUS the control-chain closure. A loop CONDITION
        # (a comparison with control_in=Loop) and its input closure -- e.g. the
        # `Length(@a)` bound of a foreach-over-array (`for my $x (@a)`) and the
        # array ArrayRef -- are reachable only via the Loop's consumers, not the
        # Return value chain, so $g->nodes alone omits them. Without a seed the
        # ArrayRef/Length never get a repr and hit the backend NO-REPR guard when
        # the loop-condition is lowered (only visible when the body does not also
        # read an element, which would pull the array into the value chain).
        my %seen;
        my @seed_nodes;
        for my $n ($g->nodes->@*, _control_chain_nodes($g)) {
            next unless blessed($n);
            push @seed_nodes, $n unless $seen{ $n->id }++;
        }
        for my $node (@seed_nodes) {
            next if _is_narrowed($node->representation);
            # A qr// compiled-regex literal is a Constant of const_type 'regex';
            # its repr is Regex (the matcher value the backend resolves
            # statically). Keyed on const_type, not node kind, so it can't live
            # in the op-keyed seed table.
            if ($node->operation eq 'Constant'
                && $node->can('const_type')
                && ($node->const_type // '') eq 'regex') {
                $node->set_representation('Regex');
                next;
            }
            my $seed = $_SEED_REPR{ $node->operation } // next;
            $node->set_representation($seed);
        }
    }
    _propagate_computed_reprs($graphs);
    return;
}

# _control_chain_nodes($graph) — the statement-effect nodes reachable ONLY via
# control_in (an element-store Assign / void Call demoted to control_in), PLUS
# their transitive input closure. $g->nodes walks inputs from the returns' value
# only, so a store's value subtree (e.g. `$a[0] = $b[0]`, where $b[0] is reached
# only through the store) is otherwise unseen and stays untyped. Follows
# control_in from every returns() node, then closes over inputs of each.
#
# A loop-body / branch-body store whose RESULT is never read (no value edge and
# no post-body read observes its memory) is reachable only through the body's
# control node (a Proj). The Return's control_in chain reaches the Loop/If via
# the exit Region's inputs, but the BODY Proj hangs off the Loop/If as a
# consumer, and the store hangs off that body Proj as a consumer. So this walk
# also follows consumers that are Projs (the CFG body entry) or statement effects
# (nodes carrying a control_in — the stores themselves). The consumer step is
# scoped to those two kinds — arbitrary value fan-out is not pulled in — so it
# discovers control-only-reachable stores without over-collecting (019f3559).
sub _control_chain_nodes ($graph) {
    my %seen;
    my @out;
    # Seed: the control_in predecessor of each return + effect in the chain,
    # PLUS any trailing void statement-effect Calls carried as extra Return
    # inputs. A void method call (`$c->inc;`) is not the return value, so the
    # loader keeps it as inputs[1..] rather than demoting it to control_in; its
    # own control_in chain threads the preceding void effects. Seeding from it
    # here lets those effects be discovered and repr-stamped (else the backend
    # NO-REPR guard fires on a non-tail void Call).
    my @q;
    for my $r (grep { blessed($_) } $graph->returns->@*) {
        my $c = $r->can('control_in') ? $r->control_in : undef;
        push @q, $c if defined $c && blessed($c);
        if ($r->can('inputs') && defined $r->inputs) {
            my @ins = $r->inputs->@*;
            push @q, grep {
                blessed($_) && $_->can('control_in') && defined $_->control_in
            } @ins[ 1 .. $#ins ];
        }
    }
    while (my $n = shift @q) {
        next unless blessed($n);
        next if $seen{ $n->id }++;
        push @out, $n;
        # Follow control_in (chained effects) AND inputs (the effect's operands).
        my $c = $n->can('control_in') ? $n->control_in : undef;
        push @q, $c if defined $c && blessed($c);
        push @q, grep { blessed($_) } $n->inputs->@*
            if $n->can('inputs') && defined $n->inputs;
        # Follow consumers that are body Projs (the CFG entry into a loop/branch
        # body) or statement effects (nodes carrying a control_in — the stores
        # themselves): a body-nested store hangs off its body Proj as a consumer,
        # and that Proj hangs off the Loop/If as a consumer, so consumers are the
        # only edges that reach it.
        if ($n->can('consumers') && defined $n->consumers) {
            push @q, grep {
                blessed($_)
                    && ($_->operation eq 'Proj'
                        || ($_->can('control_in') && defined $_->control_in))
            } $n->consumers->@*;
        }
    }
    return @out;
}

sub _propagate_computed_reprs ($graphs) {
    for my $g (values %$graphs) {
        # $g->nodes walks inputs only; a threaded statement-effect node (an
        # element-store Assign / void Call) reached only via control_in is not in
        # it. Augment with the control-chain nodes so their reprs get inferred
        # too -- else a store of a value whose repr this pass derives (e.g. a
        # Subscript) leaves the Assign untyped and it hits the backend NO-REPR
        # guard.
        my %seen;
        my @nodes;
        for my $n ($g->nodes->@*, _control_chain_nodes($g)) {
            next unless blessed($n);
            push @nodes, $n unless $seen{ $n->id }++;
        }
        my $changed = 1;
        while ($changed) {
            $changed = 0;
            for my $node (@nodes) {
                # A JOIN-OP STAMP CAN GO STALE UNDER ITS OWN OPERANDS. The
                # bailout below is what keeps this fixpoint terminating, but a
                # `join` node (Add/Multiply/And/...) computed its answer FROM
                # its inputs, and a later pass can narrow those inputs -- two
                # `Call :Num` operands becoming `Call :Int` once their callee
                # settled. The Add then holds a Num nothing supports any more,
                # and the corpus specs for F14/F15 pin the Int.
                #
                # RE-DERIVED ONLY DOWNWARD, and only when every operand is
                # narrowed: the recomputed join must be a strict SUBTYPE of the
                # stamp it replaces. That preserves termination (a stamp
                # descends a finite lattice finitely often) and keeps this
                # forward inference -- the node is retyped from its own inputs,
                # never from a consumer's requirement.
                if (_is_narrowed($node->representation)
                    && ($_COMPUTED_REPR{ $node->operation } // '') eq 'join') {
                    my $inputs = $node->can('inputs') ? $node->inputs : undef;
                    my @operand_reprs =
                        map  { $_->representation }
                        grep { blessed($_) && $_->can('representation')
                                 && _is_narrowed($_->representation) }
                        ($inputs ? $inputs->@* : ());
                    my $have = $node->representation;
                    if ($inputs && @operand_reprs == scalar(grep { blessed($_) } $inputs->@*)
                        && @operand_reprs) {
                        my $want = _join_repr(@operand_reprs);
                        if (defined $want && $want ne $have
                            && Chalk::Grammar::Perl::TypeLibrary::is_subtype($want, $have)) {
                            $node->set_representation($want);
                            $changed = 1;
                        }
                    }
                }

                next if _is_narrowed($node->representation);
                my $op = $node->operation;

                # A Subscript reads an element out of an aggregate container:
                # its repr is the element type, inferred from the container's
                # element reprs (an ArrayRef/HashRef of Ints yields an Int).
                # BUT a statically-provable MISS (an out-of-bounds literal array
                # index, or a hash key absent from a literal HashRef) reads
                # perl's undef, not an element -- it must load as Slot (the
                # tagged {defined=false} path the backend prints as Undef:), NOT
                # the element type (which the backend prints as the payload 0, a
                # silent miscompile). Only fires over a SCALAR-literal aggregate
                # (a Constant index/key and a container whose inputs are all
                # plain scalars -- no nested list-flattening aggregate); a
                # dynamic index/key or a flattened container stays the element
                # repr (019f2e25).
                if ($op eq 'Subscript') {
                    if (_static_miss( $node->inputs->[0], $node->inputs->[1] )) {
                        # `Undef`, not `Slot` (perigrin, 2026-08-27/29). A read
                        # that is not there has a TYPE -- undef -- and `Undef`
                        # is a lattice member. `Slot` is its ENCODING and is not
                        # in the lattice at all, so writing it here overwrote
                        # the type axis with an encoding: the one destructive
                        # use of the `representation` alias, and the reason
                        # nothing in lib/ could safely read ->stamp.
                        #
                        # The producer already agrees: an out-of-range literal
                        # index and an absent literal hash key both arrive
                        # stamped `Undef` (verified on the wire, producer
                        # 9d23bda). So this now REINFORCES the wire's answer
                        # rather than replacing it.
                        $node->set_stamp('Undef');
                        $changed = 1;
                        next;
                    }
                    my $repr = _element_repr( $node->inputs->[0] );
                    next unless defined $repr;
                    my $prev = $node->representation;
                    next if defined $prev && $prev eq $repr;
                    $node->set_representation($repr);
                    $changed = 1;
                    next;
                }

                # An Assign's result IS the stored value, so its repr is the
                # value input's (inputs[-1], the rhs; a stmt-effect store's
                # leading control was already split off by the loader). Run in
                # the fixpoint so the value's own repr (e.g. a Subscript inferred
                # this same pass) is available before the Assign is stamped.
                if ($op eq 'Assign') {
                    my $value = $node->inputs->[-1];
                    next unless defined $value && blessed($value);
                    my $repr = $value->representation // next;
                    my $prev = $node->representation;
                    next if defined $prev && $prev eq $repr;
                    $node->set_representation($repr);
                    $changed = 1;
                    next;
                }

                my $rule = $_COMPUTED_REPR{$op} // next;
                if ($rule ne 'join') {
                    my $prev = $node->representation;
                    next if defined $prev && $prev eq $rule;
                    $node->set_representation($rule);
                    $changed = 1;
                    next;
                }
                my @in = grep { defined && blessed($_) } $node->inputs->@*;

                # A TernaryExpr's inputs are (cond, then, else), but `$c ? $a :
                # $b` NEVER evaluates to `$c` -- the condition is not a value
                # the expression can yield, so it must not enter the join.
                # Including it poisons the result: a Boolean condition is off the
                # Int<:Num<:Str chain, so no candidate dominates and the node
                # goes untyped even when both arms agree.
                #
                # The PRODUCER already joins arms-only (FromOptree.pm:4145,
                # Stamp::join($true_val->stamp, $false_val->stamp)); this side
                # disagreed with it. Order is documented there: inputs[1]=true,
                # inputs[2]=false.
                #
                # TernaryExpr ONLY. Phi's inputs are its arms, and DefinedOr is
                # a BinOp whose two operands are both results -- neither has a
                # condition among its inputs to drop.
                @in = @in[ 1 .. $#in ] if $op eq 'TernaryExpr' && @in > 1;

                my @reprs = map { $_->representation } @in;
                next if grep { !defined } @reprs;          # an input still untyped

                # A `Slot` arm is NOT dropped here, and the reason is worth
                # stating because dropping it looks reasonable.
                #
                # `Slot` is Maybe[word] with the word's type nowhere in the
                # node, so it cannot be ranked -- _join_repr has no chain to
                # place it on and the whole merge goes untyped. The tempting fix
                # is to drop the Slot arm and type the merge from the other one,
                # since `//` decides the maybe-ness anyway.
                #
                # That is WRONG, and measurably: it tells the backend to unbox
                # the Slot's payload as the other arm's type, on a claim nothing
                # established. For a Str-element array it emits
                # `phi %Str [ i64 ... ]`; where both encodings are i64 it would
                # not even fail loudly.
                #
                # A merge of "maybe" and "definitely" is resolved by PROVING one
                # arm dead (Chalk::Bootstrap::Optimizer::DefinedOrFold, which
                # deletes the merge outright when the index is statically
                # decidable) or by BOXING to the common encoding. Never by
                # unboxing on an unproven type. An untyped merge that reaches
                # the backend is a GAP, which is the correct outcome until the
                # boxing path exists.

                # KILDALL'S STORE DISCIPLINE (1973, step A4). The join folds the
                # node's EXISTING stamp in as an operand, so each successive store
                # is >= the last and the sequence is an ascending chain in a
                # lattice of height ~6. Joining inputs ALONE lets a store move
                # SIDEWAYS between incomparable elements, which the change guard
                # below cannot stop -- termination would then be luck of which
                # moves happen to be reachable rather than a proof.
                my $widest = _join_repr($node->representation, @reprs);
                next unless defined $widest;
                my $prev = $node->representation;
                    next if defined $prev && $prev eq $widest;
                    $node->set_representation($widest);
                $changed = 1;
            }
        }
    }
    return;
}

# _unwrap_ref($container) — a Ref container (`$r->[0]` where $r=\@a) aliases its
# target aggregate, so element-repr / static-miss inference must read the wrapped
# ArrayRef/HashRef, not the Ref (which carries no aggregate structure of its own).
# No-op for every non-Ref container. Mirrors Target::LLVM::_unwrap_ref_container.
sub _unwrap_ref ($container) {
    return $container unless defined $container && blessed($container)
        && $container->operation eq 'Ref';
    return $container->inputs->[0];
}

# _resolve_aggregate($node) — follow a chain of Subscript reads over LITERAL
# aggregates at CONSTANT indices back to the concrete aggregate node being read,
# so a nested deref ($r->[1][0]) can be typed statically. `Subscript(ArrayRef
# literal, const idx)` resolves to the ArrayRef's idx-th input; a HashRef needs a
# literal-key scan (not modelled -- returns the node unchanged, an honest fall
# through to undef). Returns the node unchanged when it is not a resolvable
# Subscript. Cycle-guarded via a bounded depth (aggregate nesting is shallow).
sub _resolve_aggregate ($node) {
    my $depth = 0;
    while (blessed($node) && $node->operation eq 'Subscript' && $depth++ < 64) {
        my $c   = _unwrap_ref($node->inputs->[0]);
        my $idx = $node->inputs->[1];
        last unless blessed($c) && $c->operation eq 'ArrayLiteral'
            && blessed($idx) && $idx->operation eq 'Constant'
            && ($idx->const_type // '') eq 'integer';
        my $i   = $idx->value;
        my @els = $c->inputs->@*;
        # Only a provable in-bounds literal index resolves; anything else stays a
        # Subscript (falls through to undef -- an honest GAP, not a guess).
        last if $i < 0 || $i > $#els;
        $node = _unwrap_ref($els[$i]);
    }
    return $node;
}

# _element_repr($container) — the element type of an ArrayRef/HashRef container,
# inferred as the widest element repr of its inputs JOINED WITH the repr of
# every value STORED into it. For a HashRef the inputs alternate key,value; the
# values are the odd positions. Returns undef when the element types are not yet
# known.
#
# The stores matter because a container is not frozen at its initializer: in
# `my @a=(1,2); $a[0]="hello";` the literals say Int and the live element is a
# Str. Reading the initializers alone stamps every later read Int, and a Str
# then reaches the backend wearing an Int stamp.
sub _element_repr ($container) {
    $container = _resolve_aggregate(_unwrap_ref($container));
    return undef unless defined $container && blessed($container);
    my $op = $container->operation;
    my @in = $container->inputs->@*;
    my @elems;
    if ($op eq 'ArrayLiteral') {
        @elems = @in;
    }
    elsif ($op eq 'HashLiteral') {
        @elems = @in[ grep { $_ % 2 } 0 .. $#in ];   # odd = values
    }
    else {
        return undef;   # container repr not a literal aggregate we can read
    }
    my @reprs = map { blessed($_) ? $_->representation : undef } @elems;
    # An UNTYPED store contributes undef, which fails the all-defined check
    # below — correct, because the caller runs inside the repr fixpoint and
    # will ask again once that store's rhs is typed. Answering from the
    # literals alone while a store is still untyped would commit to a type the
    # store may be about to widen.
    push @reprs, map { blessed($_) ? $_->representation : undef }
                 _element_store_values($container);
    return undef unless @reprs;
    return undef if grep { !defined } @reprs;
    # A NESTED aggregate: the elements are themselves aggregates ([[1,2],[3,4]]).
    # Aggregate reprs (ArrayRef/HashRef) are not scalar-widenable, so the element
    # type is that repr only when every element shares it homogeneously; a mixed
    # aggregate/scalar or ArrayRef/HashRef element set has no single element type
    # (references R8). Scalar elements fall through to the widening below.
    my %uniq = map { $_ => 1 } @reprs;
    if (keys %uniq == 1 && ($reprs[0] eq 'ArrayRef' || $reprs[0] eq 'HashRef')) {
        return $reprs[0];
    }
    return _join_repr(@reprs);
}

# THE ELEMENT-STORE WALK, shared by the two functions below.
#
# A store's lvalue is a Subscript over the container, so every store is
# reachable from the container by CONSUMER EDGES alone — container -> its
# Subscript consumers -> each Subscript's Assign consumer -> that Assign. No
# memory model, no statement ordering, no whole-program table. A post-store
# READ is a Subscript consumer of the container too, but it is never an
# Assign's inputs[0], which is exactly what distinguishes it from an lvalue.
#
# Returns the Assign nodes, in deterministic (node id) order.
sub _element_stores ($container) {
    $container = _resolve_aggregate(_unwrap_ref($container));
    return () unless defined $container && blessed($container)
        && $container->can('consumers');
    my @stores;
    for my $sub ($container->consumers->@*) {
        next unless blessed($sub) && $sub->operation eq 'Subscript';
        for my $use ($sub->can('consumers') ? $sub->consumers->@* : ()) {
            next unless blessed($use) && $use->operation eq 'Assign';
            my @ai = ($use->inputs // [])->@*;
            next unless @ai >= 2;
            next unless blessed($ai[0]) && $ai[0] == $sub;   # lvalue, not rhs
            push @stores, $use;
        }
    }
    my %seen;
    return grep { !$seen{ $_->id }++ }
           sort { ($a->id // '') cmp ($b->id // '') } @stores;
}

# _has_element_store($container) — true iff anything is ever stored into this
# container's elements. A consumer asking "is this container still the literal I
# can see?" must answer no from the FIRST store, whether or not that store's
# value can be read: an untyped store still changes what lives there.
sub _has_element_store ($container) {
    return scalar(_element_stores($container)) ? true : false;
}

# _element_store_values($container) — the value each store writes (an Assign's
# rhs is its last input), in the same order.
sub _element_store_values ($container) {
    return map { ($_->inputs // [])->[-1] } _element_stores($container);
}

# _static_miss($container, $index) — true iff a Subscript read is a provable
# MISS at load time: an out-of-bounds integer index into a literal ArrayRef, or
# a string key absent from a literal HashRef. Only literal-over-literal accesses
# are decidable here; a dynamic container or index returns false (the read keeps
# the element repr and is bounds-checked at runtime). A miss reads perl's undef,
# so the Subscript must load as Slot, not the element type.
sub _static_miss ($container, $index) {
    # Resolve a nested container the SAME way _element_repr does: a Subscript over
    # a literal aggregate at a constant index resolves to the inner literal, so an
    # OOB inner index ($r->[1][5]) is a provable miss. This MUST mirror
    # _element_repr's resolution -- if the two disagree, an OOB nested read gets
    # the element type (Int) instead of a Slot and silently reads 0 instead of
    # undef (a miscompile; found by the R8 nested-deref adversarial review).
    $container = _resolve_aggregate(_unwrap_ref($container));
    return false unless defined $container && blessed($container);
    return false unless defined $index && blessed($index)
        && $index->operation eq 'Constant';
    my $op = $container->operation;

    # A nested aggregate input is Perl list-flattening ((@x, 99) / (%base, ...)):
    # it occupies ONE input slot but expands to many elements at runtime, so a
    # static length or key-scan over inputs is wrong. Bail to element-repr (a
    # HIT) -- deciding a miss here would turn a valid read into a false Slot
    # (undef). Only a scalar-literal aggregate (all inputs plain scalars) is
    # statically decidable.
    #
    # THE TEST IS ARITY, NOT OP NAME. This listed ArrayLiteral and HashLiteral
    # because those were the flattening shapes that had been met; a Slice
    # flattens exactly the same way and was not named, so `my @t = @a[-2,-1];
    # $t[1]` counted the container's inputs as ONE, read index 1 as past the
    # end, and stamped `Undef` -- for a read perl answers 4. A stamp of Undef
    # is not a missing type, it is a WRONG one: the backend emits the tagged
    # undef path and the program prints nothing where perl prints a value.
    #
    # So the question is "can this input stand for more than one element", and
    # a node's STAMP already answers it. List/Array/Hash are the plural types;
    # anything stamped one of them occupies one slot and expands to an unknown
    # number, which is the same reason a nested literal does. Keyed on the type
    # rather than on a list of ops, so ExpressionList/ListAppend/ListAssign --
    # which are equally plural and equally unnamed here -- are covered without
    # this list having to grow again.
    #
    # Found via perl5-son's own instance of this bug (b53a881); chalk
    # reproduces it independently, and still did with their fix in place,
    # because this guard is chalk's, over chalk's own loaded graph.
    my $flattens = grep {
        blessed($_) && do {
            my $op = $_->operation;
            my $r  = $_->can('representation') ? ($_->representation // '') : '';
            $op eq 'ArrayLiteral' || $op eq 'HashLiteral'
                || $r eq 'List' || $r eq 'Array' || $r eq 'Hash'
                || ($op eq 'Slice' || $op eq 'ExpressionList'
                    || $op eq 'ListAppend' || $op eq 'ListAssign');
        }
    } $container->inputs->@*;
    return false if $flattens;

    if ($op eq 'ArrayLiteral') {
        # An integer literal index; out of bounds (or negative past the start)
        # is a miss. A negative index within range (perl's from-the-end) is NOT
        # a miss, so only flag idx >= len or idx < -len.
        return false unless ($index->const_type // '') eq 'integer';
        my $idx = $index->value;
        my $len = scalar $container->inputs->@*;
        return ($idx >= $len || $idx < -$len) ? true : false;
    }
    if ($op eq 'HashLiteral') {
        # A string key absent from the literal keys (even positions) is a miss.
        my $key = $index->value // return false;
        my @in  = $container->inputs->@*;
        for my $i (grep { $_ % 2 == 0 } 0 .. $#in) {   # even = keys
            my $k = $in[$i];
            next unless blessed($k) && $k->operation eq 'Constant';
            return false if ($k->value // '') eq $key;   # present -> not a miss
        }
        return true;   # exhausted the literal keys with no match
    }
    return false;   # container not a literal aggregate we can decide
}

# _infer_param_field_types($classes, \%graphs) — type a :param field with no
# declared type from the CONSTRUCTOR ARGUMENT: a Call(new) binds param_names[i]
# -> inputs[i], so a field whose param_name matches carries the argument's repr.
# Fills the raw field record so declare_field (the MOP / struct layout) and
# _stamp_field_access_reprs (the FieldAccess nodes) both see it. Cross-graph: the
# Call(new) is in the driver graph, the field in a class section. Returns the
# number of field types newly inferred.
sub _infer_param_field_types ($classes, $graphs) {
    my %ctor_arg_repr = _ctor_arg_reprs($graphs);
    my $inferred = 0;
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            # NOT `defined`: the producer sends `Scalar` for an untyped
            # :param field -- the honest un-narrowed top -- and Scalar is
            # defined. Guarding on definedness stopped this inference the day
            # the producer started being explicit, leaving every :reader return
            # Scalar and reaching the backend as Coerce[Scalar -> Num], which
            # has no arm. _is_narrowed already states the rule.
            next if _is_narrowed($f->{type});
            my $pn = $f->{param_name} // next;
            my $repr = $ctor_arg_repr{"$cname\0$pn"} // next;
            $f->{type} = $repr;
            $inferred++;
        }
    }
    return $inferred;
}

# _infer_field_types_from_stores($classes, \%graphs) — type a field with no
# declared type from the value an ADJUST block stores into it. An ADJUST store
# is Assign(control, FieldAccess(ix)-lvalue, value); when the value carries a
# repr, that repr is the field's type. Writes the type onto the raw field record
# (so _stamp_field_access_reprs and the MOP both see it) only when the field is
# still untyped — never overrides a declared or constructor-argument type.
# Returns the number of field types newly inferred.
sub _infer_field_types_from_stores ($classes, $graphs) {
    # (class, fieldix) -> stored value repr, from Assign(FieldAccess-lvalue, val).
    # A stmt-effect field store is threaded via control_in (not a data input of
    # the Return), so it is reachable only by following control_in as well as
    # data inputs -- Graph::nodes walks data edges, so collect the store nodes by
    # a BFS over both edge kinds from each Return.
    my %store_repr;
    for my $g (values %$graphs) {
        my %seen;
        my @queue = grep { blessed($_) } $g->returns->@*;
        while (my $node = shift @queue) {
            next if $seen{ $node->id }++;
            push @queue, grep { blessed($_) } $node->inputs->@*;
            push @queue, $node->control_in
                if $node->can('control_in') && blessed($node->control_in);

            next unless $node->operation eq 'Assign';
            # A loaded stmt-effect Assign carries control in control_in, so its
            # data inputs are [target, value].
            my ($lv, $val) = ($node->inputs->[0], $node->inputs->[1]);
            next unless blessed($lv) && $lv->operation eq 'FieldAccess';
            next unless blessed($val);
            my $repr = $val->representation // next;
            my $key  = ($lv->field_stash // '') . "\0" . ($lv->field_index // -1);
            # A field written with conflicting reprs across stores is ambiguous;
            # leave it untyped (a GAP) rather than pick one (a possible miscompile).
            $store_repr{$key} = exists $store_repr{$key}
                && ($store_repr{$key} // '') ne $repr ? undef : $repr;
        }
    }

    my $inferred = 0;
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            # NOT `defined`: the producer sends `Scalar` for an untyped
            # :param field -- the honest un-narrowed top -- and Scalar is
            # defined. Guarding on definedness stopped this inference the day
            # the producer started being explicit, leaving every :reader return
            # Scalar and reaching the backend as Coerce[Scalar -> Num], which
            # has no arm. _is_narrowed already states the rule.
            next if _is_narrowed($f->{type});
            my $repr = $store_repr{"$cname\0" . ($f->{fieldix} // -1)} // next;
            $f->{type} = $repr;
            $inferred++;
        }
    }
    return $inferred;
}

# _stamp_field_access_reprs($classes, \%graphs) — set each FieldAccess node's
# representation from its declared field type. The field type comes from the
# class section (4c-1b infers it from the field default); the backend needs a
# repr on the FieldAccess to lower a field read.
sub _stamp_field_access_reprs ($classes, $graphs) {
    # Build (class, fieldix) -> type from the class sections. For an aggregate
    # (ArrayRef/HashRef) field, also record its ELEMENT type from the default's
    # elements -- an `field $items = [10,20,30]` field reads Int elements. A
    # Subscript over a FieldAccess to that field (`$items->[0]`, `$items->@*` in
    # a loop) then carries the element repr (zhi 019f61ad).
    my (%field_type, %field_elem_type, %reader_graph_type);
    for my $cname (keys %$classes) {
        for my $f (($classes->{$cname}{fields} // [])->@*) {
            my $key = "$cname\::" . ($f->{fieldix} // -1);
            $field_type{$key} = $f->{type} if defined $f->{type};

            # A :reader field gets a SYNTHESIZED accessor graph, named
            # Class::fieldname, whose body reads the field through a PadAccess
            # rather than the FieldAccess an explicit `method get { return $v }`
            # produces. Same field, same type, different node kind -- and the
            # FieldAccess arm below is the only rule that ever typed it, so the
            # accessor body reached the end of the pipeline untyped.
            #
            # Record (graph name, varname) -> type so the walk can type it. The
            # varname is matched too: an accessor graph contains exactly one
            # field read, but keying on the graph alone would type ANY PadAccess
            # that appeared there, and a future accessor body with a local would
            # be silently mistyped.
            if ($f->{is_reader} && defined $f->{type} && defined $f->{name}) {
                my $accessor = $f->{name} =~ s/^[\$\@\%]//r;
                $reader_graph_type{"$cname\::$accessor"} =
                    { varname => $f->{name}, type => $f->{type} };
            }
            # An aggregate default's element repr (widest of its elements).
            if (defined $f->{default_ref}
                    && (my $dg = $graphs->{ $f->{default_ref} })) {
                my ($dret) = $dg->returns->@*;
                my $default = $dret ? $dret->inputs->[0] : undef;
                if (defined $default && blessed($default)
                        && $default->operation =~ /^(?:Array|Hash)Literal$/) {
                    my $er = _element_repr($default);
                    $field_elem_type{$key} = $er if defined $er;
                }
            }
        }
    }

    for my $gname (keys %$graphs) {
        my $g = $graphs->{$gname};
        my $reader = $reader_graph_type{$gname};
        for my $node ($g->nodes->@*) {
            # The :reader accessor's field read (see %reader_graph_type above).
            if ($reader && $node->operation eq 'PadAccess'
                    && !_is_narrowed($node->representation)
                    && $node->can('varname')
                    && ($node->varname // '') eq $reader->{varname}) {
                $node->set_representation($reader->{type});
                next;
            }
            if ($node->operation eq 'FieldAccess' && !_is_narrowed($node->representation)) {
                my $stash = $node->field_stash // next;
                my $fidx  = $node->field_index;
                my $type  = $field_type{"$stash\::" . ($fidx // -1)} // next;
                $node->set_representation($type);
                next;
            }
            # A Subscript reading an element out of an aggregate FIELD: its repr
            # is the field's element type (the container is a FieldAccess, not a
            # literal aggregate _element_repr can read). A LITERAL constant index
            # is left for the OOB->Slot path (references R9); only a non-literal
            # index needs this (its own _element_repr sees a FieldAccess).
            if ($node->operation eq 'Subscript' && !_is_narrowed($node->representation)) {
                my $cont = $node->inputs->[0];
                next unless blessed($cont) && $cont->operation eq 'FieldAccess';
                my $er = $field_elem_type{
                    ($cont->field_stash // '') . '::' . ($cont->field_index // -1) };
                next unless defined $er;
                $node->set_representation($er);
            }
        }
    }
    return;
}

# _stamp_method_call_reprs($classes, \%graphs, $mop) — set each method Call's repr
# from the resolved callee method's return repr (its body's Return value repr).
sub _stamp_method_call_reprs ($graphs, $mop) {
    # Build class::method -> return_repr.
    #
    # THE WIRE IS THE FIRST SOURCE, not the graph walk. The producer computes
    # each method's return type where it built the Return and knows the value
    # node, and ships it in the `method_return_types` sibling map (a sibling
    # because the {methods} value must stay a bare graph-name string that both
    # repos index the graph map with). Re-deriving what was already sent is the
    # recovery-by-scanning that the metadata channel exists to retire.
    #
    # The graph walk REMAINS, for two reasons: the producer sends `Unknown`
    # where it genuinely cannot tell (it works method-by-method and cannot see
    # a caller), and this loader has the whole program, so it can often do
    # better. Measured on plain subs: 11 of 15 agreed, 4 were Unknown-on-wire
    # and derivable here, ZERO disagreed.
    #
    # WHERE BOTH COMMIT AND DISAGREE, THAT IS A DEFECT IN ONE OF THEM. Nothing
    # compared them before, so a divergence would have been silent -- the
    # backend consuming one answer while the metadata channel carried another.
    # Refuse loudly instead.
    my %ret_repr;
    # THROUGH THE PROTOCOL, not the raw records. Every question below is one
    # the MOP already answers: which classes exist, their methods, each
    # method's wire-declared return type (declare_method carries it), and its
    # callee graph. Reaching past the metaobject into the section it was BUILT
    # FROM is what tied inference to deserialization -- and after the seal
    # those records are gone, so the reach is a lifetime bug waiting to happen.
    # ->classes returns Class OBJECTS, not names -- sorted by name here so the
    # walk stays deterministic without a second lookup.
    for my $cls (sort { $a->name cmp $b->name } $mop->classes) {
        my $cname = $cls->name;
        for my $meta ($cls->methods) {
            my $mname = $meta->name;
            # The wire value now rides on the METAOBJECT: declare_method carries
            # method_return_types, mirroring declare_sub. Read it from there, so
            # the LEFT operand of the disagreement die below is the same value
            # every downstream consumer sees. The RIGHT operand stays the graph
            # walk immediately following -- without it the die would degrade
            # into comparing a value against itself and quietly stop firing.
            my $wire = $meta->return_type;
            $ret_repr{"$cname\::$mname"} = $wire
                if _is_narrowed($wire);

            my $g = $meta->graph or next;
            my ($ret) = $g->returns->@*;
            next unless $ret;
            my $val = $ret->inputs->[0];
            next unless defined $val && blessed($val);
            my $repr = $val->representation;
            # Not merely `defined`: an unnarrowed graph-derived repr is not a
            # second opinion, so it must not be compared against the wire's.
            # `Unknown ne Str` is true and would fire the disagreement die
            # below on a graph that simply has nothing to say yet.
            next unless _is_narrowed($repr);

            # ORDERED, NOT ALTERNATIVES. `ne` asks whether two lattice points
            # are the same STRING, so `Scalar` on the wire against `Int` from
            # the graph read as a defect in one of them. It is not: Int <:
            # Scalar, the producer said "a scalar", this proved "an Int", and
            # BOTH ARE TRUE. Take the narrower and say nothing.
            #
            # WHY THE PRODUCER SENDS A SUPERTYPE. It compiles ahead of time, so
            # a node it cannot narrow may not ship `Unknown` -- that is a hole
            # in the emitted program, not a missing annotation. A subscript
            # reads ONE slot of an aggregate, always a scalar, so an
            # unnarrowable element read ships `Scalar` (which lowers to %Slot).
            # A field-held literal is exactly that: its elements live in a
            # separate default graph the producer does not cross and this
            # loader does.
            #
            # A REAL CONTRADICTION STILL DIES -- two types on different
            # branches, neither refining the other.
            if (_is_narrowed($wire) && $wire ne $repr) {
                my $wire_narrower
                    = Chalk::Grammar::Perl::TypeLibrary::is_subtype($wire, $repr);
                my $repr_narrower
                    = Chalk::Grammar::Perl::TypeLibrary::is_subtype($repr, $wire);

                if (!$wire_narrower && !$repr_narrower) {
                    die "IR: method $cname\::$mname has return type '$wire' on "
                      . "the wire but '$repr' derived from its graph, and "
                      . "neither refines the other. One of the two is wrong; "
                      . "refusing rather than picking silently.\n";
                }

                # The narrower of the two is the answer. When the WIRE is
                # narrower the graph simply had less to go on, so keep the wire
                # and do not overwrite it with the weaker derivation below.
                if ($wire_narrower) {
                    $ret_repr{"$cname\::$mname"} = $wire;
                    next;
                }

                # The GRAPH is narrower: carry that onto the metaobject too.
                # Target::LLVM reads return_type off the metaobject when it
                # emits the callee's signature, so leaving it at the wider wire
                # value emits a wider return than the call sites stamped below
                # expect. set_return_type only ever narrows, so this cannot
                # weaken a type some other pass determined.
                $meta->set_return_type($repr) if $meta;
            }
            $ret_repr{"$cname\::$mname"} = $repr;
        }

        # A :reader field DOES get a real method -- perl generates it and the
        # producer translates it, so `field $x :reader` in class P ships a
        # graph named `P::x` exactly as an explicit method would (measured).
        #
        # What it does NOT get is an entry in the class's `methods` RECORD,
        # which lists only methods written in the source. So the loop above,
        # which walks $cls->methods, never sees a reader -- and its return repr
        # has to come from THE FIELD instead: the accessor returns the field,
        # so its type is the field's type (filled by _replay_classes from the
        # default or the constructor argument). The method is named after the
        # field, sigil-stripped.
        for my $f ($cls->fields) {
            next unless $f->is_reader && defined $f->type;
            my $rname = ($f->name // '') =~ s/^[\$\@%]//r;
            $ret_repr{"$cname\::$rname"} = $f->type if length $rname;
        }
    }

    # Walk every graph's method Calls and stamp from the resolved callee.
    # Augment $g->nodes (input closure only) with the control-chain nodes: a
    # void method Call (`$c->inc;`) reached only via control_in is otherwise
    # unseen here and hits the backend NO-REPR guard.
    my $stamped = 0;
    for my $g (values %$graphs) {
        my %seen;
        my @nodes = grep { !$seen{ $_->id }++ }
            ($g->nodes->@*, _control_chain_nodes($g));
        for my $node (@nodes) {
            next unless $node->operation eq 'Call';
            next unless ($node->dispatch_kind // '') eq 'method';
            next if ($node->name // '') eq 'new';   # constructor: backend-handled
            # NO EARLY `_is_narrowed` BAILOUT. A method Call's authority is
            # its CALLEE's return type, and the callee can narrow after this
            # Call was first stamped: retiring a vacuous widening inside
            # `method inc { $n += 1 }` moves its body Num -> Int, and the
            # metaobject follows via set_return_type. A Call frozen at the
            # first answer then disagrees with the ABI it calls through, which
            # the backend refuses outright ("node repr=Num disagrees with class
            # 'Counter' vtable ABI return_repr=Int", Context.pm:8687).
            #
            # The resolution below is unchanged; the DOWNWARD-ONLY test lives
            # at the write site, where the callee's answer is actually in hand.
            my $class = $node->class_name // next;
            my $mname = $node->name // '';
            # Resolve through the EDGE. _attach_call_targets has already put the
            # callee's metaobject on the Call, resolved through
            # Chalk::MOP::Class::find_method -- which walks the superclass chain,
            # so an inherited call already names its DECLARING class here. No
            # second, hand-rolled parent walk over the raw wire records.
            #
            # A `:reader` accessor has NO metaobject -- the backend synthesizes
            # it, so no declare_method ever ran for it -- and a reader IS
            # inherited (`Child->new(v=>9)->v` on a `field $v :reader` declared
            # on Base). That case keeps the parent walk over the wire records,
            # which is the only place a reader's owning class is recorded.
            # Measured: without this fallback the inherited reader loses its
            # stamp (Int -> undef) and the backend hits its NO-REPR guard.
            # The edge is the authoritative STARTING point, not a
            # replacement for the walk. Keying only on the declaring class
            # drops the stamp whenever %ret_repr has no entry for it -- and
            # the walk could never run, because the two arms were mutually
            # exclusive on $target. A dropped stamp reaches
            # _lower_call_method's _require_repr and GAPs the WHOLE program.
            my $target = $node->target;
            my $c = ($target && $target->isa('Chalk::MOP::Method'))
                  ? $target->class->name
                  : $class;
            my $repr;
            my %walked;
            while (defined $c && !$walked{$c}++) {
                if (defined(my $r = $ret_repr{"$c\::$mname"})) { $repr = $r; last; }
                my $pc  = $mop->for_class($c);
                my $sup = $pc ? $pc->superclass : undef;
                $c = $sup ? $sup->name : undef;
            }
            defined $repr or next;
            # WRITE ON MOVE, not on visit. The caller loops
            # `while (_stamp_method_call_reprs(...) > 0)`, so a count that
            # rises on every visit never reaches zero and the loop spins
            # forever -- measured: stamped=2 at iteration 1 and still 2 at
            # iteration 600, on a class with two `:param :reader` fields.
            #
            # This is the discipline 6db5dcdc established for
            # _propagate_computed_reprs and missed here, the fifth site. It
            # became reachable when the producer started shipping a reader as
            # a real method (perl5-son 4df7576): before that a :reader had no
            # entry in the class's methods record, so this loop never saw one
            # and could not re-stamp it.
            my $prev = $node->representation;
            next if defined $prev && $prev eq $repr;

            # DOWNWARD ONLY once a stamp exists. An unnarrowed Call takes the
            # callee's answer outright; a narrowed one moves only to a strict
            # SUBTYPE of what it holds. That keeps this monotone over a finite
            # lattice (so the caller's `while (... > 0)` still terminates) and
            # keeps it forward inference: the Call is typed by its own callee,
            # never widened back by a later, weaker reading.
            next if _is_narrowed($prev)
                && !Chalk::Grammar::Perl::TypeLibrary::is_subtype($repr, $prev);

            $node->set_representation($repr);
            $stamped++;
        }
    }
    return $stamped;
}

# _classes_in_parent_order($classes) — class names sorted so a parent always
# precedes its children (a child's superclass must already be declared).
sub _classes_in_parent_order ($classes) {
    my @order;
    my %placed;
    my %placing;
    my $place;
    $place = sub ($name) {
        # %placing is the cycle guard, and it must be SEPARATE from %placed:
        # a class is marked placed only AFTER its parent is, so on a cyclic
        # chain %placed alone never stops the descent and the walk recurses
        # until memory is exhausted -- not a catchable error, just a dead
        # process. The loader is defensive over JSON of unknown provenance, so
        # a malformed wire must fail in a way a caller can catch.
        #
        # The MOP OBJECT graph cannot cycle (superclass is constructor-only and
        # parents are declared first); the risk is one layer earlier, on the raw
        # wire records. _stamp_method_call_reprs already guards the same
        # {parent} chain this way.
        return if $placed{$name} || $placing{$name}++;
        my $parent = $classes->{$name}{parent};
        $place->($parent) if defined $parent && exists $classes->{$parent};
        $placed{$name} = 1;
        push @order, $name;
    };
    $place->($_) for sort keys %$classes;
    return @order;
}

1;
