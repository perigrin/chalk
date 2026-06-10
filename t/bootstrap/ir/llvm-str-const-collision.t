# ABOUTME: I1 gate-hardening: str_const global names must be unique per-module, not per-context.
# ABOUTME: Verifies no @str_const_0 duplicate when both method body and main graph have string constants.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::Target::LLVM;

# I1 (R1 reopened):
# @str_const_<idx> is indexed PER-context (idx = scalar @{$ctx->{_str_globals}}).
# Each method body lowers in a fresh Context (counter restarts at 0); the main
# graph also starts at 0 -> two @str_const_0 definitions in one module = duplicate
# symbol (lli rejects) or wrong-payload GEP.
#
# Fix: unique per-module names — prefix body globals by class/method:
#   @<Cls>__<method>__str_const_N
# OR thread a single shared str-const counter/registry through all contexts.
#
# RED: a class with a method body containing a string literal AND a main-graph
# string literal -> assert the .ll has NO duplicate @str_const_0 and lli accepts.

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: build a class with TWO methods each having a Str constant.
# Both method bodies lower in a fresh Context, so each emits @str_const_0
# before the I1 fix (duplicate symbol). After the fix, body globals are
# prefixed by class/method name, producing unique names.
sub build_dual_str_graph {
    my $f = Chalk::IR::NodeFactory->new;

    # Method A: Constant("first" :Str)
    my $str_a = $f->make('Constant', value => 'first', const_type => 'string');
    $str_a->set_representation('Str');
    my $mi_a = Chalk::IR::MethodInfo->new(
        name        => 'get_first',
        body        => [],
        body_node   => $str_a,
        return_repr => 'Str',
    );

    # Method B: Constant("second" :Str) — same index (0) in a fresh body_ctx
    my $str_b = $f->make('Constant', value => 'second', const_type => 'string');
    $str_b->set_representation('Str');
    my $mi_b = Chalk::IR::MethodInfo->new(
        name        => 'get_second',
        body        => [],
        body_node   => $str_b,
        return_repr => 'Str',
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'MultiStr',
        methods => [$mi_a, $mi_b],
        fields  => [],
    );

    my $new_obj = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_obj->set_representation('Object');

    my $call = $f->make('MethodCall',
        method_name => 'get_first',
        inputs      => [$new_obj, $ci],
    );
    $call->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$call]);
    return ($ret, $f);
}

# Helper: build a class with THREE methods each having a Str constant.
# Three fresh body contexts each emit @str_const_0, @str_const_1 — but the
# indices reset, so body[1] and body[2] each produce @str_const_0 conflicts.
sub build_triple_str_graph {
    my $f = Chalk::IR::NodeFactory->new;

    my $str_a = $f->make('Constant', value => 'alpha', const_type => 'string');
    $str_a->set_representation('Str');
    my $mi_a = Chalk::IR::MethodInfo->new(
        name        => 'get_alpha',
        body        => [],
        body_node   => $str_a,
        return_repr => 'Str',
    );

    my $str_b = $f->make('Constant', value => 'beta', const_type => 'string');
    $str_b->set_representation('Str');
    my $mi_b = Chalk::IR::MethodInfo->new(
        name        => 'get_beta',
        body        => [],
        body_node   => $str_b,
        return_repr => 'Str',
    );

    my $str_c = $f->make('Constant', value => 'gamma', const_type => 'string');
    $str_c->set_representation('Str');
    my $mi_c = Chalk::IR::MethodInfo->new(
        name        => 'get_gamma',
        body        => [],
        body_node   => $str_c,
        return_repr => 'Str',
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'TripleStr',
        methods => [$mi_a, $mi_b, $mi_c],
        fields  => [],
    );

    my $new_obj = $f->make('New', param_names => [], inputs => [$ci]);
    $new_obj->set_representation('Object');
    my $call = $f->make('MethodCall',
        method_name => 'get_alpha',
        inputs      => [$new_obj, $ci],
    );
    $call->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$call]);
    return ($ret, $f);
}

# Test 1: two method bodies each with a Str constant -> no duplicate @str_const_0
# Before I1 fix: both emit @str_const_0 -> lli rejects with duplicate symbol.
# After I1 fix: body globals are prefixed by class/method -> unique names.
subtest 'two method bodies with Str constants: no duplicate @str_const_0' => sub {
    my ($ret, $f) = build_dual_str_graph();

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(!defined $err || !length $err,
        'two-method Str graph: lower() does not die')
        or do { diag("error: $err"); done_testing(); return };

    # Count all global definitions to check for duplicates.
    # Body-emitted str_const globals must be prefixed by class/method name (I1 fix),
    # so the module-level counter @str_const_0 is reserved for the main graph only.
    my @all_defs = ($ll =~ /^(\@\w+ = )/mg);
    my %global_seen;
    my @duplicates = grep { $global_seen{$_}++ } @all_defs;
    is(scalar(@duplicates), 0,
        'no duplicate global definitions in .ll (I1: body names must be unique per-module)')
        or diag("Duplicate globals: " . join(', ', @duplicates) . "\n"
                . "First 1000 chars of .ll:\n" . substr($ll, 0, 1000));

    # lli must accept the .ll
    require File::Temp;
    my ($fh, $f2) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $f2 2>&1);
    my $lli_exit = $? >> 8;
    is($lli_exit, 0, 'lli accepts the .ll (no duplicate symbol error)')
        or diag("lli output: $out\nFirst 1000 chars of .ll:\n" . substr($ll, 0, 1000));
};

# Test 2: three method bodies each with a Str constant -> no duplicate globals
subtest 'three method bodies with Str constants: no duplicate globals (I1)' => sub {
    my ($ret, $f) = build_triple_str_graph();

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret) };
    $err = $@;

    ok(!defined $err || !length $err,
        'triple-method Str graph: lower() does not die')
        or do { diag("error: $err"); done_testing(); return };

    # No duplicate global definitions
    my @all_defs2 = ($ll =~ /^(\@\w+ = )/mg);
    my %seen2;
    my @dups2 = grep { $seen2{$_}++ } @all_defs2;
    is(scalar(@dups2), 0,
        'no duplicate global definitions in .ll (I1: every global name must be unique)')
        or diag("Duplicate globals: " . join(', ', @dups2) . "\nFirst 1000 chars:\n" . substr($ll, 0, 1000));

    # lli must accept the .ll
    require File::Temp;
    my ($fh2, $f2b) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh2, ':utf8';
    print $fh2 $ll;
    close $fh2;
    my $out2 = qx($LLI $f2b 2>&1);
    my $lli_exit2 = $? >> 8;
    is($lli_exit2, 0, 'lli accepts the .ll (no duplicate symbol)')
        or diag("lli output: $out2\nFirst 1000 chars of .ll:\n" . substr($ll, 0, 1000));
};

done_testing();
