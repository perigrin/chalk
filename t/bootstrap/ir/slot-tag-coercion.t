# ABOUTME: Coerce[Scalar -> X] reads the %Slot tag instead of dying; Coerce[X -> Scalar] writes it.
# ABOUTME: Verified by running the emitted module under lli -- the VALUE must be right, not just the types.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;
use Chalk::Target::LLVM::Context;

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI" unless -x $LLI;

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

# Drive the emitter directly so the tag and the defined bit can be set to
# combinations no graph produces yet -- an Opaque cell, a pointer-tagged cell,
# an undefined cell whose payload is nonzero. These are exactly the cases where
# "read it as an Int" would be a guess.
sub read_slot_module ($defined, $tag, $payload, $to) {
    my $ctx  = Chalk::Target::LLVM::Context->new;
    my $slot = $ctx->_build_slot($defined, $payload, $tag, 'probe');
    my $out  = $ctx->_emit_read_slot_as($slot, $to, 'probe');

    my @body;
    for my $blk ($ctx->blocks->@*) {
        push @body, "$blk->{label}:";
        push @body, $blk->{insts}->@*;
        push @body, $blk->{terminator} if defined $blk->{terminator};
    }
    push @body, '  %p = getelementptr inbounds [9 x i8], [9 x i8]* @f, i64 0, i64 0';
    push @body, "  call i32 (i8*, ...) \@printf(i8* %p, i64 $out)";
    push @body, '  ret i32 0';

    return join "\n",
        Chalk::Target::LLVM::Context::_slot_type_decl(),
        '%Str = type { i8*, i64, i32 }',
        '%StrPair = type { i8*, i64 }',
        '@f = private unnamed_addr constant [9 x i8] c"got %lld\00"',
        'declare i32 @printf(i8*, ...)',
        # The Str arm calls this; a stub is enough because no case below is
        # Str-tagged, and the arm still has to LINK.
        'define double @chalk_str_to_num(i8* %a, i64 %b) { ret double 0.0 }',
        'define i32 @main() {',
        @body,
        '}',
        '';
}

subtest 'an undefined cell and a not-established tag both decline to read the payload' => sub {
    # Payload 42 throughout: any row that prints 42 read the payload it was
    # told not to.
    my @cases = (
        [ 'true',  'Int',      42, 42, 'a readable tag IS consulted (the control)' ],
        [ 'true',  'Opaque',   42,  0, 'Opaque declines -- NOT a fall-through to Int' ],
        [ 'false', 'Int',      42,  0, 'undef ignores the tag even when it is readable' ],
        [ 'false', 'Undef',    42,  0, 'undef with the Undef tag' ],
        [ 'true',  'Object',   42,  0, 'an Object pointer is not read as an integer' ],
        # A REFERENCE AS A NUMBER IS ITS ADDRESS in perl ($r == $s): the payload.
        [ 'true',  'ArrayRef', 42, 42, 'an ArrayRef reads as its address' ],
        [ 'true',  'HashRef',  42, 42, 'a HashRef reads as its address' ],
        [ 'true',  'CodeRef',  42, 42, 'a CodeRef reads as its address' ],
        [ 'true',  'Boolean',  42,  1, 'Boolean reads truthiness, not the payload word' ],
    );

    plan tests => scalar(@cases) * 2;

    for my $tc (@cases) {
        my ($def, $tag, $payload, $want, $desc) = @$tc;
        my ($out, $exit) = run_lli(read_slot_module($def, $tag, $payload, 'Int'));
        is($exit, 0,          "$desc: lli exits 0");
        is($out,  "got $want", "$desc");
    }
};

subtest 'the die this step removed is gone, and its arms are reachable' => sub {
    plan tests => 3;

    my $src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
        local $/;
        <$fh>;
    };

    unlike($src, qr/needs a T2 decision about how to read a/,
        'the "needs a T2 decision" die no longer exists');

    # A GAP die whose text still described Scalar as un-lowerable would be the
    # same claim under another name.
    unlike($src, qr/Scalar is \s*"?\s*lowerable, but which reading to emit is not settled/s,
        'no surviving copy of the "reading is not settled" claim');

    like($src, qr/sub _emit_read_slot_as/,
        'the tag dispatch that replaced it is present');
};

done_testing;
