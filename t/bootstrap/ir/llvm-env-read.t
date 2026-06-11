# ABOUTME: G7 host interface — EnvRead(key) reads %ENV via the host C getenv,
# ABOUTME: libperl-free; the child lli/perl processes inherit this test's env.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

sub lli_run {
    my ($ret, %opts) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret, %opts);
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
    $e->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$e]);
    my ($out, $ll) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Str:hostval', '$ENV{CHALK_G7_TEST} read through getenv');
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        '.ll is libperl-free');
    like($ll, qr/\@getenv/, 'the read goes through the host C getenv');
};

subtest 'EnvRead of an UNSET variable yields the empty string (documented divergence: perl gives undef)' => sub {
    delete local $ENV{CHALK_G7_UNSET};
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_UNSET');
    $e->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$e]);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded (no NULL-deref)') or do { diag("error: $@"); return };
    is($out, 'Str:', 'missing key reads as the empty string (undef face = tracked follow-up)');
};

subtest 'EnvRead composes: length($ENV{...})' => sub {
    local $ENV{CHALK_G7_TEST} = 'sevench';
    my $f = _mk();
    my $e = $f->make('EnvRead', key => 'CHALK_G7_TEST');
    $e->set_representation('Str');
    my $len = $f->make('Length', inputs => [$e]);
    $len->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$len]);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Int:7', 'length of the env value (runtime strlen)');
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
        $e->set_representation('Str');
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
    $new_o->set_representation('Object');
    my $call = $f->make('Call', dispatch_kind => 'method', name => 'env_a',
        class_name => 'Envy', inputs => [$new_o]);
    $call->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$call]);

    my ($out, $ll) = eval { lli_run($ret, mop => $mop) };
    ok(!$@, 'two method bodies with EnvRead lower + run')
        or do { diag("error: $@"); return };
    is($out, 'Str:mbody', 'method-body EnvRead reads the env');
    like($ll, qr/declare i8\* \@getenv/, '@getenv is declared (F6 propagation)');
    my @defs = $ll =~ /^(\@\S*env_(?:key|empty)\S*) =/mg;
    my %seen; my @dups = grep { $seen{$_}++ } @defs;
    is(scalar @dups, 0, 'no duplicate @env_* global symbols')
        or diag("duplicates: @dups");
};

done_testing;
