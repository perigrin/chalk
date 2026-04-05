# ABOUTME: Translates old-style Constructor class names to typed Chalk::IR::Node::* objects.
# ABOUTME: Used during migration; returns undef for structural/CFG/BNF classes not yet translated.
use 5.42.0;
use utf8;

package Chalk::IR::Shim;

# Types whose consumers have all been migrated to dual-path isa checks.
# These are safe to translate — the typed isa path handles them, and the
# Constructor fallback is dead code that will be removed in Phase 5.
# All computation types whose consumers have dual-path isa checks.
my %DEFAULT_ENABLED = map { $_ => 1 } qw(
    BinaryExpr UnaryExpr MethodCallExpr BuiltinCall
    SubscriptExpr PostfixDerefExpr CompoundAssign
    HashRefExpr ArrayRefExpr AnonSubExpr
    RegexMatch RegexSubst InterpolatedString
    BacktickExpr VarDecl TryCatchStmt
);

my %ENABLED = %DEFAULT_ENABLED;

sub enable_class  ($class_name) { $ENABLED{$class_name} = 1; }
sub disable_class ($class_name) { delete $ENABLED{$class_name}; }
sub is_enabled    ($class_name) { exists $ENABLED{$class_name} }
sub reset_enabled ()            { %ENABLED = %DEFAULT_ENABLED; }

my %BINOP_MAP = (
    '+'   => 'Add',        '-'   => 'Subtract',  '*'   => 'Multiply',
    '/'   => 'Divide',     '%'   => 'Modulo',     '**'  => 'Power',
    '.'   => 'Concat',
    '=='  => 'NumEq',      '!='  => 'NumNe',      '<'   => 'NumLt',
    '>'   => 'NumGt',      '<='  => 'NumLe',      '>='  => 'NumGe',
    '<=>' => 'NumCmp',
    'eq'  => 'StrEq',      'ne'  => 'StrNe',      'lt'  => 'StrLt',
    'gt'  => 'StrGt',      'le'  => 'StrLe',      'ge'  => 'StrGe',
    'cmp' => 'StrCmp',
    '&&'  => 'And',        '||'  => 'Or',
    'and' => 'And',        'or'  => 'Or',
    '&'   => 'BitAnd',     '|'   => 'BitOr',      '^'   => 'BitXor',
    '<<'  => 'LeftShift',  '>>'  => 'RightShift',
    '='   => 'Assign',
);

my %UNOP_MAP = (
    '!'       => 'Not',
    'not'     => 'Not',
    '-'       => 'Negate',
    '~'       => 'Complement',
    'defined' => 'Defined',
);

# Classes that are structural metadata or CFG constructs deferred to Phase 3b,
# BNF grammar types, or optimizer-specific — none of these are translated.
my %NOT_TRANSLATED = map { $_ => 1 } qw(
    ReturnStmt DieCall
    Program ClassDecl MethodDecl SubDecl FieldDecl UseDecl _Attribute
    Symbol Expression Rule
    StructRef FieldAccess
    TernaryExpr
);

sub translate($factory, $constructor_class, %params) {
    # Only translate classes that have been explicitly enabled
    return undef unless $ENABLED{$constructor_class};

    # Fast exit for known-untranslated classes
    return undef if $NOT_TRANSLATED{$constructor_class};

    if ($constructor_class eq 'BinaryExpr') {
        my $op_str = $params{op}->value();
        my $type   = $BINOP_MAP{$op_str} or return undef;
        my $left   = $params{left};
        my $right  = $params{right};
        return $factory->make($type,
            inputs       => [$params{op}, $left, $right],
            left         => $left,
            right        => $right,
            compat_class => 'BinaryExpr',
        );
    }

    if ($constructor_class eq 'UnaryExpr') {
        my $op_str  = $params{op}->value();
        my $type    = $UNOP_MAP{$op_str} or return undef;
        my $operand = $params{operand};
        return $factory->make($type,
            inputs       => [$params{op}, $operand],
            operand      => $operand,
            compat_class => 'UnaryExpr',
        );
    }

    if ($constructor_class eq 'MethodCallExpr') {
        return $factory->make('Call',
            dispatch_kind => 'method',
            name          => $params{method_name}->value(),
            inputs        => [$params{invocant}, $params{method_name}, $params{args}],
            compat_class  => 'MethodCallExpr',
        );
    }

    if ($constructor_class eq 'BuiltinCall') {
        return $factory->make('Call',
            dispatch_kind => 'builtin',
            name          => $params{name}->value(),
            inputs        => [$params{name}, $params{args}],
            compat_class  => 'BuiltinCall',
        );
    }

    if ($constructor_class eq 'SubscriptExpr') {
        return $factory->make('Subscript',
            inputs       => [$params{target}, $params{index}, $params{style}],
            compat_class => 'SubscriptExpr',
        );
    }

    if ($constructor_class eq 'PostfixDerefExpr') {
        my $sigil_param = $params{sigil};
        my $is_node     = ref($sigil_param) ? 1 : 0;
        my $sigil_str   = $is_node ? $sigil_param->value() : $sigil_param;
        my @inputs      = $is_node
            ? ($params{target}, $sigil_param)
            : ($params{target});
        return $factory->make('PostfixDeref',
            sigil        => $sigil_str,
            inputs       => \@inputs,
            compat_class => 'PostfixDerefExpr',
        );
    }

    if ($constructor_class eq 'CompoundAssign') {
        return $factory->make('CompoundAssign',
            op           => $params{op}->value(),
            inputs       => [$params{op}, $params{target}, $params{value}],
            compat_class => 'CompoundAssign',
        );
    }

    if ($constructor_class eq 'HashRefExpr') {
        return $factory->make('HashRef',
            inputs       => [$params{pairs}],
            compat_class => 'HashRefExpr',
        );
    }

    if ($constructor_class eq 'ArrayRefExpr') {
        return $factory->make('ArrayRef',
            inputs       => [$params{elements}],
            compat_class => 'ArrayRefExpr',
        );
    }

    if ($constructor_class eq 'AnonSubExpr') {
        return $factory->make('AnonSub',
            inputs       => [$params{params}, $params{body}],
            compat_class => 'AnonSubExpr',
        );
    }

    if ($constructor_class eq 'RegexMatch') {
        my $flags_node = $params{flags};
        my $flags_str  = defined $flags_node ? $flags_node->value() : '';
        $flags_str //= '';
        return $factory->make('RegexMatch',
            flags        => $flags_str,
            inputs       => [$params{target}, $params{pattern}, $flags_node],
            compat_class => 'RegexMatch',
        );
    }

    if ($constructor_class eq 'RegexSubst') {
        my $flags_node = $params{flags};
        my $flags_str  = defined $flags_node ? $flags_node->value() : '';
        $flags_str //= '';
        return $factory->make('RegexSubst',
            flags        => $flags_str,
            inputs       => [$params{target}, $params{pattern}, $params{replacement}, $flags_node],
            compat_class => 'RegexSubst',
        );
    }

    if ($constructor_class eq 'InterpolatedString') {
        return $factory->make('Interpolate',
            inputs       => [$params{parts}],
            compat_class => 'InterpolatedString',
        );
    }

    if ($constructor_class eq 'BacktickExpr') {
        return $factory->make('BacktickExpr',
            inputs       => [$params{command}],
            compat_class => 'BacktickExpr',
        );
    }

    if ($constructor_class eq 'VarDecl') {
        return $factory->make('VarDecl',
            inputs       => [$params{variable}, $params{initializer}],
            compat_class => 'VarDecl',
        );
    }

    if ($constructor_class eq 'TryCatchStmt') {
        return $factory->make('TryCatch',
            inputs       => [$params{try_body}, $params{catch_var}, $params{catch_body}],
            compat_class => 'TryCatchStmt',
        );
    }

    # Unknown constructor class — fall through to old Constructor path
    return undef;
}

1;
