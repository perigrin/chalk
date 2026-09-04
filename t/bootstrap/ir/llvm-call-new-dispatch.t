# ABOUTME: Tests for Call(dispatch_kind='method', name='new') construction in LLVM lowering.
# ABOUTME: Verifies Call(new) resolves class structure through the sealed-MOP class registry.
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

sub perl_oracle {
    my ($src) = @_;
    my $prog = "use 5.42.0; use utf8;\n"
             . "my \$_result = do { $src };\n"
             . "print '[', \$_result // '', \"]\\n\";\n";
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

# Print the returned value on stdout, bracketed, instead of relying on a
# type-tag epilogue: rebuild the Return so the value flows through
# Coerce->Str into a Print hung off the graph's existing control chain.
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
    my ($ret_node, $mop, $factory) = @_;
    $ret_node = print_returned_value($factory, $ret_node) if $factory;
    my $ll = Chalk::Target::LLVM->lower($ret_node, mop => $mop, program_mode => 1);
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

    my $mop = Chalk::MOP->new;
    $mop->declare_class('Empty');
    $mop->seal;

    # Use Call(name='new') instead of New node
    my $new_e = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'new',
        class_name    => 'Empty',
        inputs        => [],
        param_names   => [],
    );
    $new_e->set_stamp('Object');

    my $ref_result = $f->make(q{RefType}, inputs => [$new_e]);
    $ref_result->set_stamp('Str');

    my $ret = $f->make_cfg('Return', inputs => [$ref_result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop, $f) };
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

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pair');
    $cls->declare_field('left', sigil => '$', type => 'Int',
        attributes => [':param', ':reader']);
    $cls->declare_field('right', sigil => '$', type => 'Int',
        attributes => [':param', ':reader']);
    $mop->seal;

    my $lval = $f->make('Constant', value => 10, const_type => 'integer');
    $lval->set_stamp('Int');
    my $rval = $f->make('Constant', value => 20, const_type => 'integer');
    $rval->set_stamp('Int');

    # Call(name='new') with :param values
    my $new_p = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'new',
        class_name    => 'Pair',
        inputs        => [$lval, $rval],
        param_names   => ['left', 'right'],
    );
    $new_p->set_stamp('Object');

    my $lr = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'left',
        class_name    => 'Pair',
        inputs        => [$new_p],
    );
    $lr->set_stamp('Int');

    my $rr = $f->make('Call',
        dispatch_kind => 'method',
        name          => 'right',
        class_name    => 'Pair',
        inputs        => [$new_p],
    );
    $rr->set_stamp('Int');

    my $result = $f->make('Add', inputs => [$lr, $rr]);
    $result->set_stamp('Int');

    my $ret = $f->make_cfg('Return', inputs => [$result]);

    my ($lli_out, $ll_text);
    eval { ($lli_out, $ll_text) = lli_run($ret, $mop, $f) };
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
