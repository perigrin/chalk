# ABOUTME: Guards implicit scalar context on an aggregate (my $n = @a, 019f300f).
# ABOUTME: Assigning an array to a scalar imposes scalar context -> the count, not the ArrayRef.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);
use Chalk::Target::LLVM;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI  = '/usr/lib/llvm-15/bin/lli';

plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI"        unless -x $LLI;

# Compile a corpus_case body through B::SoN -> loader -> Target::LLVM -> lli and
# return the type-tagged value lli prints. An array in scalar context (assigned
# to a scalar pad) must yield its element count as an Int.
sub run_i64 ($body) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh "package main;\nsub corpus_case { $body }\n"; close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return (undef, "no JSON") unless $json =~ /\S/;
    my ($graphs, $mop) = from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return (undef, "no graph");
    my $ret = $g->returns->[0] or return (undef, "no Return");
    my $ll  = eval { Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ())) };
    return (undef, "lower: $@") if $@;
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    my $exit = $? >> 8;
    return (undef, "lli exit $exit: $out") if $exit != 0;
    chomp $out;
    return ($out, undef);
}

# my $n = @a: assigning an array to a scalar imposes scalar context (padsv_store
# over an aggregate value). The result is the count, exactly like `scalar @a`.
subtest 'array assigned to a scalar yields the count (019f300f)' => sub {
    my ($v, $e) = run_i64('my @a = (1, 2, 3); my $n = @a; $n');
    is($v, 'Int:3', 'my $n = @a -> Int:3 (count, not ArrayRef)') or diag($e // '');

    # Non-boundary length so a wrong count is caught.
    my ($v5, $e5) = run_i64('my @a = (10, 20, 30, 40, 50); my $n = @a; $n');
    is($v5, 'Int:5', 'my $n = @a over 5 elems -> Int:5') or diag($e5 // '');

    # Empty array -> 0.
    my ($v0, $e0) = run_i64('my @a = (); my $n = @a; $n');
    is($v0, 'Int:0', 'my $n = @a over () -> Int:0') or diag($e0 // '');
};

# A hash assigned to a scalar (my $n = %h) also imposes scalar context: the
# producer now wraps it in Length. But Length(HashRef) backend lowering is a
# SEPARATE chain link (019f3004) -- so the producer half is done here and the
# backend GAPs honestly (a loud die, not a miscompile). Assert that handoff.
subtest 'hash in scalar context: producer wraps Length, backend GAPs honestly' => sub {
    my ($v, $e) = run_i64('my %h = (a => 1, b => 2); my $n = %h; $n');
    is($v, undef, 'my $n = %h does not lower yet (Length(HashRef) is 019f3004)');
    like($e, qr/Length operand has repr=HashRef/,
        'the GAP is loud: Length(HashRef) not lowered runtime-free (not a miscompile)');
};

done_testing();
