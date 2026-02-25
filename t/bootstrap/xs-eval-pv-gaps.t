# ABOUTME: Tests that XS emitter closes eval_pv gaps and handles compound operators.
# ABOUTME: Covers AnonSubExpr, BacktickExpr, sprintf, join, split, HashRefExpr, ArrayRefExpr, //=.
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

# === 2a. //= compound assign — defined-or-assign ===

{
    my $assign = ctor('CompoundAssign',
        op     => const_node('//='),
        target => const_node('$cache'),
        value  => const_node('"default"'),
    );

    my $code = $xs->_emit_xs_expr($assign, {});
    unlike($code, qr{not supported}, '//=: not "not supported"');
    like($code, qr/SvOK/, '//=: checks definedness with SvOK');
}

# === 2b. push as expression — av_push wrapped so it returns a value ===

{
    my $push_call = ctor('BuiltinCall',
        name => const_node('push'),
        args => [const_node('@lines'), const_node('"hello"')],
    );

    # When emitted as an expression, push must return a value (not void av_push)
    my $code = $xs->_emit_xs_expr($push_call, {});
    like($code, qr/av_push/, 'push expr: uses av_push');
    # Must be wrapped in statement expression so it has a value
    like($code, qr/\(\{.*av_push.*\}\)/, 'push expr: wrapped in statement expression');
    unlike($code, qr/^\s*av_push\(/, 'push expr: not bare av_push (void)');

    # When emitted as a statement, push should work as a simple void call
    my $stmt = $xs->_emit_xs_stmt($push_call, {});
    like($stmt, qr/av_push/, 'push stmt: uses av_push');
}

# === sv_2mortal stripping in return statements ===
{
    # Build a ReturnStmt that returns a numeric expression
    # The expression emitter wraps in sv_2mortal, but RETVAL shouldn't double-mortal
    my $num = const_node('42', 'integer');
    my $return_node = ctor('ReturnStmt', inputs => [$num]);

    my $return_code = $xs->_emit_xs_return_stmt($return_node, {});
    like($return_code, qr/RETVAL/, 'return stmt: assigns to RETVAL');
    unlike($return_code, qr/sv_2mortal/, 'return stmt: no sv_2mortal (OUTPUT section handles it)');
}

# === _needs_eval_fallback catches /* unknown node */ ===
{
    ok($xs->_needs_eval_fallback('/* unknown node */'), 'needs_eval_fallback: catches unknown node');
    ok($xs->_needs_eval_fallback('NULL /* unsupported */'), 'needs_eval_fallback: catches unsupported');
    ok(!$xs->_needs_eval_fallback('sv_setiv(fields[0], 42);'), 'needs_eval_fallback: clean code is false');
}

# === BOOT block: defop-based field initialization (no shadow constructor) ===
{
    # Build a ClassDecl with:
    # - field $name :param :reader = "unnamed"
    # - field $count :param :reader (required, no default)
    # - field $tags :reader = [] (no :param)
    my $param_attr = ctor('_Attribute', name => const_node('param'));
    my $reader_attr = ctor('_Attribute', name => const_node('reader'));

    my $name_field = ctor('FieldDecl', inputs => [
        const_node('$name', 'variable'),
        [$param_attr, $reader_attr],
        const_node('unnamed'),
    ]);
    my $count_field = ctor('FieldDecl', inputs => [
        const_node('$count', 'variable'),
        [$param_attr, $reader_attr],
        undef,  # no default — required
    ]);
    my $tags_field = ctor('FieldDecl', inputs => [
        const_node('$tags', 'variable'),
        [$reader_attr],
        ctor('ArrayRefExpr', inputs => []),
    ]);

    my $class_name = const_node('Test::DefopBoot');
    my $class_decl = ctor('ClassDecl', inputs => [$class_name, undef, [
        $name_field, $count_field, $tags_field,
    ]]);
    my $field_map = { 'name' => 0, 'count' => 1, 'tags' => 2 };

    my $boot_lines = $xs->_emit_xs_boot_block($class_decl, $field_map);
    my $boot_code = join("\n", $boot_lines->@*);

    # BOOT block structure: uses ENTER/LEAVE, no explicit seal_stash
    like($boot_code, qr/ENTER/, 'defop boot: has outer ENTER');
    like($boot_code, qr/class_setup_stash/, 'defop boot: calls setup_stash');
    unlike($boot_code, qr/class_seal_stash/, 'defop boot: no explicit seal_stash');
    like($boot_code, qr/LEAVE/, 'defop boot: has outer LEAVE (triggers seal via destructor)');

    # Per-field ENTER/LEAVE with prepare_initfield_parse
    like($boot_code, qr/class_prepare_initfield_parse/, 'defop boot: calls prepare_initfield_parse');

    # Field attributes: :param and :reader applied via class_apply_field_attributes
    like($boot_code, qr/class_apply_field_attributes/, 'defop boot: applies field attributes');
    like($boot_code, qr/"param"/, 'defop boot: has param attribute string');
    like($boot_code, qr/"reader"/, 'defop boot: has reader attribute string');

    # Field defaults via set_field_defop
    like($boot_code, qr/class_set_field_defop/, 'defop boot: sets field defaults via defop');
    like($boot_code, qr/op_next\s*=\s*NULL/, 'defop boot: clears op_next on defop');

    # No shadow constructor artifacts
    unlike($boot_code, qr/original_new/, 'defop boot: no original_new capture');
    unlike($boot_code, qr/gv_fetchmethod.*"new"/, 'defop boot: no gv_fetchmethod for new');

    # Field names present
    like($boot_code, qr/\$name/, 'defop boot: registers $name field');
    like($boot_code, qr/\$count/, 'defop boot: registers $count field');
    like($boot_code, qr/\$tags/, 'defop boot: registers $tags field');

    # Default values: "unnamed" string and [] array
    like($boot_code, qr/unnamed/, 'defop boot: has "unnamed" default for $name');
    like($boot_code, qr/newANONLIST/, 'defop boot: has [] default for $tags via newANONLIST');
}

done_testing();
