# ABOUTME: Unit tests for Perl IR Tier-A typed constructors and CFG nodes.
# ABOUTME: Validates Program, UseInfo, ClassInfo, MethodInfo, Return CFG node, Unwind CFG node creation.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Program;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;

# Reset factory for clean state
my $f = Chalk::IR::NodeFactory->new();

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

# === Return CFG node ===

{
    my $ctrl = $f->make('Start');
    my $ret = $f->make_cfg('Return',
        inputs => [$ctrl, $str_start],
    );
    ok(defined $ret, 'Return CFG node created');
    isa_ok($ret, 'Chalk::IR::Node::Return', 'Return is Chalk::IR::Node::Return');
    is($ret->operation(), 'Return', 'Return operation is Return');
    is(scalar $ret->inputs()->@*, 2, 'Return has 2 inputs (control + value)');
    is($ret->inputs()->[0], $ctrl,      'Return inputs[0] is control');
    is($ret->inputs()->[1], $str_start, 'Return inputs[1] is value');
}

# === Unwind CFG node ===

{
    my $ctrl = $f->make('Start');
    my $die = $f->make_cfg('Unwind',
        inputs => [$ctrl, [$str_die_msg]],
    );
    ok(defined $die, 'Unwind CFG node created');
    isa_ok($die, 'Chalk::IR::Node::Unwind', 'Unwind is Chalk::IR::Node::Unwind');
    is($die->operation(), 'Unwind', 'Unwind operation is Unwind');
    is(scalar $die->inputs()->@*, 2, 'Unwind has 2 inputs (control + exception_args)');
    is($die->inputs()->[0], $ctrl, 'Unwind inputs[0] is control');
    is(ref($die->inputs()->[1]), 'ARRAY', 'Unwind inputs[1] is exception args arrayref');
    is($die->inputs()->[1][0], $str_die_msg, 'Unwind args[0] is the message');
}

# === MethodInfo ===

{
    my $ctrl = $f->make('Start');
    my $ret_stmt = $f->make_cfg('Return',
        inputs => [$ctrl, $str_start],
    );
    my $meth = Chalk::IR::MethodInfo->new(
        name   => 'operation',
        params => [],
        body   => [$ret_stmt],
    );
    ok(defined $meth, 'MethodInfo created');
    isa_ok($meth, 'Chalk::IR::MethodInfo', 'MethodInfo class');
    is($meth->name(), 'operation', 'MethodInfo name is operation');
    is(ref($meth->params()), 'ARRAY', 'MethodInfo params is arrayref');
    is(scalar $meth->params()->@*, 0, 'MethodInfo params is empty');
    is(ref($meth->body()), 'ARRAY', 'MethodInfo body is arrayref');
    is($meth->body()->[0], $ret_stmt, 'MethodInfo body[0] is return stmt');
}

# === UseInfo ===

{
    my $use = Chalk::IR::UseInfo->new(
        name => '5.42.0',
        args => [],
    );
    ok(defined $use, 'UseInfo created');
    isa_ok($use, 'Chalk::IR::UseInfo', 'UseInfo class');
    is($use->name(), '5.42.0', 'UseInfo name');
    is(ref($use->args()), 'ARRAY', 'UseInfo args is arrayref');
    is(scalar $use->args()->@*, 0, 'UseInfo args is empty');
}

{
    my $use_with_args = Chalk::IR::UseInfo->new(
        name => 'experimental',
        args => [$str_class],
    );
    ok(defined $use_with_args, 'UseInfo with args created');
    is(ref($use_with_args->args()), 'ARRAY', 'UseInfo args is arrayref');
    is($use_with_args->args()->[0], $str_class, 'UseInfo args[0] is class');
}

# === ClassInfo ===

{
    my $ctrl = $f->make('Start');
    my $method_node = Chalk::IR::MethodInfo->new(
        name   => 'operation',
        params => [],
        body   => [$f->make_cfg('Return', inputs => [$ctrl, $str_start])],
    );
    my $cls = Chalk::IR::ClassInfo->new(
        name    => 'Chalk::Bootstrap::IR::Node::Start',
        parent  => 'Chalk::Bootstrap::IR::Node',
        methods => [$method_node],
        body    => [$method_node],
    );
    ok(defined $cls, 'ClassInfo created');
    isa_ok($cls, 'Chalk::IR::ClassInfo', 'ClassInfo class');
    is($cls->name(), 'Chalk::Bootstrap::IR::Node::Start', 'ClassInfo name');
    is($cls->parent(), 'Chalk::Bootstrap::IR::Node', 'ClassInfo parent');
    is(ref($cls->body()), 'ARRAY', 'ClassInfo body is arrayref');
}

{
    # ClassInfo without parent
    my $cls_no_parent = Chalk::IR::ClassInfo->new(
        name   => 'Chalk::Bootstrap::IR::Node::Start',
        parent => undef,
        body   => [],
    );
    ok(defined $cls_no_parent, 'ClassInfo without parent created');
    is($cls_no_parent->parent(), undef, 'ClassInfo parent is undef');
}

# === Program ===

{
    my $use1 = Chalk::IR::UseInfo->new(name => '5.42.0', args => []);
    my $use2 = Chalk::IR::UseInfo->new(name => 'utf8',   args => []);
    my $prog = Chalk::IR::Program->new(
        use_decls => [$use1, $use2],
    );
    ok(defined $prog, 'Program created');
    isa_ok($prog, 'Chalk::IR::Program', 'Program class');
    is(ref($prog->use_decls()), 'ARRAY', 'Program use_decls is arrayref');
    is(scalar $prog->use_decls()->@*, 2, 'Program has 2 use_decls');
    is($prog->use_decls()->[0], $use1, 'Program use_decls[0] is use1');
}

# === CFG uniqueness — Return nodes are always distinct (CFG semantics) ===

{
    my $ctrl = $f->make('Start');
    my $ret1 = $f->make_cfg('Return', inputs => [$ctrl, $str_hello]);
    my $ret2 = $f->make_cfg('Return', inputs => [$ctrl, $str_hello]);
    isnt(refaddr($ret1), refaddr($ret2), 'Return CFG nodes are always unique (no hash consing)');
}

done_testing();
