# ABOUTME: Tests for Scope::merge_for_loop() — creates Phis at loop merge points.
# ABOUTME: Verifies eager Phi creation for loop-carried variables directly in ForeachStatement.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::IR::Node::Phi;

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

my $start  = $factory->make('Start');
my $const1 = $factory->make('Constant', const_type => 'integer', value => '1');
my $const2 = $factory->make('Constant', const_type => 'integer', value => '2');
my $const3 = $factory->make('Constant', const_type => 'integer', value => '3');

my $loop = $factory->make('Loop', entry_ctrl => $start, backedge_ctrl => undef);

# Case 1: body assigns $x (body_val differs from pre_val) — creates Phi with backedge
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$x', $const1);

    my %body_final = ('$x' => $const2);

    my $post_scope = $pre_scope->merge_for_loop(\%body_final, $loop, $factory, undef);

    my $x_val = $post_scope->lookup('$x');
    ok(defined $x_val, 'case1: $x defined after merge_for_loop');
    ok($x_val isa Chalk::Bootstrap::IR::Node::Phi, 'case1: $x is a Phi node');
    is($x_val->inputs()->[0], $loop, 'case1: Phi region is the Loop node');
    is($x_val->inputs()->[1][0], $const1, 'case1: Phi pre-loop value is const1');
    is($x_val->inputs()->[1][1], $const2, 'case1: Phi backedge wired to body-final const2');
}

# Case 2: body does not assign $y — no Phi, keeps pre_loop value
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$y', $const3);

    my %body_final = ();  # $y not modified in body

    my $post_scope = $pre_scope->merge_for_loop(\%body_final, $loop, $factory, undef);

    my $y_val = $post_scope->lookup('$y');
    is($y_val, $const3, 'case2: $y unchanged (no Phi) when body does not assign it');
}

# Case 3: body assigns same value as pre-loop — no Phi (identity check)
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$z', $const1);

    my %body_final = ('$z' => $const1);  # same node

    my $post_scope = $pre_scope->merge_for_loop(\%body_final, $loop, $factory, undef);

    my $z_val = $post_scope->lookup('$z');
    is($z_val, $const1, 'case3: $z unchanged (no Phi) when body assigns same node');
}

# Case 4: iterator variable excluded from Phi creation
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$i', $const1);
    $pre_scope = $pre_scope->define('$sum', $const2);

    my %body_final = ('$i' => $const3, '$sum' => $const3);

    # $i is the iterator — should NOT get a Phi
    my $post_scope = $pre_scope->merge_for_loop(\%body_final, $loop, $factory, '$i');

    my $i_val = $post_scope->lookup('$i');
    is($i_val, $const1, 'case4: iterator $i excluded from Phi creation');

    my $sum_val = $post_scope->lookup('$sum');
    ok($sum_val isa Chalk::Bootstrap::IR::Node::Phi, 'case4: $sum (non-iterator) gets a Phi');
    is($sum_val->inputs()->[1][1], $const3, 'case4: $sum backedge wired to body-final value');
}

# Case 5: multiple variables — some get Phi, some do not
{
    my $pre_scope = Chalk::Bootstrap::Scope->new();
    $pre_scope = $pre_scope->define('$a', $const1);
    $pre_scope = $pre_scope->define('$b', $const2);
    $pre_scope = $pre_scope->define('$c', $const3);

    # $a and $c modified; $b not
    my %body_final = ('$a' => $const2, '$c' => $const1);

    my $post_scope = $pre_scope->merge_for_loop(\%body_final, $loop, $factory, undef);

    ok($post_scope->lookup('$a') isa Chalk::Bootstrap::IR::Node::Phi,
        'case5: $a gets Phi (modified)');
    is($post_scope->lookup('$b'), $const2,
        'case5: $b unchanged (no Phi)');
    ok($post_scope->lookup('$c') isa Chalk::Bootstrap::IR::Node::Phi,
        'case5: $c gets Phi (modified)');
}

done_testing();
