# ABOUTME: I3 gate-hardening: %StrPair type must be declared whenever it is referenced.
# ABOUTME: Verifies post-class re-emit guard for %StrPair mirrors the H1 memcmp guard.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
use Chalk::Target::LLVM;

# I3 (R1 reopened):
# %StrPair is emitted by _emit_class_registry_ir when some method RETURNS Str
# (the $need_strpair LOCAL check at ~line 366 scans return_repr). But _need_strpair
# is also SET at ~3545 (New.:param Str binding in _lower_new) and this sets
# $ctx->{_need_strpair}=1 during lower_value — which happens BEFORE _emit_class_registry_ir
# runs. However, _emit_class_registry_ir uses a LOCAL variable scan, not $ctx->{_need_strpair}.
# So a class with a Str :param field but NO Str-returning methods: _lower_new emits
# %StrPair refs at line 3521-3545, but the LOCAL scan at 365-372 finds no Str return ->
# %StrPair NOT declared -> lli rejects ("base element of getelementptr must be sized").
#
# Same pattern as H1 memcmp: the flag is propagated/set but the post-class re-emit
# guard doesn't exist for _need_strpair.
#
# Fix: add post-class re-emit guarded by _strpair_emitted (mirror of _memcmp_emitted);
# set _strpair_emitted=1 at the existing line-376 emit site to prevent double-declare.

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Helper: build a class with a Str :param field but NO Str-returning methods.
# The outer graph calls the Int-returning method -> class scan returns $need_strpair=0
# -> %StrPair NOT emitted. But _lower_new emits %StrPair* references during param binding.
sub build_str_param_int_return_graph {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('StrParamIntReturn');

    $cls->declare_field('name', sigil => '$', type => 'Str',
        attributes => [':param']);

    # Method returns Int (not Str) — line 372 scan gets $need_strpair=0
    my $int_body = $f->make('Constant', value => 42, const_type => 'integer');
    $int_body->set_representation('Int');
    my $m = $cls->declare_method('get_int', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$int_body]));

    $mop->seal;

    my $str_val = $f->make('Constant', value => 'hello', const_type => 'string');
    $str_val->set_representation('Str');

    # New with Str :param — _lower_new at line ~3521 emits %StrPair instructions
    my $new_obj = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'StrParamIntReturn',
        param_names => ['name'],
        inputs      => [$str_val],
    );
    $new_obj->set_representation('Object');

    # Call the Int method (so the outer Return is Int, not Str)
    my $call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'get_int',
        class_name    => 'StrParamIntReturn',
        inputs        => [$new_obj],
    );
    $call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$call]);
    return ($ret, $f, $mop);
}

# Test 1: Str :param field + Int-returning method -> .ll must have %StrPair declaration
# Before I3 fix: _lower_new emits %StrPair* refs but %StrPair not declared -> lli rejects.
# After I3 fix: post-class re-emit block adds %StrPair when _need_strpair set.
subtest 'Str :param field + Int-returning method: %StrPair must be declared (I3)' => sub {
    my ($ret, $f, $mop) = build_str_param_int_return_graph();

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret, mop => $mop) };
    $err = $@;

    ok(!defined $err || !length $err,
        'Str-param Int-return class: lower() does not die')
        or do { diag("error: $err"); done_testing(); return };

    # Must have at least one %StrPair declaration
    my @strpair_decls = ($ll =~ /^%StrPair\s*=/mg);
    is(scalar(@strpair_decls), 1,
        '.ll has exactly one %StrPair declaration (I3: emitted even when no method returns Str)')
        or diag("Found " . scalar(@strpair_decls) . " %StrPair declarations (expected 1);\n"
                . "First 800 chars:\n" . substr($ll, 0, 800));

    # lli must accept the .ll
    require File::Temp;
    my ($fh, $tmpf) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $tmpf 2>&1);
    my $lli_exit = $? >> 8;
    is($lli_exit, 0, 'lli accepts .ll (no undeclared %StrPair)')
        or diag("lli output: $out\nFirst 800 chars of .ll:\n" . substr($ll, 0, 800));
};

# Test 2: a Str-returning method (line-376 path) still has exactly one %StrPair
# (no double-declare from both line-376 emit AND post-class re-emit).
subtest 'Str-returning method: exactly one %StrPair (I3 no double-declare)' => sub {
    my $f   = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('StrReturn');

    my $str_val = $f->make('Constant', value => 'world', const_type => 'string');
    $str_val->set_representation('Str');

    my $m = $cls->declare_method('get_str', return_type => 'Str');
    $m->graph->merge($f->make_cfg('Return', inputs => [$str_val]));

    $mop->seal;

    my $new_obj = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'StrReturn', param_names => [], inputs => []);
    $new_obj->set_representation('Object');

    my $call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'get_str',
        class_name    => 'StrReturn',
        inputs        => [$new_obj],
    );
    $call->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($ll, $err);
    eval { $ll = Chalk::Target::LLVM->lower($ret, mop => $mop) };
    $err = $@;

    ok(!defined $err || !length $err,
        'Str-returning method: lower() does not die')
        or do { diag("error: $err"); done_testing(); return };

    my @strpair_decls = ($ll =~ /^%StrPair\s*=/mg);
    is(scalar(@strpair_decls), 1,
        'exactly one %StrPair declaration (no double-declare from post-class re-emit, I3)')
        or diag("Found " . scalar(@strpair_decls) . " declarations;\nFirst 600 chars:\n" . substr($ll, 0, 600));

    require File::Temp;
    my ($fh, $tmpf) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $tmpf 2>&1);
    my $lli_exit = $? >> 8;
    is($lli_exit, 0, 'lli accepts .ll (Str-returning method)')
        or diag("lli: $out\nFirst 600 chars:\n" . substr($ll, 0, 600));
};

done_testing();
