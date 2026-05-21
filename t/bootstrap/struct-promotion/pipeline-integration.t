# ABOUTME: Tests for struct promotion pipeline integration.
# ABOUTME: Verifies the run() entry point and schema reporting.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::IR::Node::Return;
use Chalk::IR::MethodInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::Program;
use Chalk::IR::NodeFactory;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constant', const_type => $type, value => $value);
}

# Operator-to-typed-class map used to dispatch BinaryExpr to polymorphic typed
# nodes (Add, Assign, ...) — mirrors Chalk::IR::Shim::%BINOP_MAP.
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
    'x'   => 'Repeat',
    '=~'  => 'Match',      '!~'  => 'NotMatch',
    '//'  => 'DefinedOr',
    'xor' => 'Xor',
    '..'  => 'Range',      '...' => 'Yada',
    'isa' => 'IsaOp',
);

# Helper: create a typed IR node by legacy Constructor class name.
# Dispatches directly to Chalk::IR::NodeFactory and preserves compat_class
# so $node->class() still returns the legacy name expected by the optimizer.
sub ctor($class, %inputs) {
    state $typed = Chalk::IR::NodeFactory->new;
    if ($class eq 'BinaryExpr') {
        my $op_str = $inputs{op}->value();
        my $type   = $BINOP_MAP{$op_str}
            or die "ctor: unknown binary op '$op_str'";
        return $typed->make($type,
            inputs       => [$inputs{op}, $inputs{left}, $inputs{right}],
            left         => $inputs{left},
            right        => $inputs{right},
            compat_class => 'BinaryExpr',
        );
    }
    if ($class eq 'SubscriptExpr') {
        return $typed->make('Subscript',
            inputs       => [$inputs{target}, $inputs{index}, $inputs{style}],
            compat_class => 'SubscriptExpr',
        );
    }
    if ($class eq 'HashRefExpr') {
        return $typed->make('HashRef',
            inputs       => [$inputs{pairs}],
            compat_class => 'HashRefExpr',
        );
    }
    if ($class eq 'VarDecl') {
        return $typed->make('VarDecl',
            inputs       => [$inputs{control}, $inputs{variable}, $inputs{initializer}],
            compat_class => 'VarDecl',
        );
    }
    die "ctor: unsupported class '$class'";
}

# Helper: create a Return CFG node
sub ret_node($val) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make_cfg('Return',
        inputs => [ $factory->make('Start'), $val ],
    );
}

# Helper: create a MethodInfo metadata struct
sub method_info($name, $body, %opts) {
    return Chalk::IR::MethodInfo->new(
        name        => $name,
        params      => $opts{params} // [],
        return_type => $opts{return_type},
        body        => $body,
    );
}

# Helper: create a ClassInfo metadata struct
sub class_info($name, @body) {
    my (@methods, @subs, @fields);
    for my $item (@body) {
        if ($item isa Chalk::IR::MethodInfo) { push @methods, $item; }
        elsif ($item isa Chalk::IR::SubInfo)  { push @subs,    $item; }
    }
    return Chalk::IR::ClassInfo->new(
        name    => $name,
        methods => \@methods,
        subs    => \@subs,
        fields  => \@fields,
        body    => \@body,
    );
}

# Helper: create a Program IR struct
sub program_ir($class_info) {
    return Chalk::IR::Program->new(
        classes => [$class_info],
    );
}

# Helper: walk an IR tree collecting all typed nodes
sub walk_ir($root, $visitor) {
    my @work = ($root);
    while (@work) {
        my $node = shift @work;
        next unless defined $node;
        $visitor->($node);
        if ($node isa Chalk::IR::Program) {
            push @work, $node->classes()->@*;
        } elsif ($node isa Chalk::IR::ClassInfo) {
            push @work, $node->body()->@*;
        } elsif ($node isa Chalk::IR::MethodInfo) {
            push @work, $node->body()->@*;
        } elsif ($node isa Chalk::IR::Node) {
            for my $input ($node->inputs()->@*) {
                next unless defined $input;
                if (ref($input) eq 'ARRAY') {
                    push @work, grep { defined } $input->@*;
                } else {
                    push @work, $input;
                }
            }
        }
    }
}

# === Test: run() orchestrates analyze + rewrite ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    # Build a simple class with _make_item pattern
    my $item_var = const_node('variable', '$item');
    my $x_var    = const_node('variable', '$x');

    my $empty_hash = ctor('HashRefExpr', pairs => []);
    my $var_decl = ctor('VarDecl',
        variable    => $item_var,
        initializer => $empty_hash,
    );

    my $sub = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'x'),
        style  => const_node('enum', 'hash'),
    );
    my $assign = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => $sub,
        right => const_node('integer', '1'),
    );

    my $return_stmt = ret_node($item_var);

    my $method = method_info('_maker', [$var_decl, $assign, $return_stmt]);
    my $class_decl = class_info('TestPipeline', $method);
    my $program = program_ir($class_decl);

    # Run the full pipeline
    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my ($rewritten, $schemas) = $optimizer->run([
        { class_name => 'TestPipeline', ir => $program }
    ]);

    ok(defined $rewritten, 'run() returns rewritten classes');
    ok(ref $rewritten eq 'ARRAY', 'rewritten is an arrayref');
    is(scalar $rewritten->@*, 1, 'one class rewritten');

    ok(defined $schemas, 'run() returns schemas');
    ok(ref $schemas eq 'HASH', 'schemas is a hashref');
    is(scalar keys $schemas->%*, 1, 'one schema detected');

    # Verify IR was actually rewritten
    my $found_struct_ref = false;
    walk_ir($rewritten->[0]{ir}, sub($node) {
        if ($node isa Chalk::IR::Node && $node->class() eq 'StructRef') {
            $found_struct_ref = true;
        }
    });

    ok($found_struct_ref, 'run() produces IR with StructRef nodes');
}

# === Test: run() with no promotable hashes returns unchanged IR ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $method = method_info('simple', [ret_node(const_node('integer', '42'))]);
    my $class_decl = class_info('TestEmpty', $method);
    my $program = program_ir($class_decl);

    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my ($rewritten, $schemas) = $optimizer->run([
        { class_name => 'TestEmpty', ir => $program }
    ]);

    is(scalar keys $schemas->%*, 0, 'no schemas when no hashes');
    is(scalar $rewritten->@*, 1, 'one class returned unchanged');
}

done_testing;
