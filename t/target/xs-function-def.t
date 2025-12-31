# ABOUTME: Test XS visitor for FunctionDef (standalone function definitions)
# ABOUTME: Verifies correct XSUB generation for non-method functions
use 5.42.0;
use Test::More;
use lib 'lib';

use Chalk::Target::XS;
use Chalk::IR::Graph;
use Chalk::IR::Node::FunctionDef;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::IR::Type::Integer;

# Test 1: FunctionDef visitor returns XSUB
subtest 'FunctionDef generates XSUB' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a simple function: sub answer { return 42; }
    my $constant = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->constant(42),
    );
    $graph->add_node($constant);

    my $return = Chalk::IR::Node::Return->new(
        control => undef,
        value   => $constant,
    );
    $graph->add_node($return);

    my $func_def = Chalk::IR::Node::FunctionDef->new(
        inputs     => [],
        name       => 'answer',
        parameters => [],
    );
    $func_def->set_body_node({ type => 'block', statements => [$return] });
    $graph->add_node($func_def);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    my $xs_node = $xs->visit($func_def);
    ok(defined $xs_node, 'FunctionDef visitor returns XS node');
    isa_ok($xs_node, 'Chalk::Target::XS::AST::XSUB', 'FunctionDef returns XSUB');

    my $code = $xs_node->emit();
    ok(defined $code, 'FunctionDef emits code');
    like($code, qr/answer/, 'XSUB has function name');
    like($code, qr/RETVAL/, 'XSUB has return value');
};

# Test 2: FunctionDef with parameters
subtest 'FunctionDef with parameters' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Create a function: sub add { my ($a, $b) = @_; return $a + $b; }
    # For this test, we just check parameter handling, not the body logic
    my $constant = Chalk::IR::Node::Constant->new(
        value => 0,
        type  => Chalk::IR::Type::Integer->constant(0),
    );
    $graph->add_node($constant);

    my $return = Chalk::IR::Node::Return->new(
        control => undef,
        value   => $constant,
    );
    $graph->add_node($return);

    my $func_def = Chalk::IR::Node::FunctionDef->new(
        inputs     => [],
        name       => 'add',
        parameters => ['$a', '$b'],
    );
    $func_def->set_body_node({ type => 'block', statements => [$return] });
    $graph->add_node($func_def);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    my $xs_node = $xs->visit($func_def);
    ok(defined $xs_node, 'FunctionDef with params returns XS node');

    my $code = $xs_node->emit();
    ok(defined $code, 'FunctionDef with params emits code');
    like($code, qr/add/, 'XSUB has function name');
    like($code, qr/\ba\b/, 'XSUB includes first parameter');
    like($code, qr/\bb\b/, 'XSUB includes second parameter');
};

# Test 3: FunctionDef differs from methods (no implicit self)
subtest 'FunctionDef has no implicit self' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $constant = Chalk::IR::Node::Constant->new(
        value => 1,
        type  => Chalk::IR::Type::Integer->constant(1),
    );
    $graph->add_node($constant);

    my $return = Chalk::IR::Node::Return->new(
        control => undef,
        value   => $constant,
    );
    $graph->add_node($return);

    my $func_def = Chalk::IR::Node::FunctionDef->new(
        inputs     => [],
        name       => 'helper',
        parameters => ['$x'],
    );
    $func_def->set_body_node({ type => 'block', statements => [$return] });
    $graph->add_node($func_def);

    my $xs = Chalk::Target::XS->new(
        graph       => $graph,
        module_name => 'Test',
    );

    my $xs_node = $xs->visit($func_def);
    my $code = $xs_node->emit();

    # Functions should NOT have 'self' parameter unlike methods
    unlike($code, qr/\bself\b/, 'FunctionDef has no implicit self parameter');
    like($code, qr/\bx\b/, 'FunctionDef has explicit parameter');
};

done_testing();
