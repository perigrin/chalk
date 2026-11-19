# ABOUTME: Coerce[Scalar -> X] reads the %Slot tag instead of dying; Coerce[X -> Scalar] writes it.
# ABOUTME: Verified by running the emitted module under lli -- the VALUE must be right, not just the types.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;

sub run_lli ($ll_text) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll_text;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ($out, $exit);
}

# Round-trip a constant through the uniform cell: Constant(:$from) ->
# Coerce(from -> Scalar) -> Coerce(Scalar -> $to) -> print -> Return.
#
# The BOX writes the tag from the source repr; the READ dispatches on it. If the
# tag were dropped, ignored, or overwritten with a guess, the read would take
# the wrong arm and the printed value would be wrong -- which is why this test
# checks the value under lli rather than grepping the .ll for instructions.
#
# The value is observed the way a program observes one: PRINTED on stdout,
# bracketed so a correctly-printed empty string is distinguishable from nothing
# printed at all. Each wrong-arm failure mode this file exists to catch is a
# wrong VALUE, not merely a wrong type -- a Num payload read as an Int would
# print the raw bit pattern rather than 3, and a %StrPair pointer read as an
# integer would print a heap address -- so the discrimination survives the loss
# of the type tag. Three Prints rather than a Concat: a Coerce'd Int has no
# tracked length.
sub roundtrip_graph ($from, $value, $to) {
    my $f = Chalk::IR::NodeFactory->new;

    my $c = $f->make('Constant', value => $value,
                     const_type => ($from eq 'Str' ? 'string' : 'number'));
    $c->set_stamp($from);

    my $box = $f->make('Coerce', inputs => [$c],
                       from_repr => $from, to_repr => 'Scalar');
    $box->set_stamp('Scalar');

    my $read = $f->make('Coerce', inputs => [$box],
                        from_repr => 'Scalar', to_repr => $to);
    $read->set_stamp($to);

    my $str = $read;
    if ($to ne 'Str') {
        $str = $f->make('Coerce', inputs => [$read],
                        from_repr => $to, to_repr => 'Str');
        $str->set_stamp('Str');
    }

    my $ctrl = $f->make_cfg('Start');
    for my $part ('[', $str, "]\n") {
        my $val = ref $part ? $part : do {
            my $k = $f->make('Constant', value => $part, const_type => 'string');
            $k->set_stamp('Str');
            $k;
        };
        my $pr = $f->make('Print', inputs => [$val]);
        $pr->set_control_in($ctrl);
        $ctrl = $pr;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($ctrl);
    return $ret;
}

subtest 'Coerce[Scalar -> X] reads the tag: every reading, every target' => sub {
    # The oracle is perl itself. Each row is (source repr, literal, target repr,
    # what the program must print on stdout).
    my @cases = (
        # An Int-tagged payload read as each target.
        [ Int => 7,       Int     => '[7]'   ],
        [ Int => 7,       Num     => '[7]'   ],
        [ Int => 42,      Str     => '[42]'  ],
        [ Int => 7,       Boolean => '[1]'   ],
        [ Int => 0,       Boolean => '[]'    ],

        # A Num-tagged payload. These are the rows that fail if the tag is
        # ignored: the payload is a bitcast double, so reading it as an Int
        # yields the raw bit pattern rather than 3.
        [ Num => 3.5,     Num     => '[3.5]' ],
        [ Num => 3.5,     Int     => '[3]'   ],
        [ Num => 3.5,     Str     => '[3.5]' ],
        [ Num => 3.5,     Boolean => '[1]'   ],
        [ Num => 0.0,     Boolean => '[]'    ],

        # A Str-tagged payload is a %StrPair POINTER. Read as an integer it
        # would be a heap address; the tag is what keeps it a string.
        [ Str => 'hello', Str     => '[hello]' ],
        [ Str => '12abc', Num     => '[12]'    ],
        [ Str => '12abc', Int     => '[12]'    ],
        [ Str => '12abc', Boolean => '[1]'     ],
        [ Str => '0',     Boolean => '[]'      ],
        [ Str => '',      Boolean => '[]'      ],
        [ Str => 'abc',   Boolean => '[1]'     ],
    );

    plan tests => scalar(@cases) * 2;

    for my $tc (@cases) {
        my ($from, $value, $to, $want) = @$tc;
        my $desc = "$from(" . (length $value ? $value : q{''}) . ") -> Scalar -> $to";

        my $ll = eval { Chalk::Target::LLVM->lower(roundtrip_graph($from, $value, $to), program_mode => 1) };
        if ($@) {
            fail("$desc: lowering failed: $@");
            fail("$desc: (skipped)");
            next;
        }

        my ($out, $exit) = run_lli($ll);
        is($exit, 0,     "$desc: lli exits 0");
        is($out,  $want, "$desc: lli printed '$out'");
    }
};

done_testing;
