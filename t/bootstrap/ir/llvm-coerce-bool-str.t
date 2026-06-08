# ABOUTME: Tests for Coerce(Bool->Str) LLVM lowering — bool string-face globals (G2 reopen-1).
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
use Chalk::IR::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: build a graph where Not(Int) -> Coerce(Bool->Str) -> Return(:Str).
# Not(nonzero) = false -> Coerce -> "" -> oracle Str:
# Not(0)       = true  -> Coerce -> "1" -> oracle Str:1
#
# We use an integer constant as input to Not, so Bool comes from a real
# truthiness operation (not a synthetic Bool constant).
#
#   Constant(val :Int) -> Coerce(Int->Bool) :Bool -> Not :Bool
#                         -> Coerce(Bool->Str) :Str -> Return

sub make_not_bool_str_graph {
    my ($int_val) = @_;   # 0 = falsy (Not -> true -> "1"), nonzero = truthy (Not -> false -> "")
    my $f = Chalk::IR::NodeFactory->new;

    my $cval = $f->make('Constant', value => $int_val, const_type => 'integer');
    $cval->set_representation('Int');

    # Coerce Int->Bool (truthiness)
    my $coerce_ib = $f->make('Coerce',
        from_repr => 'Int',
        to_repr   => 'Bool',
        inputs    => [$cval],
    );
    $coerce_ib->set_representation('Bool');

    # Not: logical negation
    my $not_node = $f->make('Not', inputs => [$coerce_ib]);
    $not_node->set_representation('Bool');

    # Coerce Bool->Str: string-face "" or "1"
    my $coerce_bs = $f->make('Coerce',
        from_repr => 'Bool',
        to_repr   => 'Str',
        inputs    => [$not_node],
    );
    $coerce_bs->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$coerce_bs]);
    return $ret;
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
# CBS1: Coerce(Bool->Str) with truthy input (5): Not(5) = false, Str face = "".
# Oracle: Str:  (type-tagged empty string)
# Lowers without dying.
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(5);
    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "CBS1: Coerce(Bool->Str) truthy-input lowers without dying (err: $@)");
    ok(defined $ll, 'CBS1: lower() returns defined text');
}

# ---------------------------------------------------------------------------
# CBS2: Coerce(Bool->Str) with falsy input (0): Not(0) = true, Str face = "1".
# Oracle: Str:1  (type-tagged "1")
# Lowers without dying.
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(0);
    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "CBS2: Coerce(Bool->Str) falsy-input lowers without dying (err: $@)");
    ok(defined $ll, 'CBS2: lower() returns defined text');
}

# ---------------------------------------------------------------------------
# CBS3: Coerce(Bool->Str) truthy input — lli compiles without "undefined value".
# This is the key defect: the prior stub set _need_bool_str_globals but never
# emitted the globals, causing lli to reject with "use of undefined value".
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(5);
    my $ll  = Chalk::IR::Target::LLVM->lower($ret);

    my ($exit, $out) = run_ll($ll);

    unlike($out, qr/undefined value/i,
        'CBS3: lli does NOT report "undefined value" for false-face Bool->Str');
    is($exit, 0, 'CBS3: lli exits 0 for false-face Bool->Str');
}

# ---------------------------------------------------------------------------
# CBS4: Coerce(Bool->Str) falsy input — lli compiles without "undefined value".
# The false-face ("") is the tricky one: [1 x i8] c"\00" (NUL only, empty string).
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(0);
    my $ll  = Chalk::IR::Target::LLVM->lower($ret);

    my ($exit, $out) = run_ll($ll);

    unlike($out, qr/undefined value/i,
        'CBS4: lli does NOT report "undefined value" for true-face Bool->Str');
    is($exit, 0, 'CBS4: lli exits 0 for true-face Bool->Str');
}

# ---------------------------------------------------------------------------
# CBS5: Bilateral oracle — truthy input (5), Not -> false -> "" -> Str:
# perl oracle: my $a = 5; !$a gives false; "${\!$a}" eq ""
# type-tagged: Str:
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(5);
    my $ll  = Chalk::IR::Target::LLVM->lower($ret);

    my ($exit, $out) = run_ll($ll);

    is($exit, 0, 'CBS5: lli exit 0 for truthy->false->Str:');
    is($out, 'Str:', 'CBS5: truthy input: Not(5)->false->Str: (empty string face)');
}

# ---------------------------------------------------------------------------
# CBS6: Bilateral oracle — falsy input (0), Not -> true -> "1" -> Str:1
# perl oracle: my $a = 0; !$a gives true; "${\!$a}" eq "1"
# type-tagged: Str:1
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(0);
    my $ll  = Chalk::IR::Target::LLVM->lower($ret);

    my ($exit, $out) = run_ll($ll);

    is($exit, 0, 'CBS6: lli exit 0 for falsy->true->Str:1');
    is($out, 'Str:1', 'CBS6: falsy input: Not(0)->true->Str:1 ("1" string face)');
}

# ---------------------------------------------------------------------------
# CBS7: .ll is libperl-free for false-face case (truthy input 5).
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(5);
    my $ll  = Chalk::IR::Target::LLVM->lower($ret);

    unlike($ll, qr/Perl_/,    'CBS7: false-face Bool->Str .ll: no Perl_ C-API');
    unlike($ll, qr/\bSV\b/,   'CBS7: false-face Bool->Str .ll: no SV type');
    unlike($ll, qr/libperl/,  'CBS7: false-face Bool->Str .ll: no libperl');
}

# ---------------------------------------------------------------------------
# CBS8: .ll is libperl-free for true-face case (falsy input 0).
# ---------------------------------------------------------------------------
{
    my $ret = make_not_bool_str_graph(0);
    my $ll  = Chalk::IR::Target::LLVM->lower($ret);

    unlike($ll, qr/Perl_/,    'CBS8: true-face Bool->Str .ll: no Perl_ C-API');
    unlike($ll, qr/\bSV\b/,   'CBS8: true-face Bool->Str .ll: no SV type');
    unlike($ll, qr/libperl/,  'CBS8: true-face Bool->Str .ll: no libperl');
}

# ---------------------------------------------------------------------------
# CBS9: The emitted .ll declares both @coerce_bool_str_true and
# @coerce_bool_str_false at the module level (bilateral global presence check).
# ---------------------------------------------------------------------------
{
    my $ret_t = make_not_bool_str_graph(0);   # true face (Not(0) = true)
    my $ll_t  = Chalk::IR::Target::LLVM->lower($ret_t);

    like($ll_t, qr/\@coerce_bool_str_true/,
        'CBS9: true-face .ll declares @coerce_bool_str_true global');
    like($ll_t, qr/\@coerce_bool_str_false/,
        'CBS9: true-face .ll declares @coerce_bool_str_false global');

    my $ret_f = make_not_bool_str_graph(5);   # false face (Not(5) = false)
    my $ll_f  = Chalk::IR::Target::LLVM->lower($ret_f);

    like($ll_f, qr/\@coerce_bool_str_true/,
        'CBS9: false-face .ll declares @coerce_bool_str_true global');
    like($ll_f, qr/\@coerce_bool_str_false/,
        'CBS9: false-face .ll declares @coerce_bool_str_false global');
}

# ---------------------------------------------------------------------------
# Finding 3 regression tests: _lower_not / _ensure_i1 repr-undef guard.
#
# F3A: Not with an explicit :Bool operand lowers correctly (Bool -> Bool).
#      This is the normal case the guard must not break.
# F3B: Not with an undef-repr operand must die loudly (not silently mismatch).
# ---------------------------------------------------------------------------

# F3A: Not over a Bool-repr Coerce(Int->Bool) lowers correctly — no type mismatch.
{
    use Chalk::IR::Node::Not;

    my $f = Chalk::IR::NodeFactory->new;

    my $c5 = $f->make('Constant', value => 5, const_type => 'integer');
    $c5->set_representation('Int');

    my $coerce = $f->make('Coerce', from_repr => 'Int', to_repr => 'Bool', inputs => [$c5]);
    $coerce->set_representation('Bool');

    # Not over an explicit :Bool operand — _ensure_i1 must pass through as i1.
    my $not_node = $f->make('Not', inputs => [$coerce]);
    $not_node->set_representation('Bool');

    my $ret = $f->make_cfg('Return', inputs => [$not_node]);

    my $ll;
    eval { $ll = Chalk::IR::Target::LLVM->lower($ret) };
    ok(!$@, "F3A: Not(Bool) lowers without dying (err: $@)");

    SKIP: {
        skip 'F3A lowering failed', 3 unless defined $ll;

        like($ll, qr/xor i1/, 'F3A: .ll contains xor i1 (Not lowering)');

        my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
        binmode $fh, ':utf8';
        print $fh $ll;
        close $fh;

        my $out  = qx($LLI $tmp 2>&1);
        my $exit = $? >> 8;
        chomp $out;

        is($exit, 0,        'F3A: lli exits 0 for Not(Bool) graph');
        is($out, 'Bool:',   'F3A: Not(5) gives false = Bool: (type-tagged)');
    }
}

# F3B: Not with an operand that has NO repr set must die loudly (not silently
# default to Int and emit an icmp ne i64 on an i1 value — which is type-invalid).
{
    use Chalk::IR::Node::Not;

    my $f = Chalk::IR::NodeFactory->new;

    my $c5 = $f->make('Constant', value => 5, const_type => 'integer');
    # Intentionally leave representation unset — simulates a programming error
    # where a Bool-typed value has lost its repr annotation.

    my $not_node = $f->make('Not', inputs => [$c5]);
    $not_node->set_representation('Bool');

    my $ret = $f->make_cfg('Return', inputs => [$not_node]);

    eval { Chalk::IR::Target::LLVM->lower($ret) };
    like($@, qr/representation/i,
        'F3B: Not with undef-repr operand dies loudly mentioning representation');
}

done_testing;
