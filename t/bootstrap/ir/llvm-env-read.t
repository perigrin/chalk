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
    my ($ret) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret);
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

done_testing;
