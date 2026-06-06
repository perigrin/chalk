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
    E1 => \&_build_E1,
    F1 => \&_build_F1,
    F2 => \&_build_F2,
    F3 => \&_build_F3,
    G1 => \&_build_G1,
    G2 => \&_build_G2,
    G3 => \&_build_G3,
    G4 => \&_build_G4,
    K1 => \&_build_K1,
    K2 => \&_build_K2,
);

1;
