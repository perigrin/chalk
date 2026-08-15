# ABOUTME: Perl type hierarchy and function/operator type signatures for parse-time validation.
# ABOUTME: Consumed by TypeInference semiring; sits alongside KeywordTable and PrecedenceTable.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Grammar::Perl::TypeLibrary {
    # Type hierarchy from docs/perl-types-practical.md.
    # Each type maps to its direct parent. 'Any' has no parent.
    # 'None' is the bottom type (subtype of everything).
    my %PARENT = (
        # Scalar branch
        Scalar    => 'Any',
        Undef     => 'Scalar',
        Bool      => 'Scalar',
        Regex     => 'Scalar',
        Str       => 'Scalar',
        Num       => 'Str',
        Int       => 'Num',
        DualVar   => 'Scalar',
        Ref       => 'Scalar',
        ScalarRef => 'Ref',
        ArrayRef  => 'Ref',
        HashRef   => 'Ref',
        CodeRef   => 'Ref',
        GlobRef   => 'Ref',
        Object    => 'Ref',

        # Collection branch
        List      => 'Any',
        Array     => 'List',
        Hash      => 'List',

        # Code branch
        Code      => 'Any',

        # Glob branch (symbol table entries, distinct from GlobRef)
        Glob      => 'Any',
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
            Undef Bool Regex Int DualVar
            ScalarRef ArrayRef HashRef CodeRef GlobRef Object
            Array Hash Code Glob
        );
        for my $type (@leaf_types) {
            $TYPE_BITSET{$type} = 1 << $bit++;
        }

        # Internal intermediate types get their own bit too, so that
        # is_subtype(Num, Num) and is_subtype(Str, Str) work via exact match
        # and subtypes include their ancestor's bit.
        $TYPE_BITSET{Num} = (1 << $bit++);
        $TYPE_BITSET{Str} = (1 << $bit++);
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

        # Any is the root — OR of all types
        $TYPE_BITSET{Any} = 0;
        for my $type (keys %TYPE_BITSET) {
            $TYPE_BITSET{Any} |= $TYPE_BITSET{$type};
        }

        # Unknown is the PESSIMISTIC top: the same position as Any and the same
        # value set, but a different obligation — exactly TypeScript's
        # `unknown` vs `any`.
        #
        #   Any     opts OUT of checking. A legitimate static answer (`push`'s
        #           second argument accepts anything, and that is a fact).
        #   Unknown is SOUND top: inference has not determined the type, and
        #           nothing may be done with the value until it is NARROWED.
        #
        # They are mutually assignable (both top, same values), so Unknown
        # carries Any's bits and Any gains Unknown's — is_subtype is true in
        # both directions. What differs is what each MEANS to a consumer: an
        # `Any` reaching the backend is a design fact, an `Unknown` reaching it
        # is an inference failure.
        #
        # This distinction is the point. 'Scalar' used to double as the "I do
        # not know" placeholder (the producer wrote it for an unstamped
        # operand), so the backend's Scalar GAP could not tell "this scalar type
        # is not lowered yet" from "nothing ever typed this".
        $TYPE_BITSET{Unknown} = $TYPE_BITSET{Any};
        $TYPE_BITSET{Any}    |= $TYPE_BITSET{Unknown};

        # None is the bottom type — 0 (subtype of everything by convention)
        $TYPE_BITSET{None} = 0;
    }

    # Builtin function signatures: argument types, minimum arity, and return type.
    # Last entry in arg_types applies to all remaining positions (variadic).
    my %BUILTIN_SIGNATURES = (
        # Array operations
        # Variadic positions use Any (Perl flattening: accepts scalars AND arrays)
        push    => { min_arity => 2, arg_types => ['Array', 'Any'],              return_type => 'Int' },
        pop     => { min_arity => 1, arg_types => ['Array'],                     return_type => 'Scalar' },
        shift   => { min_arity => 1, arg_types => ['Array'],                     return_type => 'Scalar' },
        unshift => { min_arity => 2, arg_types => ['Array', 'Any'],              return_type => 'Int' },
        splice  => { min_arity => 1, arg_types => ['Array', 'Num', 'Num', 'Any'], return_type => 'List' },

        # Hash operations
        keys    => { min_arity => 1, arg_types => ['Hash'],                      return_type => 'List' },
        values  => { min_arity => 1, arg_types => ['Hash'],                      return_type => 'List' },
        delete  => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Scalar' },
        exists  => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Bool' },
        each    => { min_arity => 1, arg_types => ['Hash'],                      return_type => 'List' },

        # String operations
        length  => { min_arity => 0, arg_types => ['Str'],                       return_type => 'Int' },
        chomp   => { min_arity => 0, arg_types => ['Any'],                       return_type => 'Int' },
        chop    => { min_arity => 0, arg_types => ['Any'],                       return_type => 'Str' },
        chr     => { min_arity => 1, arg_types => ['Int'],                       return_type => 'Str' },
        ord     => { min_arity => 0, arg_types => ['Str'],                       return_type => 'Int' },
        join    => { min_arity => 2, arg_types => ['Str', 'Any'],                return_type => 'Str' },
        split   => { min_arity => 1, arg_types => ['Regex', 'Str', 'Num'],       return_type => 'List' },
        sprintf => { min_arity => 1, arg_types => ['Str', 'Any'],                return_type => 'Str' },
        substr  => { min_arity => 2, arg_types => ['Str', 'Num', 'Num'],         return_type => 'Str' },

        # Type test
        defined => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Bool' },
        ref     => { min_arity => 1, arg_types => ['Scalar'],                    return_type => 'Str' },

        # Context
        scalar  => { min_arity => 1, arg_types => ['Any'],                       return_type => 'Scalar' },

        # Control (variadic: accept scalars and arrays via flattening)
        die     => { min_arity => 0, arg_types => ['Any'],                       return_type => 'None' },
        warn    => { min_arity => 0, arg_types => ['Any'],                       return_type => 'Bool' },

        # OO
        bless   => { min_arity => 1, arg_types => ['Ref', 'Str'],               return_type => 'Object' },

        # I/O (variadic)
        print   => { min_arity => 0, arg_types => ['Any'],                       return_type => 'Bool' },
        say     => { min_arity => 0, arg_types => ['Any'],                       return_type => 'Bool' },

        # Flow control (variadic: return LIST)
        return  => { min_arity => 0, arg_types => ['Any'],                       return_type => 'Any' },

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
    my %POLYMORPHIC_TYPES = map { $_ => true } qw(Scalar Any List);

    # Returns true if $actual_type satisfies $required_type.
    # undef actual passes permissively (unknown type at parse time).
    # 'Any' required always passes.
    # For polymorphic types (Scalar, Any, List — assigned to variables),
    # also pass when the required type is a subtype of actual, since the
    # variable could hold any value within its type at runtime.
    sub type_satisfies($actual_type, $required_type) {
        return true if $required_type eq 'Any';
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
        if ($context eq 'Bool') {
            return 'Bool';
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
        my $num_num_bool = { left => 'Num',    right => 'Num',   result => 'Bool' };
        my $str_str_str  = { left => 'Str',    right => 'Str',   result => 'Str' };
        my $str_str_bool = { left => 'Str',    right => 'Str',   result => 'Bool' };
        my $any_any_any  = { left => 'Any',    right => 'Any',   result => 'Any' };
        my $any_any_bool = { left => 'Any',    right => 'Any',   result => 'Bool' };
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
        $BINARY_OP_SIGNATURES{'isa'} = { left => 'Scalar', right => 'Str', result => 'Bool' };

        # Regex binding
        $BINARY_OP_SIGNATURES{'=~'} = { left => 'Str', right => 'Regex', result => 'Bool' };
        $BINARY_OP_SIGNATURES{'!~'} = { left => 'Str', right => 'Regex', result => 'Bool' };

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
        '!'   => { operand => 'Any', result => 'Bool' },
        'not' => { operand => 'Any', result => 'Bool' },
        '~'   => { operand => 'Int', result => 'Int' },
        '\\'  => { operand => 'Any', result => 'Ref' },
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

        # Two-argument ops. String comparison is (Str, Str) -> Bool for every
        # member; Concat is (Str, Str) -> Str.
        StrEq  => 'eq',  StrNe  => 'ne',  StrLt => 'lt',
        StrGt  => 'gt',  StrLe  => 'le',  StrGe => 'ge',
        StrCmp => 'cmp',
        Concat => '.',

        # DELIBERATELY ABSENT -- BitAnd/BitOr/BitXor. Numeric `&` is
        # (Int, Int) -> Int while string-bitwise `&.` is a Str operator, and
        # BOTH lower to the same node type, so the NODE does not determine its
        # operand types and no single answer here is correct. Splitting the
        # node types is the fix; until then these decline, costing a coercion
        # opportunity rather than risking a wrong coercion.
        #
        # ALSO ABSENT -- Print. `print` is variadic with arg_types ['Any'] BY
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
        Length => { map { $_ => 1 } qw(Array ArrayRef Hash HashRef Str) },
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
    # each of which means "no opinion", not "Any". A coercion to Any is not a
    # coercion, so 'Any' reads as undef.
    #
    # $position is the operand's index in the SIGNATURE -- left is 0, right is
    # 1 -- and NOT its index in a node's inputs array. Those differ: a BinOp
    # node carries a leading control slot, so its left operand sits at
    # inputs[1]. Callers walking an inputs array must convert.
    #
    # A trailing 'Any' in arg_types is variadic and covers all later positions,
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

        return (defined $want && $want ne 'Any') ? $want : undef;
    }

    # A builtin is variadic when its last argument slot is 'Any' -- the
    # convention %BUILTIN_SIGNATURES already uses for the positions perl
    # flattens a list into (`print`, `join`, `sprintf`, `push`).
    sub _is_variadic($args) {
        return @$args && $args->[-1] eq 'Any';
    }

    # The IR ops this library can answer for. Exposed so a test can assert
    # every entry names a node type that actually exists: an entry for a
    # nonexistent node is dead weight that reads as coverage, because no such
    # node is ever built and the entry can never be consulted.
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
    sub _signatures_conflict($a, $b) {
        my @a = _operand_types($a);
        my @b = _operand_types($b);
        my $shared = @a < @b ? @a : @b;
        for my $i (0 .. $shared - 1) {
            next unless defined $a[$i] && defined $b[$i];
            return true if $a[$i] ne $b[$i];
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
