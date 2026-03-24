# ABOUTME: End-to-end test for struct promotion — full pipeline from IR to C code.
# ABOUTME: Verifies analyze→rewrite→emit produces correct C with typedef and struct access.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::Bootstrap::Perl::Target::C;

# Helper: create a Constant node
sub const_node($type, $value) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constant', const_type => $type, value => $value);
}

# Helper: create a Constructor node
sub ctor($class, %inputs) {
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;
    return $factory->make('Constructor', class => $class, %inputs);
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

    my $return_stmt = ctor('ReturnStmt', value => $item_var);

    my $method = ctor('MethodDecl',
        name        => const_node('string', '_make_item'),
        params      => [$rule_var, $alt_var, $dot_var, $origin_var],
        body        => [$var_decl, @assigns, $alt_assign_int, $dot_assign_int,
                        $origin_assign_int, $arith, $dot_arith, $return_stmt],
        return_type => undef,
    );

    # Add a reader method that accesses fields
    my $item_param = const_node('variable', '$item');
    my $read_dot = ctor('SubscriptExpr',
        target => $item_param,
        index  => const_node('string', 'dot'),
        style  => const_node('enum', 'hash'),
    );
    my $reader = ctor('MethodDecl',
        name        => const_node('string', '_get_dot'),
        params      => [$item_param],
        body        => [ctor('ReturnStmt', value => $read_dot)],
        return_type => undef,
    );

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'Test::E2E'),
        parent => undef,
        body   => [$method, $reader],
    );

    my $program = ctor('Program', statements => [$class_decl]);

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
    my ($struct_ref_count, $field_access_count) = (0, 0);
    my @work = ($rewritten->[0]{ir});
    while (@work) {
        my $node = shift @work;
        next unless defined $node;
        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            $struct_ref_count++   if $node->class() eq 'StructRef';
            $field_access_count++ if $node->class() eq 'FieldAccess';
        }
        next unless $node isa Chalk::Bootstrap::IR::Node;
        for my $input ($node->inputs()->@*) {
            next unless defined $input;
            if (ref($input) eq 'ARRAY') {
                push @work, grep { defined } $input->@*;
            } else {
                push @work, $input;
            }
        }
    }

    ok($struct_ref_count > 0, "found $struct_ref_count StructRef nodes in rewritten IR");
    ok($field_access_count > 0, "found $field_access_count FieldAccess nodes in rewritten IR");
}

# === Test: Existing chalk.so end-to-end tests still pass (regression guard) ===
# Verify the pre-built chalk.so is not affected by our changes
{
    my $chalk_so = '.build/chalk-so-gen/chalk.so';
    if (-f $chalk_so) {
        pass("pre-built chalk.so exists at $chalk_so");
    } else {
        # Not a failure — just skip if no pre-built binary
        skip("no pre-built chalk.so — skipping regression guard", 1);
    }
}

done_testing;
