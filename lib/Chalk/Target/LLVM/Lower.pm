# ABOUTME: The LLVM target's T2 entry: lower_program checks a program is T2's, builds it (Builder),
# ABOUTME: prints it (Printer); narrow_graphs narrows a graph's Chalk stamps to LLVM types.
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Lower;

use Chalk::Target::LLVM::Builder;
use Chalk::Target::LLVM::Printer;
use Chalk::IR::Value;      # narrow_num tests operands with isa
use Chalk::IR::Analysis;   # not_a_value_type, is_fractional_constant: T1's facts
use Chalk::IR::ReferenceFlow;   # may a reference's value reach a deref: T1's question

# lower_program($return_node) -> the module's text, or undef when T2 refuses
# the program.
# $PATH: what the last lower_program did -- { path => 't2' }, or
# { path => 'refused', why => T2's reason } -- read by whoever lowered (the
# pipeline puts it on its unit; Chalk::Target::LLVM::lower dies with the reason).
our $PATH;
sub lower_program {
    my ($class, $ret, %opt) = @_;
    my $b = bless { blocks => [], cur => undef, memo => {}, strs => {}, mop => $opt{mop} }, 'Chalk::Target::LLVM::Builder';
    # AN EVAL OR A TRY anywhere in the program (the whole program: a sub's own
    # nodes do not show its caller's try)
    $b->{has_eval} = scalar grep { $_->can('eval_id') && defined $_->eval_id || $_->operation eq 'TryCatch' }
        Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    # A CALL print TAKES THROUGH A COERCE is in list context (print's list);
    # the Coerce lists no consumer, so it is found from the Print.
    # AN ARRAY OR HASH FIELD is a list wherever a list is asked (B::SoN stamps
    # its FieldAccess Scalar: `join "", @s` joined its count, "1" for "p").
    local %Chalk::Target::LLVM::Builder::LIST_FIELD = map { ( refaddr($_) => 1 ) }
        grep { $_->operation eq 'FieldAccess' && ( ( eval { $b->field_of($_) } )[1] // '$' ) =~ /\A[@%]\z/ }
        Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    # (want=list too: a Coerce before print is also a scalar's -- `my $n = f();
    # print $n` is the call, coerced, B::SoN having folded $n -- 45 for 2)
    local %Chalk::Target::LLVM::Builder::PRINTED = map { ( refaddr( $_->inputs->[0] ) => 1 ) }
        grep { $_->operation eq 'Coerce' && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'Call'
               && ( $_->inputs->[0]->can('want') ? $_->inputs->[0]->want // '' : '' ) eq 'list' }
        map { grep { blessed($_) } $_->inputs->@* }
        grep { $_->operation eq 'Print' } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    # caller ANYWHERE: each call of a sub pushes its site, for caller to read.
    local $Chalk::Target::LLVM::Builder::FRAMES = scalar grep {
        $_->operation eq 'Call' && $_->reads_call_stack
    } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    my $ok = eval {
        # THE MOP IS READ SEALED: an unsealed one may still change under the reader.
        Chalk::Target::LLVM::Builder::out('an unsealed MOP') if $opt{mop} && !$opt{mop}->is_sealed;
        # A LIST ASSIGN TO AN ARRAY OR HASH (which takes the rest of the list)
        # is list_assign's: on wire v2 an Assign is a record or on both chains
        # (the loader's L5), and one on both is placed, its reads at its
        # version or after. A RECORD of one (off both chains: nothing runs it)
        # is not T2's: one B::SoN left floating was never made, and its array
        # read empty (`my ($f, @rest) = (1, 2, 3)`: "1 " for "1 2 3"). Nor one
        # of a variable B::SoN also binds as a value (`my @r = (9, 9); ($x, @r)
        # = f()`: its reads stayed the first list's -- "9 9").
        # AND ONE INTO SCALARS FROM A `my` ARRAY OR HASH KEPT IN MEMORY (one
        # B::SoN does not stamp Array or Hash): B::SoN bound its scalars by
        # place, the first to the array itself, on the chain or not (`my ($f,
        # $s) = @r`: "2 " for "2 3"; `my ($f) = @r` read after a pop: the count).
        {
            my @list_assigns = grep {
                $_->operation eq 'Assign' && $_->can('targets') && defined $_->targets
                    # (`my ($c, @x) = @_` is T2's: the arguments, taken by place)
                    && !( blessed( $_->inputs->[-1] ) && $_->inputs->[-1]->operation eq 'ArgsSource' )
            } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
            my %bound = !@list_assigns ? () : map { ( ( $_->operation eq 'HashLiteral' ? '%' : '@' ) . $_->symbol => 1 ) }
                grep { $_->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ && defined $_->symbol }
                Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
            for my $a (@list_assigns) {
                my @in = $a->inputs->@*;
                my @t = splice @in, 0, $a->targets;
                my @agg = grep { blessed($_) && ( $_->operation eq 'PadAccess' && ( $_->sigil // '' ) =~ /\A[\@%]\z/
                                                  || $_->operation =~ /\A(?:ArrayLiteral|HashLiteral|EntryDef)\z/ && ( $_->can('sigil') ? $_->sigil // '' : '' ) ne '$' ) } @t;
                Chalk::Target::LLVM::Builder::out('a list assignment to an array or hash')
                    if @agg && ( $a->record || grep { $_->operation eq 'PadAccess' && $bound{ $_->sigil . $_->symbol } } @agg );
                Chalk::Target::LLVM::Builder::out('a list assignment into scalars from an array or hash kept in memory')
                    if ( grep { blessed($_) && $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' } @t )
                    && grep { blessed($_) && ( $_->is_my_array || $_->is_my_hash ) && ( $_->stamp // '' ) !~ /\A(?:Array|Hash)\z/ } @in;
            }
            # A `my` SCALAR TWO LIST ASSIGNMENTS BIND, ONE AFTER THE OTHER:
            # B::SoN reads it by name -- one node, at no memory version --
            # so a value made from it after the first is made once, and read
            # again after the second (`($a, $b) = g(); print "$a"; ($a, $b) =
            # h(); print "$a"` printed g's twice). Arms that each bind it (one
            # taken) are not one after the other.
            my %binds;    # a scalar target => the list assigns that bind it
            for my $a (@list_assigns) {
                push $binds{ refaddr($_) }->@*, $a for grep {
                    blessed($_) && $_->operation eq 'PadAccess' && ( $_->sigil // '' ) eq '$' && !blessed( $_->mem_in )
                } $a->inputs->@[ 0 .. $a->targets - 1 ];
            }
            for my $as ( grep { $_->@* > 1 } values %binds ) {
                for my $a (@$as) {
                    # (what control reaches from $a, as Region::reached_by walks it)
                    my ( %after, @q );
                    @q = ($a);
                    while ( defined( my $n = shift @q ) ) {
                        next if $after{ refaddr($n) }++;
                        push @q, grep { blessed($_) && ( $_->operation eq 'Region'
                                        || ( $_->can('control_in') && blessed( $_->control_in ) && refaddr( $_->control_in ) == refaddr($n) )
                                        || $_->operation eq 'Proj' && $n->operation =~ /\A(?:If|Loop)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($n) ) }
                            ( $n->consumers // [] )->@*;
                    }
                    Chalk::Target::LLVM::Builder::out('a `my` scalar two list assignments bind one after the other (its reads are one node, at no memory version)')
                        if grep { refaddr($_) != refaddr($a) && $after{ refaddr($_) } } @$as;
                }
            }
        }
        # A SCALAR DEREF A REFERENCE T2 DOES NOT MAKE MAY REACH (a glob's, a
        # field's): refused, not read wrong at run time. T2 makes one to a `my`
        # scalar kept in memory, a literal (read-only), a choice of such, an
        # array or a hash (`\(@a)` and `\$_[0]` among them), an array's or a
        # hash's element, a named sub (\&name: a code value, tag 8 -- a scalar
        # deref of it dies as perl's). Whether one's value MAY REACH the
        # deref is T1's question (Chalk::IR::ReferenceFlow): through stores,
        # calls and returns, conservatively -- not merely that both are in the
        # program (Symbol::gensym's `\*{...}`, loaded by File::Temp, refused
        # every program that loaded it).
        {
            my @all = Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
            my @unmade = grep { $_->operation eq 'Ref' && !( ( $_->stamp // '' ) =~ /\A(?:ArrayRef|HashRef)\z/
                          || $_->is_alias_ref || $_->is_element_ref || $_->is_hash_element_ref
                          || blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'Constant' && ( $_->inputs->[0]->const_type // '' ) eq 'code'
                          || Chalk::Target::LLVM::Builder::_scalar_ref_of( $_->inputs->[0] ) ) } @all;
            # (the walk is asked only where both are there)
            Chalk::Target::LLVM::Builder::out('a scalar deref where a reference T2 does not make may reach it')
                if @unmade && ( grep { $_->operation eq 'PostfixDeref' && ( $_->sigil // '' ) eq '$' && !$_->alias_element } @all )
                && defined Chalk::IR::ReferenceFlow->new( nodes => \@all, mop => $opt{mop} )->scalar_deref_reached(@unmade);
        }
        $b->build($ret); 1 };
    unless ($ok) { $PATH = { path => 'refused', why => ( $@ =~ s/\n.*//sr ) }; return undef }
    # A PRINTING FAILURE (a conversion T2 lacks) is a refusal too, by its reason:
    # it once escaped as a bare death (pvm 140).
    my $ir = eval { Chalk::Target::LLVM::Printer::print_module($b) };
    $PATH = defined $ir ? { path => 't2' } : { path => 'refused', why => 'T2 printing: ' . ( $@ =~ s/\n.*//sr ) };
    return $ir;
}

# =====================================================================
# NARROWING: a Chalk type to the LLVM type that represents it.
#
# NOT A TYPE MAPPING BUT A NARROWING ANALYSIS. perigrin, stating the design
# (docs/plans/2026-08-31-t2-is-a-narrowing-analysis.md):
#
#   "T2 needs to do a type mapping from a Chalk type to an LLVM type but
#    the types aren't 1:1 ... Num for example is the parent type of Int so
#    a Num maps to double|i64 and then T2 does narrowing passes to get a
#    single representation type."
#
# A stamp names a type AND EVERYTHING BELOW IT on the lattice, so it
# denotes a SET of candidate machine types:
#
#     Scalar -> everything below, or %Slot    narrowing, else box
#     Str    -> {%Str, double, i64...}        is it ever rendered?
#     Num    -> {double, i64...}              is it ever fractional?
#     Int    -> {i8,u8,...,i64,u64}           sign and range
#
# NOTHING ON THE SPINE IS ALREADY CONCRETE: `Str :> Num`, and a bounded
# positive Int could be u8. Width and sign selection need an interval
# lattice, a widening operator at loop Phis and sign tracking; until they
# are built `Int` answers `i64`. `_choose` picks from the candidate SET, so
# adding evidence shrinks a set without changing the shape.
#
# IT COSTS NO NEW FIELD. A node has ONE stamp field (`representation()` reads
# it): narrowing changes what it holds -- a Chalk type before, an LLVM type
# after -- so a Chalk name surviving narrow_graphs is a T2 bug findable
# without reasoning about the program.
#
# THE MAPPING IS INJECTIVE, a design requirement. `Boolean` and `Undef` both
# denote one bit; the four reference types are all boxed pointers. Collapsed,
# a consumer holding `i1` cannot tell which it had, and a check meaning two
# things at once is the failure mode this codebase keeps recording. LLVM
# enforces the distinction for free -- named struct types are NOMINAL
# (measured against lli-15: an %Undef where a %Bool = type { i1 } was defined
# is a verifier error) -- and a brand costs an insertvalue/extractvalue pair
# a post-T2 rewrite can unwind with no analysis.
#
# WHAT IS NOT T2'S here is T1's, asked of Chalk::IR::Analysis: which types
# are no value's (not_a_value_type), whether a literal is fractional
# (is_fractional_constant).
our %CANDIDATES = (
    # Decidable today: one candidate. BRANDED where the machine type is shared.
    Boolean  => ['%Boolean'],    # { i1 }, distinct from Undef
    Undef    => ['%Undef'],      # { i1 }, distinct from Boolean
    Object   => ['%Object*'],
    ArrayRef => ['%ArrayRef*'],
    HashRef  => ['%HashRef*'],
    CodeRef  => ['%CodeRef*'],
    Array    => ['%Array*'],
    Hash     => ['%Hash*'],

    # THE SPINE: each names its type and everything below it.
    Int      => ['i64'],                       # until intervals: one
    Num      => ['double', 'i64'],
    Str      => ['%Str', 'double', 'i64'],
    Scalar   => ['%Slot', '%Str', 'double', 'i64'],
);

# narrow_graphs(\%graphs) -> void. Rewrites every node's stamp in place: IN
# PLACE because the stamp field is the same slot before and after, so every
# consumer holding a node sees the narrowed type.
sub narrow_graphs ($class, $graphs) {
    for my $gname (sort keys %$graphs) {
        my %seen;
        for my $node ($graphs->{$gname}->nodes->@*) {
            next unless blessed($node);
            next if $seen{ $node->id }++;
            $class->_narrow_node($node, $gname);
        }
    }
    return;
}

# _narrow_node($node, $gname) -> void. One node's Chalk stamp becomes its
# LLVM type, or narrowing refuses and says why.
sub _narrow_node ($class, $node, $gname) {
    my $stamp = $node->stamp;

    # AN UNSTAMPED node is T1's gap (inference never reached it), left alone
    # so the NO-REPR diagnostics keep naming the right pass.
    return unless defined $stamp;

    # ALREADY AN LLVM TYPE (narrowing is idempotent): recognised by not being
    # a Chalk lattice name, so nothing has to be threaded.
    my $why = Chalk::IR::Analysis::not_a_value_type($stamp);
    return unless exists $CANDIDATES{$stamp} || $why || $stamp eq 'Unknown';

    die "T2: cannot narrow '$stamp' in $gname (op=" . $node->operation . "): $why. "
      . "Reaching T2 with it means non-value vocabulary leaked into the value pipeline.\n"
        if $why;

    # UNKNOWN IS T2 REPORTING ITS OWN FAILURE, where the decision is made,
    # with the graph still in hand -- not an emission-time error blaming T1.
    die "T2: cannot narrow 'Unknown' in $gname (op=" . $node->operation . "). Unknown is the "
      . "lattice TOP -- inference ran and could not determine this node, so there is no "
      . "candidate set to choose from. This is T2 failing to narrow, not a missing table entry.\n"
        if $stamp eq 'Unknown';

    $node->set_stamp($class->_choose($node, $stamp));
    return;
}

# llvm_type_for($chalk_type) -> the LLVM type a DECLARED type narrows to.
#
# THE MOP IS NOT REWRITTEN, DELIBERATELY: a field's, a method's or a sub's
# declared type is the program's own view of itself, and the MOP is meant to
# become a RUNTIME metaobject (`$obj->meta->field('n')->type` must answer
# `Int`, which is what the language says). So the Chalk type stays canonical
# on the metaobject and the LLVM type is derived here, on demand -- one
# decision in one place, not one per consumer.
sub llvm_type_for ($class, $chalk_type) {
    return undef unless defined $chalk_type;
    # Already an LLVM type, or a name narrowing does not take (Unknown here is
    # the caller's to diagnose): passed through.
    return $chalk_type unless exists $CANDIDATES{$chalk_type};
    return $CANDIDATES{$chalk_type}[0];
}

# narrow_num($node) -> 'double' or 'i64'. THE ONLY MULTI-CANDIDATE CHOICE.
#
# Getting it wrong is a live miscompile (t/corpus/mdtest/arithmetic.md: `my
# $n = 9007199254740993; my $s = $n + 0.0` -- the sitofp cannot hold an i64
# above 2^53). THREE CONSTRAINT SOURCES (36 of 54 Num nodes directly, 46 of
# 54 after propagation: docs/plans/2026-09-04-narrowing-reaches-85-percent.md):
#
#   (a) a consumer states a requirement
#   (b) a fractional literal constrains itself
#   (c) every value input is already Int -- the inputs PROVE i64
#
# ORDER MATTERS: fractional evidence is POSITIVE evidence about this value,
# "all inputs are Int" evidence about its operands, so a node with one
# fractional and one integral input is a double.
sub narrow_num ($class, $node) {
    my $stamp = $node->stamp // '';
    die "T2: narrow_num expects a Num-stamped node, got '"
      . ($stamp eq '' ? '(unstamped)' : $stamp) . "' (op="
      . $node->operation . ")\n"
        unless $stamp eq 'Num';

    # (b) A FRACTIONAL LITERAL IS ITS OWN CONSTRAINT, and a fractional input
    # propagates the same way -- before (c), so Add(Int, 1.5) is a double.
    return 'double' if Chalk::IR::Analysis::is_fractional_constant($node);
    for my $in (($node->inputs // [])->@*) {
        next unless defined $in && ref $in && $in->can('operation');
        return 'double' if Chalk::IR::Analysis::is_fractional_constant($in);
    }

    # (c) EVERY VALUE INPUT IS ALREADY Int: nothing needs a float -- the 2^53
    # case, a Coerce(Int -> Num) over an Int constant.
    my @vals = grep { defined $_ && ref $_ && $_ isa Chalk::IR::Value } (($node->inputs // [])->@*);
    if (@vals) {
        my $every_int = 1;
        for my $v (@vals) {
            $every_int = 0 unless ($v->stamp // '') eq 'Int';
        }
        return 'i64' if $every_int;
    }

    # DEFAULT, FORCED RATHER THAN CHOSEN. A named rule, so a test can INVERT it
    # to prove a constraint is load-bearing rather than agreeing with it.
    return $class->_default_num_repr;
}

# _default_num_repr -> the representation an unobserved Num takes. FORCED:
# double and i64 are incomparable and the emitter needs one (GHC: no
# representation polymorphism with principal types). `i64` because it is
# perl's -- a literal stays an IV until something makes it an NV, and IV_MAX+1
# promotes rather than wraps.
sub _default_num_repr ($class) { return 'i64' }

# _choose($node, $stamp) -> the single LLVM type: the head of the candidate
# set, the widest safe choice -- what "nothing has been proven" means.
# `%Slot` for an unnarrowed Scalar is the FALLBACK, not the goal.
sub _choose ($class, $node, $stamp) {
    my $candidates = $CANDIDATES{$stamp}
        or die "T2: no candidate set for '$stamp' (op=" . $node->operation . ")\n";
    return $candidates->[0];
}

1;
