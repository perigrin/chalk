# ABOUTME: A method call is emitted at the ABI type and unboxed to the node's repr.
# ABOUTME: Calling at the narrower type reads the callee's %Slot as a raw i64.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# THE CONTRACT, already stated at Context.pm:7881 before this test existed:
# "THE CALL IS AT THE ABI; THE NODE MAY KNOW MORE. When the vtable declares
# Scalar the callee returns %Slot, but this node's repr may have been refined
# to something narrower -- Int <: Scalar. ... The refinement is honoured at the
# boundary, not by calling at the narrower type: the callee has ONE emitted
# body at ONE machine type."
#
# The unbox arm implementing that was unreachable: $result_repr was the NODE's
# repr, so `$result_repr eq 'Scalar'` was false exactly when the callee did
# return a %Slot, and the fn-ptr cast named `i64 (i8*)` for a `%Slot (i8*)`
# function.
#
# TWO EARLIER ATTEMPTS FAILED HERE, both by changing the CALLEE to match the
# node -- narrowing the vtable entry, then the metaobject. Both emitted
# 4622382067542392832 for perl's 11: 11.0's bits read as an i64. This asserts
# the VALUE, not merely that a module lowers, because that is the only check
# that separated a fix from a miscompile.

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found" unless -x $LLI;

my $wire = do {
    open my $fh, '<', 't/bootstrap/ir/data/method-call-abi-boundary.json'
        or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
my $driver = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no driver';
my $mop    = $driver->mop                   or plan skip_all => 'no mop';
my ($ret)  = $driver->returns->@*;

subtest 'the disagreement this exercises is real' => sub {
    my ($counter) = grep { $_->name eq 'Counter' } $mop->classes;
    ok $counter, 'class Counter present' or return;
    my ($val) = grep { $_->name eq 'val' } $counter->methods;
    is +($val ? $val->return_type : undef), 'Scalar',
        'the metaobject declares val returns Scalar';

    my ($call) = grep {
        $_->operation eq 'Call'
            && ($_->can('dispatch_kind') ? ($_->dispatch_kind // '') : '') eq 'method'
            && ($_->name // '') eq 'val'
    } $driver->nodes->@*;
    is +($call ? $call->representation : undef), 'Int',
        'the call site node was narrowed to Int';
};

my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1, mop => $mop) };
my $err = $@;

subtest 'it lowers' => sub {
    ok defined $ll, 'lower() returned' or diag "died: $err";
};

subtest 'the call is emitted at the ABI type, not the node type' => sub {
    plan skip_all => 'did not lower' unless defined $ll;
    like $ll, qr/call %Slot \S+\(i8\* \S+\).*Call\(method\) val/,
        'val is called at %Slot, the type its body returns';
    like $ll, qr/extractvalue %Slot .*Call\(method\) val: Slot payload/,
        'and the payload is unboxed at the call site';
};

subtest 'it runs and agrees with perl' => sub {
    plan skip_all => 'did not lower' unless defined $ll;
    my $f = ($ENV{TMPDIR} // '/tmp') . "/chalk-abi-$$.ll";
    open my $fh, '>', $f or die $!;
    binmode $fh, ':utf8';
    print $fh $ll;
    close $fh;
    my $out = qx{$LLI $f 2>&1};
    my $rc  = $? >> 8;
    unlink $f;
    is $rc,  0,      'lli exits 0' or diag $out;
    is $out, "11\n", 'prints 11 -- NOT 4622382067542392832 (11.0 read as i64)';
};

done_testing;
