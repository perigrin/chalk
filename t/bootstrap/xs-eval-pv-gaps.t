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

# === Native C builtins: length, shift, keys, values, delete ===

# Helper: build a variable reference node
my sub var_node($name) {
    return const_node($name, 'variable');
}

# length($str) — should emit SvCUR, not eval_pv("length()")
{
    my $builtin = ctor('BuiltinCall', inputs => [
        const_node('length'),
        [var_node('$input')],
    ]);
    my $code = $xs->_emit_xs_expr($builtin, { input => true });
    like($code, qr/SvCUR/, 'length: emits SvCUR for native string length');
    unlike($code, qr/eval_pv\("length\(\)"/, 'length: no broken eval_pv stub');
}

# shift(@arr) — should emit av_shift, not eval_pv("shift()")
{
    my $builtin = ctor('BuiltinCall', inputs => [
        const_node('shift'),
        [var_node('@agenda')],
    ]);
    my $code = $xs->_emit_xs_expr($builtin, { agenda => true });
    like($code, qr/av_shift/, 'shift: emits av_shift for native array shift');
    unlike($code, qr/eval_pv\("shift\(\)"/, 'shift: no broken eval_pv stub');
}

# keys(%hash) — should emit HvUSEDKEYS, not eval_pv("keys()")
{
    my $deref = ctor('PostfixDerefExpr', inputs => [
        var_node('$hash'),
        const_node('%'),
    ]);
    my $builtin = ctor('BuiltinCall', inputs => [
        const_node('keys'),
        [$deref],
    ]);
    my $code = $xs->_emit_xs_expr($builtin, { hash => true });
    like($code, qr/HvUSEDKEYS/, 'keys: emits HvUSEDKEYS for native hash key count');
    unlike($code, qr/eval_pv\("keys\(\)"/, 'keys: no broken eval_pv stub');
}

# values(%hash) — should emit hv_iternext loop, not eval_pv("values()")
{
    my $deref = ctor('PostfixDerefExpr', inputs => [
        var_node('$hash'),
        const_node('%'),
    ]);
    my $builtin = ctor('BuiltinCall', inputs => [
        const_node('values'),
        [$deref],
    ]);
    my $code = $xs->_emit_xs_expr($builtin, { hash => true });
    like($code, qr/hv_iternext/, 'values: emits hv_iternext loop');
    unlike($code, qr/eval_pv\("values\(\)"/, 'values: no broken eval_pv stub');
}

# delete($hash{$key}) — should emit hv_delete, not eval_pv("delete()")
{
    my $subscript = ctor('SubscriptExpr', inputs => [
        var_node('$cache'),
        var_node('$pos'),
    ]);
    my $builtin = ctor('BuiltinCall', inputs => [
        const_node('delete'),
        [$subscript],
    ]);
    my $code = $xs->_emit_xs_expr($builtin, { cache => true, pos => true });
    like($code, qr/hv_delete/, 'delete: emits hv_delete for hash entry removal');
    unlike($code, qr/eval_pv\("delete\(\)"/, 'delete: no broken eval_pv stub');
}

# pack('NN', ...) — native C via htonl
{
    my $builtin = ctor('BuiltinCall',
        name => const_node('pack'),
        args => [const_node("'NN'"), var_node('$core_id'), var_node('$origin')],
    );
    my $code = $xs->_emit_xs_expr($builtin, { core_id => true, origin => true });
    like($code, qr/htonl/, 'pack NN: uses htonl for big-endian');
    unlike($code, qr/eval_pv/, 'pack NN: no eval_pv');
}

# exists($hash{$key}) — native C via hv_exists_ent
{
    my $subscript = ctor('SubscriptExpr',
        target => var_node('$chart'),
        index  => var_node('$pos'),
        style  => const_node('{'),
    );
    my $builtin = ctor('BuiltinCall',
        name => const_node('exists'),
        args => [$subscript],
    );
    my $code = $xs->_emit_xs_expr($builtin, { chart => true, pos => true });
    like($code, qr/hv_exists_ent/, 'exists: uses hv_exists_ent');
    unlike($code, qr/eval_pv/, 'exists: no eval_pv');
}

# substr($str, $off, $len) — native C via SvPV
{
    my $builtin = ctor('BuiltinCall',
        name => const_node('substr'),
        args => [var_node('$input'), var_node('$pos'), var_node('$len')],
    );
    my $code = $xs->_emit_xs_expr($builtin, { input => true, pos => true, len => true });
    like($code, qr/SvPV/, 'substr: uses SvPV for native C');
    unlike($code, qr/eval_pv/, 'substr: no eval_pv');
}

# Generic fallback: truly unhandled builtins should preserve arguments
{
    my $builtin = ctor('BuiltinCall',
        name => const_node('unpack'),
        args => [const_node("'NN'"), var_node('$data')],
    );
    my $code = $xs->_emit_xs_expr($builtin, { data => true });
    like($code, qr/eval_pv/, 'unpack fallback: uses eval_pv');
    like($code, qr/unpack\(/, 'unpack fallback: preserves function name');
    unlike($code, qr/eval_pv\("unpack\(\)"/, 'unpack fallback: not an empty stub');
}

# === Method call invocant: no SvRV dereference ===
# Method call on an object should push the object reference directly,
# not SvRV(obj). call_method needs the blessed reference on the stack.
{
    # $obj->method_name() where $obj is a local variable
    my $invocant = var_node('$start_rule');
    my $method_call = ctor('MethodCallExpr',
        invocant    => $invocant,
        method_name => const_node('expressions'),
        args        => [],
    );

    my $code = $xs->_emit_xs_expr($method_call, { start_rule => true });
    like($code, qr/call_method\("expressions"/, 'method call: calls expressions');
    like($code, qr/XPUSHs\(start_rule_sv\)/, 'method call: pushes object directly, not SvRV');
    unlike($code, qr/XPUSHs\(SvRV\(start_rule_sv\)\)/, 'method call: no SvRV on invocant');
}

# === Method call on PostfixDerefExpr invocant ===
# $obj->method() — IR has PostfixDerefExpr('$') wrapping invocant
# because Perl's -> arrow implies scalar dereference. Should unwrap
# the deref for method call purposes since call_method needs blessed ref.
{
    my $inner = var_node('$rule');
    my $deref = ctor('PostfixDerefExpr',
        target => $inner,
        sigil  => const_node('$'),
    );
    my $method_call = ctor('MethodCallExpr',
        invocant    => $deref,
        method_name => const_node('name'),
        args        => [],
    );

    my $code = $xs->_emit_xs_expr($method_call, { rule => true });
    like($code, qr/call_method\("name"/, 'deref method call: calls name');
    unlike($code, qr/XPUSHs\(SvRV\(/, 'deref method call: no SvRV wrapping invocant');
}

# === map { {} } (0 .. $n) — chart initialization ===
# The map builtin with a block should not produce eval_pv("map(0 .. $n)")
# because $n is a C variable not a Perl variable.
{
    my $range = ctor('BinaryExpr',
        op    => const_node('..'),
        left  => const_node('0', 'integer'),
        right => var_node('$n'),
    );
    my $block = ctor('AnonSubExpr',
        params => [],
        body   => [ctor('HashRefExpr', pairs => [])],
    );
    my $map_call = ctor('BuiltinCall',
        name => const_node('map'),
        args => [$block, $range],
    );
    my $code = $xs->_emit_xs_expr($map_call, { n => true });
    # Should not reference $n as a Perl variable in eval_pv
    unlike($code, qr/eval_pv\("map\(/, 'map init: not a broken eval_pv with C vars');
}

# === Hash field reset: %hash = () emits empty hashref, not undef ===
# When a hash field is reset like %waiting_for = (), the XS emitter must
# produce newRV_noinc((SV*)newHV()) not &PL_sv_undef. Using undef causes
# segfaults when code later dereferences the field as a hash.
{
    # VarDecl for %waiting_for with no initializer (IR for %hash = ())
    my $var_decl = ctor('VarDecl',
        variable    => const_node('%waiting_for'),
        initializer => undef,
    );
    # Simulate field_map context by calling _emit_xs_var_decl with a field map
    # that maps waiting_for to field index 5
    my $code = $xs->_emit_xs_var_decl($var_decl, { waiting_for => true });
    # For % variables, default should be empty hashref, not undef
    unlike($code, qr/PL_sv_undef/, 'hash field reset: not undef');
    like($code, qr/newHV/, 'hash field reset: creates empty hash');
}

# === Array field reset: @arr = () emits empty arrayref, not undef ===
{
    my $var_decl = ctor('VarDecl',
        variable    => const_node('@_gc_min_origin_at'),
        initializer => undef,
    );
    my $code = $xs->_emit_xs_var_decl($var_decl, { _gc_min_origin_at => true });
    unlike($code, qr/PL_sv_undef/, 'array field reset: not undef');
    like($code, qr/newAV/, 'array field reset: creates empty array');
}

# === Local hash variable: my %hash emits empty hashref ===
{
    my $var_decl = ctor('VarDecl',
        variable    => const_node('%processed'),
        initializer => undef,
    );
    my $code = $xs->_emit_xs_var_decl($var_decl, {});
    unlike($code, qr/PL_sv_undef/, 'local hash var: not undef');
    like($code, qr/newHV/, 'local hash var: creates empty hash');
}

# === Local array variable: my @agenda emits empty arrayref ===
{
    my $var_decl = ctor('VarDecl',
        variable    => const_node('@agenda'),
        initializer => undef,
    );
    my $code = $xs->_emit_xs_var_decl($var_decl, {});
    unlike($code, qr/PL_sv_undef/, 'local array var: not undef');
    like($code, qr/newAV/, 'local array var: creates empty array');
}

# === Full Earley.pm compilation: check _run_parse patterns ===
# These tests generate the full XS for Earley.pm and verify specific
# patterns in the _run_parse method are correct.
{
    use lib 't/bootstrap/lib';
    require TestXSHelpers;
    TestXSHelpers->import(qw(setup_xs_grammar parse_file_ir));

    my $gen = setup_xs_grammar('Chalk::Grammar::Perl::Remaining');
    my ($ir, $sa, $ctx) = parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm');
    my $xs_gen = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::RunParse');
    my $dist = $xs_gen->generate_distribution_with_cfg($ir, $sa, $ctx);
    my $xs_code = $dist->{'lib/Test/RunParse.xs'};
    ok(defined $xs_code, 'generated XS code for Earley.pm');

    # Extract _run_parse method
    my ($run_parse) = $xs_code =~ /(_run_parse\(self.*?\nSV \*\n|\z)/s;
    # More flexible: grab from _run_parse to next XSUB header
    ($run_parse) = $xs_code =~ /(_run_parse.*?)(?=^[A-Z]\w* \*$|^void$|^\z)/ms;
    ok(defined $run_parse && length($run_parse) > 100, '_run_parse method extracted');

    # While-shift: while (my $entry = shift @agenda) must capture shifted value
    # Bad:  while (SvTRUE(av_shift(...)))
    # Good: while ((entry_sv = av_shift(...)) != &PL_sv_undef)
    unlike($run_parse, qr/while \(SvTRUE\(av_shift/,
        'while-shift: not SvTRUE(av_shift) — must capture shifted value');
    like($run_parse, qr/entry_sv\s*=\s*av_shift/,
        'while-shift: assigns shifted value to entry_sv');

    # Hash spread: { %$item, value => completed_value } must not use get_sv
    # Bad:  get_sv("Test::RunParse::$item", GV_ADD)
    # Good: should copy hash entries from item_sv and add value key
    unlike($run_parse, qr/get_sv\("Test::RunParse::\\\$item"/,
        'hash spread: no broken get_sv for hash spread');

    # Entry variable: while (my $entry = shift) should use entry_sv from shift
    # Bad:  get_sv("Test::RunParse::entry", GV_ADD)
    unlike($run_parse, qr/get_sv\("Test::RunParse::entry"/,
        'while-shift var: no get_sv for entry variable');

    # exists/delete with subscript chains should not use eval_pv
    # _chart_has uses: exists $chart->[$pos]{$core_id}[$origin]
    # The subscript chain must be inside the exists, not wrapping it
    unlike($xs_code, qr/eval_pv\("exists\(\$/,
        'exists: no eval_pv("exists($var)") — subscript chain should be inside');
    unlike($xs_code, qr/eval_pv\("delete\(\$/,
        'delete: no eval_pv("delete($var)") — subscript chain should be inside');

    # No get_sv calls should remain in the entire XS code for local variables
    # Variables from list destructuring must resolve to C locals, not Perl globals
    my @get_sv_calls;
    while ($xs_code =~ /get_sv\("Test::RunParse::([\w\$]+)"/g) {
        push @get_sv_calls, $1;
    }
    is(scalar @get_sv_calls, 0,
        'no get_sv for local variables (all resolve to C locals)')
        or diag("Remaining get_sv calls: " . join(', ', @get_sv_calls));

    # === Remaining eval_pv calls should use native C ===

    # Terminal::match should use call_pv, not eval_pv with variable references
    unlike($xs_code, qr/eval_pv\("Chalk::Bootstrap::Terminal::match\(/,
        'Terminal::match: no eval_pv with C-local variable references');

    # Anonymous sub callback: eval_pv is OK for creating closures, but
    # variables inside must reference package globals (::_anon_*), not C locals.
    # Check that the sub body uses $::_anon_ prefix for captured variables.
    if ($xs_code =~ /eval_pv\("sub \(([^)]*)\).*?\\n(.*?)\\n"\s*,\s*TRUE\)/) {
        my $body = $2;
        # Body should use $::_anon_ prefixed variables, not bare C locals
        unlike($body, qr/\$(?!::_anon_|rule_name)\w+/,
            'anon sub: captured variables use package globals, not C locals');
    }
    # Verify bindings are set before eval_pv
    like($xs_code, qr/sv_setsv\(get_sv\("::_anon_/,
        'anon sub: C-local variables bound to package globals before eval_pv');
}

done_testing();
