# ABOUTME: An inlined positional argument binds its REPRESENTATION, not just an SSA ref.
# ABOUTME: A Scalar-stamped node holding a bound i64 makes every consumer read it wrongly.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# WHY: `_arg_bind` substitutes the caller's already-lowered SSA ref for a
# callee's positional arg-read (`$_[0]` or `shift @_`), keyed by refaddr. It
# replaced the VALUE and left the callee node's representation alone. So a
# `Subscript` stamped `Scalar` came to hold a bare `i64`, and the surrounding
# `Coerce[Scalar -> Num]` emitted a %Slot tag dispatch against a non-Slot:
#
#   error: '%tmp_1' defined with type 'i64' but expected '%Slot'
#
# The binding has to carry the repr, because the repr is what every consumer
# uses to decide how to read the value.

my $wire = do {
    open my $fh, '<', 't/bootstrap/ir/data/positional-arg-inline.json'
        or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
my $driver = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no driver graph';
my ($ret)  = $driver->returns->@*;

# program_mode => 1 as the corpus driver passes it (LLVMDriver.pm:68): it
# suppresses the Int:/Str: return-value epilogue, which is a debug aid rather
# than program output. Without it this probe sees a trailing "Undef:" line that
# the corpus never sees.
my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
my $err = $@;

subtest 'the module lowers at all' => sub {
    ok defined $ll, 'lower() returned' or diag "died: $err";
};

subtest 'no tag dispatch is emitted against a non-Slot value' => sub {
    plan skip_all => 'did not lower' unless defined $ll;

    # The specific corruption: an extractvalue %Slot whose operand was never
    # built as a Slot. We cannot typecheck here, so assert the SHAPE that
    # caused it -- a Scalar coercion inside an inlined body whose input is the
    # bound argument.
    my @slot_reads = ($ll =~ /extractvalue %Slot (\S+),/g);
    my %built;
    $built{$1} = 1 while $ll =~ /(\S+) = insertvalue %Slot/g;
    $built{$1} = 1 while $ll =~ /(\S+) = phi %Slot/g;
    $built{$1} = 1 while $ll =~ /(\S+) = load %Slot/g;
    $built{$1} = 1 while $ll =~ /(\S+) = call %Slot/g;

    my @orphans = grep { !$built{$_} } @slot_reads;
    is scalar(@orphans), 0, 'every %Slot read has a %Slot producer'
        or diag "orphaned Slot reads: @orphans";
};

subtest 'it runs and agrees with perl' => sub {
    plan skip_all => 'did not lower' unless defined $ll;
    my $dir = $ENV{TMPDIR} // '/tmp';
    my $f   = "$dir/chalk-f8-$$.ll";
    open my $fh, '>', $f or die $!;
    print $fh $ll;
    close $fh;
    my $out = qx{/usr/lib/llvm-15/bin/lli $f 2>&1};
    my $rc  = $? >> 8;
    unlink $f;
    is $rc, 0, 'lli exits 0' or diag $out;
    is $out, "11\n", 'prints 11, as perl does';
};

done_testing;
