# ABOUTME: Tests that XS emitter closes eval_pv gaps for AnonSubExpr, BacktickExpr,
# ABOUTME: sprintf, join, split, non-empty HashRefExpr, and non-empty ArrayRefExpr.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::XS;

# Build a minimal IR to test emitter methods.
# We construct IR nodes directly and call _emit_xs_expr on them.

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $nf = Chalk::Bootstrap::IR::NodeFactory->instance();

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::EvalPvGaps');

# Helper: build a Constant node
my sub const_node($val, $type = 'string') {
    return $nf->make('Constant', value => $val, const_type => $type);
}

# Helper: build a Constructor node
my sub ctor($class, %args) {
    return $nf->make('Constructor', class => $class, %args);
}

# === 1a. AnonSubExpr — should emit the actual sub source, not empty sub { } ===

{
    my $param1 = const_node('$x');
    my $param2 = const_node('$y');
    my $return_val = ctor('BinaryExpr',
        op    => const_node('+'),
        left  => const_node('$x'),
        right => const_node('$y'),
    );
    my $return_stmt = ctor('ReturnStmt', value => $return_val);
    my $anon = ctor('AnonSubExpr',
        params => [$param1, $param2],
        body   => [$return_stmt],
    );

    my $code = $xs->_emit_xs_expr($anon, {});
    like($code, qr/eval_pv/, 'AnonSubExpr: uses eval_pv');
    unlike($code, qr/sub\s*\{\s*\}/, 'AnonSubExpr: not an empty sub placeholder');
    like($code, qr/\$x.*\$y/s, 'AnonSubExpr: contains param names');
    like($code, qr/return/, 'AnonSubExpr: contains body (return statement)');
}

# === 1b. BacktickExpr — should emit actual command, not placeholder ===

{
    my $cmd = const_node('ls -la');
    my $bt = ctor('BacktickExpr', command => $cmd);

    my $code = $xs->_emit_xs_expr($bt, {});
    like($code, qr/eval_pv/, 'BacktickExpr: uses eval_pv');
    like($code, qr/ls -la/, 'BacktickExpr: contains actual command');
    unlike($code, qr/TODO/, 'BacktickExpr: no TODO comment');
}

# === 1c. sprintf — native C via sv_setpvf ===

{
    my $fmt = const_node('"%s=%s"');
    my $arg1 = const_node('$key');
    my $arg2 = const_node('$val');
    my $call = ctor('BuiltinCall',
        name => const_node('sprintf'),
        args => [$fmt, $arg1, $arg2],
    );

    my $code = $xs->_emit_xs_expr($call, {});
    like($code, qr/sv_setpvf|Perl_sv_setpvf/, 'sprintf: uses native sv_setpvf');
    unlike($code, qr/eval_pv\("sprintf\(\)"/, 'sprintf: not a placeholder eval_pv');
}

# === 1d. join — native C via sv_catsv loop ===

{
    my $sep = const_node('", "');
    my $arr = const_node('@items');
    my $call = ctor('BuiltinCall',
        name => const_node('join'),
        args => [$sep, $arr],
    );

    my $code = $xs->_emit_xs_expr($call, { 'items' => 'AV' });
    like($code, qr/sv_catsv/, 'join: uses sv_catsv');
    unlike($code, qr/eval_pv\("join\(\)"/, 'join: not a placeholder eval_pv');
}

# === 1e. split — eval_pv with actual args ===

{
    my $pat = const_node('/\\s+/');
    my $str = const_node('$_');
    my $call = ctor('BuiltinCall',
        name => const_node('split'),
        args => [$pat, $str],
    );

    my $code = $xs->_emit_xs_expr($call, {});
    like($code, qr/eval_pv/, 'split: uses eval_pv');
    like($code, qr/split/, 'split: contains split call');
    like($code, qr/\\s\+/, 'split: contains actual pattern');
    unlike($code, qr/eval_pv\("split\(\)"/, 'split: not a placeholder eval_pv');
}

# === 1f. Non-empty HashRefExpr — hv_store loop ===

{
    my $key1 = const_node("'name'");
    my $val1 = const_node('$name');
    my $key2 = const_node("'age'");
    my $val2 = const_node('$age');
    my $hash = ctor('HashRefExpr',
        pairs => [$key1, $val1, $key2, $val2],
    );

    my $code = $xs->_emit_xs_expr($hash, {});
    like($code, qr/hv_store/, 'HashRefExpr: non-empty uses hv_store');
    unlike($code, qr/elements dropped/, 'HashRefExpr: no "elements dropped" comment');
}

# === 1f (empty). Empty HashRefExpr — still works ===

{
    my $hash = ctor('HashRefExpr', pairs => []);
    my $code = $xs->_emit_xs_expr($hash, {});
    like($code, qr/newRV_noinc.*newHV/, 'HashRefExpr: empty still uses newHV');
}

# === 1g. Non-empty ArrayRefExpr — av_push loop ===

{
    my $elem1 = const_node('1');
    my $elem2 = const_node('2');
    my $elem3 = const_node('3');
    my $arr = ctor('ArrayRefExpr',
        elements => [$elem1, $elem2, $elem3],
    );

    my $code = $xs->_emit_xs_expr($arr, {});
    like($code, qr/av_push/, 'ArrayRefExpr: non-empty uses av_push');
    unlike($code, qr/elements dropped/, 'ArrayRefExpr: no "elements dropped" comment');
}

# === 1g (empty). Empty ArrayRefExpr — still works ===

{
    my $arr = ctor('ArrayRefExpr', elements => []);
    my $code = $xs->_emit_xs_expr($arr, {});
    like($code, qr/newRV_noinc.*newAV/, 'ArrayRefExpr: empty still uses newAV');
}

done_testing();
