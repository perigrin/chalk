# ABOUTME: Tests for struct promotion pipeline integration.
# ABOUTME: Verifies the run() entry point and schema reporting.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Optimizer::StructPromotion;

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

    my $return_stmt = ctor('ReturnStmt', value => $item_var);

    my $method = ctor('MethodDecl',
        name        => const_node('string', '_maker'),
        params      => [],
        body        => [$var_decl, $assign, $return_stmt],
        return_type => undef,
    );

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestPipeline'),
        parent => undef,
        body   => [$method],
    );

    my $program = ctor('Program', statements => [$class_decl]);

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
    my @work = ($rewritten->[0]{ir});
    while (@work) {
        my $node = shift @work;
        next unless defined $node;
        if ($node isa Chalk::Bootstrap::IR::Node::Constructor
            && $node->class() eq 'StructRef') {
            $found_struct_ref = true;
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

    ok($found_struct_ref, 'run() produces IR with StructRef nodes');
}

# === Test: run() with no promotable hashes returns unchanged IR ===
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $method = ctor('MethodDecl',
        name        => const_node('string', 'simple'),
        params      => [],
        body        => [ctor('ReturnStmt', value => const_node('integer', '42'))],
        return_type => undef,
    );

    my $class_decl = ctor('ClassDecl',
        name   => const_node('string', 'TestEmpty'),
        parent => undef,
        body   => [$method],
    );

    my $program = ctor('Program', statements => [$class_decl]);

    my $optimizer = Chalk::Bootstrap::Optimizer::StructPromotion->new();
    my ($rewritten, $schemas) = $optimizer->run([
        { class_name => 'TestEmpty', ir => $program }
    ]);

    is(scalar keys $schemas->%*, 0, 'no schemas when no hashes');
    is(scalar $rewritten->@*, 1, 'one class returned unchanged');
}

done_testing;
