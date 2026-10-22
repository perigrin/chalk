# ABOUTME: G7 host interface — EnvRead(key) reads %ENV via the host C getenv,
# ABOUTME: libperl-free; the child lli/perl processes inherit this test's env.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Print the returned value on stdout, bracketed, instead of relying on a
# type-tag epilogue: rebuild the Return so the value flows through
# Coerce->Str into Prints hung off the graph's existing control chain.
# Three Prints (not a Concat) because Concat needs tracked lengths on both
# operands, which a Coerce'd Int does not have.
sub print_returned_value {
    my ($f, $ret_node) = @_;

    my $v = $ret_node->inputs->[0];
    my $s = $v;
    if (($v->stamp // '') ne 'Str') {
        $s = $f->make('Coerce', inputs => [$v],
            from_repr => $v->stamp, to_repr => 'Str');
        $s->set_stamp('Str');
    }

    my $open = $f->make('Constant', value => '[', const_type => 'string');
    $open->set_stamp('Str');
    my $close = $f->make('Constant', value => "]\n", const_type => 'string');
    $close->set_stamp('Str');

    my $ctrl = $ret_node->control_in // $f->make_cfg('Start');
    for my $part ($open, $s, $close) {
        my $p = $f->make('Print', inputs => [$part]);
        $p->set_control_in($ctrl);
        $ctrl = $p;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($ctrl);
    return $ret;
}

sub lli_run {
    my ($ret, %opts) = @_;
    my $factory = delete $opts{factory};
    $ret = print_returned_value($factory, $ret) if $factory;
    my $ll = Chalk::Target::LLVM->lower($ret, %opts, program_mode => 1);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out = `$LLI $f 2>&1`;
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out\n--- .ll ---\n$ll" if $exit;
    chomp $out;
    return ($out, $ll);
}

sub _mk { Chalk::IR::NodeFactory->new }

subtest 'EnvRead of a set variable returns its value' => sub {
    local $ENV{CHALK_G7_TEST} = 'hostval';
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_TEST');
    $e->set_stamp('Str');
    my $ret = $f->make_cfg('Return', inputs => [$e]);
    my ($out, $ll) = eval { lli_run($ret, factory => $f) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '[hostval]', '$ENV{CHALK_G7_TEST} read through getenv');
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        '.ll is libperl-free');
    like($ll, qr/\@getenv/, 'the read goes through the host C getenv');
};

subtest 'EnvRead of an UNSET variable prints as the empty string, as perl prints undef' => sub {
    delete local $ENV{CHALK_G7_UNSET};
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_UNSET');
    $e->set_stamp('Str');
    my $ret = $f->make_cfg('Return', inputs => [$e]);
    my ($out) = eval { lli_run($ret, factory => $f) };
    ok(!$@, 'lowering + lli succeeded (no NULL-deref)') or do { diag("error: $@"); return };
    is($out, '[]', 'missing key prints as the empty string');
};

# AN UNSET KEY IS UNDEF TO `//` AND `defined`, though it still prints as the
# empty string. Read as defined, `my $n = $ENV{N} // 3` set $n to "" and a
# `while ($i < $n)` never ran -- thirteen pvm corpus cases printed the wrong
# thing through lli (perl5-son's corpus-llvm-roundtrip.pl).
subtest 'EnvRead of an UNSET variable is undef to //' => sub {
    delete local $ENV{CHALK_G7_UNSET};
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_UNSET');
    $e->set_stamp('Str');
    my $d = $f->make('Constant', value => 'dflt', const_type => 'string');
    $d->set_stamp('Str');
    my $dor = $f->make('DefinedOr', inputs => [$e, $d]);
    $dor->set_stamp('Str');
    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    my ($out) = eval { lli_run($ret, factory => $f) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '[dflt]', 'an unset key takes the // default');
};

subtest 'EnvRead of a SET variable is defined to //' => sub {
    local $ENV{CHALK_G7_TEST} = 'hostval';
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_TEST');
    $e->set_stamp('Str');
    my $d = $f->make('Constant', value => 'dflt', const_type => 'string');
    $d->set_stamp('Str');
    my $dor = $f->make('DefinedOr', inputs => [$e, $d]);
    $dor->set_stamp('Str');
    my $ret = $f->make_cfg('Return', inputs => [$dor]);
    my ($out) = eval { lli_run($ret, factory => $f) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '[hostval]', 'a set key is its value');
};

subtest 'defined($ENV{...}) is false for an unset key' => sub {
    delete local $ENV{CHALK_G7_UNSET};
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_UNSET');
    $e->set_stamp('Str');
    my $def = $f->make('Defined', inputs => [$e]);
    $def->set_stamp('Boolean');
    my $ret = $f->make_cfg('Return', inputs => [$def]);
    my ($out) = eval { lli_run($ret, factory => $f) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '[]', 'not defined (false prints as the empty string)');
};

subtest 'EnvRead composes: length($ENV{...})' => sub {
    local $ENV{CHALK_G7_TEST} = 'sevench';
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_TEST');
    $e->set_stamp('Str');
    my $len = $f->make('Length', inputs => [$e]);
    $len->set_stamp('Int');
    my $ret = $f->make_cfg('Return', inputs => [$len]);
    my ($out) = eval { lli_run($ret, factory => $f) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '[7]', 'length of the env value (runtime strlen)');
};

# Review findings 1+2 (one trigger): EnvRead inside METHOD BODIES must
# (a) propagate _need_getenv to the module prologue (the F6 flag class —
# otherwise the .ll references an undeclared @getenv), and (b) prefix its
# key/empty globals by class/method (the @rxs_lit/@str_const symbol rule —
# otherwise two bodies both emit @env_key_0, a duplicate symbol).
subtest 'EnvRead in two method bodies: declared getenv, no duplicate globals' => sub {
    local $ENV{CHALK_G7_TEST} = 'mbody';
    require Chalk::MOP;
    my $f = _mk();

    my $mk_body = sub {
        my ($key) = @_;
        my $e = $f->make('EnvRead', key => $key);
        $e->set_stamp('Str');
        return $e;
    };

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Envy');
    my $mi_a = $cls->declare_method('env_a', return_type => 'Str');
    $mi_a->graph->merge($f->make_cfg('Return', inputs => [$mk_body->('CHALK_G7_TEST')]));
    my $mi_b = $cls->declare_method('env_b', return_type => 'Str');
    $mi_b->graph->merge($f->make_cfg('Return', inputs => [$mk_body->('CHALK_G7_OTHER')]));
    $mop->seal;

    my $new_o = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Envy', param_names => [], inputs => []);
    $new_o->set_stamp('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'env_a',
        class_name => 'Envy', inputs => [$new_o]);
    $call->set_stamp('Str');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $ll) = eval { lli_run($ret, mop => $mop, factory => $f) };
    ok(!$@, 'two method bodies with EnvRead lower + run')
        or do { diag("error: $@"); return };
    is($out, '[mbody]', 'method-body EnvRead reads the env');
    like($ll, qr/declare i8\* \@getenv/, '@getenv is declared (F6 propagation)');
    my @defs = $ll =~ /^(\@\S*env_(?:key|empty)\S*) =/mg;
    my %seen; my @dups = grep { $seen{$_}++ } @defs;
    is(scalar @dups, 0, 'no duplicate @env_* global symbols')
        or diag("duplicates: @dups");
};

done_testing;
