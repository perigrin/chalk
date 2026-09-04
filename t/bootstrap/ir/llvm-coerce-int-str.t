# ABOUTME: Adversarial tests for Coerce(Int -> Str) LLVM lowering (I6 coerce).
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

# Build a program: Constant(int :Int) -> Coerce(Int -> Str) -> Print -> Return(Undef).
# The producer emits this coercion for a non-Str operand of an interpolation
# Concat, of a print/say argument, or of an `eq`; a print argument is exactly
# what this builds, so the backend arm is exercised the way a real program
# reaches it. The Coerce result is already Str, so Print takes it directly —
# no bridging coercion needed.
#
# The value is bracketed by literal sentinels so an empty result would be
# distinguishable from no output at all. (No case here is empty, which makes
# these the non-empty control for the empty-valued cases elsewhere in the
# suite.)
#
# This was a distinct `Stringify` node until it was merged into Coerce — the two
# implemented the same X->Str edge and had already diverged.
#
# Returns the Return node plus the :Str node: printing erases the Int-vs-Str
# distinction the old Str: tag carried (a Str "3" and an Int 3 both print "3"),
# so the caller asserts that half on the node.
sub make_stringify_int_graph {
    my ($int_val) = @_;
    my $f = Chalk::IR::NodeFactory->new;

    my $c = $f->make('Constant', value => $int_val, const_type => 'number');
    $c->set_stamp('Int');

    my $s = $f->make('Coerce', inputs => [$c],
                     from_repr => 'Int', to_repr => 'Str');
    $s->set_stamp('Str');

    my $lb = $f->make('Constant', value => '[', const_type => 'string');
    $lb->set_stamp('Str');
    my $rb = $f->make('Constant', value => ']', const_type => 'string');
    $rb->set_stamp('Str');

    my $start = $f->make_cfg('Start');
    my $print = $f->make('Print', inputs => [$lb, $s, $rb]);
    $print->set_control_in($start);

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);

    return ($ret, $s);
}

# The decimal digits of the int, as a program prints them.
my @cases = (
    [3,     "3",     "single positive digit"],
    [42,    "42",    "multi positive digits"],
    [0,     "0",     "zero (loop would emit no digit -- special-cased)"],
    [-5,    "-5",    "negative single digit (sign + digit-count length)"],
    [-123,  "-123",  "negative multi digit"],
    [1000,  "1000",  "trailing zeros preserved"],
);

my $P = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";

subtest q{Coerce(Int -> Str): printed decimal face == perl} => sub {
    plan tests => scalar(@cases) * 5;

    for my $tc (@cases) {
        my ($int, $expected, $desc) = @$tc;

        my ($ret_node, $str_node) = make_stringify_int_graph($int);

        # The type half of the old Str: tag — unrecoverable from stdout, since
        # a Str "3" and an Int 3 both print as "3".
        is($str_node->stamp, 'Str',
            "$desc: the coerced node is Str-repr (the type half of the old tag)");

        my $ll = eval { Chalk::Target::LLVM->lower($ret_node, program_mode => 1) };
        if ($@) {
            fail("$desc: LLVM lowering failed: $@");
            fail("$desc: (skip)");
            fail("$desc: (skip)");
            fail("$desc: (skip)");
            next;
        }

        my ($lli_out, $lli_exit) = run_lli($ll);

        is($lli_exit, 0, "$desc: lli exits 0");
        is($lli_out, "[$expected]", "$desc: printed '$lli_out' == '[$expected]'");

        # Cross-check against live perl, so the table is not the only oracle.
        my $perl_out = scalar qx{$P -e 'print "[", $int, "]"' 2>/dev/null};
        is($lli_out, $perl_out, "$desc: printed face matches perl ('$perl_out')");

        ok($ll !~ /Perl_|\bSV\b|sv_|libperl/, "$desc: .ll is libperl-free");
    }
};

done_testing;
