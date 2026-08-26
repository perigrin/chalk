# ABOUTME: Guards direct named-sub call lowering (corpus subs.md F1, zhi 019f51e7-82c6).
# ABOUTME: `sub foo { return 1 } foo()` must lower end-to-end and return Int:1.

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

# Compile a full source file (which may define named subs alongside
# corpus_case) through B::SoN -> loader -> Target::LLVM -> lli and return the
# type-tagged value lli prints for corpus_case. A direct named-sub call
# (dispatch_kind=direct) must resolve its callee graph and lower to its result.
sub run_i64 ($src) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh "package main;\n$src\n"; close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return (undef, "no JSON") unless $json =~ /\S/;
    my $graphs = from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    my $g = $graphs->{'main::corpus_case'} or return (undef, "no graph");
    my $ret = $g->returns->[0] or return (undef, "no Return");
    my $ll  = Chalk::Target::LLVM->lower($ret, (defined $mop ? (mop => $mop) : ()));
    my ($lfh, $lltmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lfh $ll; close $lfh;
    my $out = qx($LLI $lltmp 2>&1);
    my $exit = $? >> 8;
    return (undef, "lli exit $exit: $out") if $exit != 0;
    chomp $out;
    return ($out, undef);
}

# F1: a direct named-sub call with no args. The callee returns Int:1; the call
# site must resolve `foo` to its graph and lower to that constant. The perl
# oracle for `sub foo { return 1 } foo()` is Int:1.
subtest 'F1: direct named-sub call returns the callee result (019f51e7)' => sub {
    my ($v, $e) = run_i64("sub foo { return 1 }\nsub corpus_case { foo() }");
    is($v, 'Int:1', 'foo() -> Int:1') or diag($e // '');
};

# Teeth: the callee name must be DERIVED from the call, not hardcoded to "foo"
# and not returning a fixed 1. A differently-named sub returning a different
# value must lower to that sub's result -- a hardcoded-name or fixed-value
# shortcut would fail here while passing the foo/1 case above.
subtest 'F1 teeth: a renamed sub with a different value resolves correctly' => sub {
    my ($v7) = run_i64("sub bar { return 7 }\nsub corpus_case { bar() }");
    is($v7, 'Int:7', 'bar() -> Int:7 (name derived, not hardcoded to foo)');

    my ($v42) = run_i64("sub answer { return 42 }\nsub corpus_case { answer() }");
    is($v42, 'Int:42', 'answer() -> Int:42 (value from callee, not fixed 1)');

    # Two subs defined; the call must select the RIGHT one by name.
    my ($vsel) = run_i64("sub aaa { return 3 }\nsub bbb { return 9 }\nsub corpus_case { bbb() }");
    is($vsel, 'Int:9', 'bbb() among {aaa,bbb} selects bbb -> Int:9');
};

done_testing();
