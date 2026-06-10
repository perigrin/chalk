# ABOUTME: Tests for Phase 5.2: New → Call(dispatch_kind='method', name='new') in LLVM lowering.
# ABOUTME: Verifies Call(dispatch_kind='method', name='new') lowers identically to New.
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
# Test 1: Call(dispatch_kind='method', name='new') for class-simple
# ---------------------------------------------------------------------------

subtest 'Call(name=new): class-simple ref($e) => "Empty" (Str)' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Empty',
        methods => [],
        fields  => [],
    );

    # Use Call(name='new') instead of New node
    my $new_e = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'new',
        inputs        => [$ci],
        param_names   => [],
    );
    $new_e->set_representation('Object');

    my $ref_result = $f->make('Ref', inputs => [$new_e]);
    $ref_result->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$ref_result]);

    # This SHOULD fail right now (Call name='new' not handled = RED)
    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "Call(new) lowering + lli succeeded: $@") or do {
        diag("Error: $@");
        return;
    };

    my $oracle = perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Empty { }
        my $e = Empty->new;
        ref($e)
    });
    is($lli_out, $oracle, "lli==perl: $oracle");
};

# ---------------------------------------------------------------------------
# Test 2: Call(name='new') with :param fields
# ---------------------------------------------------------------------------

subtest 'Call(name=new): field-attrs Pair->new(left=>10, right=>20), left+right => 30' => sub {
    my $f = Chalk::IR::NodeFactory->new;

    my $mf_l = Chalk::MOP::Field->new(
        name       => 'left',
        sigil      => '$',
        class      => undef,
        fieldix    => 0,
        type       => 'Int',
        attributes => [':param', ':reader'],
    );
    my $mf_r = Chalk::MOP::Field->new(
        name       => 'right',
        sigil      => '$',
        class      => undef,
        fieldix    => 1,
        type       => 'Int',
        attributes => [':param', ':reader'],
    );

    my $ci = Chalk::IR::ClassInfo->new(
        name    => 'Pair',
        fields  => [$mf_l, $mf_r],
        methods => [],
    );

    my $lval = $f->make('Constant', value => 10, const_type => 'integer');
    $lval->set_representation('Int');
    my $rval = $f->make('Constant', value => 20, const_type => 'integer');
    $rval->set_representation('Int');

    # Call(name='new') with :param values
    my $new_p = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'new',
        inputs        => [$ci, $lval, $rval],
        param_names   => ['left', 'right'],
    );
    $new_p->set_representation('Object');

    my $lr = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'left',
        inputs        => [$new_p, $ci],
    );
    $lr->set_representation('Int');

    my $rr = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'right',
        inputs        => [$new_p, $ci],
    );
    $rr->set_representation('Int');

    my $result = $f->make('Add', inputs => [$lr, $rr]);
    $result->set_representation('Int');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret) };
    ok(!$@, "Call(new) with :param fields succeeded: $@") or do {
        diag("Error: $@");
        return;
    };

    my $oracle = perl_oracle(q{
        use feature 'class'; no warnings 'experimental::class';
        class Pair {
            field $left  :param :reader;
            field $right :param :reader;
        }
        my $p = Pair->new(left => 10, right => 20);
        $p->left + $p->right
    });
    is($lli_out, $oracle, "lli==perl: $oracle");
};

done_testing;
