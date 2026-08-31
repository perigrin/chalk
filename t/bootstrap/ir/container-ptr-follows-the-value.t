# ABOUTME: A container's typed pointer is resolved from what the value IS, not its stamp.
# ABOUTME: The ArrayRef constructor always yields i8*, whatever repr the node carries.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# WHY: `_container_ptr` bitcasts i8* -> %Array* only when the node's
# representation is exactly 'ArrayRef'. But `_lower_array_ref` ALWAYS returns
# the boxed i8* -- its own comment calls that "the canonical ref result". So a
# node stamped `Array` (not `ArrayRef`) got the i8* handed straight to a GEP
# expecting %Array*, and lli rejected the module:
#
#   error: '%tmp_26' defined with type 'i8*' but expected '%Array*'
#     %tmp_27 = getelementptr inbounds %Array, %Array* %tmp_26, i32 0, i32 0
#
# The stamp and the emitted value disagreed. The same defect class as the
# inlined-argument repr drift: a decision made from a recorded fact that the
# emission had already moved past.

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI" unless -x $LLI;

my $wire = do {
    open my $fh, '<', 't/bootstrap/ir/data/foreach-lexical-array.json'
        or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
my $driver = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no driver graph';
my ($ret)  = $driver->returns->@*;

my $ll = eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
my $err = $@;

subtest 'it lowers' => sub {
    ok defined $ll, 'lower() returned' or diag "died: $err";
};

subtest 'every %Array GEP receives an %Array*, never a raw i8*' => sub {
    plan skip_all => 'did not lower' unless defined $ll;

    # Collect the SSA names that hold an i8* (the boxed form), then check none
    # of them is the operand of a %Array/%Hash GEP.
    my %is_i8p;
    $is_i8p{$1} = 1 while $ll =~ /(\S+) = bitcast \S+ \S+ to i8\*/g;

    my @bad;
    while ($ll =~ /getelementptr inbounds %(Array|Hash), %\1\* (\S+),/g) {
        my ($kind, $operand) = ($1, $2);
        push @bad, "$operand fed to a %$kind GEP but holds an i8*"
            if $is_i8p{$operand};
    }
    is scalar(@bad), 0, 'no boxed pointer reaches a typed GEP'
        or diag join "\n", @bad;
};

subtest 'it runs and agrees with perl' => sub {
    plan skip_all => 'did not lower' unless defined $ll;
    my $dir = $ENV{TMPDIR} // '/tmp';
    my $f   = "$dir/chalk-d3b-$$.ll";
    open my $fh, '>', $f or die $!;
    print $fh $ll;
    close $fh;
    my $out = qx{$LLI $f 2>&1};
    my $rc  = $? >> 8;
    unlink $f;
    is $rc,  0,      'lli exits 0' or diag $out;
    is $out, "60\n", 'prints 60 (10+20+30), as perl does';
};

done_testing;
