# ABOUTME: Tests for Coerce(Boolean->Str) LLVM lowering — bool string-face globals (G2 reopen-1).
# ABOUTME: Verifies lli compiles/runs, output matches perl oracle, and .ll is libperl-free.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Coerce;
use Chalk::IR::Node::Return;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: build a graph where Not(Int) -> Coerce(Boolean->Str) -> Return(:Str).
# Not(nonzero) = false -> Coerce -> "" -> oracle Str:
# Not(0)       = true  -> Coerce -> "1" -> oracle Str:1
#
# We use an integer constant as input to Not, so Boolean comes from a real
# truthiness operation (not a synthetic Boolean constant).
#
#   Constant(val :Int) -> Coerce(Int->Boolean) :Boolean -> Not :Boolean
#                         -> Coerce(Boolean->Str) :Str -> Return

sub make_not_bool_str_graph {
    my ($int_val) = @_;   # 0 = falsy (Not -> true -> "1"), nonzero = truthy (Not -> false -> "")
    my $f = Chalk::IR::NodeFactory->new;

    my $cval = $f->make('Constant', value => $int_val, const_type => 'integer');
    $cval->set_stamp('Int');

    # Coerce Int->Boolean (truthiness)
    my $coerce_ib = $f->make('Coerce',
        from_repr => 'Int',
        to_repr   => 'Boolean',
        inputs    => [$cval],
    );
    $coerce_ib->set_stamp('Boolean');

    # Not: logical negation
    my $not_node = $f->make('Not', inputs => [$coerce_ib]);
    $not_node->set_stamp('Boolean');

    # Coerce Boolean->Str: string-face "" or "1"
    my $coerce_bs = $f->make('Coerce',
        from_repr => 'Boolean',
        to_repr   => 'Str',
        inputs    => [$not_node],
    );
    $coerce_bs->set_stamp('Str');

    my $ret = $f->make_cfg('Return', inputs => [$coerce_bs]);
    return ($ret, $coerce_bs);
}

# Program form of the same graph: print the Str-face value bracketed by literal
# sentinels, then return Undef. A program's observable contract is stdout plus
# exit status — there is no type-tag channel. The brackets are load-bearing:
# the false face IS the empty string, so "[]" distinguishes "correctly printed
# empty" from "printed nothing at all".
# Program form of the same graph: print the Str-face value bracketed by literal
# sentinels, then return Undef. A program's observable contract is stdout plus
# exit status — there is no type-tag channel. The brackets are load-bearing:
# the false face IS the empty string, so "[]" distinguishes "correctly printed
# empty" from "printed nothing at all".
sub make_not_bool_str_program {
    my ($int_val) = @_;
    my $f = Chalk::IR::NodeFactory->new;

    my $cval = $f->make('Constant', value => $int_val, const_type => 'integer');
    $cval->set_stamp('Int');

    my $coerce_ib = $f->make('Coerce',
        from_repr => 'Int',
        to_repr   => 'Boolean',
        inputs    => [$cval],
    );
    $coerce_ib->set_stamp('Boolean');

    my $not_node = $f->make('Not', inputs => [$coerce_ib]);
    $not_node->set_stamp('Boolean');

    my $coerce_bs = $f->make('Coerce',
        from_repr => 'Boolean',
        to_repr   => 'Str',
        inputs    => [$not_node],
    );
    $coerce_bs->set_stamp('Str');

    my $lb = $f->make('Constant', value => '[', const_type => 'string');
    $lb->set_stamp('Str');
    my $rb = $f->make('Constant', value => ']', const_type => 'string');
    $rb->set_stamp('Str');

    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$lb, $coerce_bs, $rb]);
    $print->set_control_in($start);

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    return ($ret, $coerce_bs);
}

sub run_ll {
    my ($ll) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($exit, $out, $tmp);
}

# ---------------------------------------------------------------------------
# CBS1: Coerce(Boolean->Str) with truthy input (5): Not(5) = false, Str face = "".
# Oracle: Str:  (type-tagged empty string)
# Lowers without dying.
# ---------------------------------------------------------------------------
{
    my ($ret) = make_not_bool_str_program(5);
    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "CBS1: Coerce(Boolean->Str) truthy-input lowers without dying (err: $@)");
    ok(defined $ll, 'CBS1: lower() returns defined text');
}

# ---------------------------------------------------------------------------
# CBS2: Coerce(Boolean->Str) with falsy input (0): Not(0) = true, Str face = "1".
# Oracle: Str:1  (type-tagged "1")
# Lowers without dying.
# ---------------------------------------------------------------------------
{
    my ($ret) = make_not_bool_str_program(0);
    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "CBS2: Coerce(Boolean->Str) falsy-input lowers without dying (err: $@)");
    ok(defined $ll, 'CBS2: lower() returns defined text');
}

# ---------------------------------------------------------------------------
# CBS3: Coerce(Boolean->Str) truthy input — lli compiles without "undefined value".
# This is the key defect: the prior stub set _need_bool_str_globals but never
# emitted the globals, causing lli to reject with "use of undefined value".
# ---------------------------------------------------------------------------
{
    my ($ret) = make_not_bool_str_program(5);
    my $ll  = Chalk::Target::LLVM->lower($ret, program_mode => 1);

    my ($exit, $out) = run_ll($ll);

    unlike($out, qr/undefined value/i,
        'CBS3: lli does NOT report "undefined value" for false-face Boolean->Str');
    is($exit, 0, 'CBS3: lli exits 0 for false-face Boolean->Str');
}

# ---------------------------------------------------------------------------
# CBS4: Coerce(Boolean->Str) falsy input — lli compiles without "undefined value".
# The false-face ("") is the tricky one: [1 x i8] c"\00" (NUL only, empty string).
# ---------------------------------------------------------------------------
{
    my ($ret) = make_not_bool_str_program(0);
    my $ll  = Chalk::Target::LLVM->lower($ret, program_mode => 1);

    my ($exit, $out) = run_ll($ll);

    unlike($out, qr/undefined value/i,
        'CBS4: lli does NOT report "undefined value" for true-face Boolean->Str');
    is($exit, 0, 'CBS4: lli exits 0 for true-face Boolean->Str');
}

# ---------------------------------------------------------------------------
# CBS5: Bilateral oracle — truthy input (5), Not -> false -> "" (empty Str face).
# perl oracle: my $a = 5; !$a gives false; "${\!$a}" eq ""
#
# The old type-tag `Str:` carried TWO facts: the VALUE ("") and the TYPE (Str,
# not Bool). Printing erases the type half — a false Boolean and an empty Str
# both print as nothing — so the type half is asserted on the node directly and
# the value half is read off stdout, bracketed so empty is distinguishable from
# absent.
# ---------------------------------------------------------------------------
{
    my ($ret, $val) = make_not_bool_str_program(5);
    my $ll  = Chalk::Target::LLVM->lower($ret, program_mode => 1);

    my ($exit, $out) = run_ll($ll);

    is($exit, 0, 'CBS5: lli exit 0 for truthy->false->empty Str face');
    is($out, '[]', 'CBS5: truthy input: Not(5)->false->"" (empty string face)');
    is($val->stamp, 'Str',
        'CBS5: the printed value is Str-repr, not Boolean (the type half of the old tag)');
}

# ---------------------------------------------------------------------------
# CBS6: Bilateral oracle — falsy input (0), Not -> true -> "1" Str face.
# perl oracle: my $a = 0; !$a gives true; "${\!$a}" eq "1"
#
# The non-empty control for CBS5: same program shape, non-empty output. If the
# Print path were emitting nothing at all, this leg would read "[]" too.
# ---------------------------------------------------------------------------
{
    my ($ret, $val) = make_not_bool_str_program(0);
    my $ll  = Chalk::Target::LLVM->lower($ret, program_mode => 1);

    my ($exit, $out) = run_ll($ll);

    is($exit, 0, 'CBS6: lli exit 0 for falsy->true->"1" Str face');
    is($out, '[1]', 'CBS6: falsy input: Not(0)->true->"1" ("1" string face)');
    is($val->stamp, 'Str',
        'CBS6: the printed value is Str-repr, not Boolean (the type half of the old tag)');
}

# ---------------------------------------------------------------------------
# CBS7: .ll is libperl-free for false-face case (truthy input 5).
# ---------------------------------------------------------------------------
{
    my ($ret) = make_not_bool_str_program(5);
    my $ll  = Chalk::Target::LLVM->lower($ret, program_mode => 1);

    unlike($ll, qr/Perl_/,    'CBS7: false-face Boolean->Str .ll: no Perl_ C-API');
    unlike($ll, qr/\bSV\b/,   'CBS7: false-face Boolean->Str .ll: no SV type');
    unlike($ll, qr/libperl/,  'CBS7: false-face Boolean->Str .ll: no libperl');
}

# ---------------------------------------------------------------------------
# CBS8: .ll is libperl-free for true-face case (falsy input 0).
# ---------------------------------------------------------------------------
{
    my ($ret) = make_not_bool_str_program(0);
    my $ll  = Chalk::Target::LLVM->lower($ret, program_mode => 1);

    unlike($ll, qr/Perl_/,    'CBS8: true-face Boolean->Str .ll: no Perl_ C-API');
    unlike($ll, qr/\bSV\b/,   'CBS8: true-face Boolean->Str .ll: no SV type');
    unlike($ll, qr/libperl/,  'CBS8: true-face Boolean->Str .ll: no libperl');
}

# ---------------------------------------------------------------------------
# CBS9: The emitted .ll materializes BOTH Boolean string faces, bilaterally.
#
# This used to assert on @coerce_bool_str_true/@coerce_bool_str_false. Those
# globals were emitted unconditionally by the Str-return type-tag epilogue and
# the Coerce lowering never referenced them: it emits its own @bool_str_N pair
# and selects between them. With the epilogue gone the old names never appear,
# so the check now names what the Coerce actually builds — the true face
# [2 x i8] c"1\0" and the false face [1 x i8] c"\0" (NUL only = empty string) —
# plus the select that picks one.
# ---------------------------------------------------------------------------
{
    for my $case ([0, 'true-face'], [5, 'false-face']) {
        my ($int_val, $label) = $case->@*;
        my ($r) = make_not_bool_str_program($int_val);
        my $ll  = Chalk::Target::LLVM->lower($r, program_mode => 1);

        like($ll, qr/\@bool_str_\d+ = private unnamed_addr constant \[2 x i8\] c"1\\00"/,
            "CBS9: $label .ll materializes the true face \"1\" as [2 x i8]");
        like($ll, qr/\@bool_str_\d+ = private unnamed_addr constant \[1 x i8\] c"\\00"/,
            "CBS9: $label .ll materializes the false face \"\" as [1 x i8] (NUL only)");
        like($ll, qr/select i1 .*Coerce\[Boolean->Str\] -> ptr/,
            "CBS9: $label .ll selects between the two faces at runtime");
    }
}

# ---------------------------------------------------------------------------
# Finding 3 regression tests: _lower_not / _ensure_i1 repr-undef guard.
#
# F3A: Not with an explicit :Boolean operand lowers correctly (Boolean -> Boolean).
#      This is the normal case the guard must not break.
# F3B: Not with an undef-repr operand must die loudly (not silently mismatch).
# ---------------------------------------------------------------------------

# F3A: Not over a Boolean-repr Coerce(Int->Boolean) lowers correctly — no type mismatch.
{
    use Chalk::IR::Node::Not;

    my $f = Chalk::IR::NodeFactory->new;

    my $c5 = $f->make('Constant', value => 5, const_type => 'integer');
    $c5->set_stamp('Int');

    my $coerce = $f->make('Coerce', from_repr => 'Int', to_repr => 'Boolean', inputs => [$c5]);
    $coerce->set_stamp('Boolean');

    # Not over an explicit :Boolean operand — _ensure_i1 must pass through as i1.
    my $not_node = $f->make('Not', inputs => [$coerce]);
    $not_node->set_stamp('Boolean');

    # The Not result is Boolean. A program cannot observe a Boolean directly:
    # the backend refuses Print of a Boolean arg ("Print takes Str, so this
    # needs a Coerce"), exactly as a source program would go through
    # stringification. So the Boolean-ness is asserted on the node and the
    # value is observed through the Coerce, bracketed to separate "printed
    # empty" from "printed nothing".
    is($not_node->stamp, 'Boolean',
        'F3A: Not(Boolean) result is Boolean-repr (the type half of the old Bool: tag)');

    my $to_str = $f->make('Coerce',
        from_repr => 'Boolean', to_repr => 'Str', inputs => [$not_node]);
    $to_str->set_stamp('Str');

    my $lb = $f->make('Constant', value => '[', const_type => 'string');
    $lb->set_stamp('Str');
    my $rb = $f->make('Constant', value => ']', const_type => 'string');
    $rb->set_stamp('Str');

    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$lb, $to_str, $rb]);
    $print->set_control_in($start);

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    ok(!$@, "F3A: Not(Boolean) lowers without dying (err: $@)");

    SKIP: {
        skip 'F3A lowering failed', 3 unless defined $ll;

        like($ll, qr/xor i1/, 'F3A: .ll contains xor i1 (Not lowering)');

        my ($exit, $out) = run_ll($ll);

        is($exit, 0,     'F3A: lli exits 0 for Not(Boolean) graph');
        is($out, '[]',   'F3A: Not(5) gives false, whose Str face is the empty string');
    }
}

# F3B: Not with an operand that has NO repr set must die loudly (not silently
# default to Int and emit an icmp ne i64 on an i1 value — which is type-invalid).
{
    use Chalk::IR::Node::Not;

    my $f = Chalk::IR::NodeFactory->new;

    my $c5 = $f->make('Constant', value => 5, const_type => 'integer');
    # Intentionally leave representation unset — simulates a programming error
    # where a Boolean-typed value has lost its repr annotation.

    my $not_node = $f->make('Not', inputs => [$c5]);
    $not_node->set_stamp('Boolean');

    my $ret = $f->make_cfg('Return', inputs => [$not_node]);

    eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    like($@, qr/representation/i,
        'F3B: Not with undef-repr operand dies loudly mentioning representation');
}

done_testing;
