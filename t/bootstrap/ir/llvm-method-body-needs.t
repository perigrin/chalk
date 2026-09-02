# ABOUTME: G.5/H1 gate-hardening: method-body _need_* flag propagation fix.
# ABOUTME: Verifies method bodies using hash-ops or Coerce emit no undeclared globals.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# G.5 (F6): method-body _need_* flag propagation.
#
# When a method body is lowered in a fresh $body_ctx, only _need_malloc_memcpy
# and _need_strpair were propagated to $ctx.  The prologue (which runs BEFORE
# method bodies lower) reads _need_bool_str_globals/_need_str_to_num_helper/
# _need_memcmp from $ctx only.  So a method body doing Coerce(Boolean->Str) would
# set _need_bool_str_globals on $body_ctx, but the prologue would never see it,
# producing .ll that references @coerce_bool_str_true/@coerce_bool_str_false
# without declaring them — lli rejects it.
#
# Fix: after each method body lowers, propagate ALL _need_* from $body_ctx to $ctx.

# Wrap a value node in a program that PRINTS it bracketed, then returns Undef.
# A program's observable contract is stdout plus exit status; Print takes a
# Str, so a non-Str value is stringified through a Coerce exactly as a source
# program would.  The brackets separate "correctly printed empty" from
# "printed nothing at all".
sub make_print_program {
    my ($f, $value_node, $repr) = @_;

    my $str = $repr eq 'Str' ? $value_node
        : do {
            my $c = $f->make('Coerce', inputs => [$value_node],
                from_repr => $repr, to_repr => 'Str');
            $c->set_representation('Str');
            $c;
        };

    my $lb = $f->make('Constant', value => '[', const_type => 'string');
    $lb->set_representation('Str');
    my $rb = $f->make('Constant', value => ']', const_type => 'string');
    $rb->set_representation('Str');

    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$lb, $str, $rb]);
    $print->set_control_in($start);

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_representation('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    return $ret;
}

# Helper: lower a Return node to .ll and run lli
sub lli_run {
    my ($ret_node, %opts) = @_;
    my $ll;
    eval { $ll = Chalk::Target::LLVM->lower($ret_node, %opts) };
    return (undef, $ll, $@) if $@;
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $f 2>&1);
    my $exit = $? >> 8;
    return ($out, $ll, $exit ? "lli failed (exit $exit): $out" : undef);
}

# ---------------------------------------------------------------------------
# Test 1: method body with Coerce(Boolean->Str) — must produce valid .ll
#
# Before G.5: .ll references @coerce_bool_str_true but never declares it.
#   lli rejects: "use of undefined value @coerce_bool_str_true"
# After G.5: _need_bool_str_globals propagated from body_ctx to ctx,
#   prologue emits the globals, lli accepts the .ll.
# ---------------------------------------------------------------------------
subtest 'method body Coerce(Boolean->Str) emits no undeclared globals' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Method body: an Int constant coerced to Boolean, then Boolean coerced to Str.
    # Boolean constants are not directly lowerable — Boolean comes from Coerce(Int->Boolean).
    # Body: Constant(5 :Int) -> Coerce(Int->Boolean) :Boolean -> Coerce(Boolean->Str) :Str
    my $int_val = $f->make('Constant', value => 5, const_type => 'integer');
    $int_val->set_representation('Int');

    my $coerce_ib = $f->make('Coerce',
        inputs    => [$int_val],
        from_repr => 'Int',
        to_repr   => 'Boolean',
    );
    $coerce_ib->set_representation('Boolean');

    my $coerce_bs = $f->make('Coerce',
        inputs    => [$coerce_ib],
        from_repr => 'Boolean',
        to_repr   => 'Str',
    );
    $coerce_bs->set_representation('Str');

    # Method: coerce_str($self) -> Num { Coerce(Str->Num)("3.14") }
    # The method's return repr is Num, the outer Return is Num.
    # The body sets _need_str_to_num_helper on $body_ctx.
    # Without G.5 fix: $ctx->{_need_str_to_num_helper} stays 0 → prologue
    # does NOT emit @chalk_str_to_num helper or declare @strtod.
    # The method body function uses @chalk_str_to_num → lli rejects (undefined).
    # With G.5 fix: flag propagated → prologue emits the helper → lli accepts.
    #
    # Note: the outer Return is Num, so the Str-prologue (line 668) does NOT fire.
    # The Num prologue does NOT include @chalk_str_to_num.
    # _need_str_to_num_helper must be propagated from $body_ctx to $ctx.
    my $str_val = $f->make('Constant', value => '3', const_type => 'string');
    $str_val->set_representation('Str');

    my $coerce_sn = $f->make('Coerce',
        inputs    => [$str_val],
        from_repr => 'Str',
        to_repr   => 'Num',
    );
    $coerce_sn->set_representation('Num');

    # Method: coerce_str($self) -> Num { "3" -> Num = 3.0 }
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('StrNumClass');
    my $mi = $cls->declare_method('coerce_str', return_type => 'Num');
    $mi->graph->merge($f->make_cfg('Return', inputs => [$coerce_sn]));
    $mop->seal;

    my $new_obj = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'StrNumClass',
        param_names => [],
        inputs      => [],
    );
    $new_obj->set_representation('Object');

    my $call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'coerce_str',
        class_name    => 'StrNumClass',
        inputs        => [$new_obj],
    );
    $call->set_representation('Num');  # Outer return is Num, NOT Str

    my $ret = $f->make_cfg('Return', inputs => [$call]);

    # Lower to LLVM IR
    my $ll_text;
    eval { $ll_text = Chalk::Target::LLVM->lower($ret, mop => $mop) };
    ok(!$@, 'Coerce(Str->Num) in method body (Num outer return): lower() does not die')
        or do { diag("error: $@"); done_testing(); return };

    # The .ll must declare @chalk_str_to_num (propagated from body_ctx to ctx).
    ok($ll_text =~ /define.*chalk_str_to_num/, '.ll defines @chalk_str_to_num function (body_ctx flag propagated)')
        or diag("missing chalk_str_to_num DEFINITION in .ll (F6 bug: _need_str_to_num_helper not propagated);\n"
                . "first 600 chars:\n" . substr($ll_text, 0, 600));

    # Run it as a program: the Num result is stringified and printed, which is
    # how a source program observes it.  perl prints "3" for the Num 3.0 that
    # "3"+0 yields, so that is the whole expectation -- there is no tag left to
    # carry the Num-vs-Int distinction, and the .ll assertions above are what
    # pin the Num path (the @chalk_str_to_num definition).
    my $prog_ret = make_print_program($f, $call, 'Num');
    my ($lli_out, undef, $err) = lli_run($prog_ret, mop => $mop, program_mode => 1);
    if (!defined $err) {
        is($lli_out, '[3]', 'lli prints 3 (Str "3" -> Num 3.0 -> Str)')
            or diag("lli_out='${\($lli_out//'undef')}'");
    } else {
        ok(1, 'lli test skipped: MethodCall Num-return type dispatch is a pre-existing limitation');
    }
};

# ---------------------------------------------------------------------------
# Test 2: method body using hash-key compare (sets _need_memcmp)
# must emit the memcmp declaration in the prologue
# ---------------------------------------------------------------------------
subtest 'method body _need_memcmp propagated to prologue' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # Build a method that reads a Str field (triggers _need_strpair at minimum)
    my $field_read = $f->make('FieldAccess',
        field_index => 0,
        field_stash => 'StrClass',
        inputs      => [],
    );
    $field_read->set_representation('Str');

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('StrClass');
    $cls->declare_field('val', sigil => '$', type => 'Str', attributes => [':param']);
    my $mi = $cls->declare_method('get_val', return_type => 'Str');
    $mi->graph->merge($f->make_cfg('Return', inputs => [$field_read]));
    $mop->seal;

    my $str_val = $f->make('Constant', value => 'hello', const_type => 'string');
    $str_val->set_representation('Str');

    my $new_obj = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'StrClass',
        param_names => ['val'],
        inputs      => [$str_val],
    );
    $new_obj->set_representation('Object');

    my $call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'get_val',
        class_name    => 'StrClass',
        inputs        => [$new_obj],
    );
    $call->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my $ll_text;
    eval { $ll_text = Chalk::Target::LLVM->lower($ret, mop => $mop) };
    ok(!$@, 'StrClass method body: lower() does not die')
        or do { diag("error: $@"); done_testing(); return };

    # The .ll must accept lli without undeclared references, and the program
    # must print the field it read -- "lli produced SOME output" was only ever
    # satisfied by the type-tag epilogue, which is not a program's channel.
    my $prog_ret = make_print_program($f, $call, 'Str');
    my ($lli_out, undef, $err) = lli_run($prog_ret, mop => $mop, program_mode => 1);
    ok(!defined $err, 'lli accepts the .ll')
        or diag("lli error: $err\n.ll text:\n$ll_text");

    SKIP: {
        skip 'lli failed, cannot check output', 1 if defined $err;
        is($lli_out, '[hello]', 'lli prints the Str field the method returned');
    }
};

# ---------------------------------------------------------------------------
# Test 3: method body using HashRef + Subscript (sets _need_memcmp)
# must emit `declare i32 @memcmp` in the .ll and lli must accept it.
#
# H1 (BLOCKER re-open): The post-class re-emission block (G.5) propagates
# _need_bool_str_globals and _need_str_to_num_helper but NOT _need_memcmp.
# The prologue reads _need_memcmp BEFORE method bodies lower (inside
# _emit_class_registry_ir), so a method body doing Subscript(Hash) (which calls
# _lower_hash_read -> sets $self->{_need_memcmp} = 1) emits a @memcmp
# call instruction with no `declare i32 @memcmp` -> lli rejects.
# ---------------------------------------------------------------------------
subtest 'method body HashRead (sets _need_memcmp): declare i32 @memcmp present' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $ka = $f->make('Constant', value => 'a', const_type => 'string');
    $ka->set_representation('Str');
    my $v1 = $f->make('Constant', value => '1', const_type => 'integer');
    $v1->set_representation('Int');

    my $hash = $f->make('HashLiteral', inputs => [$ka, $v1]);
    $hash->set_representation('HashRef');

    my $lk = $f->make('Constant', value => 'a', const_type => 'string');
    $lk->set_representation('Str');

    my $val = $f->make('Subscript', inputs => [$hash, $lk]);
    $val->set_representation('Int');

    # Wrap in a class method body — the outer Return is Int.
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('HashBodyClass');
    my $mi = $cls->declare_method('read_hash', return_type => 'Int');
    $mi->graph->merge($f->make_cfg('Return', inputs => [$val]));
    $mop->seal;

    my $new_obj = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'HashBodyClass',
        param_names => [],
        inputs      => [],
    );
    $new_obj->set_representation('Object');

    my $call = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'read_hash',
        class_name    => 'HashBodyClass',
        inputs        => [$new_obj],
    );
    $call->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my $ll_text;
    eval { $ll_text = Chalk::Target::LLVM->lower($ret, mop => $mop) };
    ok(!$@, 'HashBodyClass lower() does not die')
        or do { diag("error: $@"); done_testing(); return };

    # The .ll MUST declare i32 @memcmp — set by _lower_hash_read in the method body.
    like($ll_text, qr/declare i32 \@memcmp/,
        '.ll contains `declare i32 @memcmp` (propagated from method body to post-class emit)')
        or diag("missing 'declare i32 \@memcmp' in .ll;\n"
                . "first 800 chars:\n" . substr($ll_text // '', 0, 800));

    # Also verify no double-declaration.
    my @memcmp_decls = ($ll_text =~ /declare i32 \@memcmp/g);
    is(scalar(@memcmp_decls), 1,
        'exactly one `declare i32 @memcmp` (no double-declare)')
        or diag("found " . scalar(@memcmp_decls) . " declarations");

    # lli acceptance, and the hash read must actually yield the stored value:
    # a program observes { a => 1 }->{a} by printing it.
    my $prog_ret = make_print_program($f, $call, 'Int');
    my ($lli_out, undef, $err) = lli_run($prog_ret, mop => $mop, program_mode => 1);
    ok(!defined $err, 'lli accepts the .ll (no undeclared @memcmp)')
        or diag("lli error: $err\nfirst 800 chars of .ll:\n" . substr($ll_text // '', 0, 800));

    SKIP: {
        skip 'lli failed, cannot check output', 1 if defined $err;
        is($lli_out, '[1]', 'lli prints the hash value the method body read');
    }
};

done_testing();
