# ABOUTME: Tests for Call(dispatch_kind='method') vtable dispatch in LLVM lowering.
# ABOUTME: Verifies Call(dispatch_kind='method') resolves through the sealed-MOP class registry.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::MOP;
use Chalk::Target::LLVM;

my $P   = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Run the equivalent perl program and capture what it PRINTS -- a program's
# observable contract is stdout, not a type tag. The brackets are load-bearing:
# they separate "correctly printed the empty string" from "printed nothing".
sub perl_oracle {
    my ($src) = @_;
    my $prog = "use 5.42.0; use utf8;\nmy \$_result = do { $src };\n"
             . "print \"[\", \$_result, \"]\";\n";
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog;
    close $fh;
    my $out = qx($P $f 2>&1);
    my $exit = $? >> 8;
    die "perl oracle failed (exit $exit): $out" if $exit;
    return $out;
}

# Wrap a value node in a program that PRINTS it bracketed, then returns Undef.
# A program's observable contract is stdout plus exit status, so the value has
# to reach stdout the way a source program would: Print takes a Str, so a
# non-Str value is stringified through a Coerce first, exactly as source would.
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

sub lli_run {
    my ($ret_node, $mop) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret_node, mop => $mop, program_mode => 1);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $f 2>&1);
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out" if $exit;
    return ($out, $ll);
}

# ---------------------------------------------------------------------------
# Test 1: method-simple with Call(dispatch_kind='method')
# Uses Call node instead of MethodCall; should produce same output as MethodCall.
# ---------------------------------------------------------------------------

subtest 'Call(dispatch_kind=method, name=greet): $g->greet => 42 (Int)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $body42 = $f->make('Constant', value => 42, const_type => 'integer');
    $body42->set_representation('Int');

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Greeter');
    my $m   = $cls->declare_method('greet', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body42]));
    $mop->seal;

    my $new_g = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name  => 'Greeter',
        param_names => [],
        inputs      => [],
    );
    $new_g->set_representation('Object');

    # Use Call(dispatch_kind='method') instead of MethodCall
    my $result = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'greet',
        class_name    => 'Greeter',
        inputs        => [$new_g],
    );
    $result->set_representation('Int');

    my $ret = make_print_program($f, $result, 'Int');

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop) };
    ok(!$@, "Call(method) lowering + lli succeeded: $@") or do {
        diag("Error: $@");
        return;
    };

    my $oracle = perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Greeter { method greet { return 42 } }
        my $g = Greeter->new;
        $g->greet
    });
    is($lli_out, $oracle, "lli==perl: $oracle");
};

# ---------------------------------------------------------------------------
# Test 2: Call(dispatch_kind='method') on missing method dies loudly
# ---------------------------------------------------------------------------

subtest 'Call(dispatch_kind=method) on absent method dies loudly' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $body = $f->make('Constant', value => 1, const_type => 'integer');
    $body->set_representation('Int');

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Greeter');
    my $m   = $cls->declare_method('greet', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body]));
    $mop->seal;

    my $new_g = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Greeter', param_names => [], inputs => []);
    $new_g->set_representation('Object');

    # Call 'wave' which does not exist
    my $bad = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'wave',
        class_name    => 'Greeter',
        inputs        => [$new_g],
    );
    $bad->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$bad]);

    my $died = false;
    eval { Chalk::Target::LLVM->lower($ret, mop => $mop) };
    ok($@, 'lowering dies for Call(method) on absent method');
    like($@ // '', qr/wave|absent|vtable|method/i,
        'die message mentions missing method or vtable');
};

# Branch-review I4 guards: silent-Int defaults and ABI mismatches must die.
subtest 'guard: a field with NO declared type dies GAP (no silent Int default)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    # field $name :param :reader (NO type) — the bound value is a Str; the
    # registry defaulting the repr to Int produced exit-0 garbage output.
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Untyped');
    $cls->declare_field('name', sigil => '$', attributes => [':param', ':reader']);
    $mop->seal;

    my $val = $f->make('Constant', value => 'cat', const_type => 'string');
    $val->set_representation('Str');
    my $new_o = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Untyped', param_names => ['name'], inputs => [$val]);
    $new_o->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'name',
        class_name => 'Untyped', inputs => [$new_o]);
    $call->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    eval { Chalk::Target::LLVM->lower($ret, mop => $mop) };
    like($@, qr/GAP/, 'untyped field dies GAP instead of silently lowering as Int');
};

subtest 'guard: Call(method) node repr disagreeing with the vtable ABI dies' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $body = $f->make('Constant', value => '42', const_type => 'integer');
    $body->set_representation('Int');
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Mismatch');
    my $m   = $cls->declare_method('answer', return_type => 'Int');
    $m->graph->merge($f->make_cfg('Return', inputs => [$body]));
    $mop->seal;

    my $new_o = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Mismatch', param_names => [], inputs => []);
    $new_o->set_representation('Object');
    # The node CLAIMS Str but the vtable define returns i64 — through the i8*
    # fn-ptr bitcast lli ACCEPTS the wrong-ABI call (the silent channel).
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'answer',
        class_name => 'Mismatch', inputs => [$new_o]);
    $call->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    eval { Chalk::Target::LLVM->lower($ret, mop => $mop) };
    like($@, qr/GAP|repr|ABI|mismatch/i,
        'node-vs-registry return-repr mismatch dies loudly');
};

done_testing;
