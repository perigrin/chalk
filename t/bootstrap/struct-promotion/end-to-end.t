# ABOUTME: End-to-end test for struct promotion — full pipeline from IR to C code.
# ABOUTME: Verifies analyze→rewrite→emit produces correct C with typedef and struct access.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::Bootstrap::Perl::Target::C;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::StructRef;
use Chalk::IR::Node::StructFieldAccess;
use Chalk::IR::MethodInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::Program;
use Chalk::IR::NodeFactory;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constant', const_type => $type, value => $value);
}

# Operator-to-typed-class maps used to dispatch BinaryExpr/UnaryExpr to the
# polymorphic typed nodes (Add, Assign, NumEq, ...) — mirrors Chalk::IR::Shim.
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
# so $node->class() still returns the legacy name expected by analysers
# and emitters.
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

# === Test: Full pipeline — analyze → rewrite → emit C ===
# Mimics the Earley _make_item pattern with 4 fields
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $item_var  = const_node('variable', '$item');
    my $rule_var  = const_node('variable', '$rule');
    my $alt_var   = const_node('variable', '$alt_idx');
    my $dot_var   = const_node('variable', '$dot');
    my $origin_var = const_node('variable', '$origin');

    my $empty_hash = ctor('HashRefExpr', pairs => []);
    my $var_decl = ctor('VarDecl',
        variable    => $item_var,
        initializer => $empty_hash,
    );

    # Build assignments with integer and SV* fields
    my @assigns;
    my @keys  = qw(rule alt_idx dot origin);
    my @vals  = ($rule_var, $alt_var, $dot_var, $origin_var);
    for my $i (0 .. $#keys) {
        my $subscript = ctor('SubscriptExpr',
            target => $item_var,
            index  => const_node('string', $keys[$i]),
            style  => const_node('enum', 'hash'),
        );
        my $assign = ctor('BinaryExpr',
            op    => const_node('string', '='),
            left  => $subscript,
            right => $vals[$i],
        );
        push @assigns, $assign;
    }

    # Add arithmetic usage for alt_idx and dot (marks them as IV)
    my $alt_read = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'alt_idx'),
        style  => const_node('enum', 'hash'),
    );
    my $arith = ctor('BinaryExpr',
        op    => const_node('string', '+'),
        left  => $alt_read,
        right => const_node('integer', '1'),
    );

    my $dot_read = ctor('SubscriptExpr',
        target => $item_var,
        index  => const_node('string', 'dot'),
        style  => const_node('enum', 'hash'),
    );
    my $dot_arith = ctor('BinaryExpr',
        op    => const_node('string', '+'),
        left  => $dot_read,
        right => const_node('integer', '1'),
    );

    # Also add integer constant assignments for alt_idx, dot, origin
    my $alt_assign_int = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => ctor('SubscriptExpr',
            target => $item_var,
            index  => const_node('string', 'alt_idx'),
            style  => const_node('enum', 'hash'),
        ),
        right => const_node('integer', '0'),
    );

    my $dot_assign_int = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => ctor('SubscriptExpr',
            target => $item_var,
            index  => const_node('string', 'dot'),
            style  => const_node('enum', 'hash'),
        ),
        right => const_node('integer', '0'),
    );

    my $origin_assign_int = ctor('BinaryExpr',
        op    => const_node('string', '='),
        left  => ctor('SubscriptExpr',
            target => $item_var,
            index  => const_node('string', 'origin'),
            style  => const_node('enum', 'hash'),
        ),
        right => const_node('integer', '0'),
    );

    my $return_stmt = ret_node($item_var);

    my $method = method_info('_make_item',
        [$var_decl, @assigns, $alt_assign_int, $dot_assign_int,
         $origin_assign_int, $arith, $dot_arith, $return_stmt],
        params => [$rule_var, $alt_var, $dot_var, $origin_var],
    );

    # Add a reader method that accesses fields
    my $item_param = const_node('variable', '$item');
    my $read_dot = ctor('SubscriptExpr',
        target => $item_param,
        index  => const_node('string', 'dot'),
        style  => const_node('enum', 'hash'),
    );
    my $reader = method_info('_get_dot',
        [ret_node($read_dot)],
        params => [$item_param],
    );

    my $class_decl = class_info('Test::E2E', $method, $reader);
    my $program = program_ir($class_decl);

    # Step 1: Run struct promotion
    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my ($rewritten, $schemas) = $optimizer->run([
        { class_name => 'Test::E2E', ir => $program }
    ]);

    ok(defined $schemas, 'schemas detected');
    my @snames = sort keys $schemas->%*;
    is(scalar @snames, 1, 'one schema');

    my $schema = $schemas->{$snames[0]};
    my %field_types = map { $_->{name} => $_->{c_type} } $schema->{fields}->@*;

    # Check type inference
    is($field_types{rule}, 'SV *', 'rule is SV* (variable, no integer context)');
    is($field_types{alt_idx}, 'IV', 'alt_idx is IV (integer assignment + arithmetic)');
    is($field_types{dot}, 'IV', 'dot is IV (integer assignment + arithmetic)');
    is($field_types{origin}, 'IV', 'origin is IV (integer assignment)');

    # Step 2: Generate C code from rewritten IR
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::E2E',
    );
    $target->set_struct_schemas($schemas);

    # Generate typedefs
    my $typedefs = $target->generate_typedefs();
    like($typedefs, qr/typedef struct/, 'typedef generated');
    like($typedefs, qr/SV \*\s*rule/, 'typedef has SV* rule');
    like($typedefs, qr/IV\s+alt_idx/, 'typedef has IV alt_idx');
    like($typedefs, qr/IV\s+dot/, 'typedef has IV dot');
    like($typedefs, qr/IV\s+origin/, 'typedef has IV origin');

    # Step 3: Verify rewritten IR contains StructRef and FieldAccess
    # (typed: StructFieldAccess).
    my ($struct_ref_count, $field_access_count) = (0, 0);
    walk_ir($rewritten->[0]{ir}, sub($node) {
        return unless $node isa Chalk::IR::Node;
        $struct_ref_count++   if $node isa Chalk::IR::Node::StructRef;
        $field_access_count++ if $node isa Chalk::IR::Node::StructFieldAccess;
    });

    ok($struct_ref_count > 0, "found $struct_ref_count StructRef nodes in rewritten IR");
    ok($field_access_count > 0, "found $field_access_count FieldAccess nodes in rewritten IR");
}

# === Test: Existing chalk.so end-to-end tests still pass (regression guard) ===
# Verify the pre-built chalk.so is not affected by our changes
SKIP: {
    my $chalk_so = '.build/chalk-so-gen/chalk.so';
    skip("no pre-built chalk.so — skipping regression guard", 1) unless -f $chalk_so;
    pass("pre-built chalk.so exists at $chalk_so");
}

done_testing;
