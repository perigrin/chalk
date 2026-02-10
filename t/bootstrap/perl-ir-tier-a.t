# ABOUTME: Unit tests for Perl IR constructor types via NodeFactory.
# ABOUTME: Validates Program, UseDecl, ClassDecl, MethodDecl, ReturnStmt, DieCall creation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

# === Helper constants ===

my $str_hello = $f->make('Constant', const_type => 'string', value => 'hello');
my $str_start = $f->make('Constant', const_type => 'string', value => 'Start');
my $str_542   = $f->make('Constant', const_type => 'string', value => '5.42.0');
my $str_utf8  = $f->make('Constant', const_type => 'string', value => 'utf8');
my $str_exp   = $f->make('Constant', const_type => 'string', value => 'experimental');
my $str_class = $f->make('Constant', const_type => 'string', value => 'class');
my $str_op    = $f->make('Constant', const_type => 'string', value => 'operation');
my $str_name  = $f->make('Constant', const_type => 'string', value => 'Chalk::Bootstrap::IR::Node::Start');
my $str_parent = $f->make('Constant', const_type => 'string', value => 'Chalk::Bootstrap::IR::Node');
my $str_die_msg = $f->make('Constant', const_type => 'string', value => 'Subclass must implement name()');

# === Constructor:ReturnStmt ===

{
    my $ret = $f->make('Constructor',
        class => 'ReturnStmt',
        value => $str_start,
    );
    ok(defined $ret, 'ReturnStmt created');
    is($ret->operation(), 'Constructor', 'ReturnStmt operation is Constructor');
    is($ret->class(), 'ReturnStmt', 'ReturnStmt class is ReturnStmt');
    is(scalar $ret->inputs()->@*, 1, 'ReturnStmt has 1 input');
    is($ret->inputs()->[0], $str_start, 'ReturnStmt value is str_start');
}

# === Constructor:DieCall ===

{
    my $die = $f->make('Constructor',
        class => 'DieCall',
        args  => [$str_die_msg],
    );
    ok(defined $die, 'DieCall created');
    is($die->operation(), 'Constructor', 'DieCall operation is Constructor');
    is($die->class(), 'DieCall', 'DieCall class is DieCall');
    is(scalar $die->inputs()->@*, 1, 'DieCall has 1 input');
    is(ref($die->inputs()->[0]), 'ARRAY', 'DieCall args is arrayref');
    is($die->inputs()->[0][0], $str_die_msg, 'DieCall args[0] is the message');
}

# === Constructor:MethodDecl ===

{
    my $ret_stmt = $f->make('Constructor',
        class => 'ReturnStmt',
        value => $str_start,
    );
    my $meth = $f->make('Constructor',
        class  => 'MethodDecl',
        name   => $str_op,
        params => [],
        body   => [$ret_stmt],
    );
    ok(defined $meth, 'MethodDecl created');
    is($meth->class(), 'MethodDecl', 'MethodDecl class');
    is(scalar $meth->inputs()->@*, 3, 'MethodDecl has 3 inputs');
    is($meth->inputs()->[0], $str_op, 'MethodDecl name is operation');
    is(ref($meth->inputs()->[1]), 'ARRAY', 'MethodDecl params is arrayref');
    is(scalar $meth->inputs()->[1]->@*, 0, 'MethodDecl params is empty');
    is(ref($meth->inputs()->[2]), 'ARRAY', 'MethodDecl body is arrayref');
    is($meth->inputs()->[2][0], $ret_stmt, 'MethodDecl body[0] is return stmt');
}

# === Constructor:UseDecl ===

{
    my $use = $f->make('Constructor',
        class       => 'UseDecl',
        module_name => $str_542,
        import_args => undef,
    );
    ok(defined $use, 'UseDecl created');
    is($use->class(), 'UseDecl', 'UseDecl class');
    is(scalar $use->inputs()->@*, 2, 'UseDecl has 2 inputs');
    is($use->inputs()->[0], $str_542, 'UseDecl module_name');
    is($use->inputs()->[1], undef, 'UseDecl import_args is undef');
}

{
    my $use_with_args = $f->make('Constructor',
        class       => 'UseDecl',
        module_name => $str_exp,
        import_args => [$str_class],
    );
    ok(defined $use_with_args, 'UseDecl with args created');
    is(ref($use_with_args->inputs()->[1]), 'ARRAY', 'UseDecl import_args is arrayref');
    is($use_with_args->inputs()->[1][0], $str_class, 'UseDecl import_args[0] is class');
}

# === Constructor:ClassDecl ===

{
    my $method_node = $f->make('Constructor',
        class  => 'MethodDecl',
        name   => $str_op,
        params => [],
        body   => [$f->make('Constructor', class => 'ReturnStmt', value => $str_start)],
    );
    my $cls = $f->make('Constructor',
        class  => 'ClassDecl',
        name   => $str_name,
        parent => $str_parent,
        body   => [$method_node],
    );
    ok(defined $cls, 'ClassDecl created');
    is($cls->class(), 'ClassDecl', 'ClassDecl class');
    is(scalar $cls->inputs()->@*, 3, 'ClassDecl has 3 inputs');
    is($cls->inputs()->[0], $str_name, 'ClassDecl name');
    is($cls->inputs()->[1], $str_parent, 'ClassDecl parent');
    is(ref($cls->inputs()->[2]), 'ARRAY', 'ClassDecl body is arrayref');
}

{
    # ClassDecl without parent
    my $cls_no_parent = $f->make('Constructor',
        class  => 'ClassDecl',
        name   => $str_name,
        parent => undef,
        body   => [],
    );
    ok(defined $cls_no_parent, 'ClassDecl without parent created');
    is($cls_no_parent->inputs()->[1], undef, 'ClassDecl parent is undef');
}

# === Constructor:Program ===

{
    my $use1 = $f->make('Constructor',
        class => 'UseDecl', module_name => $str_542, import_args => undef,
    );
    my $use2 = $f->make('Constructor',
        class => 'UseDecl', module_name => $str_utf8, import_args => undef,
    );
    my $prog = $f->make('Constructor',
        class      => 'Program',
        statements => [$use1, $use2],
    );
    ok(defined $prog, 'Program created');
    is($prog->class(), 'Program', 'Program class');
    is(scalar $prog->inputs()->@*, 1, 'Program has 1 input');
    is(ref($prog->inputs()->[0]), 'ARRAY', 'Program statements is arrayref');
    is(scalar $prog->inputs()->[0]->@*, 2, 'Program has 2 statements');
    is($prog->inputs()->[0][0], $use1, 'Program statement[0] is use1');
}

# === Hash consing ===

{
    my $ret1 = $f->make('Constructor', class => 'ReturnStmt', value => $str_hello);
    my $ret2 = $f->make('Constructor', class => 'ReturnStmt', value => $str_hello);
    is(refaddr($ret1), refaddr($ret2), 'ReturnStmt hash consing: same inputs -> same node');
}

done_testing();
