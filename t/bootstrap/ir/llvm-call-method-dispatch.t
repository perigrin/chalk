# ABOUTME: Tests for Phase 5.1: MethodCall → Call(dispatch_kind='method') in LLVM lowering.
# ABOUTME: Verifies Call(dispatch_kind='method') lowers identically to MethodCall.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::MOP::Field;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;

my $P   = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

sub perl_oracle {
    my ($src) = @_;
    my $tag = Chalk::CodeGen::Harness::TypeTag::oracle_perl_fragment();
    my $prog = "use 5.42.0; use utf8;\nmy \$_result = do { $src };\n$tag\n";
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $prog;
    close $fh;
    my $out = qx($P $f 2>&1);
    my $exit = $? >> 8;
    die "perl oracle failed (exit $exit): $out" if $exit;
    chomp $out;
    return $out;
}

sub lli_run {
    my ($ret_node) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret_node);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx($LLI $f 2>&1);
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out" if $exit;
    chomp $out;
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

    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'greet',
        body        => [],
        body_node   => $body42,
        return_repr => 'Int',
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Greeter',
        methods => [$mi],
        fields  => [],
    );

    # New with ClassInfo
    my $new_g = $f->make('New',
        param_names => [],
        inputs      => [$ci],
    );
    $new_g->set_representation('Object');

    # Use Call(dispatch_kind='method') instead of MethodCall
    my $result = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'greet',
        inputs        => [$new_g, $ci],
    );
    $result->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    # This SHOULD fail right now (Call dispatch_kind='method' not handled = RED)
    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
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

    my $mi = Chalk::IR::MethodInfo->new(
        name        => 'greet',
        body        => [],
        body_node   => $body,
        return_repr => 'Int',
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Greeter',
        methods => [$mi],
        fields  => [],
    );

    my $new_g = $f->make('New', param_names => [], inputs => [$ci]);
    $new_g->set_representation('Object');

    # Call 'wave' which does not exist
    my $bad = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'wave',
        inputs        => [$new_g, $ci],
    );
    $bad->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$bad]);

    my $died = false;
    eval { Chalk::Target::LLVM->lower($ret) };
    ok($@, 'lowering dies for Call(method) on absent method');
    like($@ // '', qr/wave|absent|vtable|method/i,
        'die message mentions missing method or vtable');
};

done_testing;
