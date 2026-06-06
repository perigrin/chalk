# ABOUTME: Hand-authored MOP/Program graphs for the smallest data-only tier-1 idioms.
# ABOUTME: graph_for($tag) returns a Chalk::MOP built DIRECTLY node-by-node, never via JSON.
package Chalk::CodeGen::Harness::HandGraphs;
use 5.42.0;
use utf8;

use Chalk::MOP;
use Chalk::MOP::Class;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::Ref;

# Dispatch table from corpus tag to builder sub.
# Each builder returns a Chalk::MOP built directly node-by-node.
# The table is populated after all subs are defined to avoid forward-reference issues.
my %BUILDERS;

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Return a Chalk::MOP built directly for the given corpus tag.
# Accepts both class-method call (HandGraphs->graph_for($tag)) and
# instance-method call on a blessed object. Returns undef for unknown tags.
sub graph_for {
    my ($invocant, $tag) = @_;
    my $builder = $BUILDERS{$tag};
    return undef unless defined $builder;
    return $builder->();
}

# ---------------------------------------------------------------------------
# A1: class C { method m() { my $x = 1; return $x; } }
#
# SoN graph (all data-only; no Region/Phi needed):
#   Start  -- control_in edge --> VarDecl($x, Constant(1))
#   VarDecl -- control_in edge --> Return(Constant('$x', variable))
#
# Node layout:
#   start         : Start
#   const_1       : Constant(value=1, const_type=integer)
#   const_name    : Constant(value='$x', const_type=string)   [VarDecl name slot]
#   var_x         : VarDecl(inputs=[const_name, const_1])
#   const_x_read  : Constant(value='$x', const_type=variable) [read $x]
#   ret           : Return(inputs=[const_x_read])
#
# Control chain: start <- var_x.control_in, var_x <- ret.control_in
# ---------------------------------------------------------------------------
sub _build_A1 {
    my $factory = Chalk::IR::NodeFactory->new;

    # Start node — the control entry point.
    my $start = $factory->make_cfg('Start', inputs => []);

    # Constant nodes.
    my $const_name = $factory->make('Constant',
        value      => '$x',
        const_type => 'string',
    );
    my $const_1 = $factory->make('Constant',
        value      => '1',
        const_type => 'integer',
    );
    my $const_x_read = $factory->make('Constant',
        value      => '$x',
        const_type => 'variable',
    );

    # VarDecl: name=$x, init=1. Control predecessor is Start.
    my $var_x = $factory->make('VarDecl',
        inputs => [$const_name, $const_1],
        scope  => 'my',
    );
    $var_x->set_control_in($start);

    # Return: value=$x read. Control predecessor is VarDecl.
    my $ret = $factory->make_cfg('Return', inputs => [$const_x_read]);
    $ret->set_control_in($var_x);

    # Populate graph.
    my $graph = Chalk::IR::Graph->new;
    $graph->merge($start);
    $graph->merge($const_name);
    $graph->merge($const_1);
    $graph->merge($const_x_read);
    $graph->merge($var_x);
    $graph->merge($ret);

    # Wire MOP.
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );
    return $mop;
}

# ---------------------------------------------------------------------------
# A4: class C { method m() { my $x; $x = 1; return $x; } }
#
# VarDecl with no initializer, followed by a bare Assign ($x = 1), then Return.
# The Assign node is a BinOp: inputs[0]=op-constant('='), [1]=lhs, [2]=rhs.
# This matches _emit_binary_expr which reads inputs[0].value() as the op string.
# Control chain: Start <- var_x.control_in <- assign.control_in <- ret.control_in
# ---------------------------------------------------------------------------
sub _build_A4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl for uninitialised $x (no init slot).
    my $const_name = $factory->make('Constant',
        value      => '$x',
        const_type => 'string',
    );
    my $var_x = $factory->make('VarDecl',
        inputs => [$const_name, undef],
        scope  => 'my',
    );
    $var_x->set_control_in($start);

    # Assign: $x = 1.
    # BinOp layout: inputs[0]=Constant('='), inputs[1]=lhs, inputs[2]=rhs.
    # _emit_binary_expr reads: op=inputs[0].value(), left=inputs[1], right=inputs[2].
    my $op_eq   = $factory->make('Constant', value => '=',  const_type => 'string');
    my $lhs_x   = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $const_1 = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $assign  = $factory->make('Assign', inputs => [$op_eq, $lhs_x, $const_1]);
    $assign->set_control_in($var_x);

    # Return: value=$x.
    my $const_x_read = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $ret = $factory->make_cfg('Return', inputs => [$const_x_read]);
    $ret->set_control_in($assign);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $const_name, $var_x, $op_eq, $lhs_x, $const_1, $assign, $const_x_read, $ret) {
        $graph->merge($n) if defined $n;
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );
    return $mop;
}

# ---------------------------------------------------------------------------
# A5: class C { field $x :param; method m() { return $x; } }
#
# The field $x is declared on the MOP class; no VarDecl node in the method.
# The method body is just: return $x;
# Control chain: Start <- ret.control_in
# ---------------------------------------------------------------------------
sub _build_A5 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start        = $factory->make_cfg('Start', inputs => []);
    my $const_x_read = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $ret          = $factory->make_cfg('Return', inputs => [$const_x_read]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($start);
    $graph->merge($const_x_read);
    $graph->merge($ret);

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_field('$x',
        sigil      => '$',
        param_name => 'x',
        attributes => [':param'],
    );
    $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );
    return $mop;
}

# ---------------------------------------------------------------------------
# E1: class C { method m() { my $x = 1; $x } }
#
# Implicit/synthetic return: the trailing expression is the body's value.
# Modelled as a Return with synthetic=true so the emitter omits `return`.
# Control chain: Start <- var_x.control_in <- ret.control_in (synthetic)
# ---------------------------------------------------------------------------
sub _build_E1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    my $const_name = $factory->make('Constant', value => '$x', const_type => 'string');
    my $const_1    = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $var_x      = $factory->make('VarDecl',
        inputs => [$const_name, $const_1],
        scope  => 'my',
    );
    $var_x->set_control_in($start);

    my $const_x_read = $factory->make('Constant', value => '$x', const_type => 'variable');
    # Construct Return directly because make_cfg does not forward extra named params
    # (like synthetic) to the node constructor — only id and inputs are threaded.
    my $ret = Chalk::IR::Node::Return->new(
        id        => 'Return#hand_E1',
        inputs    => [$const_x_read],
        synthetic => true,
    );
    $ret->set_control_in($var_x);

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($start);
    $graph->merge($const_name);
    $graph->merge($const_1);
    $graph->merge($var_x);
    $graph->merge($const_x_read);
    $graph->merge($ret);

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );
    return $mop;
}

# ---------------------------------------------------------------------------
# F3: class C { method m() { my $r = foo(1, 2); return $r; } }
#
# VarDecl whose init value is a Call to function 'foo' with args (1, 2).
# Uses dispatch_kind='builtin' because the emitter only handles 'builtin'
# and 'method' dispatch kinds. The builtin Call node layout matches
# _emit_builtin_call: inputs[0]=Constant(name), inputs[1]=\@args.
# Control chain: Start <- var_r.control_in <- ret.control_in
# ---------------------------------------------------------------------------
sub _build_F3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Call node: foo(1, 2).
    # Layout for dispatch_kind='builtin': inputs[0]=Constant(fn-name), inputs[1]=\@args.
    my $name_foo = $factory->make('Constant', value => 'foo', const_type => 'string');
    my $const_1  = $factory->make('Constant', value => '1',   const_type => 'integer');
    my $const_2  = $factory->make('Constant', value => '2',   const_type => 'integer');
    my @call_args = ($const_1, $const_2);
    my $call_foo = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'foo',
        inputs        => [$name_foo, \@call_args],
    );

    # VarDecl: $r = foo(1, 2).
    my $const_r_name = $factory->make('Constant', value => '$r', const_type => 'string');
    my $var_r = $factory->make('VarDecl',
        inputs => [$const_r_name, $call_foo],
        scope  => 'my',
    );
    $var_r->set_control_in($start);

    # Return: $r.
    my $const_r_read = $factory->make('Constant', value => '$r', const_type => 'variable');
    my $ret = $factory->make_cfg('Return', inputs => [$const_r_read]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_foo, $const_1, $const_2, $call_foo, $const_r_name, $var_r, $const_r_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );
    return $mop;
}

# ---------------------------------------------------------------------------
# A2: class C { method m() { my @list = (1, 2, 3); return scalar @list; } }
#
# VarDecl(@list) initialized from ArrayRef([1,2,3]).
# Return: scalar(@list) — emitted as builtin call scalar([@list]).
# Control chain: Start <- var_list.control_in <- ret.control_in
# ---------------------------------------------------------------------------
sub _build_A2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Array elements: 1, 2, 3
    my $e1 = $factory->make('Constant', value => '1', const_type => 'integer');
    my $e2 = $factory->make('Constant', value => '2', const_type => 'integer');
    my $e3 = $factory->make('Constant', value => '3', const_type => 'integer');

    # ArrayRef node: inputs[0] = perl arrayref of element nodes
    my @elems = ($e1, $e2, $e3);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);

    # VarDecl: my @list = (1, 2, 3)
    my $name_list = $factory->make('Constant', value => '@list', const_type => 'string');
    my $var_list  = $factory->make('VarDecl',
        inputs => [$name_list, $arr_ref],
        scope  => 'my',
    );
    $var_list->set_control_in($start);

    # scalar(@list) — builtin call
    my $name_scalar = $factory->make('Constant', value => 'scalar', const_type => 'string');
    my $list_read   = $factory->make('Constant', value => '@list',  const_type => 'variable');
    my @scalar_args = ($list_read);
    my $call_scalar = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar @list
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($var_list);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $e1, $e2, $e3, $arr_ref, $name_list, $var_list,
               $name_scalar, $list_read, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# A3: class C { method m() { my %h = (a => 1, b => 2); return $h{a}; } }
#
# VarDecl(%h) initialized from HashRef(a,1,b,2).
# Return: Subscript($h, 'a', 'hash') — emits $h{'a'} (aggregate var, so no arrow).
# Control chain: Start <- var_h.control_in <- ret.control_in
# ---------------------------------------------------------------------------
sub _build_A3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Hash pairs: a => 1, b => 2
    my $key_a = $factory->make('Constant', value => 'a', const_type => 'string');
    my $val_1 = $factory->make('Constant', value => '1', const_type => 'integer');
    my $key_b = $factory->make('Constant', value => 'b', const_type => 'string');
    my $val_2 = $factory->make('Constant', value => '2', const_type => 'integer');

    # HashRef node: inputs[0] = perl arrayref of interleaved key/value nodes
    my @pairs = ($key_a, $val_1, $key_b, $val_2);
    my $hash_ref = $factory->make('HashRef', inputs => [\@pairs]);

    # VarDecl: my %h = (a => 1, b => 2)
    my $name_h = $factory->make('Constant', value => '%h', const_type => 'string');
    my $var_h  = $factory->make('VarDecl',
        inputs => [$name_h, $hash_ref],
        scope  => 'my',
    );
    $var_h->set_control_in($start);

    # Subscript: $h{a}
    # inputs[0]=target, inputs[1]=key, inputs[2]=Constant(style)
    my $h_read  = $factory->make('Constant', value => '$h', const_type => 'variable');
    my $key_a2  = $factory->make('Constant', value => 'a',  const_type => 'string');
    my $style   = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_ha  = $factory->make('Subscript',
        inputs => [$h_read, $key_a2, $style],
    );

    # Return: $h{a}
    my $ret = $factory->make_cfg('Return', inputs => [$sub_ha]);
    $ret->set_control_in($var_h);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $key_a, $val_1, $key_b, $val_2, $hash_ref, $name_h, $var_h,
               $h_read, $key_a2, $style, $sub_ha, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# I3: class C { method m() { my sub helper ($n) { return $n * 2; } return helper(3); } }
#
# Represented as VarDecl($helper, AnonSub) + Return(Subscript($helper,[3],call)).
# The oracle runs 'my sub' by name; the generated code calls via coderef $helper->(3).
# Both return 6, so behavioral equivalence gives PASS.
# Control chain: Start <- var_helper <- ret
# ---------------------------------------------------------------------------
sub _build_I3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # AnonSub body: return $n * 2
    my $op_mul   = $factory->make('Constant', value => '*',  const_type => 'string');
    my $n_var    = $factory->make('Constant', value => '$n', const_type => 'variable');
    my $two      = $factory->make('Constant', value => '2',  const_type => 'integer');
    my $mul_op   = $factory->make('Multiply', inputs => [$op_mul, $n_var, $two]);
    my $ret_inner = $factory->make_cfg('Return', inputs => [$mul_op]);

    # AnonSub: param=$n, body=[return $n*2]
    my $n_param  = $factory->make('Constant', value => '$n', const_type => 'string');
    my @params   = ($n_param);
    my @body     = ($ret_inner);
    my $anon_sub = $factory->make('AnonSub', inputs => [\@params, \@body]);

    # VarDecl: my $helper = sub ($n) { ... }
    my $name_h  = $factory->make('Constant', value => '$helper', const_type => 'string');
    my $var_h   = $factory->make('VarDecl', inputs => [$name_h, $anon_sub], scope => 'my');
    $var_h->set_control_in($start);

    # $helper->(3) — coderef call
    my $h_read    = $factory->make('Constant', value => '$helper', const_type => 'variable');
    my $arg_3     = $factory->make('Constant', value => '3',       const_type => 'integer');
    my $call_style = $factory->make('Constant', value => 'call',   const_type => 'string');
    my @call_args = ($arg_3);
    my $call_h    = $factory->make('Subscript', inputs => [$h_read, \@call_args, $call_style]);

    # Return: $helper->(3)
    my $ret = $factory->make_cfg('Return', inputs => [$call_h]);
    $ret->set_control_in($var_h);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_mul, $n_var, $two, $mul_op, $ret_inner,
               $n_param, $anon_sub, $name_h, $var_h,
               $h_read, $arg_3, $call_style, $call_h, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M3: class C { method m($name) { return "hello $name"; } }
#
# Method param $name. Return Interpolate([Constant('hello '), Constant('$name',variable)]).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # "hello $name" — Interpolate with literal and variable parts
    my $lit_hello = $factory->make('Constant', value => 'hello ', const_type => 'string');
    my $var_name  = $factory->make('Constant', value => '$name',  const_type => 'variable');
    my @parts     = ($lit_hello, $var_name);
    my $interp    = $factory->make('Interpolate', inputs => [\@parts]);

    # Return: "hello $name"
    my $ret = $factory->make_cfg('Return', inputs => [$interp]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $lit_hello, $var_name, $interp, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$name'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M4: class C { method m() { my @list = (1, 2); return "got @list"; } }
#
# VarDecl(@list), Return(Interpolate([Constant('got '), Constant('@list',variable)])).
# Control chain: Start <- var_list <- ret
# ---------------------------------------------------------------------------
sub _build_M4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # my @list = (1, 2)
    my $e1      = $factory->make('Constant', value => '1',     const_type => 'integer');
    my $e2      = $factory->make('Constant', value => '2',     const_type => 'integer');
    my @elems   = ($e1, $e2);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);
    my $name_l  = $factory->make('Constant', value => '@list', const_type => 'string');
    my $var_l   = $factory->make('VarDecl', inputs => [$name_l, $arr_ref], scope => 'my');
    $var_l->set_control_in($start);

    # "got @list" — Interpolate
    my $lit_got  = $factory->make('Constant', value => 'got ',  const_type => 'string');
    my $var_list = $factory->make('Constant', value => '@list', const_type => 'variable');
    my @parts    = ($lit_got, $var_list);
    my $interp   = $factory->make('Interpolate', inputs => [\@parts]);

    # Return: "got @list"
    my $ret = $factory->make_cfg('Return', inputs => [$interp]);
    $ret->set_control_in($var_l);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $e1, $e2, $arr_ref, $name_l, $var_l, $lit_got, $var_list, $interp, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M8: class C { method m($r) { return $r->[0]; } }
#
# Method param $r (scalar ref). Return Subscript($r, 0, array) — arrow style.
# $r is not an aggregate var so emits $r->[0].
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M8 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $r->[0] — arrow subscript (not aggregate)
    my $r_read  = $factory->make('Constant', value => '$r',   const_type => 'variable');
    my $idx_0   = $factory->make('Constant', value => '0',    const_type => 'integer');
    my $style_a = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_r0  = $factory->make('Subscript', inputs => [$r_read, $idx_0, $style_a]);

    # Return: $r->[0]
    my $ret = $factory->make_cfg('Return', inputs => [$sub_r0]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $r_read, $idx_0, $style_a, $sub_r0, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$r'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M9: class C { method m($r) { return $r->{key}; } }
#
# Method param $r. Return Subscript($r, 'key', hash) — arrow style.
# $r is not an aggregate var so emits $r->{'key'}.
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M9 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $r->{'key'}
    my $r_read  = $factory->make('Constant', value => '$r',  const_type => 'variable');
    my $key     = $factory->make('Constant', value => 'key', const_type => 'string');
    my $style_h = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_rk  = $factory->make('Subscript', inputs => [$r_read, $key, $style_h]);

    # Return: $r->{'key'}
    my $ret = $factory->make_cfg('Return', inputs => [$sub_rk]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $r_read, $key, $style_h, $sub_rk, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$r'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M10: class C { method m() { my @list = (1, 2); my $r = \@list; return $r->[0]; } }
#
# VarDecl(@list), VarDecl($r, Ref(@list)), Return(Subscript($r, 0, array)).
# Ref is a UnaryOp with op='\'. The emitter emits \@list for Ref(@list).
# Control chain: Start <- var_list <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_M10 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # my @list = (1, 2)
    my $e1      = $factory->make('Constant', value => '1',     const_type => 'integer');
    my $e2      = $factory->make('Constant', value => '2',     const_type => 'integer');
    my @elems   = ($e1, $e2);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);
    my $name_l  = $factory->make('Constant', value => '@list', const_type => 'string');
    my $var_l   = $factory->make('VarDecl', inputs => [$name_l, $arr_ref], scope => 'my');
    $var_l->set_control_in($start);

    # my $r = \@list — Ref node (UnaryOp with op='\')
    my $op_ref   = $factory->make('Constant', value => '\\',   const_type => 'string');
    my $list_var = $factory->make('Constant', value => '@list', const_type => 'variable');
    my $ref_node = $factory->make('Ref', inputs => [$op_ref, $list_var]);
    my $name_r   = $factory->make('Constant', value => '$r',   const_type => 'string');
    my $var_r    = $factory->make('VarDecl', inputs => [$name_r, $ref_node], scope => 'my');
    $var_r->set_control_in($var_l);

    # $r->[0]
    my $r_read  = $factory->make('Constant', value => '$r',   const_type => 'variable');
    my $idx_0   = $factory->make('Constant', value => '0',    const_type => 'integer');
    my $style_a = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_r0  = $factory->make('Subscript', inputs => [$r_read, $idx_0, $style_a]);

    # Return: $r->[0]
    my $ret = $factory->make_cfg('Return', inputs => [$sub_r0]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $e1, $e2, $arr_ref, $name_l, $var_l,
               $op_ref, $list_var, $ref_node, $name_r, $var_r,
               $r_read, $idx_0, $style_a, $sub_r0, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M11: class C { method m() { my %h = (k => 1); my $r = \%h; return $r->{k}; } }
#
# VarDecl(%h), VarDecl($r, Ref(%h)), Return(Subscript($r, k, hash)).
# Control chain: Start <- var_h <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_M11 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # my %h = (k => 1)
    my $key_k    = $factory->make('Constant', value => 'k', const_type => 'string');
    my $val_1    = $factory->make('Constant', value => '1', const_type => 'integer');
    my @pairs    = ($key_k, $val_1);
    my $hash_ref = $factory->make('HashRef', inputs => [\@pairs]);
    my $name_h   = $factory->make('Constant', value => '%h', const_type => 'string');
    my $var_h    = $factory->make('VarDecl', inputs => [$name_h, $hash_ref], scope => 'my');
    $var_h->set_control_in($start);

    # my $r = \%h
    my $op_ref  = $factory->make('Constant', value => '\\', const_type => 'string');
    my $h_var   = $factory->make('Constant', value => '%h', const_type => 'variable');
    my $ref_node = $factory->make('Ref', inputs => [$op_ref, $h_var]);
    my $name_r  = $factory->make('Constant', value => '$r', const_type => 'string');
    my $var_r   = $factory->make('VarDecl', inputs => [$name_r, $ref_node], scope => 'my');
    $var_r->set_control_in($var_h);

    # $r->{k}
    my $r_read  = $factory->make('Constant', value => '$r',  const_type => 'variable');
    my $key_k2  = $factory->make('Constant', value => 'k',   const_type => 'string');
    my $style_h = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_rk  = $factory->make('Subscript', inputs => [$r_read, $key_k2, $style_h]);

    # Return: $r->{k}
    my $ret = $factory->make_cfg('Return', inputs => [$sub_rk]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $key_k, $val_1, $hash_ref, $name_h, $var_h,
               $op_ref, $h_var, $ref_node, $name_r, $var_r,
               $r_read, $key_k2, $style_h, $sub_rk, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M12: class C { method m() { return Foo::Bar->new(); } }
#
# Static method call: Call(method, Constant('Foo::Bar', bareword), 'new', []).
# Foo::Bar doesn't exist; both oracle and generated raise matching exceptions.
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M12 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Foo::Bar->new()
    my $class_fb = $factory->make('Constant', value => 'Foo::Bar', const_type => 'bareword');
    my $name_new = $factory->make('Constant', value => 'new',      const_type => 'string');
    my @new_args = ();
    my $call_new = $factory->make('Call',
        dispatch_kind => 'method',
        name          => 'new',
        inputs        => [$class_fb, $name_new, \@new_args],
    );

    # Return: Foo::Bar->new()
    my $ret = $factory->make_cfg('Return', inputs => [$call_new]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $class_fb, $name_new, $call_new, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M13: class C { method m() { return Foo::Bar::baz(1); } }
#
# Qualified function call: Call(builtin, 'Foo::Bar::baz', [1]).
# Foo::Bar::baz doesn't exist; both oracle and generated raise matching exceptions.
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M13 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Foo::Bar::baz(1)
    my $name_baz = $factory->make('Constant', value => 'Foo::Bar::baz', const_type => 'string');
    my $arg_1    = $factory->make('Constant', value => '1',             const_type => 'integer');
    my @baz_args = ($arg_1);
    my $call_baz = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'Foo::Bar::baz',
        inputs        => [$name_baz, \@baz_args],
    );

    # Return: Foo::Bar::baz(1)
    my $ret = $factory->make_cfg('Return', inputs => [$call_baz]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_baz, $arg_1, $call_baz, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M14: class C { method m($a) { return "got " . $a; } }
#
# Method param $a. Return BinOp(., Constant('got '), $a).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M14 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # "got " . $a
    my $op_dot = $factory->make('Constant', value => '.',     const_type => 'string');
    my $lit    = $factory->make('Constant', value => 'got ',  const_type => 'string');
    my $a_var  = $factory->make('Constant', value => '$a',    const_type => 'variable');
    my $concat = $factory->make('Concat', inputs => [$op_dot, $lit, $a_var]);

    # Return: "got " . $a
    my $ret = $factory->make_cfg('Return', inputs => [$concat]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_dot, $lit, $a_var, $concat, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$a'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M15: class C { method m($x) { my $y; $y //= $x; return $y; } }
#
# VarDecl($y, undef), CompoundAssign(//=, $y, $x), Return($y).
# Control chain: Start <- var_y <- compound_assign <- ret
# ---------------------------------------------------------------------------
sub _build_M15 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my $y (uninitialised)
    my $name_y = $factory->make('Constant', value => '$y', const_type => 'string');
    my $var_y  = $factory->make('VarDecl', inputs => [$name_y, undef], scope => 'my');
    $var_y->set_control_in($start);

    # $y //= $x
    my $op_dfeq = $factory->make('Constant', value => '//=', const_type => 'string');
    my $y_lhs   = $factory->make('Constant', value => '$y',  const_type => 'variable');
    my $x_var   = $factory->make('Constant', value => '$x',  const_type => 'variable');
    my $compound = $factory->make('CompoundAssign',
        op     => '//=',
        inputs => [$op_dfeq, $y_lhs, $x_var],
    );
    $compound->set_control_in($var_y);

    # Return: $y
    my $y_read = $factory->make('Constant', value => '$y', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$y_read]);
    $ret->set_control_in($compound);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_y, $var_y, $op_dfeq, $y_lhs, $x_var, $compound, $y_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$x'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M22: class C { method m() { my @r = sort { $a <=> $b } (3, 1, 2); return $r[0]; } }
#
# sort with comparison block: AnonSub({$a <=> $b}), then list args.
# VarDecl(@r), Return(Subscript($r, 0, array)).
# Control chain: Start <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_M22 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Block body: $a <=> $b
    my $op_cmp = $factory->make('Constant', value => '<=>',  const_type => 'string');
    my $a_var  = $factory->make('Constant', value => '$a',   const_type => 'variable');
    my $b_var  = $factory->make('Constant', value => '$b',   const_type => 'variable');
    my $cmp_op = $factory->make('NumCmp', inputs => [$op_cmp, $a_var, $b_var]);

    # AnonSub (block form): no params, body = [$cmp_op]
    my @no_params  = ();
    my @block_body = ($cmp_op);
    my $block      = $factory->make('AnonSub', inputs => [\@no_params, \@block_body]);

    # sort args: block + list elements
    my $name_sort = $factory->make('Constant', value => 'sort', const_type => 'string');
    my $e3        = $factory->make('Constant', value => '3',    const_type => 'integer');
    my $e1        = $factory->make('Constant', value => '1',    const_type => 'integer');
    my $e2        = $factory->make('Constant', value => '2',    const_type => 'integer');
    my @sort_args = ($block, $e3, $e1, $e2);
    my $call_sort = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'sort',
        inputs        => [$name_sort, \@sort_args],
    );

    # VarDecl: my @r = sort { ... } (3, 1, 2)
    my $name_r  = $factory->make('Constant', value => '@r', const_type => 'string');
    my $var_r   = $factory->make('VarDecl', inputs => [$name_r, $call_sort], scope => 'my');
    $var_r->set_control_in($start);

    # $r[0] — aggregate subscript
    my $r_read  = $factory->make('Constant', value => '$r',   const_type => 'variable');
    my $idx_0   = $factory->make('Constant', value => '0',    const_type => 'integer');
    my $style_a = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_r0  = $factory->make('Subscript', inputs => [$r_read, $idx_0, $style_a]);

    # Return: $r[0]
    my $ret = $factory->make_cfg('Return', inputs => [$sub_r0]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_cmp, $a_var, $b_var, $cmp_op, $block, $name_sort,
               $e3, $e1, $e2, $call_sort, $name_r, $var_r,
               $r_read, $idx_0, $style_a, $sub_r0, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M23: class C { method m() { my %h = (a => 1); delete $h{a}; return scalar keys %h; } }
#
# VarDecl(%h), bare Call(delete, [Subscript($h,a,hash)]), Return(scalar(keys(%h))).
# Control chain: Start <- var_h <- delete_call <- ret
# ---------------------------------------------------------------------------
sub _build_M23 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # my %h = (a => 1)
    my $key_a    = $factory->make('Constant', value => 'a', const_type => 'string');
    my $val_1    = $factory->make('Constant', value => '1', const_type => 'integer');
    my @pairs    = ($key_a, $val_1);
    my $hash_ref = $factory->make('HashRef', inputs => [\@pairs]);
    my $name_h   = $factory->make('Constant', value => '%h', const_type => 'string');
    my $var_h    = $factory->make('VarDecl', inputs => [$name_h, $hash_ref], scope => 'my');
    $var_h->set_control_in($start);

    # delete $h{a} — Call(delete, [Subscript($h, a, hash)])
    my $h_lhs   = $factory->make('Constant', value => '$h',   const_type => 'variable');
    my $key_a2  = $factory->make('Constant', value => 'a',    const_type => 'string');
    my $style_h = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_ha  = $factory->make('Subscript', inputs => [$h_lhs, $key_a2, $style_h]);
    my $name_del = $factory->make('Constant', value => 'delete', const_type => 'string');
    my @del_args = ($sub_ha);
    my $call_del = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'delete',
        inputs        => [$name_del, \@del_args],
    );
    $call_del->set_control_in($var_h);

    # keys %h — Call(keys, [%h])
    my $name_keys = $factory->make('Constant', value => 'keys', const_type => 'string');
    my $h_read    = $factory->make('Constant', value => '%h',   const_type => 'variable');
    my @keys_args = ($h_read);
    my $call_keys = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'keys',
        inputs        => [$name_keys, \@keys_args],
    );

    # scalar(keys(%h)) — Call(scalar, [Call(keys)])
    my $name_scalar  = $factory->make('Constant', value => 'scalar', const_type => 'string');
    my @scalar_args  = ($call_keys);
    my $call_scalar  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar keys %h
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($call_del);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $key_a, $val_1, $hash_ref, $name_h, $var_h,
               $h_lhs, $key_a2, $style_h, $sub_ha, $name_del, $call_del,
               $name_keys, $h_read, $call_keys,
               $name_scalar, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# M24: class C { method m($r) { return $r->{a}->[0]; } }
#
# Method param $r. Chained subscript: Subscript(Subscript($r, a, hash), 0, array).
# Emits $r->{'a'}->[0]. Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_M24 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $r->{'a'} — outer hash subscript (arrow style, not aggregate)
    my $r_read   = $factory->make('Constant', value => '$r',   const_type => 'variable');
    my $key_a    = $factory->make('Constant', value => 'a',    const_type => 'string');
    my $style_h  = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_rha  = $factory->make('Subscript', inputs => [$r_read, $key_a, $style_h]);

    # ->->[0] — inner array subscript
    my $idx_0    = $factory->make('Constant', value => '0',    const_type => 'integer');
    my $style_a  = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_arr  = $factory->make('Subscript', inputs => [$sub_rha, $idx_0, $style_a]);

    # Return: $r->{a}->[0]
    my $ret = $factory->make_cfg('Return', inputs => [$sub_arr]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $r_read, $key_a, $style_h, $sub_rha, $idx_0, $style_a, $sub_arr, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$r'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# H1: class C { method m() { my @r = map { $_ * 2 } (1, 2, 3); return scalar @r; } }
#
# VarDecl(@r, Call(map, [AnonSub({$_*2}), 1, 2, 3])), Return(scalar(@r)).
# The AnonSub is the block form: inputs[0]=[] params, inputs[1]=[BinOp(*,_,2)].
# Control chain: Start <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_H1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Block body: $_ * 2
    my $op_mul    = $factory->make('Constant', value => '*',  const_type => 'string');
    my $topic_var = $factory->make('Constant', value => '$_', const_type => 'variable');
    my $two       = $factory->make('Constant', value => '2',  const_type => 'integer');
    my $mul_op    = $factory->make('Multiply', inputs => [$op_mul, $topic_var, $two]);

    # AnonSub (block form): no params, body = [$mul_op]
    my @no_params  = ();
    my @block_body = ($mul_op);
    my $block      = $factory->make('AnonSub', inputs => [\@no_params, \@block_body]);

    # map args: AnonSub + list elements
    my $name_map = $factory->make('Constant', value => 'map', const_type => 'string');
    my $e1       = $factory->make('Constant', value => '1',   const_type => 'integer');
    my $e2       = $factory->make('Constant', value => '2',   const_type => 'integer');
    my $e3       = $factory->make('Constant', value => '3',   const_type => 'integer');
    my @map_args = ($block, $e1, $e2, $e3);
    my $call_map = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'map',
        inputs        => [$name_map, \@map_args],
    );

    # VarDecl: my @r = map { ... } (1,2,3)
    my $name_r  = $factory->make('Constant', value => '@r', const_type => 'string');
    my $var_r   = $factory->make('VarDecl', inputs => [$name_r, $call_map], scope => 'my');
    $var_r->set_control_in($start);

    # scalar(@r)
    my $name_scalar = $factory->make('Constant', value => 'scalar', const_type => 'string');
    my $r_read      = $factory->make('Constant', value => '@r',     const_type => 'variable');
    my @scalar_args = ($r_read);
    my $call_scalar = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar @r
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_mul, $topic_var, $two, $mul_op, $block, $name_map,
               $e1, $e2, $e3, $call_map, $name_r, $var_r,
               $name_scalar, $r_read, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# H2: class C { method m() { my @r = grep { $_ > 1 } (1, 2, 3); return scalar @r; } }
#
# VarDecl(@r, Call(grep, [AnonSub({$_>1}), 1, 2, 3])), Return(scalar(@r)).
# The AnonSub block body is BinOp(>, $_, 1).
# Control chain: Start <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_H2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # Block body: $_ > 1
    my $op_gt     = $factory->make('Constant', value => '>',  const_type => 'string');
    my $topic_var = $factory->make('Constant', value => '$_', const_type => 'variable');
    my $one_val   = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $gt_op     = $factory->make('NumGt', inputs => [$op_gt, $topic_var, $one_val]);

    # AnonSub (block form): no params, body = [$gt_op]
    my @no_params  = ();
    my @block_body = ($gt_op);
    my $block      = $factory->make('AnonSub', inputs => [\@no_params, \@block_body]);

    # grep args
    my $name_grep = $factory->make('Constant', value => 'grep', const_type => 'string');
    my $e1        = $factory->make('Constant', value => '1',    const_type => 'integer');
    my $e2        = $factory->make('Constant', value => '2',    const_type => 'integer');
    my $e3        = $factory->make('Constant', value => '3',    const_type => 'integer');
    my @grep_args = ($block, $e1, $e2, $e3);
    my $call_grep = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'grep',
        inputs        => [$name_grep, \@grep_args],
    );

    # VarDecl: my @r = grep { ... } (1,2,3)
    my $name_r  = $factory->make('Constant', value => '@r', const_type => 'string');
    my $var_r   = $factory->make('VarDecl', inputs => [$name_r, $call_grep], scope => 'my');
    $var_r->set_control_in($start);

    # scalar(@r)
    my $name_scalar = $factory->make('Constant', value => 'scalar', const_type => 'string');
    my $r_read      = $factory->make('Constant', value => '@r',     const_type => 'variable');
    my @scalar_args = ($r_read);
    my $call_scalar = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar @r
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_gt, $topic_var, $one_val, $gt_op, $block, $name_grep,
               $e1, $e2, $e3, $call_grep, $name_r, $var_r,
               $name_scalar, $r_read, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# H3: class C { method m() { my @r = sort (3, 1, 2); return $r[0]; } }
#
# sort without block: Call(sort, [3, 1, 2]).
# VarDecl(@r), Return(Subscript($r, 0, array)).
# Control chain: Start <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_H3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # sort(3, 1, 2)
    my $name_sort = $factory->make('Constant', value => 'sort', const_type => 'string');
    my $e3        = $factory->make('Constant', value => '3',    const_type => 'integer');
    my $e1        = $factory->make('Constant', value => '1',    const_type => 'integer');
    my $e2        = $factory->make('Constant', value => '2',    const_type => 'integer');
    my @sort_args = ($e3, $e1, $e2);
    my $call_sort = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'sort',
        inputs        => [$name_sort, \@sort_args],
    );

    # VarDecl: my @r = sort(3, 1, 2)
    my $name_r  = $factory->make('Constant', value => '@r', const_type => 'string');
    my $var_r   = $factory->make('VarDecl', inputs => [$name_r, $call_sort], scope => 'my');
    $var_r->set_control_in($start);

    # $r[0] — aggregate subscript
    my $r_read  = $factory->make('Constant', value => '$r',   const_type => 'variable');
    my $idx_0   = $factory->make('Constant', value => '0',    const_type => 'integer');
    my $style_a = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_r0  = $factory->make('Subscript', inputs => [$r_read, $idx_0, $style_a]);

    # Return: $r[0]
    my $ret = $factory->make_cfg('Return', inputs => [$sub_r0]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_sort, $e3, $e1, $e2, $call_sort, $name_r, $var_r,
               $r_read, $idx_0, $style_a, $sub_r0, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# H4: class C { method m() { my $f = sub ($x) { return $x + 1; }; return $f->(1); } }
#
# AnonSub with param $x and body [Return(BinOp(+,$x,1))].
# VarDecl($f, AnonSub), Return(Subscript($f, [1], call)).
# Control chain: Start <- var_f <- ret
# ---------------------------------------------------------------------------
sub _build_H4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # AnonSub body: return $x + 1
    my $op_plus = $factory->make('Constant', value => '+',  const_type => 'string');
    my $x_var   = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $one_val = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $add_op  = $factory->make('Add', inputs => [$op_plus, $x_var, $one_val]);

    # Return node inside the anon sub body
    my $ret_inner = $factory->make_cfg('Return', inputs => [$add_op]);

    # AnonSub: params=['$x'], body=[ret_inner]
    my $x_param   = $factory->make('Constant', value => '$x', const_type => 'string');
    my @params    = ($x_param);
    my @body      = ($ret_inner);
    my $anon_sub  = $factory->make('AnonSub', inputs => [\@params, \@body]);

    # VarDecl: my $f = sub ($x) { ... }
    my $name_f  = $factory->make('Constant', value => '$f', const_type => 'string');
    my $var_f   = $factory->make('VarDecl', inputs => [$name_f, $anon_sub], scope => 'my');
    $var_f->set_control_in($start);

    # $f->(1) — coderef call: Subscript($f, [1], call)
    my $f_read    = $factory->make('Constant', value => '$f', const_type => 'variable');
    my $arg_1     = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $call_style = $factory->make('Constant', value => 'call', const_type => 'string');
    my @call_args = ($arg_1);
    my $call_f    = $factory->make('Subscript', inputs => [$f_read, \@call_args, $call_style]);

    # Return: $f->(1)
    my $ret = $factory->make_cfg('Return', inputs => [$call_f]);
    $ret->set_control_in($var_f);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_plus, $x_var, $one_val, $add_op, $ret_inner,
               $x_param, $anon_sub, $name_f, $var_f,
               $f_read, $arg_1, $call_style, $call_f, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# D6: class C { method m($n) { my $x = $n > 0 ? 1 : 2; return $x; } }
#
# Method param $n. VarDecl($x) = TernaryExpr(BinOp(>, $n, 0), 1, 2). Return $x.
# Control chain: Start <- var_x <- ret
# ---------------------------------------------------------------------------
sub _build_D6 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $n > 0 — BinOp with operator '>'
    my $op_gt  = $factory->make('Constant', value => '>',  const_type => 'string');
    my $n_var  = $factory->make('Constant', value => '$n', const_type => 'variable');
    my $zero   = $factory->make('Constant', value => '0',  const_type => 'integer');
    my $cond   = $factory->make('NumGt', inputs => [$op_gt, $n_var, $zero]);

    # $n > 0 ? 1 : 2 — TernaryExpr
    my $one    = $factory->make('Constant', value => '1', const_type => 'integer');
    my $two    = $factory->make('Constant', value => '2', const_type => 'integer');
    my $ternary = $factory->make('TernaryExpr', inputs => [$cond, $one, $two]);

    # VarDecl: my $x = $n > 0 ? 1 : 2
    my $name_x = $factory->make('Constant', value => '$x', const_type => 'string');
    my $var_x  = $factory->make('VarDecl', inputs => [$name_x, $ternary], scope => 'my');
    $var_x->set_control_in($start);

    # Return: $x
    my $x_read = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$x_read]);
    $ret->set_control_in($var_x);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_gt, $n_var, $zero, $cond, $one, $two, $ternary, $name_x, $var_x, $x_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$n'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# J1: class C { method m($s) { return $s =~ /foo/; } }
#
# Method param $s. Return RegexMatch($s, /foo/).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_J1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $s =~ /foo/
    my $s_var  = $factory->make('Constant', value => '$s',   const_type => 'variable');
    my $pat    = $factory->make('Constant', value => '/foo/', const_type => 'regex');
    my $match  = $factory->make('RegexMatch', inputs => [$s_var, $pat]);

    # Return: $s =~ /foo/
    my $ret = $factory->make_cfg('Return', inputs => [$match]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $s_var, $pat, $match, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$s'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# J2: class C { method m($s) { $s =~ s/foo/bar/; return $s; } }
#
# Method param $s. Bare RegexSubst($s, foo, bar, ''), then Return($s).
# RegexSubst is a statement-position side-effect: set_control_in on it.
# Control chain: Start <- subst <- ret
# ---------------------------------------------------------------------------
sub _build_J2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $s =~ s/foo/bar/
    my $s_var  = $factory->make('Constant', value => '$s',  const_type => 'variable');
    my $pat    = $factory->make('Constant', value => 'foo', const_type => 'string');
    my $repl   = $factory->make('Constant', value => 'bar', const_type => 'string');
    my $flags  = $factory->make('Constant', value => '',    const_type => 'string');
    my $subst  = $factory->make('RegexSubst', inputs => [$s_var, $pat, $repl, $flags]);
    $subst->set_control_in($start);

    # Return: $s (after substitution)
    my $s_read = $factory->make('Constant', value => '$s', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$s_read]);
    $ret->set_control_in($subst);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $s_var, $pat, $repl, $flags, $subst, $s_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$s'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# J3: class C { method m() { my @keys = qw(a b c); return scalar @keys; } }
#
# qw(a b c) desugars to ArrayRef(['a','b','c']). VarDecl, Return(scalar(@keys)).
# Control chain: Start <- var_keys <- ret
# ---------------------------------------------------------------------------
sub _build_J3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # qw(a b c) — ArrayRef of string constants
    my $str_a  = $factory->make('Constant', value => 'a', const_type => 'string');
    my $str_b  = $factory->make('Constant', value => 'b', const_type => 'string');
    my $str_c  = $factory->make('Constant', value => 'c', const_type => 'string');
    my @elems  = ($str_a, $str_b, $str_c);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);

    # VarDecl: my @keys = qw(a b c)
    my $name_keys = $factory->make('Constant', value => '@keys', const_type => 'string');
    my $var_keys  = $factory->make('VarDecl', inputs => [$name_keys, $arr_ref], scope => 'my');
    $var_keys->set_control_in($start);

    # scalar(@keys)
    my $name_scalar  = $factory->make('Constant', value => 'scalar',  const_type => 'string');
    my $keys_read    = $factory->make('Constant', value => '@keys',   const_type => 'variable');
    my @scalar_args  = ($keys_read);
    my $call_scalar  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar @keys
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($var_keys);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $str_a, $str_b, $str_c, $arr_ref, $name_keys, $var_keys,
               $name_scalar, $keys_read, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# L1: class C { method m($a, $b) { return $a && $b; } }
#
# Method params $a, $b. Return BinOp(&&, $a, $b).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_L1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $a && $b
    my $op_and = $factory->make('Constant', value => '&&', const_type => 'string');
    my $a_var  = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $b_var  = $factory->make('Constant', value => '$b', const_type => 'variable');
    my $and_op = $factory->make('And', inputs => [$op_and, $a_var, $b_var]);

    # Return: $a && $b
    my $ret = $factory->make_cfg('Return', inputs => [$and_op]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_and, $a_var, $b_var, $and_op, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$a', '$b'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# L2: class C { method m($a, $b) { return $a || $b; } }
#
# Method params $a, $b. Return BinOp(||, $a, $b).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_L2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $a || $b
    my $op_or  = $factory->make('Constant', value => '||', const_type => 'string');
    my $a_var  = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $b_var  = $factory->make('Constant', value => '$b', const_type => 'variable');
    my $or_op  = $factory->make('Or', inputs => [$op_or, $a_var, $b_var]);

    # Return: $a || $b
    my $ret = $factory->make_cfg('Return', inputs => [$or_op]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_or, $a_var, $b_var, $or_op, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$a', '$b'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# L3: class C { method m($a, $b) { return $a // $b; } }
#
# Method params $a, $b. Return BinOp(//, $a, $b).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_L3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $a // $b
    my $op_defedor = $factory->make('Constant', value => '//', const_type => 'string');
    my $a_var      = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $b_var      = $factory->make('Constant', value => '$b', const_type => 'variable');
    my $defor_op   = $factory->make('DefinedOr', inputs => [$op_defedor, $a_var, $b_var]);

    # Return: $a // $b
    my $ret = $factory->make_cfg('Return', inputs => [$defor_op]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_defedor, $a_var, $b_var, $defor_op, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$a', '$b'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# L4: class C { method m($a) { return !$a; } }
#
# Method param $a. Return UnaryOp(!, $a).
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_L4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # !$a
    my $op_not = $factory->make('Constant', value => '!',  const_type => 'string');
    my $a_var  = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $not_op = $factory->make('Not', inputs => [$op_not, $a_var]);

    # Return: !$a
    my $ret = $factory->make_cfg('Return', inputs => [$not_op]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $op_not, $a_var, $not_op, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => ['$a'], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# F1: class C { method m() { return $self->foo->bar; } }
#
# Chained method calls: $self->foo returns something, then ->bar is called on it.
# foo and bar are undefined on C; both oracle and generated raise matching
# "Can't locate object method" exceptions. Verdict = PASS via exception axis.
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_F1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $self->foo() — first method call, no args
    my $self_var  = $factory->make('Constant', value => '$self', const_type => 'variable');
    my $name_foo  = $factory->make('Constant', value => 'foo',   const_type => 'string');
    my @foo_args  = ();
    my $call_foo  = $factory->make('Call',
        dispatch_kind => 'method',
        name          => 'foo',
        inputs        => [$self_var, $name_foo, \@foo_args],
    );

    # $result->bar() — second method call on result of foo
    my $name_bar  = $factory->make('Constant', value => 'bar', const_type => 'string');
    my @bar_args  = ();
    my $call_bar  = $factory->make('Call',
        dispatch_kind => 'method',
        name          => 'bar',
        inputs        => [$call_foo, $name_bar, \@bar_args],
    );

    # Return: result of ->bar
    my $ret = $factory->make_cfg('Return', inputs => [$call_bar]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $self_var, $name_foo, $call_foo, $name_bar, $call_bar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# F2: class C { method m() { return $self->foo(1, 2, 3); } }
#
# Method call with arguments. foo is undefined; both oracle and generated
# raise matching "Can't locate object method" exceptions. Verdict = PASS.
# Control chain: Start <- ret
# ---------------------------------------------------------------------------
sub _build_F2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $self->foo(1, 2, 3)
    my $self_var = $factory->make('Constant', value => '$self', const_type => 'variable');
    my $name_foo = $factory->make('Constant', value => 'foo',   const_type => 'string');
    my $arg1     = $factory->make('Constant', value => '1',     const_type => 'integer');
    my $arg2     = $factory->make('Constant', value => '2',     const_type => 'integer');
    my $arg3     = $factory->make('Constant', value => '3',     const_type => 'integer');
    my @foo_args = ($arg1, $arg2, $arg3);
    my $call_foo = $factory->make('Call',
        dispatch_kind => 'method',
        name          => 'foo',
        inputs        => [$self_var, $name_foo, \@foo_args],
    );

    # Return: result of ->foo(1,2,3)
    my $ret = $factory->make_cfg('Return', inputs => [$call_foo]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $self_var, $name_foo, $arg1, $arg2, $arg3, $call_foo, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# G1: class C { method m() { my $r = [1, 2]; return $r->@*; } }
#
# VarDecl($r, ArrayRef([1,2])), Return(PostfixDeref($r, '@')).
# Control chain: Start <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_G1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # [1, 2] — array reference constructor
    my $e1     = $factory->make('Constant', value => '1', const_type => 'integer');
    my $e2     = $factory->make('Constant', value => '2', const_type => 'integer');
    my @elems  = ($e1, $e2);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);

    # VarDecl: my $r = [1, 2]
    my $name_r = $factory->make('Constant', value => '$r', const_type => 'string');
    my $var_r  = $factory->make('VarDecl', inputs => [$name_r, $arr_ref], scope => 'my');
    $var_r->set_control_in($start);

    # $r->@* — PostfixDeref with '@' sigil
    # inputs[0]=target, inputs[1]=Constant(sigil); named param sigil='@'
    my $r_read    = $factory->make('Constant', value => '$r', const_type => 'variable');
    my $sigil_at  = $factory->make('Constant', value => '@',  const_type => 'string');
    my $deref     = $factory->make('PostfixDeref',
        sigil  => '@',
        inputs => [$r_read, $sigil_at],
    );

    # Return: $r->@*
    my $ret = $factory->make_cfg('Return', inputs => [$deref]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $e1, $e2, $arr_ref, $name_r, $var_r, $r_read, $sigil_at, $deref, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# G2: class C { method m() { my $r = { a => 1 }; return $r->%*; } }
#
# VarDecl($r, HashRef({a=>1})), Return(PostfixDeref($r, '%')).
# Control chain: Start <- var_r <- ret
# ---------------------------------------------------------------------------
sub _build_G2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # { a => 1 } — hash reference constructor
    my $key_a    = $factory->make('Constant', value => 'a', const_type => 'string');
    my $val_1    = $factory->make('Constant', value => '1', const_type => 'integer');
    my @pairs    = ($key_a, $val_1);
    my $hash_ref = $factory->make('HashRef', inputs => [\@pairs]);

    # VarDecl: my $r = { a => 1 }
    my $name_r = $factory->make('Constant', value => '$r', const_type => 'string');
    my $var_r  = $factory->make('VarDecl', inputs => [$name_r, $hash_ref], scope => 'my');
    $var_r->set_control_in($start);

    # $r->%* — PostfixDeref with '%' sigil
    my $r_read    = $factory->make('Constant', value => '$r', const_type => 'variable');
    my $sigil_pct = $factory->make('Constant', value => '%',  const_type => 'string');
    my $deref     = $factory->make('PostfixDeref',
        sigil  => '%',
        inputs => [$r_read, $sigil_pct],
    );

    # Return: $r->%*
    my $ret = $factory->make_cfg('Return', inputs => [$deref]);
    $ret->set_control_in($var_r);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $key_a, $val_1, $hash_ref, $name_r, $var_r, $r_read, $sigil_pct, $deref, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# G3: class C { method m() { my @a = (1, 2); return $a[0]; } }
#
# VarDecl(@a, ArrayRef([1,2])), Return(Subscript($a, 0, array)).
# @a is an aggregate var so emitter produces $a[0] (no arrow).
# Control chain: Start <- var_a <- ret
# ---------------------------------------------------------------------------
sub _build_G3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # my @a = (1, 2)
    my $e1     = $factory->make('Constant', value => '1', const_type => 'integer');
    my $e2     = $factory->make('Constant', value => '2', const_type => 'integer');
    my @elems  = ($e1, $e2);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);
    my $name_a  = $factory->make('Constant', value => '@a', const_type => 'string');
    my $var_a   = $factory->make('VarDecl', inputs => [$name_a, $arr_ref], scope => 'my');
    $var_a->set_control_in($start);

    # $a[0] — Subscript, style=array, aggregate var -> emits $a[0]
    my $a_read  = $factory->make('Constant', value => '$a',   const_type => 'variable');
    my $idx_0   = $factory->make('Constant', value => '0',    const_type => 'integer');
    my $style_a = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_a0  = $factory->make('Subscript', inputs => [$a_read, $idx_0, $style_a]);

    # Return: $a[0]
    my $ret = $factory->make_cfg('Return', inputs => [$sub_a0]);
    $ret->set_control_in($var_a);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $e1, $e2, $arr_ref, $name_a, $var_a, $a_read, $idx_0, $style_a, $sub_a0, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# G4: class C { method m() { my %h = (k => 1); return $h{k}; } }
#
# VarDecl(%h, HashRef({k=>1})), Return(Subscript($h, k, hash)).
# %h is an aggregate var so emitter produces $h{k} (no arrow).
# Control chain: Start <- var_h <- ret
# ---------------------------------------------------------------------------
sub _build_G4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # my %h = (k => 1)
    my $key_k    = $factory->make('Constant', value => 'k', const_type => 'string');
    my $val_1    = $factory->make('Constant', value => '1', const_type => 'integer');
    my @pairs    = ($key_k, $val_1);
    my $hash_ref = $factory->make('HashRef', inputs => [\@pairs]);
    my $name_h   = $factory->make('Constant', value => '%h', const_type => 'string');
    my $var_h    = $factory->make('VarDecl', inputs => [$name_h, $hash_ref], scope => 'my');
    $var_h->set_control_in($start);

    # $h{k} — Subscript, style=hash, aggregate var -> emits $h{k}
    my $h_read   = $factory->make('Constant', value => '$h',  const_type => 'variable');
    my $key_k2   = $factory->make('Constant', value => 'k',   const_type => 'string');
    my $style_h  = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_hk   = $factory->make('Subscript', inputs => [$h_read, $key_k2, $style_h]);

    # Return: $h{k}
    my $ret = $factory->make_cfg('Return', inputs => [$sub_hk]);
    $ret->set_control_in($var_h);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $key_k, $val_1, $hash_ref, $name_h, $var_h, $h_read, $key_k2, $style_h, $sub_hk, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B1: class C { method m() { my @list = (); push @list, 1; return scalar @list; } }
#
# VarDecl empty @list, bare Call(push, @list, 1), Return(scalar(@list)).
# push is no-parens builtin. Control chain: Start <- var_list <- push_call <- ret
# ---------------------------------------------------------------------------
sub _build_B1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my @list = ()
    my $name_list = $factory->make('Constant', value => '@list', const_type => 'string');
    my @no_elems  = ();
    my $arr_ref   = $factory->make('ArrayRef', inputs => [\@no_elems]);
    my $var_list  = $factory->make('VarDecl', inputs => [$name_list, $arr_ref], scope => 'my');
    $var_list->set_control_in($start);

    # push @list, 1
    my $name_push  = $factory->make('Constant', value => 'push', const_type => 'string');
    my $list_var   = $factory->make('Constant', value => '@list', const_type => 'variable');
    my $one        = $factory->make('Constant', value => '1',     const_type => 'integer');
    my @push_args  = ($list_var, $one);
    my $call_push  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'push',
        inputs        => [$name_push, \@push_args],
    );
    $call_push->set_control_in($var_list);

    # scalar(@list)
    my $name_scalar  = $factory->make('Constant', value => 'scalar', const_type => 'string');
    my $list_read    = $factory->make('Constant', value => '@list',  const_type => 'variable');
    my @scalar_args  = ($list_read);
    my $call_scalar  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar @list
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($call_push);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_list, $arr_ref, $var_list, $name_push, $list_var, $one, $call_push,
               $name_scalar, $list_read, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B2: class C { method m() { print "hi"; return 1; } }
#
# Bare Call(print, "hi"), Return(1).
# print is no-parens builtin. Control chain: Start <- print_call <- ret
# ---------------------------------------------------------------------------
sub _build_B2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # print "hi"
    my $name_print = $factory->make('Constant', value => 'print', const_type => 'string');
    my $str_hi     = $factory->make('Constant', value => 'hi',    const_type => 'string');
    my @print_args = ($str_hi);
    my $call_print = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'print',
        inputs        => [$name_print, \@print_args],
    );
    $call_print->set_control_in($start);

    # Return: 1
    my $one = $factory->make('Constant', value => '1', const_type => 'integer');
    my $ret = $factory->make_cfg('Return', inputs => [$one]);
    $ret->set_control_in($call_print);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_print, $str_hi, $call_print, $one, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B3: class C { method m() { say "hi"; return 1; } }
#
# Bare Call(say, "hi"), Return(1).
# say is no-parens builtin. Control chain: Start <- say_call <- ret
# ---------------------------------------------------------------------------
sub _build_B3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # say "hi"
    my $name_say  = $factory->make('Constant', value => 'say', const_type => 'string');
    my $str_hi    = $factory->make('Constant', value => 'hi',  const_type => 'string');
    my @say_args  = ($str_hi);
    my $call_say  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'say',
        inputs        => [$name_say, \@say_args],
    );
    $call_say->set_control_in($start);

    # Return: 1
    my $one = $factory->make('Constant', value => '1', const_type => 'integer');
    my $ret = $factory->make_cfg('Return', inputs => [$one]);
    $ret->set_control_in($call_say);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_say, $str_hi, $call_say, $one, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B4: class C { method m() { die "boom"; } }
#
# Bare Unwind node carrying the die argument. Unwind is a CFG exit node;
# inputs[0] is an arrayref of die arguments. Control chain: Start <- unwind
# ---------------------------------------------------------------------------
sub _build_B4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # die "boom" — Unwind node, inputs[0] = arrayref of args
    my $str_boom   = $factory->make('Constant', value => 'boom', const_type => 'string');
    my @die_args   = ($str_boom);
    my $unwind     = $factory->make_cfg('Unwind', inputs => [\@die_args]);
    $unwind->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $str_boom, $unwind) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B5: class C { method m() { foo(1, 2); return 1; } }
#
# Bare Call(foo, 1, 2) as a side-effect statement, Return(1).
# foo is not defined: both oracle and generated code raise an undefined-sub
# exception; the Comparator sees matching exceptions and returns PASS.
# Control chain: Start <- call_foo <- ret
# ---------------------------------------------------------------------------
sub _build_B5 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # foo(1, 2)
    my $name_foo = $factory->make('Constant', value => 'foo', const_type => 'string');
    my $arg1     = $factory->make('Constant', value => '1',   const_type => 'integer');
    my $arg2     = $factory->make('Constant', value => '2',   const_type => 'integer');
    my @foo_args = ($arg1, $arg2);
    my $call_foo = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'foo',
        inputs        => [$name_foo, \@foo_args],
    );
    $call_foo->set_control_in($start);

    # Return: 1
    my $one = $factory->make('Constant', value => '1', const_type => 'integer');
    my $ret = $factory->make_cfg('Return', inputs => [$one]);
    $ret->set_control_in($call_foo);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_foo, $arg1, $arg2, $call_foo, $one, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B6: class C { method m() { $self->bar(); return 1; } }
#
# Bare method Call($self, bar, []) as side-effect, Return(1).
# bar is not defined on class C: both oracle and generated code raise a
# "Can't locate object method" exception; Comparator sees matching exceptions.
# Control chain: Start <- call_bar <- ret
# ---------------------------------------------------------------------------
sub _build_B6 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # $self->bar()
    # Method Call layout: inputs[0]=invocant, inputs[1]=Constant(method_name), inputs[2]=\@args
    my $self_var  = $factory->make('Constant', value => '$self', const_type => 'variable');
    my $name_bar  = $factory->make('Constant', value => 'bar',   const_type => 'string');
    my @bar_args  = ();
    my $call_bar  = $factory->make('Call',
        dispatch_kind => 'method',
        name          => 'bar',
        inputs        => [$self_var, $name_bar, \@bar_args],
    );
    $call_bar->set_control_in($start);

    # Return: 1
    my $one = $factory->make('Constant', value => '1', const_type => 'integer');
    my $ret = $factory->make_cfg('Return', inputs => [$one]);
    $ret->set_control_in($call_bar);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $self_var, $name_bar, $call_bar, $one, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B7: class C { method m() { my @list = (); unshift @list, 1; return scalar @list; } }
#
# VarDecl empty @list, bare Call(unshift, @list, 1), Return(scalar(@list)).
# unshift is no-parens builtin. Control chain: Start <- var_list <- unshift <- ret
# ---------------------------------------------------------------------------
sub _build_B7 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my @list = ()
    my $name_list = $factory->make('Constant', value => '@list', const_type => 'string');
    my @no_elems  = ();
    my $arr_ref   = $factory->make('ArrayRef', inputs => [\@no_elems]);
    my $var_list  = $factory->make('VarDecl', inputs => [$name_list, $arr_ref], scope => 'my');
    $var_list->set_control_in($start);

    # unshift @list, 1
    my $name_unsh  = $factory->make('Constant', value => 'unshift', const_type => 'string');
    my $list_var   = $factory->make('Constant', value => '@list',   const_type => 'variable');
    my $one        = $factory->make('Constant', value => '1',       const_type => 'integer');
    my @unsh_args  = ($list_var, $one);
    my $call_unsh  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'unshift',
        inputs        => [$name_unsh, \@unsh_args],
    );
    $call_unsh->set_control_in($var_list);

    # scalar(@list)
    my $name_scalar = $factory->make('Constant', value => 'scalar', const_type => 'string');
    my $list_read   = $factory->make('Constant', value => '@list',  const_type => 'variable');
    my @scalar_args = ($list_read);
    my $call_scalar = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'scalar',
        inputs        => [$name_scalar, \@scalar_args],
    );

    # Return: scalar @list
    my $ret = $factory->make_cfg('Return', inputs => [$call_scalar]);
    $ret->set_control_in($call_unsh);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_list, $arr_ref, $var_list, $name_unsh, $list_var, $one, $call_unsh,
               $name_scalar, $list_read, $call_scalar, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# B8: class C { method m() { warn "hi"; return 1; } }
#
# Bare Call(warn, "hi"), Return(1).
# warn uses no-parens list syntax (added to the emitter's no-parens list).
# warn output goes to STDERR; the harness captures it and both S=P match.
# Control chain: Start <- warn_call <- ret
# ---------------------------------------------------------------------------
sub _build_B8 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # warn "hi"
    my $name_warn  = $factory->make('Constant', value => 'warn', const_type => 'string');
    my $str_hi     = $factory->make('Constant', value => 'hi',   const_type => 'string');
    my @warn_args  = ($str_hi);
    my $call_warn  = $factory->make('Call',
        dispatch_kind => 'builtin',
        name          => 'warn',
        inputs        => [$name_warn, \@warn_args],
    );
    $call_warn->set_control_in($start);

    # Return: 1
    my $one = $factory->make('Constant', value => '1', const_type => 'integer');
    my $ret = $factory->make_cfg('Return', inputs => [$one]);
    $ret->set_control_in($call_warn);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_warn, $str_hi, $call_warn, $one, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# C1: class C { method m() { my $x = 1; $x = 2; return $x; } }
#
# VarDecl, bare Assign ($x = 2), Return.
# Same pattern as A4 but the reassigned value is 2, not the initial 1.
# Control chain: Start <- var_x <- assign <- ret
# ---------------------------------------------------------------------------
sub _build_C1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my $x = 1
    my $name_x  = $factory->make('Constant', value => '$x', const_type => 'string');
    my $const_1 = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $var_x   = $factory->make('VarDecl', inputs => [$name_x, $const_1], scope => 'my');
    $var_x->set_control_in($start);

    # Assign: $x = 2
    my $op_eq    = $factory->make('Constant', value => '=',  const_type => 'string');
    my $x_lhs    = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $const_2  = $factory->make('Constant', value => '2',  const_type => 'integer');
    my $assign   = $factory->make('Assign', inputs => [$op_eq, $x_lhs, $const_2]);
    $assign->set_control_in($var_x);

    # Return: $x
    my $x_read = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$x_read]);
    $ret->set_control_in($assign);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_x, $const_1, $var_x, $op_eq, $x_lhs, $const_2, $assign, $x_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# C2: class C { method m() { my $x = 1; $x += 2; return $x; } }
#
# VarDecl, CompoundAssign ($x += 2), Return.
# CompoundAssign layout: inputs[0]=Constant(op), inputs[1]=target, inputs[2]=value.
# The CompoundAssign node also carries op as a named :param.
# Control chain: Start <- var_x <- compound_assign <- ret
# ---------------------------------------------------------------------------
sub _build_C2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my $x = 1
    my $name_x  = $factory->make('Constant', value => '$x', const_type => 'string');
    my $const_1 = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $var_x   = $factory->make('VarDecl', inputs => [$name_x, $const_1], scope => 'my');
    $var_x->set_control_in($start);

    # CompoundAssign: $x += 2
    my $op_plus = $factory->make('Constant', value => '+=', const_type => 'string');
    my $x_lhs   = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $const_2 = $factory->make('Constant', value => '2',  const_type => 'integer');
    my $compound = $factory->make('CompoundAssign',
        op     => '+=',
        inputs => [$op_plus, $x_lhs, $const_2],
    );
    $compound->set_control_in($var_x);

    # Return: $x
    my $x_read = $factory->make('Constant', value => '$x', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$x_read]);
    $ret->set_control_in($compound);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_x, $const_1, $var_x, $op_plus, $x_lhs, $const_2, $compound, $x_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# C3: class C { method m() { my $s = "a"; $s .= "b"; return $s; } }
#
# VarDecl, CompoundAssign ($s .= "b"), Return.
# Control chain: Start <- var_s <- compound_assign <- ret
# ---------------------------------------------------------------------------
sub _build_C3 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my $s = "a"
    my $name_s  = $factory->make('Constant', value => '$s', const_type => 'string');
    my $str_a   = $factory->make('Constant', value => 'a',  const_type => 'string');
    my $var_s   = $factory->make('VarDecl', inputs => [$name_s, $str_a], scope => 'my');
    $var_s->set_control_in($start);

    # CompoundAssign: $s .= "b"
    my $op_dot  = $factory->make('Constant', value => '.=', const_type => 'string');
    my $s_lhs   = $factory->make('Constant', value => '$s', const_type => 'variable');
    my $str_b   = $factory->make('Constant', value => 'b',  const_type => 'string');
    my $compound = $factory->make('CompoundAssign',
        op     => '.=',
        inputs => [$op_dot, $s_lhs, $str_b],
    );
    $compound->set_control_in($var_s);

    # Return: $s
    my $s_read = $factory->make('Constant', value => '$s', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$s_read]);
    $ret->set_control_in($compound);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_s, $str_a, $var_s, $op_dot, $s_lhs, $str_b, $compound, $s_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# C4: class C { method m() { my @a = (1); $a[0] = 2; return $a[0]; } }
#
# VarDecl(@a), Assign(Subscript($a,0,array), 2), Return(Subscript($a,0,array)).
# The Subscript on the LHS is an aggregate var, so emits $a[0] (no arrow).
# Control chain: Start <- var_a <- assign <- ret
# ---------------------------------------------------------------------------
sub _build_C4 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my @a = (1)
    my $name_a  = $factory->make('Constant', value => '@a', const_type => 'string');
    my $one     = $factory->make('Constant', value => '1',  const_type => 'integer');
    my @elems   = ($one);
    my $arr_ref = $factory->make('ArrayRef', inputs => [\@elems]);
    my $var_a   = $factory->make('VarDecl', inputs => [$name_a, $arr_ref], scope => 'my');
    $var_a->set_control_in($start);

    # Subscript: $a[0] (LHS)
    my $a_lhs   = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $idx_0   = $factory->make('Constant', value => '0',  const_type => 'integer');
    my $style_a = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_lhs = $factory->make('Subscript', inputs => [$a_lhs, $idx_0, $style_a]);

    # Assign: $a[0] = 2
    my $op_eq  = $factory->make('Constant', value => '=', const_type => 'string');
    my $two    = $factory->make('Constant', value => '2', const_type => 'integer');
    my $assign = $factory->make('Assign', inputs => [$op_eq, $sub_lhs, $two]);
    $assign->set_control_in($var_a);

    # Return: $a[0]
    my $a_read  = $factory->make('Constant', value => '$a', const_type => 'variable');
    my $idx_0b  = $factory->make('Constant', value => '0',  const_type => 'integer');
    my $style_b = $factory->make('Constant', value => 'array', const_type => 'string');
    my $sub_ret = $factory->make('Subscript', inputs => [$a_read, $idx_0b, $style_b]);
    my $ret     = $factory->make_cfg('Return', inputs => [$sub_ret]);
    $ret->set_control_in($assign);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_a, $one, $arr_ref, $var_a, $a_lhs, $idx_0, $style_a, $sub_lhs,
               $op_eq, $two, $assign, $a_read, $idx_0b, $style_b, $sub_ret, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# C5: class C { method m() { my %h = (); $h{k} = 1; return $h{k}; } }
#
# VarDecl(%h) with empty HashRef, Assign(Subscript($h,k,hash), 1), Return(Subscript).
# Control chain: Start <- var_h <- assign <- ret
# ---------------------------------------------------------------------------
sub _build_C5 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my %h = ()
    my $name_h   = $factory->make('Constant', value => '%h', const_type => 'string');
    my @no_pairs = ();
    my $hash_ref = $factory->make('HashRef', inputs => [\@no_pairs]);
    my $var_h    = $factory->make('VarDecl', inputs => [$name_h, $hash_ref], scope => 'my');
    $var_h->set_control_in($start);

    # Subscript: $h{k} (LHS)
    my $h_lhs    = $factory->make('Constant', value => '$h',   const_type => 'variable');
    my $key_k    = $factory->make('Constant', value => 'k',    const_type => 'string');
    my $style_h  = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_lhs  = $factory->make('Subscript', inputs => [$h_lhs, $key_k, $style_h]);

    # Assign: $h{k} = 1
    my $op_eq   = $factory->make('Constant', value => '=', const_type => 'string');
    my $one     = $factory->make('Constant', value => '1', const_type => 'integer');
    my $assign  = $factory->make('Assign', inputs => [$op_eq, $sub_lhs, $one]);
    $assign->set_control_in($var_h);

    # Return: $h{k}
    my $h_read   = $factory->make('Constant', value => '$h',   const_type => 'variable');
    my $key_k2   = $factory->make('Constant', value => 'k',    const_type => 'string');
    my $style_h2 = $factory->make('Constant', value => 'hash', const_type => 'string');
    my $sub_ret  = $factory->make('Subscript', inputs => [$h_read, $key_k2, $style_h2]);
    my $ret      = $factory->make_cfg('Return', inputs => [$sub_ret]);
    $ret->set_control_in($assign);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_h, $hash_ref, $var_h, $h_lhs, $key_k, $style_h, $sub_lhs,
               $op_eq, $one, $assign, $h_read, $key_k2, $style_h2, $sub_ret, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# K1: class C { method m() { my $i = 0; ++$i; return $i; } }
#
# Pre-increment: ++$i. The IR represents this as CompoundAssign($i += 1)
# since there is no dedicated PreIncrement node and the behavior as a bare
# statement is identical. The return value is always $i after increment.
# Control chain: Start <- var_i <- compound_assign <- ret
# ---------------------------------------------------------------------------
sub _build_K1 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my $i = 0
    my $name_i  = $factory->make('Constant', value => '$i', const_type => 'string');
    my $zero    = $factory->make('Constant', value => '0',  const_type => 'integer');
    my $var_i   = $factory->make('VarDecl', inputs => [$name_i, $zero], scope => 'my');
    $var_i->set_control_in($start);

    # ++$i as CompoundAssign: $i += 1
    my $op_plus = $factory->make('Constant', value => '+=', const_type => 'string');
    my $i_lhs   = $factory->make('Constant', value => '$i', const_type => 'variable');
    my $one     = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $incr    = $factory->make('CompoundAssign',
        op     => '+=',
        inputs => [$op_plus, $i_lhs, $one],
    );
    $incr->set_control_in($var_i);

    # Return: $i
    my $i_read = $factory->make('Constant', value => '$i', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$i_read]);
    $ret->set_control_in($incr);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_i, $zero, $var_i, $op_plus, $i_lhs, $one, $incr, $i_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# ---------------------------------------------------------------------------
# K2: class C { method m() { my $i = 0; $i++; return $i; } }
#
# Post-increment: $i++. As a bare statement the effect is identical to
# ++$i (both increment $i by 1). Represented as CompoundAssign($i += 1).
# Control chain: Start <- var_i <- compound_assign <- ret
# ---------------------------------------------------------------------------
sub _build_K2 {
    my $factory = Chalk::IR::NodeFactory->new;

    my $start = $factory->make_cfg('Start', inputs => []);

    # VarDecl: my $i = 0
    my $name_i  = $factory->make('Constant', value => '$i', const_type => 'string');
    my $zero    = $factory->make('Constant', value => '0',  const_type => 'integer');
    my $var_i   = $factory->make('VarDecl', inputs => [$name_i, $zero], scope => 'my');
    $var_i->set_control_in($start);

    # $i++ as CompoundAssign: $i += 1
    my $op_plus = $factory->make('Constant', value => '+=', const_type => 'string');
    my $i_lhs   = $factory->make('Constant', value => '$i', const_type => 'variable');
    my $one     = $factory->make('Constant', value => '1',  const_type => 'integer');
    my $incr    = $factory->make('CompoundAssign',
        op     => '+=',
        inputs => [$op_plus, $i_lhs, $one],
    );
    $incr->set_control_in($var_i);

    # Return: $i
    my $i_read = $factory->make('Constant', value => '$i', const_type => 'variable');
    my $ret    = $factory->make_cfg('Return', inputs => [$i_read]);
    $ret->set_control_in($incr);

    my $graph = Chalk::IR::Graph->new;
    for my $n ($start, $name_i, $zero, $var_i, $op_plus, $i_lhs, $one, $incr, $i_read, $ret) {
        $graph->merge($n);
    }

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('C');
    $cls->declare_method('m', params => [], graph => $graph);
    return $mop;
}

# Populate the dispatch table after all builders are defined.
%BUILDERS = (
    A1 => \&_build_A1,
    A2 => \&_build_A2,
    A3 => \&_build_A3,
    A4 => \&_build_A4,
    A5 => \&_build_A5,
    B1 => \&_build_B1,
    B2 => \&_build_B2,
    B3 => \&_build_B3,
    B4 => \&_build_B4,
    B5 => \&_build_B5,
    B6 => \&_build_B6,
    B7 => \&_build_B7,
    B8 => \&_build_B8,
    C1 => \&_build_C1,
    C2 => \&_build_C2,
    C3 => \&_build_C3,
    C4 => \&_build_C4,
    C5 => \&_build_C5,
    D6 => \&_build_D6,
    E1 => \&_build_E1,
    H1 => \&_build_H1,
    H2 => \&_build_H2,
    H3 => \&_build_H3,
    H4 => \&_build_H4,
    I3 => \&_build_I3,
    F1 => \&_build_F1,
    F2 => \&_build_F2,
    F3 => \&_build_F3,
    G1 => \&_build_G1,
    G2 => \&_build_G2,
    G3 => \&_build_G3,
    G4 => \&_build_G4,
    J1 => \&_build_J1,
    J2 => \&_build_J2,
    J3 => \&_build_J3,
    K1 => \&_build_K1,
    K2 => \&_build_K2,
    L1 => \&_build_L1,
    L2 => \&_build_L2,
    L3 => \&_build_L3,
    L4 => \&_build_L4,
    M3  => \&_build_M3,
    M4  => \&_build_M4,
    M8  => \&_build_M8,
    M9  => \&_build_M9,
    M10 => \&_build_M10,
    M11 => \&_build_M11,
    M12 => \&_build_M12,
    M13 => \&_build_M13,
    M14 => \&_build_M14,
    M15 => \&_build_M15,
    M22 => \&_build_M22,
    M23 => \&_build_M23,
    M24 => \&_build_M24,
);

1;
