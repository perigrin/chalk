# ABOUTME: Adversarial tests for Stringify(Int)->Str LLVM lowering (I6 coerce).
# ABOUTME: lli output must match the perl oracle for positive, negative, and zero ints.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Return;
use Chalk::Target::LLVM;
use Chalk::CodeGen::Harness::TypeTag;

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

sub run_lli {
    my ($ll_text) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll_text;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

# Build a graph: Constant(int :Int) -> Stringify :Str -> Return.
# The producer emits Stringify for a non-Str operand of an interpolation Concat;
# here we exercise the backend arm in isolation (the Stringify IS the return
# value, so its Str face is what the epilogue prints via Str:%.*s).
sub make_stringify_int_graph {
    my ($int_val) = @_;
    my $f = Chalk::IR::NodeFactory->new;

    my $c = $f->make('Constant', value => $int_val, const_type => 'number');
    $c->set_representation('Int');

    my $s = $f->make('Stringify', inputs => [$c]);
    $s->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$s]);
    return $ret;
}

# The decimal digits of the int, printed as a Str: the tag is "Str:<digits>".
my @cases = (
    [3,     "Str:3",     "single positive digit"],
    [42,    "Str:42",    "multi positive digits"],
    [0,     "Str:0",     "zero (loop would emit no digit -- special-cased)"],
    [-5,    "Str:-5",    "negative single digit (sign + digit-count length)"],
    [-123,  "Str:-123",  "negative multi digit"],
    [1000,  "Str:1000",  "trailing zeros preserved"],
);

subtest 'Stringify(Int)->Str: lli == expected decimal face' => sub {
    plan tests => scalar(@cases) * 3;

    for my $tc (@cases) {
        my ($int, $expected_tag, $desc) = @$tc;

        my $ret_node = make_stringify_int_graph($int);
        my $ll = eval { Chalk::Target::LLVM->lower($ret_node) };
        if ($@) {
            fail("$desc: LLVM lowering failed: $@");
            fail("$desc: (skip)");
            fail("$desc: (skip)");
            next;
        }

        my ($lli_out, $lli_exit) = run_lli($ll);

        is($lli_exit, 0, "$desc: lli exits 0");
        is($lli_out, $expected_tag, "$desc: lli output '$lli_out' == '$expected_tag'");
        ok($ll !~ /Perl_|\bSV\b|sv_|libperl/, "$desc: .ll is libperl-free");
    }
};

done_testing;
