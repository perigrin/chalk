# ABOUTME: Perl type hierarchy and function/operator type signatures for parse-time validation.
# ABOUTME: Consumed by TypeInference semiring; sits alongside KeywordTable and PrecedenceTable.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Perl::TypeLibrary {
    # Type hierarchy. Each type maps to its direct parent; 'Unknown' has no
    # parent. 'None' is the bottom type (subtype of everything).
    #
    # This is the CANONICAL lattice. It matches the formal paper's "Complete Type
    # Hierarchy" (2-perl-types-formal.md), which is verified mechanically over all
    # 729 ordered pairs by types-paper/appendix-a/lattice-check.pl. B::SoN's
    # SoN::IR::Stamp mirrors this table; the two must not drift.
    #
    # Unknown is the sole root, matching the paper's tree.
    # WHAT A TYPE MAY BE REPRESENTED BY (perigrin, 2026-08-29), which this
    # table determines and which nothing in the IR should encode:
    #
    #   a Chalk type may be represented by the representation of ANY OF ITS
    #   SUBTYPES, or by its own.
    #
    # So `Str`'s candidates are its own (%Str) plus everything in its downward
    # cone -- Num's, Int's, Boolean's, VString's. That is WHY a Str may be a
    # `double`: Num <: Str, so Num's representation is available to it whenever
    # what actually flows is a Num. Not a special case, and not (as an earlier
    # note here framed it) a matter of "what nothing observes" -- observation
    # analysis is how T2 PROVES which subtype's representation applies; the
    # SUBTYPE RELATION is what makes it legal.
    #
    # And the other half, which is the constraint on this side: CHALK'S IR
    # NEITHER KNOWS NOR CARES what the representation is or should be. The type
    # is the IR's business; the representation is T2's, chosen per site with
    # context in hand (see Target/LLVM/Context.pm::_repr_to_llvm_type, whose
    # one-argument shape cannot express that). `Node.pm:55` already records the
    # structural half -- there is no separate `representation` field, it was
    # folded into `stamp` -- and retiring the deprecated alias is the remaining
    # work.

    my %PARENT = (
        # Scalar branch (arity 1)
        Scalar    => 'List',        # {1} is a subset of {0,1,2,...}
        Void      => 'List',        # arity 0: yields nothing. Sibling of Scalar.
        Undef     => 'Scalar',
        Str       => 'Scalar',
        Num       => 'Str',
        Int       => 'Num',
        # BOOLEAN IS IN NEITHER Str NOR Num. It sat under Str, described as
        # "Str carrying boolean marking", because every string operation works
        # on a boolean with no coercion -- "x".true."y".false."z" is "x1yz",
        # length(true)/length(false) are 1/0, uc(true) is "1". That is
        # SUBSTITUTABILITY, and it is only half the subtype test:
        #
        #     A <: B  iff  (A subset-of B) and (every op of B holds for A)
        #
        # Membership is the other half, and it fails. Str membership asks for
        # an ADMISSIBLE detour type S preserving the value. Measured on 5.42.0:
        #
        #     false   direct Str ""     via Num "0"    DIFFER
        #     true    direct Str "1"    via Num "1"    agree
        #
        # `true` is preserved; `false` is not, and one counterexample falsifies
        # membership. S=Str is inadmissible (vacuous -- identity on every Str)
        # and S=Boolean is circular (Str's definition would depend on Boolean,
        # inverting the stratification Scalar -> Str -> Num -> Int).
        #
        # TESTING ONE VALUE GETS THIS WRONG, since `true` agrees. So does
        # testing one factor. perl-type-system-formal.md always said so:
        # "Scalar contains values that belong neither to Str nor to Num -
        # including Boolean (true/false), Undef (undef), Ref (references), and
        # DualVars". The implementation contradicted the spec.
        #
        # CONSEQUENCE FOR CONSUMERS: join(Boolean, Int) was Str and is now
        # Scalar, which is why this is not cosmetic -- the old answer invited a
        # consumer to treat `-c $f` and `length $x` as the same kind of thing.
        # They have no common type below Scalar. In the LLVM backend Scalar
        # ENCODES AS %Slot (a tagged 16-byte cell) where Str is %Str (an
        # unboxed ptr/len aggregate), so such a join now yields a boxed value
        # that must be read back through its tag -- a refusal there is the
        # boundary working, not a regression.
        Boolean   => 'Scalar',      # in Scalar, in neither Str nor Num
        VString   => 'Str',         # v-strings: Str carrying 'V' magic
        DualVar   => 'Scalar',      # in Scalar but in neither Str nor Num
        Ref       => 'Scalar',
        Object    => 'Ref',
        Regex     => 'Object',      # compiled patterns: blessed into Regexp
        ScalarRef => 'Ref',
        LValueRef => 'ScalarRef',   # \substr: aliases a RANGE, not a whole scalar
        ArrayRef  => 'Ref',
        HashRef   => 'Ref',
        CodeRef   => 'Ref',
        GlobRef   => 'Ref',

        # Collection branch
        List      => 'Unknown',
        Array     => 'List',
        Hash      => 'List',

        # These four parent straight to the root. WHY THEY BELONG THERE IS NOT
        # SETTLED -- what follows is what is measured, and what is not.
        #
        # A PRIOR RATIONALE HERE WAS FALSE, and it misled a reader on
        # 2026-09-01. It said "Named entities rather than expression results.
        # Each is reachable only by naming it or through a glob ... `f` is a
        # call site rather than the sub". That is wrong about `Code`:
        # `sub { ... }` is an expression yielding a subroutine with no name and
        # no symbol-table entry, and `\&f` takes one directly without a glob.
        # An anonymous `method { ... }` under `feature class` is the same.
        #
        # It also invited a reading it never claimed. "Named entities rather
        # than expression results" distinguishes how a thing is OBTAINED; it
        # says nothing about whether it is a value. Membership in this table
        # already settles that question in the affirmative -- the table types
        # VALUES, so anything in it is a value at some point in the program.
        # The backend agrees: `_box_payload` boxes a CodeRef into a %Slot
        # alongside Int, Num and Str.
        #
        # MEASURED, and unaffected by the above (2026-08-28, exhaustive over
        # all 26 members): these four parenting straight to `Unknown` is the
        # ONLY route by which a join CLIMBS to the root. 180 ordered pairs join
        # to `Unknown` with neither operand `Unknown`, and every one involves
        # Code/Glob/IO/Format (48 appearances each); every other type appears
        # only when paired with one of them. Ordinary joins stay put --
        # join(List,Int) = List, join(Array,Int) = List,
        # join(Int,ArrayRef) = Scalar.
        #
        # WHAT IS NOT ESTABLISHED. That those 180 joins are program-level
        # ERRORS rather than gaps in this table. An earlier version of this
        # comment asserted it ("a program-level error rather than an
        # imprecision"), resting on the false rationale above. With the
        # rationale gone the inference is gone: a join climbing to the root may
        # equally mean one operand is parented too high. Do not treat
        # `join(Code, X) = Unknown` as evidence about the PROGRAM until a
        # narrower parent for Code has been ruled out.
        #
        # A NARROWER PARENT IS UNTESTED, not rejected. `Ref` is wrong (a Code
        # is not a reference; CodeRef already sits under Ref). Between `Scalar`
        # and `List` the question is whether a bare sub flattens in list
        # context, which nobody here has measured. `Glob <: List` was PROPOSED
        # on 2026-08-28 for the five-typed-slots reading
        # (*x{SCALAR,ARRAY,HASH,CODE,IO} are all populable at once) and
        # declined; that decision rested on the same false rationale and is
        # worth reopening rather than citing.
        Code      => 'Unknown',     # subroutines
        Glob      => 'Unknown',     # symbol table entries, distinct from GlobRef
        IO        => 'Unknown',     # filehandles/directory handles (*STDOUT{IO})
        Format    => 'Unknown',     # write() templates
    );

    # Cache for is_subtype lookups
    my %subtype_cache;

    # Bitfield representation for O(1) subtype checking (design doc Section 3.3).
    # Each leaf type gets a unique bit. Parent types are the OR of all descendant bits.
    # IsSubtype(child, parent) = (parent & child) == child.
    my %TYPE_BITSET;
    {
        # Assign a unique bit position to each leaf type.
        my $bit = 0;
        my @leaf_types = qw(
            Undef Boolean VString Regex Int DualVar Void
            LValueRef ArrayRef HashRef CodeRef GlobRef
            Array Hash Code Glob IO Format
        );
        for my $type (@leaf_types) {
            $TYPE_BITSET{$type} = 1 << $bit++;
        }

        # Internal intermediate types get their own bit too, so that
        # is_subtype(Num, Num) and is_subtype(Str, Str) work via exact match
        # and subtypes include their ancestor's bit.
        # Object and ScalarRef are here rather than above because each now has a
        # child (Regex, LValueRef) and so is no longer a leaf.
        $TYPE_BITSET{Num} = (1 << $bit++);
        $TYPE_BITSET{Str} = (1 << $bit++);
        $TYPE_BITSET{Object} = (1 << $bit++);
        $TYPE_BITSET{ScalarRef} = (1 << $bit++);
        $TYPE_BITSET{Ref} = (1 << $bit++);
        $TYPE_BITSET{Scalar} = (1 << $bit++);
        $TYPE_BITSET{List} = (1 << $bit++);

        # Now propagate: each type's bitset includes its own bit OR all descendant bits.
        # Walk the hierarchy bottom-up by iterating until stable.
        for my $child (keys %PARENT) {
            my $current = $child;
            while (my $parent = $PARENT{$current}) {
                $TYPE_BITSET{$parent} //= 0;
                $TYPE_BITSET{$parent} |= $TYPE_BITSET{$child};
                $current = $parent;
            }
        }

        # Unknown is the structural root — OR of all types.
        $TYPE_BITSET{Unknown} = 0;
        for my $type (keys %TYPE_BITSET) {
            $TYPE_BITSET{Unknown} |= $TYPE_BITSET{$type};
        }

        # Unknown is the only top: inference has not determined the type, and
        # nothing may be done with the value until it is NARROWED. It is a claim
        # about our knowledge, not a licence to skip checking.
        #
        # Distinct from Scalar, which is a legitimate static answer — one value
        # whose concrete type was never narrowed. A backend GAP must be able to
        # tell "this scalar type is not lowered yet" from "nothing ever typed
        # this".

        # None is the bottom type — 0 (subtype of everything by convention)
        $TYPE_BITSET{None} = 0;
    }

    # Builtin function signatures: argument types, minimum arity, and return type.
    # Last entry in arg_types applies to all remaining positions (variadic).
    my %BUILTIN_SIGNATURES = (
        # Array operations
        # Variadic positions use List (Perl flattening: accepts scalars AND arrays)
        push    => { min_arity => 2, arg_types => ['Array', 'List'],              return_type => 'Int' },
        pop     => { min_arity => 1, arg_types => ['Array'],                     return_type => 'Scalar' },
        shift   => { min_arity => 1, arg_types => ['Array'],                     return_type => 'Scalar' },
        unshift => { min_arity => 2, arg_types => ['Array', 'List'],              return_type => 'Int' },
        splice  => { min_arity => 1, arg_types => ['Array', 'Num', 'Num', 'List'], return_type => 'List' },

        # Hash operations
        keys    => { min_arity => 1, arg_types => ['Hash'],                      return_type => 'List' },
        values  => { min_arity => 1, arg_types => ['Hash'],                      return_type => 'List' },
        delete  => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Scalar' },
        exists  => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Boolean' },
        each    => { min_arity => 1, arg_types => ['Hash'],                      return_type => 'List' },

        # String operations
        length  => { min_arity => 0, arg_types => ['Str'],                       return_type => 'Int' },
        chomp   => { min_arity => 0, arg_types => ['List'],                       return_type => 'Int' },
        chop    => { min_arity => 0, arg_types => ['List'],                       return_type => 'Str' },
        chr     => { min_arity => 1, arg_types => ['Int'],                       return_type => 'Str' },
        ord     => { min_arity => 0, arg_types => ['Str'],                       return_type => 'Int' },
        join    => { min_arity => 2, arg_types => ['Str', 'List'],                return_type => 'Str' },
        split   => { min_arity => 1, arg_types => ['Regex', 'Str', 'Num'],       return_type => 'List' },
        sprintf => { min_arity => 1, arg_types => ['Str', 'List'],                return_type => 'Str' },
        substr  => { min_arity => 2, arg_types => ['Str', 'Num', 'Num'],         return_type => 'Str' },

        # Type test
        defined => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Boolean' },
        ref     => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Str' },

        # Context
        scalar  => { min_arity => 1, arg_types => ['List'],                       return_type => 'Scalar' },

        # Control (variadic: accept scalars and arrays via flattening)
        die     => { min_arity => 0, arg_types => ['List'],                       return_type => 'None' },
        warn    => { min_arity => 0, arg_types => ['List'],                       return_type => 'Boolean' },

        # OO
        bless   => { min_arity => 1, arg_types => ['Ref', 'Str'],               return_type => 'Object' },

        # I/O (variadic)
        print   => { min_arity => 0, arg_types => ['List'],                       return_type => 'Boolean' },
        say     => { min_arity => 0, arg_types => ['List'],                       return_type => 'Boolean' },

        # Flow control (variadic: return LIST)
        return  => { min_arity => 0, arg_types => ['List'],                       return_type => 'List' },

        # Block-first builtins (parse via CallExpression alt 2/3)
        map     => { min_arity => 2, arg_types => ['Code', 'List'],              return_type => 'List' },
        grep    => { min_arity => 2, arg_types => ['Code', 'List'],              return_type => 'List' },
        sort    => { min_arity => 1, arg_types => ['List'],                      return_type => 'List' },
    );

    # Returns the signature hash for a builtin, or undef if not a builtin.
    sub get_builtin($name) {
        return $BUILTIN_SIGNATURES{$name};
    }

    # Returns true if the name is a known builtin function.
    sub has_builtin($name) {
        return exists $BUILTIN_SIGNATURES{$name} ? true : false;
    }

    # Types that represent polymorphic containers at parse time — a variable
    # typed as Scalar could hold Str, Int, Num, etc. at runtime. These pass
    # permissively against any subtype requirement within their branch.
    my %POLYMORPHIC_TYPES = map { $_ => true } qw(Scalar List);

    # Returns true if $actual_type satisfies $required_type.
    # undef actual passes permissively (unknown type at parse time).
    # A 'List' requirement always passes -- see the flattening rule below.
    # For polymorphic types (Scalar, List — assigned to variables),
    # also pass when the required type is a subtype of actual, since the
    # variable could hold any value within its type at runtime.
    sub type_satisfies($actual_type, $required_type) {
        return true if !defined $actual_type;
        # Subtype: Int satisfies Num (child → parent)
        return true if is_subtype($actual_type, $required_type);
        # Polymorphic supertype: Scalar satisfies Str (variable could hold Str at runtime)
        # but Str does NOT satisfy Int (concrete type mismatch)
        if ($POLYMORPHIC_TYPES{$actual_type}) {
            return true if is_subtype($required_type, $actual_type);
        }
        # Perl flattens any scalar/array/hash into list context at runtime.
        # Any concrete type satisfies a `List` position.
        return true if $required_type eq 'List';
        return false;
    }

    # Returns the bitfield for a type name, or undef if unknown.
    sub type_bitset($type) {
        return $TYPE_BITSET{$type};
    }

    # Returns true if $child is a subtype of (or equal to) $parent.
    # is_lattice_type($name) -> is this a member of the type lattice at all?
    #
    # The lattice is %PARENT, and it is lexical -- so a caller outside this
    # module cannot ask "is this a type?" without one of these. That gap is why
    # machine ENCODINGS have been able to sit in type-shaped fields unchallenged:
    # `Slot` (the {i1 defined, i64 payload} cell) reaches the stamp field via
    # the OOB path, and nothing could cheaply tell it apart from `Undef`.
    #
    # Use it at any boundary where a type-shaped value crosses out of the
    # compiler -- serialization being the first, since a non-lattice name
    # written to the wire turns an in-memory confusion into a persistent one.
    # `Unknown` (top) and `None` (bottom) are members but are NOT %PARENT keys:
    # every branch points UP to Unknown and nothing points below None, so
    # neither has a parent entry of its own. Testing %PARENT alone rejects both
    # -- verified, and it would have silently dropped every deliberate
    # `Unknown` the producer sends.
    sub is_lattice_type($name) {
        return false unless defined $name;
        return true if $name eq 'Unknown' || $name eq 'None';
        return exists $PARENT{$name} ? true : false;
    }

    # Uses O(1) bitwise AND when both types have bitfields.
    # Falls back to parent-chain walking for unknown types.
    # None is subtype of everything.
    sub is_subtype($child, $parent) {
        return true if $child eq $parent;
        return true if $child eq 'None';

        # O(1) bitwise check: (parent_bits & child_bits) == child_bits
        my $child_bits  = $TYPE_BITSET{$child};
        my $parent_bits = $TYPE_BITSET{$parent};
        if (defined $child_bits && defined $parent_bits) {
            return ($parent_bits & $child_bits) == $child_bits ? true : false;
        }

        # Fallback for types not in the bitfield (e.g. user-defined)
        my $cache_key = "$child\0$parent";
        return $subtype_cache{$cache_key} if exists $subtype_cache{$cache_key};

        my $current = $child;
        while (my $next = $PARENT{$current}) {
            if ($next eq $parent) {
                $subtype_cache{$cache_key} = true;
                return true;
            }
            $current = $next;
        }

        $subtype_cache{$cache_key} = false;
        return false;
    }

    # Returns the ancestor chain of $type, nearest first, including $type itself.
    # 'Unknown' is the structural root and terminates every chain; None is
    # handled by the callers.
    sub _ancestors($type) {
        my @chain = ($type);
        my $current = $type;
        while (my $next = $PARENT{$current}) {
            push @chain, $next;
            $current = $next;
        }
        push @chain, 'Unknown' unless $chain[-1] eq 'Unknown';
        return @chain;
    }

    # Least upper bound: the nearest type that both arguments are subtypes of.
    #
    # This is what a merge point needs — two branches of a ternary, two callsites
    # of the same sub, a Phi's inputs. The result keeps as much information as is
    # true of BOTH inputs and no more.
    #
    # None is the identity (T join None == T), which is what lets a recursive
    # function type from its base case: the recursive arm contributes None on the
    # first pass, so Int join None == Int rather than collapsing to a top.
    #
    # Uniqueness depends on %PARENT being a TREE (one parent per type). A second
    # parent edge would allow several minimal upper bounds and no least one, so
    # anything adding one must re-establish this.
    sub join_types($left, $right) {
        return $left if !defined $right;
        return $right if !defined $left;
        return $left if $left eq $right;

        # None is bottom: the identity for join.
        return $right if $left eq 'None';
        return $left  if $right eq 'None';

        # Unknown is the pessimistic top and absorbs: joining against a type we
        # failed to infer cannot manufacture information.
        return 'Unknown' if $left eq 'Unknown' || $right eq 'Unknown';

        return $right if is_subtype($left, $right);
        return $left  if is_subtype($right, $left);

        # Nearest common ancestor: first element of the left chain that also
        # appears in the right chain. Walking nearest-first makes it the LEAST
        # upper bound rather than merely an upper bound.
        my %right_chain = map { $_ => 1 } _ancestors($right);
        for my $ancestor (_ancestors($left)) {
            return $ancestor if $right_chain{$ancestor};
        }
        return 'Unknown';
    }

    # Greatest lower bound: the nearest type that is a subtype of both arguments.
    #
    # Used for narrowing — a value reaching a position that requires Str, already
    # known to be Num, is Num. Unrelated types meet at None, which is the correct
    # answer (no value inhabits both) and not an error.
    sub meet_types($left, $right) {
        return $left if !defined $right;
        return $right if !defined $left;
        return $left if $left eq $right;

        return 'None' if $left eq 'None' || $right eq 'None';

        # Unknown is top for meet: it constrains nothing, so the other side wins.
        return $right if $left eq 'Unknown';
        return $left  if $right eq 'Unknown';

        return $left  if is_subtype($left, $right);
        return $right if is_subtype($right, $left);

        # Neither contains the other: nothing inhabits both.
        return 'None';
    }

    # Narrows a type based on evaluation context.
    # Complements type_satisfies (compatibility check) with context-based refinement.
    # type_satisfies answers "can X be used as Y?" while narrow_type answers
    # "what does X become when consumed in context C?"
    sub narrow_type($type, $context) {
        return $type unless defined $type && defined $context;
        if ($context eq 'Scalar') {
            return 'Int' if $type eq 'Array' || $type eq 'Hash';  # scalar(@arr) = count
            return 'Scalar' if $type eq 'List';
            return $type;  # already scalar-ish
        }
        if ($context eq 'Boolean') {
            return 'Boolean';
        }
        if ($context eq 'Void') {
            return undef;  # discard type info
        }
        # List context or unknown: keep as-is
        return $type;
    }

    # Binary operator signatures: operand types and result type.
    my %BINARY_OP_SIGNATURES;
    {
        my $num_num_num  = { left => 'Num',    right => 'Num',   result => 'Num' };
        my $num_num_bool = { left => 'Num',    right => 'Num',   result => 'Boolean' };
        my $str_str_str  = { left => 'Str',    right => 'Str',   result => 'Str' };
        my $str_str_bool = { left => 'Str',    right => 'Str',   result => 'Boolean' };
        # Operators that accept anything and whose RESULT is one of the operands
        # rather than a type of their own: `&&` yields whichever side it
        # short-circuited on, `=` yields the value assigned. The result is
        # genuinely undetermined at signature level -- Unknown, not List, since
        # these produce a single value and not a sequence.
        my $any_any_any  = { left => 'List',    right => 'List',   result => 'Unknown' };
        my $any_any_bool = { left => 'List',    right => 'List',   result => 'Boolean' };
        my $int_int_int  = { left => 'Int',    right => 'Int',   result => 'Int' };

        # Arithmetic
        for my $op (qw(+ - * / % **)) {
            $BINARY_OP_SIGNATURES{$op} = $num_num_num;
        }

        # String
        $BINARY_OP_SIGNATURES{'.'} = $str_str_str;
        $BINARY_OP_SIGNATURES{'x'} = { left => 'Str', right => 'Int', result => 'Str' };

        # Numeric comparison
        for my $op (qw(== != < > <= >= <=>)) {
            $BINARY_OP_SIGNATURES{$op} = $num_num_bool;
        }

        # String comparison
        for my $op (qw(eq ne lt gt le ge cmp)) {
            $BINARY_OP_SIGNATURES{$op} = $str_str_bool;
        }

        # Logical (short-circuit, return operand)
        for my $op ('&&', '||', '//', 'and', 'or') {
            $BINARY_OP_SIGNATURES{$op} = $any_any_any;
        }
        $BINARY_OP_SIGNATURES{'xor'} = $any_any_bool;

        # Bitwise
        for my $op (qw(& | ^ << >>)) {
            $BINARY_OP_SIGNATURES{$op} = $int_int_int;
        }

        # Type test
        $BINARY_OP_SIGNATURES{'isa'} = { left => 'Scalar', right => 'Str', result => 'Boolean' };

        # Regex binding
        $BINARY_OP_SIGNATURES{'=~'} = { left => 'Str', right => 'Regex', result => 'Boolean' };
        $BINARY_OP_SIGNATURES{'!~'} = { left => 'Str', right => 'Regex', result => 'Boolean' };

        # Range
        $BINARY_OP_SIGNATURES{'..'} = { left => 'Int', right => 'Int', result => 'List' };
        $BINARY_OP_SIGNATURES{'...'} = { left => 'Int', right => 'Int', result => 'List' };

        # Assignment
        $BINARY_OP_SIGNATURES{'='} = $any_any_any;
    }

    # Returns the signature hash for a binary operator, or undef if unknown.
    sub get_binary_op($op) {
        return $BINARY_OP_SIGNATURES{$op};
    }

    # Unary operator signatures: operand type and result type.
    my %UNARY_OP_SIGNATURES = (
        '-'   => { operand => 'Num', result => 'Num' },
        '+'   => { operand => 'Num', result => 'Num' },
        '!'   => { operand => 'List', result => 'Boolean' },
        'not' => { operand => 'List', result => 'Boolean' },
        '~'   => { operand => 'Int', result => 'Int' },
        '\\'  => { operand => 'List', result => 'Ref' },
    );

    # Returns the signature hash for a unary operator, or undef if unknown.
    sub get_unary_op($op) {
        return $UNARY_OP_SIGNATURES{$op};
    }

    # ------------------------------------------------------------------
    # Operand types for the IR
    # ------------------------------------------------------------------
    #
    # THERE IS NO REAL OPERATOR/BUILTIN DISTINCTION. Measured against perl's
    # own optree: `length` is `<1> length`, `ord` is `<1> ord`, `x` is
    # `<2> repeat`, `.` is `<+> multiconcat`. The `<1>`/`<2>` markers are
    # ARITY, not category -- a "builtin" and an "operator" are the same kind of
    # thing, and `length` differs from `x` only in taking one argument instead
    # of two. Perl's own documentation of the split (perlop vs perlfunc) is a
    # SPELLING distinction: named-word operators are listed as functions and
    # punctuation ones as operators, but `x` and `repeat` are one op.
    #
    # This library keeps three tables only because they were populated by
    # three different parse paths and their entries have different SHAPES
    # (arg_types arrayref vs left/right vs operand). They are one signature
    # space, and the lookup below treats them as one: a position index over
    # whatever the entry calls its operands. Merging the tables outright is the
    # obvious follow-on and is deliberately NOT done here -- their readers
    # (get_builtin/get_binary_op/get_unary_op) are consumed by the parse layer,
    # and changing their shape is a separate change from giving the IR an
    # answer it currently lacks.
    #
    # IR op name -> the source-level name whose signature governs it. The
    # signature tables are keyed by SOURCE vocabulary (`length`, `eq`) because
    # that is what the parser sees; the IR is keyed by NODE vocabulary
    # (`Length`, `StrEq`). This is the one map between them, and it is the only
    # new fact needed to let the IR ask the same tables the parser asks --
    # rather than each IR-side consumer re-deriving the answer as its own
    # hand-kept op-name list.
    #
    # Deliberately PARTIAL. An op absent here yields undef and the caller
    # leaves the operand alone, so a missing entry is a MISSED coercion (a loud
    # GAP downstream) and never a wrong one.
    #
    # Every entry must name a node type the factory can actually build --
    # asserted by t/bootstrap/ir/typelibrary-is-the-coercion-authority.t. An
    # entry for a nonexistent node type reads as coverage while being
    # unreachable; `Ord` and `Chr` were exactly that, mapped here while no such
    # node type existed, until the test measured it.
    #
    # NOT the inverse of Actions.pm's %BINOP_MAP, which is many-to-one
    # (`&&`/`and` -> And, `&`/`&.` -> BitAnd) and so not invertible in general.
    my %IR_OP_SOURCE_NAME = (
        # One-argument ops.
        Length => 'length',

        # Two-argument ops. String comparison is (Str, Str) -> Boolean for every
        # member; Concat is (Str, Str) -> Str.
        StrEq  => 'eq',  StrNe  => 'ne',  StrLt => 'lt',
        StrGt  => 'gt',  StrLe  => 'le',  StrGe => 'ge',
        StrCmp => 'cmp',
        Concat => '.',

        # DIVIDE, AND ONLY DIVIDE, OF THE ARITHMETIC FAMILY. Perl's `/` is
        # float division as a matter of SEMANTICS -- 3/4 is 0.75, not 0 -- so
        # both operands are Num whatever the source wrote. `/` already carries
        # the (Num, Num) -> Num signature below; this line is the missing link
        # that lets `operand_repr_for_ir_op` reach it.
        #
        # ITS SIBLINGS STAY OUT FOR A MEASURED REASON, AND NOT THE ONE THIS
        # COMMENT FIRST GAVE. The original claim was that `+`, `-`, `*` are
        # "genuinely polymorphic in perl (Int+Int and Num+Num are both valid)".
        # That is FALSE: `"3" + "4"` is 7, `1 + "abc"` is 1 -- `+` numifies
        # both operands unconditionally, and %BINARY_OP_SIGNATURES has always
        # given `+ - * / % **` one shared (Num, Num) -> Num entry. What varies
        # between `1+2` and `1.5+2` is the RESULT representation (B::IV vs
        # B::NV), not the operand requirement, and this table answers the
        # operand question.
        #
        # They stay out because ADMITTING THEM WAS MEASURED AND BREAKS THE
        # GATE: 224 -> 184, worklist 3 -> 43. This table is not a passive
        # lookup -- it feeds `_required_operand_repr`, which drives
        # `_insert_str_coercions`, which MINTS Coerce nodes. Publishing a
        # requirement therefore changes the emitted graph rather than merely
        # recording an observation. See
        # docs/plans/2026-09-04-publishing-the-arithmetic-family-fails.md.
        #
        # `/` is admitted anyway because its requirement is additionally a
        # SEMANTIC one -- perl's division is float division, 3/4 is 0.75 -- and
        # the backend already enforces it, so publishing it aligns the table
        # with a rule the emitter was keeping to itself.
        #
        # The backend has always known this -- its Divide arm dies unless the
        # result repr is float, "If Num were ever mapped to an integral type,
        # this site must FAIL rather than quietly pick `sdiv`" -- so the
        # requirement existed as a BACKEND ASSERTION while being absent from
        # the table meant to publish it. Adding it here makes it an
        # OBSERVATION a narrowing pass can consume, rather than a rule only the
        # emitter enforces.
        Divide => '/',
    );

    # OBSERVATION-ONLY OPS: their operand requirements are real and readable,
    # but publishing them through %IR_OP_SOURCE_NAME would mint coercions and
    # break the gate (measured, 224 -> 184). They live here instead, reachable
    # only via `observed_operand_repr`.
    #
    # `+ - * **` numify both operands unconditionally -- measured, `"3" + "4"`
    # is 7 and `1 + "abc"` is 1 -- so `Num` is the honest observation even
    # though the RESULT representation varies (B::IV for 1+2, B::NV for
    # 1.5+2). `%` is the exception: 7.9 % 3 is 1, not 1.9, so perl truncates
    # both operands and its observation is `Int`.
    my %IR_OP_OBSERVED_NAME = (
        Add      => '+',
        Subtract => '-',
        Multiply => '*',
        Power    => '**',
        Modulo   => '%',

        # DELIBERATELY ABSENT -- BitAnd/BitOr/BitXor. Numeric `&` is
        # (Int, Int) -> Int while string-bitwise `&.` is a Str operator, and
        # BOTH lower to the same node type, so the NODE does not determine its
        # operand types and no single answer here is correct. Splitting the
        # node types is the fix; until then these decline, costing a coercion
        # opportunity rather than risking a wrong coercion.
        #
        # ALSO ABSENT -- Print. `print` is variadic with arg_types ['List'] BY
        # DESIGN, because perl flattens a LIST into it (`print @a`,
        # `print undef`, `print $ref` are all legal). The Print NODE's Str-only
        # contract is a different claim about a different thing; conflating them
        # would reject legal programs at parse time. See the `print @a` case in
        # t/corpus/mdtest/statements.md.
    );

    # IR ops whose operand position ACCEPTS A SET, not a single type. An
    # operand already in the set needs no conversion; one outside it is coerced
    # toward the signature's type as usual.
    #
    # There is exactly one entry, and it is a BRIDGE OVER A PRODUCER
    # CONFLATION rather than a fact about perl. Measured, perl's `length` is
    # STRICTLY Str -- `length(@a)` on a 3-element array is 1, not 3, because
    # @a goes to scalar context (3) and `length("3")` is 1. And `scalar(@a)`
    # is not an operator at all: its optree is a bare `<0> padav[@a] s`, the
    # array in scalar context, with no op of its own.
    #
    # Chalk's producer nonetheless mints a `Length` node for BOTH -- genuine
    # `length($str)` and @a-in-scalar-context (FromOptree.pm:1362, "scalar
    # context and yields the element count (a Length)"). So the IR node stands
    # for two unrelated source constructs, and its operand set looks
    # polymorphic ([Array ArrayRef Hash HashRef Str], which is what
    # TypedInvariant records) only because of that merge. TypeLibrary is RIGHT
    # that `length => ['Str']`; the node is what is overloaded.
    #
    # Without this bridge the element-count use reads as a Str position holding
    # an ArrayRef and gets stringified -- measured, that un-lowered eight
    # corpus cases while the Str arm of the same node kept working, so only the
    # aggregate half showed it.
    #
    # THE REAL FIX is to split the node: an element-count `Length` is a
    # different operator from a byte-length `Length`, exactly as `$#a` was
    # already split out for being Length-1 rather than Length. That is a
    # producer change. Until then this entry keeps the conflated node honest
    # instead of letting a signature answer for a construct it does not
    # describe.
    #
    # Note the parse-time table could not express a set anyway: type_satisfies
    # takes ONE required type, so widening arg_types would change every reader.
    my %IR_OP_ACCEPTED_REPRS = (
        # Length KEEPS the aggregates, deliberately. The producer split Count
        # out of it (93a2d12) so a post-split wire sends Count for
        # `scalar(@a)` -- but a PRE-split wire still sends Length, and this
        # loader reads JSON of unknown provenance. Measured: narrowing to Str
        # alone cost 10 cases against pin 8c15e32 (205 -> 195), every one a
        # Length node the older producer legitimately emits.
        #
        # The narrowing is the PRODUCER's to make, because it decides which
        # node to emit. The consumer stays permissive.
        Length => { map { $_ => 1 } qw(Array ArrayRef Hash HashRef Str) },
        # Count is the aggregate half. `List` is the lattice parent over Array
        # and Hash: scalar(%h) is the key count and the answer is Int either
        # way, so the set spans both the concrete kinds and their parent.
        Count  => { map { $_ => 1 } qw(Array ArrayRef Hash HashRef List) },
    );

    # accepts_operand_repr($ir_op, $repr) -> true when the op takes this repr
    # as-is at any position, so no coercion is wanted.
    sub accepts_operand_repr($ir_op, $repr) {
        return false unless defined $repr;
        my $set = $IR_OP_ACCEPTED_REPRS{$ir_op} or return false;
        return $set->{$repr} ? true : false;
    }

    # operand_repr_for_ir_op($ir_op, $position) -> required repr, or undef.
    #
    # The coercion TARGET for one operand position of an IR node, read from the
    # same signature tables the parser uses. Returns undef when the op is not
    # mapped, its signature is unknown, or the position is unconstrained --
    # each of which means "no opinion", not "List". A coercion to List is not a
    # coercion, so 'List' reads as undef.
    #
    # $position is the operand's index in the SIGNATURE -- left is 0, right is
    # 1 -- and NOT its index in a node's inputs array. Those differ: a BinOp
    # node carries a leading control slot, so its left operand sits at
    # inputs[1]. Callers walking an inputs array must convert.
    #
    # A trailing 'List' in arg_types is variadic and covers all later positions,
    # matching how the parse-time checker reads the same table. That rule
    # applies ONLY to signatures that are actually variadic: `length` is
    # arg_types => ['Str'], one entry and not variadic, so it has no opinion
    # about a second operand it does not take. Extending the last entry
    # unconditionally would make this answer for positions the operator does
    # not have -- and an answer where there is no authority is exactly what
    # this accessor exists to avoid.
    sub operand_repr_for_ir_op($ir_op, $position) {
        my $name = $IR_OP_SOURCE_NAME{$ir_op} // return undef;

        my $want;
        if (my $sig = $BUILTIN_SIGNATURES{$name}) {
            my $args = $sig->{arg_types} // return undef;
            $want = $position <= $args->$#*  ? $args->[$position]
                  : _is_variadic($args)      ? $args->[-1]
                  :                            undef;
        }
        elsif (my $bin = $BINARY_OP_SIGNATURES{$name}) {
            $want = $position == 0 ? $bin->{left} : $bin->{right};
        }
        elsif (my $un = $UNARY_OP_SIGNATURES{$name}) {
            $want = $position == 0 ? $un->{operand} : undef;
        }

        return (defined $want && $want ne 'List') ? $want : undef;
    }

    # A builtin is variadic when its last argument slot is 'List' -- the
    # convention %BUILTIN_SIGNATURES already uses for the positions perl
    # flattens a list into (`print`, `join`, `sprintf`, `push`).
    sub _is_variadic($args) {
        return @$args && $args->[-1] eq 'List';
    }

    # The IR ops this library can answer for. Exposed so a test can assert
    # every entry names a node type that actually exists: an entry for a
    # nonexistent node is dead weight that reads as coverage, because no such
    # node is ever built and the entry can never be consulted.
    # observed_operand_repr($ir_op, $position) -> the repr this position is
    # OBSERVED to require, or undef for "nothing observes it".
    #
    # THE READ-ONLY TWIN OF `operand_repr_for_ir_op`, AND THE REASON THE TWO
    # ARE SEPARATE. That accessor looks passive and is not: its only consumer
    # is `Analysis::_required_operand_repr`, whose two callers both MUTATE THE
    # GRAPH -- `_insert_str_coercions` mints Coerce nodes, and the retire pass
    # removes them. Publishing a requirement there does not record a fact, it
    # changes the emitted IR.
    #
    # Measured: admitting the arithmetic family to %IR_OP_SOURCE_NAME took the
    # corpus gate 224 -> 184 and the worklist 3 -> 43, because most of the
    # newly-stamped nodes were coercions the change itself created. See
    # docs/plans/2026-09-04-publishing-the-arithmetic-family-fails.md.
    #
    # A narrowing pass needs those same facts with NO side effect: "what does
    # this position require?" is the input to choosing a machine
    # representation, and asking it must not rewrite the graph being analysed.
    # This is that channel. Nothing it answers causes a node to be minted, so
    # it is free to answer for ops the coercion authority declines.
    #
    # It reads the SAME signature tables, so the two cannot drift on the facts
    # -- only on which ops each is willing to speak for.
    sub observed_operand_repr($ir_op, $position) {
        # Ops the coercion authority already publishes: defer to it, so a
        # single source stays single.
        if (defined(my $shared = operand_repr_for_ir_op($ir_op, $position))) {
            return $shared;
        }

        my $name = $IR_OP_OBSERVED_NAME{$ir_op} // return undef;

        # MODULO TRUNCATES, so its observation is Int even though `%` shares
        # the (Num, Num) -> Num entry with the rest of the family. Measured:
        # 7.9 % 3 is 1, not 1.9 -- perl truncates BOTH operands before
        # dividing.
        #
        # Overridden HERE rather than by giving `%` its own
        # %BINARY_OP_SIGNATURES entry, because that hash is also read by the
        # parser and by the coercion authority; editing it is the same class of
        # change that took the corpus gate 224 -> 184. The observation channel
        # has no such reach, so the narrower fix is the safe one.
        return 'Int' if $name eq '%';

        my $sig  = $BINARY_OP_SIGNATURES{$name} // return undef;
        my $want = $position == 0 ? $sig->{left} : $sig->{right};

        # 'List' is not a coercion target and not an observation either -- it
        # says "this position accepts a sequence", which constrains no
        # representation.
        return undef if !defined $want || $want eq 'List';
        return $want;
    }

    sub ir_ops_with_signatures() {
        return sort keys %IR_OP_SOURCE_NAME;
    }

    # ------------------------------------------------------------------
    # The collision guard
    # ------------------------------------------------------------------
    #
    # A source name can legitimately appear in more than one table: `-` is both
    # binary subtraction and unary negation. That is ARITY OVERLOADING, and the
    # tables agree about the operand type, so the lookup order does not matter.
    #
    # A CONFLICT is when they disagree -- the same name carrying different
    # operand types in two tables. Then whichever table `operand_repr_for_ir_op`
    # happens to consult first silently decides, and the answer is arbitrary.
    # The accessor's whole contract is that it answers only where it has
    # authority, so an arbitrary answer is worse than none.
    #
    # This does not fire today. It exists because the shape that would cause it
    # is one edit away: the plan for this accessor originally proposed deriving
    # the IR map by inverting Actions.pm's %BINOP_MAP, which is many-to-one
    # (`&`/`&.` both -> BitAnd), and that inversion is what would pair
    # conflicting signatures under one name.

    # Operand types of a signature entry, whatever shape it is stored in.
    sub _operand_types($sig) {
        return $sig->{arg_types}->@* if $sig->{arg_types};
        return ($sig->{left}, $sig->{right}) if exists $sig->{left};
        return ($sig->{operand}) if exists $sig->{operand};
        return ();
    }

    # Two signatures conflict when they disagree about a shared operand
    # position. A position present in one and absent from the other is arity
    # overloading, not disagreement.
    sub _signatures_conflict($left, $right) {
        my @left  = _operand_types($left);
        my @right = _operand_types($right);
        my $shared = @left < @right ? @left : @right;
        for my $i (0 .. $shared - 1) {
            next unless defined $left[$i] && defined $right[$i];
            return true if $left[$i] ne $right[$i];
        }
        return false;
    }

    # _signature_conflict_for($name) -> a description of the conflict, or undef.
    sub _signature_conflict_for($name) {
        my @found = grep { defined $_->[1] } (
            [ builtin => $BUILTIN_SIGNATURES{$name}    ],
            [ binary  => $BINARY_OP_SIGNATURES{$name}  ],
            [ unary   => $UNARY_OP_SIGNATURES{$name}   ],
        );
        return undef if @found < 2;

        for my $i (0 .. $#found - 1) {
            for my $j ($i + 1 .. $#found) {
                next unless _signatures_conflict($found[$i][1], $found[$j][1]);
                return "$name: $found[$i][0] and $found[$j][0] tables disagree";
            }
        }
        return undef;
    }

    # Every conflict among the source names the IR map actually routes through.
    # Empty is the invariant; a non-empty result is a defect to fix at the
    # table, not to work around at the call site.
    sub signature_conflicts() {
        my @out;
        for my $ir_op (sort keys %IR_OP_SOURCE_NAME) {
            my $err = _signature_conflict_for($IR_OP_SOURCE_NAME{$ir_op});
            push @out, $err if defined $err;
        }
        return @out;
    }
}
