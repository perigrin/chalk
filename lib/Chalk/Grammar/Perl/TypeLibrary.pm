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
        return false;
    }

    # Returns true if $child is a subtype of (or equal to) $parent.
    # Walks the parent chain. None is subtype of everything.
    sub is_subtype($child, $parent) {
        return true if $child eq $parent;
        return true if $child eq 'None';

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
}
