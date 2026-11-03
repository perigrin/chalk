# ABOUTME: T2 for LLVM -- a program built as a new graph typed in LLVM's types (the repr
# ABOUTME: chosen once, here), then printed. Slice 1: straight-line. Out of scope: undef.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

# T1 is the Perl graph: its stamps are Perl types. T2 is the target's graph:
# each node carries the LLVM type its value is (perigrin, 2026-11-03). It is
# built fresh -- T1 is never mutated -- and may change shape: a conversion
# between representations is a node of its own (Convert), and so is a call of
# the runtime. Printing T2 decides nothing.
#
# THE REPRESENTATION IS CHOSEN HERE, ONCE. A merge whose arms are of one type
# is that type; arms of different types (a Num and a Str: T1 says Str) are a
# %Slot, each arm boxed into it, read back by its tag. That is the case T1's
# stamp-as-repr got wrong: `$c ? 0.1 + 0.2 : "x"` held as a %Str was its
# printed digits, and compared equal to 0.3.
#
# SLICE 1 is a program with no subs, loops or aggregates: constants,
# arithmetic, numeric comparisons, ?: and //, Concat, an %ENV read, print.
# Any other node makes the whole program fall back to Context.pm (lower
# returns undef), so the slice can only ever add programs, never break one.

class Chalk::Target::LLVM::T2::Node {
    field $op     :param :reader;
    field $type   :param :reader;           # i64 | double | i1 | %Str | %Slot | void
    field $inputs :param :reader = [];
    field $attr   :param :reader = {};
    field $name   :reader;                  # its SSA name, given by the printer
    method set_name ($n) { $name = $n }
}

package Chalk::Target::LLVM::T2;

use Scalar::Util qw(blessed refaddr);

# Undef and a Scalar nothing narrowed are each a %Slot: its tag says which.
my %SCALAR = (Int => 'i64', Num => 'double', Str => '%Str', Boolean => 'i1', Undef => '%Slot', Scalar => '%Slot');
my %ARITH  = (Add => 'add', Subtract => 'sub', Multiply => 'mul');
my %CMP    = (NumLt => 'lt', NumGt => 'gt', NumLe => 'le', NumGe => 'ge', NumEq => 'eq', NumNe => 'ne');

sub _n { Chalk::Target::LLVM::T2::Node->new(@_) }

# lower_program($return_node) -> the module's text, or undef when the program
# is not slice 1's.
sub lower_program {
    my ($class, $ret) = @_;
    my $b = bless { blocks => [], cur => undef, memo => {}, strs => {} }, 'Chalk::Target::LLVM::T2::Builder';
    my $ok = eval { $b->build($ret); 1 };
    return undef unless $ok;
    return Chalk::Target::LLVM::T2::Printer::print_module($b);
}

package Chalk::Target::LLVM::T2::Builder;

use Scalar::Util qw(blessed refaddr);

sub out { die "T2: out of its slices ($_[0])\n" }

sub new_block {
    my ($b, $label) = @_;
    my $blk = { label => $label . scalar(@{ $b->{blocks} }), nodes => [], term => undef };
    push @{ $b->{blocks} }, $blk;
    return $b->{cur} = $blk;
}

sub emit {
    my ($b, %a) = @_;
    my $n = Chalk::Target::LLVM::T2::_n(%a);
    push @{ $b->{cur}{nodes} }, $n;
    return $n;
}

# The program: its control chain walked forward from Start to its Return.
sub build {
    my ($b, $ret) = @_;
    out('no Return') unless blessed($ret) && $ret->operation eq 'Return';
    # Back to Start: through a merge's Region and a loop's exit Proj.
    my $start = $ret;
    for (1 .. 100_000) {
        last if $start->operation eq 'Start';
        $start = $start->can('control_in') && blessed($start->control_in) ? $start->control_in
               : $start->operation =~ /\A(?:Region|Proj)\z/ ? $start->inputs->[0]
               : out('no way back to Start from ' . $start->operation);
    }
    $b->{ret} = $ret;
    $b->new_block('entry');
    $b->walk($start);
    $b->{cur}{term} = [ 'ret' ];
}

# successors($ctl) -> the nodes whose control is $ctl, each once.
sub successors {
    my ($ctl) = @_;
    my %seen;
    return grep { blessed($_) && $_->can('control_in') && blessed($_->control_in)
                  && refaddr($_->control_in) == refaddr($ctl) && !$seen{ refaddr($_) }++ }
           ( $ctl->consumers // [] )->@*;
}

# walk($ctl): the statements after $ctl, in order, to a Return or the end of
# a body. A statement of a kind T2 does not have makes the program fall back:
# skipped, its effect would be lost.
sub walk {
    my ($b, $ctl) = @_;
    while (1) {
        my @s = successors($ctl);
        # ONLY THE PROGRAM'S Return ends it: another hung on the same control is
        # not this program's (a graph built over an earlier one).
        @s = grep { $_->operation ne 'Return' || refaddr($_) == refaddr($b->{ret}) } @s;
        return unless @s;
        out('a control node with ' . scalar(@s) . ' successors') if @s > 1;
        my $s = $s[0];
        my $op = $s->operation;
        return if $op eq 'Return';
        if ($op eq 'Print') {
            # One print of each argument, in order (perl prints the list).
            $b->emit(op => 'Print', type => 'void', inputs => [ $b->as($b->value($_), '%Str') ]) for $s->inputs->@*;
            $ctl = $s;
        }
        elsif ($op eq 'Loop') { $ctl = $b->loop($s) }
        else { out("a statement $op") }
    }
}

# loop($Loop) -> the control node the program continues from: a header of
# phis (each its initial value, then the body's) and the condition, a body
# walked forward back to the header, and an exit.
sub loop {
    my ($b, $L) = @_;
    my %proj = map { ( $_->index => $_ ) } grep { $_->operation eq 'Proj' } successors_by_input($L);
    my ($bodyp, $exitp) = @proj{0, 1};
    out('a loop without a body and an exit') unless $bodyp && $exitp;
    my @phis = grep { $_->operation eq 'Phi' && blessed($_->region) && refaddr($_->region) == refaddr($L)
                      && !Chalk::Target::LLVM::Context::_is_memory_phi($_) } ( $L->consumers // [] )->@*;
    my %seen;
    @phis = grep { !$seen{ refaddr($_) }++ } @phis;
    my @cond = grep { $_->operation !~ /\A(?:Phi|Proj)\z/ } successors($L);
    out('a loop condition that is not one value') unless @cond == 1;
    out('a loop phi with other than two ways in') if grep { scalar( @{ $_->inputs } ) != 2 } @phis;

    my $pre = $b->{cur};
    my @init = map { $b->as($b->value($_->inputs->[0]), $b->loop_type($_)) } @phis;
    my $pre_end = $b->{cur};
    my $head = $b->new_block('loop');
    $pre_end->{term} = [ 'br', $head ];
    # THE PHI IS MADE NOW, ITS BACK EDGE WHEN THE BODY IS: the body reads it.
    my @t2 = map {
        my $p = $b->emit(op => 'Phi', type => $b->loop_type($phis[$_]), inputs => [ $init[$_] ], attr => { from => [$pre_end] });
        $b->{memo}{ refaddr( $phis[$_] ) } = $p;
    } 0 .. $#phis;
    my $cond = $b->truth($b->value($cond[0]));
    my $head_end = $b->{cur};
    my $body = $b->new_block('body');
    my @back;
    {
        # A value made in the body is the body's: not seen after the loop.
        local $b->{memo} = { %{ $b->{memo} } };
        $b->walk($bodyp);
        @back = map { $b->as($b->value($phis[$_]->inputs->[1]), $t2[$_]->type) } 0 .. $#phis;
    }
    my $body_end = $b->{cur};
    $body_end->{term} = [ 'br', $head ];
    for my $i (0 .. $#t2) {
        push @{ $t2[$i]->inputs }, $back[$i];
        push @{ $t2[$i]->attr->{from} }, $body_end;
    }
    my $exit = $b->new_block('exit');
    $head_end->{term} = [ 'condbr', $cond, $body, $exit ];
    my ($region) = grep { $_->operation eq 'Region' } ( $exitp->consumers // [] )->@*;
    return $region // $exitp;
}

# successors_by_input($n) -> the nodes that take $n as an input (a Loop's Projs).
sub successors_by_input {
    my ($n) = @_;
    my %seen;
    return grep { blessed($_) && grep({ blessed($_) && refaddr($_) == refaddr($n) } $_->inputs->@*) && !$seen{ refaddr($_) }++ }
           ( $n->consumers // [] )->@*;
}

# A LOOP PHI'S TYPE: its stamp, except a Str one, which a Num may reach on a
# later pass -- boxed, as a merge of differing arms is.
sub loop_type {
    my ($b, $phi) = @_;
    my $st = $phi->stamp // ''; # static type
    return '%Slot' if $st eq 'Str';
    return $SCALAR{$st} // out("a loop phi stamped $st");
}

# The T2 type a T1 value is, decided once.
sub type_of {
    my ($b, $v) = @_;
    my $op = $v->operation;
    return '%Slot' if $op eq 'EnvRead' || $op eq 'DefinedOr';   # may be undef
    if ($op eq 'TernaryExpr') {
        my %t = map { ( $b->type_of($_) => 1 ) } $v->inputs->@[1, 2];
        return keys %t == 1 ? ( keys %t )[0] : '%Slot';
    }
    my $st = $v->stamp // ''; # static type
    return $SCALAR{$st} // out("a value stamped $st ($op)");
}

# value($t1) -> the T2 node for a T1 value, built once.
sub value {
    my ($b, $v) = @_;
    return $b->{memo}{ refaddr($v) } //= $b->_value($v);
}

sub _value {
    my ($b, $v) = @_;
    my $op = $v->operation;
    my $ty = $b->type_of($v);
    if ($op eq 'Constant') {
        my $c = $v->value;
        return $b->emit(op => 'Undef', type => '%Slot') if $ty eq '%Slot';
        return $b->emit(op => 'Const', type => $ty, attr => { value => $c }) if $ty ne '%Str';
        $b->{strs}{$c} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'ConstStr', type => '%Str', attr => { value => $c, id => $b->{strs}{$c} });
    }
    if ($op eq 'Coerce') {
        # TO Undef IS NOT A CONVERSION: undef has no value to convert into, and
        # boxing the value would keep it.
        out('a coercion to Undef') if ( $v->stamp // '' ) eq 'Undef'; # static type
        return $b->as($b->value($v->inputs->[0]), $ty);
    }
    if ($op eq 'Divide') {
        # A DIVISION T1 TYPED Int is T1's error (7/2 is 3.5): not truncated here.
        out('a Divide typed Int') if $ty eq 'i64';
        # PERL DIVIDES AS NUMBERS and dies on a zero divisor, naming where.
        my $msg = "Illegal division by zero at " . ( $v->can('file') && $v->file // '-' )
                 . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
        $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
        my $q = $b->emit(op => 'Div', type => 'double',
            inputs => [ map { $b->as($b->value($_), 'double') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
        return $b->as($q, $ty);
    }
    if ($op eq 'Modulo') {
        # PERL'S % IS OF INTEGERS, its sign the right side's, and dies on zero.
        out('a % not typed Int') unless $ty eq 'i64';
        my $msg = "Illegal modulus zero at " . ( $v->can('file') && $v->file // '-' )
                 . " line " . ( $v->can('line') && $v->line // 0 ) . ".\n";
        $b->{strs}{$msg} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'Mod', type => 'i64',
            inputs => [ map { $b->as($b->value($_), 'i64') } $v->inputs->@[0, 1] ],
            attr => { msg => $msg, id => $b->{strs}{$msg} });
    }
    if (my $a = $ARITH{$op}) {
        my @in = map { $b->as($b->value($_), $ty) } $v->inputs->@[0, 1];
        return $b->emit(op => 'Arith', type => $ty, inputs => \@in, attr => { op => $a });
    }
    if (my $c = $CMP{$op}) {
        my @in = map { $b->value($_) } $v->inputs->@[0, 1];
        my $t = ( grep { $_->type ne 'i64' } @in ) ? 'double' : 'i64';
        return $b->emit(op => 'Cmp', type => 'i1', inputs => [ map { $b->as($_, $t) } @in ], attr => { op => $c });
    }
    if ($op eq 'Concat') {
        return $b->emit(op => 'Concat', type => '%Str', inputs => [ map { $b->as($b->value($_), '%Str') } $v->inputs->@[0, 1] ]);
    }
    if ($op eq 'EnvRead') {
        my $k = $v->key // out('an EnvRead with no key');
        $b->{strs}{$k} //= scalar keys %{ $b->{strs} };
        return $b->emit(op => 'Env', type => '%Slot', attr => { key => $k, id => $b->{strs}{$k} });
    }
    if ($op eq 'DefinedOr' || $op eq 'TernaryExpr') {
        # A MERGE: its condition, an arm built in each block, a phi at the join.
        my ($cond, $then, $else);
        if ($op eq 'TernaryExpr') {
            ($cond, $then, $else) = $v->inputs->@*;
            $cond = $b->truth($b->value($cond));
        }
        else {
            my $lhs = $b->value($v->inputs->[0]);
            out('a // whose left side is not a Slot') unless $lhs->type eq '%Slot';
            $cond = $b->emit(op => 'Defined', type => 'i1', inputs => [$lhs]);
            ($then, $else) = ($lhs, $v->inputs->[1]);
        }
        my $from = $b->{cur};
        # A VALUE MADE IN AN ARM IS THE ARM'S: it does not dominate the join, so
        # it is not seen after it (each arm gets the memo as it was before).
        my $tb = $b->new_block('then');
        my ($tv, $ev);
        { local $b->{memo} = { %{ $b->{memo} } };
          $tv = $b->as( blessed($then) && $then->isa('Chalk::Target::LLVM::T2::Node') ? $then : $b->value($then), $ty ); }
        my $tend = $b->{cur};
        my $eb = $b->new_block('else');
        { local $b->{memo} = { %{ $b->{memo} } };
          $ev = $b->as($b->value($else), $ty); }
        my $eend = $b->{cur};
        my $jb = $b->new_block('join');
        $from->{term} = [ 'condbr', $cond, $tb, $eb ];
        $tend->{term} = [ 'br', $jb ];
        $eend->{term} = [ 'br', $jb ];
        return $b->emit(op => 'Phi', type => $ty, inputs => [ $tv, $ev ], attr => { from => [ $tend, $eend ] });
    }
    out($op);
}

# truth($node) -> an i1: perl's truth of a value of any slice type.
sub truth {
    my ($b, $n) = @_;
    return $n if $n->type eq 'i1';
    return $b->emit(op => 'Truth', type => 'i1', inputs => [$n]);
}

# as($node, $type) -> the node converted to that type (itself if it is one).
sub as {
    my ($b, $n, $ty) = @_;
    return $n if $n->type eq $ty;
    return $b->emit(op => 'Convert', type => $ty, inputs => [$n], attr => { from => $n->type });
}

package Chalk::Target::LLVM::T2::Printer;

use Scalar::Util qw(refaddr);

# THE CONVERSIONS T2 HAS, from>to: the builder asks here before it makes one
# (a program needing another falls back), the printer prints from it.
our %CONVERT = (
    'i64>double' => 'sitofp', 'i64>%Str' => 't2_i64_str', 'double>%Str' => 't2_num_str',
    '%Str>double' => 't2_str_num', 'i1>%Str' => 't2_bool_str', 'i64>%Slot' => 't2_box_i64',
    'double>%Slot' => 't2_box_num', '%Str>%Slot' => 't2_box_str', '%Slot>double' => 't2_slot_num',
    '%Slot>%Str' => 't2_slot_str', 'i1>i64' => 'zext', 'i1>double' => 't2_bool_num',
    '%Slot>i64' => 't2_slot_i64', '%Str>i64' => 't2_str_i64', 'double>i64' => 'fptosi',
    'i64>i1' => 't2_truth_i64', 'double>i1' => 't2_truth_num', '%Str>i1' => 't2_truth_str',
    '%Slot>i1' => 't2_truth_slot', 'i1>%Slot' => 't2_box_bool',
);

# The printer names each node, then writes one line (or a runtime call) per
# node. It chooses nothing: every type is already on the node.
sub print_module {
    my ($bld) = @_;   # not $b: sort below uses $a and $b
    my $i = 0;
    $_->set_name('%v' . $i++) for map { @{ $_->{nodes} } } @{ $bld->{blocks} };
    my @L = ('; chalk T2: a graph typed in LLVM types, printed', _prelude());
    my $strs = $bld->{strs};
    for my $s (sort { $strs->{$a} <=> $strs->{$b} } keys %$strs) {
        my $len = do { use bytes; length $s };
        push @L, sprintf('@s%d = private unnamed_addr constant [%d x i8] c"%s\00"', $strs->{$s}, $len + 1, _c($s));
    }
    push @L, 'define i32 @main() {';
    for my $blk (@{ $bld->{blocks} }) {
        push @L, "$blk->{label}:";
        push @L, map { '  ' . _line($_) } @{ $blk->{nodes} };
        my ($k, @t) = @{ $blk->{term} // ['ret'] };
        push @L, $k eq 'ret' ? '  ret i32 0'
               : $k eq 'br'  ? "  br label %$t[0]{label}"
               :               "  br i1 " . $t[0]->name . ", label %$t[1]{label}, label %$t[2]{label}";
    }
    push @L, '}', '';
    return join("\n", @L);
}

sub _c { my $s = shift; $s =~ s/([^\x20-\x21\x23-\x5b\x5d-\x7e])/sprintf('\\%02X', ord $1)/ge; $s }

sub _line {
    my ($n) = @_;
    my ($op, $ty, $nm, @in) = ($n->op, $n->type, $n->name, @{ $n->inputs });
    my %a = %{ $n->attr };
    my $arg = sub { join ', ', map { $_->type . ' ' . $_->name } @_ };
    if ($op eq 'Const') {
        return "$nm = add i64 0, " . ( 0 + $a{value} ) if $ty eq 'i64';
        return "$nm = fadd double 0.0, " . _double($a{value}) if $ty eq 'double';
        return "$nm = add i1 0, " . ( $a{value} ? 1 : 0 ) if $ty eq 'i1';
        die "T2: a constant of $ty";
    }
    if ($op eq 'ConstStr') {
        my $len = do { use bytes; length $a{value} };
        return "$nm = call %Str \@t2_str(i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    if ($op eq 'Env') {
        my $len = do { use bytes; length $a{key} };
        return "$nm = call %Slot \@t2_env(i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0))";
    }
    if ($op eq 'Arith') {
        my %fop = (add => 'fadd', sub => 'fsub', mul => 'fmul', div => 'fdiv');
        my $o = $ty eq 'double' ? $fop{ $a{op} } : $a{op};
        return "$nm = $o $ty " . $in[0]->name . ', ' . $in[1]->name;
    }
    if ($op eq 'Cmp') {
        my $t = $in[0]->type;
        my $o = $t eq 'double' ? "fcmp o$a{op}" : 'icmp ' . ( { eq => 'eq', ne => 'ne' }->{ $a{op} } // "s$a{op}" );
        $o = 'fcmp une' if $t eq 'double' && $a{op} eq 'ne';
        return "$nm = $o $t " . $in[0]->name . ', ' . $in[1]->name;
    }
    return "$nm = call %Slot \@t2_slot(i8 0, i64 0)" if $op eq 'Undef';
    if ($op eq 'Mod') {
        my $len = do { use bytes; length $a{msg} };
        return "$nm = call i64 \@t2_mod(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    if ($op eq 'Div') {
        my $len = do { use bytes; length $a{msg} };
        return "$nm = call double \@t2_div(" . $arg->(@in) . ", i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$a{id}, i64 0, i64 0), i64 $len)";
    }
    return "$nm = call %Str \@t2_concat(" . $arg->(@in) . ')' if $op eq 'Concat';
    return "call void \@t2_print(" . $arg->(@in) . ')' if $op eq 'Print';
    return "$nm = call i1 \@t2_defined(" . $arg->(@in) . ')' if $op eq 'Defined';
    if ($op eq 'Truth') {
        my %f = ('i64' => 't2_truth_i64', double => 't2_truth_num', '%Str' => 't2_truth_str', '%Slot' => 't2_truth_slot');
        return "$nm = call i1 \@$f{ $in[0]->type }(" . $arg->(@in) . ')';
    }
    if ($op eq 'Convert') {
        my $f = $CONVERT{"$a{from}>$ty"} // die "T2: no conversion $a{from} -> $ty";
        return "$nm = $f $a{from} " . $in[0]->name . " to $ty" if $f =~ /\A(?:sitofp|zext|fptosi)\z/;
        return "$nm = call $ty \@$f(" . $arg->(@in) . ')';
    }
    if ($op eq 'Phi') {
        return "$nm = phi $ty " . join(', ', map { '[ ' . $in[$_]->name . ", %$a{from}[$_]{label} ]" } 0 .. $#in);
    }
    die "T2: cannot print $op";
}

# A double's bits: a hex pattern as given (0x7FF0000000000000 is +Inf), else
# the value's -- which numifies "Inf" and "NaN" as perl does.
sub _double {
    my $v = shift;
    return uc($v) =~ s/^0X/0x/r if $v =~ /\A0x[0-9a-f]{16}\z/i;
    return '0x' . uc unpack('H16', pack('d>', 0 + $v));
}

# The runtime a slice-1 module calls: %Str is { i8*, i64 }; %Slot is a tag
# (0 undef, 1 Int, 2 Num, 3 Str) and an i64 payload (a Num's bits, a Str's
# heap pointer). Numbers print as perl prints them: %.15g, Inf, -Inf, NaN.
sub _prelude { return <<'LL' }
%Str = type { i8*, i64 }
%Slot = type { i8, i64 }
declare i32 @snprintf(i8*, i64, i8*, ...)
declare i8* @malloc(i64)
declare i8* @memcpy(i8*, i8*, i64)
declare i8* @getenv(i8*)
declare i64 @strlen(i8*)
declare double @strtod(i8*, i8**)
declare i64 @write(i32, i8*, i64)
@fmt_g = private unnamed_addr constant [6 x i8] c"%.15g\00"
@fmt_d = private unnamed_addr constant [4 x i8] c"%ld\00"
@lit_inf = private unnamed_addr constant [4 x i8] c"Inf\00"
@lit_ninf = private unnamed_addr constant [5 x i8] c"-Inf\00"
@lit_nan = private unnamed_addr constant [4 x i8] c"NaN\00"
@lit_one = private unnamed_addr constant [2 x i8] c"1\00"
@lit_zero = private unnamed_addr constant [2 x i8] c"0\00"
define internal %Str @t2_str(i8* %p, i64 %n) {
  %a = insertvalue %Str undef, i8* %p, 0
  %b = insertvalue %Str %a, i64 %n, 1
  ret %Str %b
}
define internal void @t2_print(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  call i64 @write(i32 1, i8* %p, i64 %n)
  ret void
}
define internal %Str @t2_concat(%Str %x, %Str %y) {
  %xp = extractvalue %Str %x, 0
  %xn = extractvalue %Str %x, 1
  %yp = extractvalue %Str %y, 0
  %yn = extractvalue %Str %y, 1
  %n = add i64 %xn, %yn
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %xp, i64 %xn)
  %mid = getelementptr i8, i8* %buf, i64 %xn
  call i8* @memcpy(i8* %mid, i8* %yp, i64 %yn)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_i64_str(i64 %v) {
  %buf = call i8* @malloc(i64 24)
  %f = getelementptr [4 x i8], [4 x i8]* @fmt_d, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 24, i8* %f, i64 %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal %Str @t2_num_str(double %v) {
entry:
  %nan = fcmp uno double %v, %v
  br i1 %nan, label %isnan, label %notnan
isnan:
  %pn = getelementptr [4 x i8], [4 x i8]* @lit_nan, i64 0, i64 0
  %rn = call %Str @t2_str(i8* %pn, i64 3)
  ret %Str %rn
notnan:
  %pinf = fcmp oeq double %v, 0x7FF0000000000000
  br i1 %pinf, label %ispinf, label %notpinf
ispinf:
  %pi = getelementptr [4 x i8], [4 x i8]* @lit_inf, i64 0, i64 0
  %ri = call %Str @t2_str(i8* %pi, i64 3)
  ret %Str %ri
notpinf:
  %ninf = fcmp oeq double %v, 0xFFF0000000000000
  br i1 %ninf, label %isninf, label %finite
isninf:
  %pm = getelementptr [5 x i8], [5 x i8]* @lit_ninf, i64 0, i64 0
  %rm = call %Str @t2_str(i8* %pm, i64 4)
  ret %Str %rm
finite:
  %zero = fcmp oeq double %v, 0.0
  br i1 %zero, label %iszero, label %nonzero
iszero:
  %pz = getelementptr [2 x i8], [2 x i8]* @lit_zero, i64 0, i64 0
  %rz = call %Str @t2_str(i8* %pz, i64 1)
  ret %Str %rz
nonzero:
  %buf = call i8* @malloc(i64 32)
  %f = getelementptr [6 x i8], [6 x i8]* @fmt_g, i64 0, i64 0
  %n32 = call i32 (i8*, i64, i8*, ...) @snprintf(i8* %buf, i64 32, i8* %f, double %v)
  %n = sext i32 %n32 to i64
  %r = call %Str @t2_str(i8* %buf, i64 %n)
  ret %Str %r
}
define internal double @t2_str_num(%Str %s) {
  %p = extractvalue %Str %s, 0
  %n = extractvalue %Str %s, 1
  %n1 = add i64 %n, 1
  %buf = call i8* @malloc(i64 %n1)
  call i8* @memcpy(i8* %buf, i8* %p, i64 %n)
  %end = getelementptr i8, i8* %buf, i64 %n
  store i8 0, i8* %end
  %d = call double @strtod(i8* %buf, i8** null)
  ret double %d
}
define internal i64 @t2_str_i64(%Str %s) {
  %d = call double @t2_str_num(%Str %s)
  %i = fptosi double %d to i64
  ret i64 %i
}
define internal %Str @t2_bool_str(i1 %b) {
  %p = getelementptr [2 x i8], [2 x i8]* @lit_one, i64 0, i64 0
  %n = zext i1 %b to i64
  %r = call %Str @t2_str(i8* %p, i64 %n)
  ret %Str %r
}
define internal double @t2_bool_num(i1 %b) {
  %d = uitofp i1 %b to double
  ret double %d
}
define internal %Slot @t2_slot(i8 %t, i64 %v) {
  %a = insertvalue %Slot undef, i8 %t, 0
  %b = insertvalue %Slot %a, i64 %v, 1
  ret %Slot %b
}
define internal %Slot @t2_box_i64(i64 %v) {
  %s = call %Slot @t2_slot(i8 1, i64 %v)
  ret %Slot %s
}
define internal %Slot @t2_box_num(double %v) {
  %i = bitcast double %v to i64
  %s = call %Slot @t2_slot(i8 2, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_box_str(%Str %v) {
  %m = call i8* @malloc(i64 16)
  %p = bitcast i8* %m to %Str*
  store %Str %v, %Str* %p
  %i = ptrtoint %Str* %p to i64
  %s = call %Slot @t2_slot(i8 3, i64 %i)
  ret %Slot %s
}
define internal %Slot @t2_env(i8* %k) {
entry:
  %v = call i8* @getenv(i8* %k)
  %none = icmp eq i8* %v, null
  br i1 %none, label %undef, label %set
undef:
  %u = call %Slot @t2_slot(i8 0, i64 0)
  ret %Slot %u
set:
  %n = call i64 @strlen(i8* %v)
  %s = call %Str @t2_str(i8* %v, i64 %n)
  %b = call %Slot @t2_box_str(%Str %s)
  ret %Slot %b
}
define internal %Slot @t2_box_bool(i1 %b) {
entry:
  br i1 %b, label %t, label %f
t:
  %one = call %Slot @t2_box_i64(i64 1)
  ret %Slot %one
f:
  %e = call %Str @t2_str(i8* null, i64 0)
  %no = call %Slot @t2_box_str(%Str %e)
  ret %Slot %no
}
declare void @exit(i32)
define internal double @t2_div(double %x, double %y, i8* %msg, i64 %n) {
entry:
  %z = fcmp oeq double %y, 0.0
  br i1 %z, label %die, label %ok
die:
  call i64 @write(i32 2, i8* %msg, i64 %n)
  call void @exit(i32 255)
  unreachable
ok:
  %q = fdiv double %x, %y
  ret double %q
}
define internal i64 @t2_mod(i64 %x, i64 %y, i8* %msg, i64 %n) {
entry:
  %z = icmp eq i64 %y, 0
  br i1 %z, label %die, label %ok
die:
  call i64 @write(i32 2, i8* %msg, i64 %n)
  call void @exit(i32 255)
  unreachable
ok:
  %r = srem i64 %x, %y
  %rnz = icmp ne i64 %r, 0
  %rneg = icmp slt i64 %r, 0
  %yneg = icmp slt i64 %y, 0
  %diff = xor i1 %rneg, %yneg
  %fix = and i1 %rnz, %diff
  %r2 = add i64 %r, %y
  %res = select i1 %fix, i64 %r2, i64 %r
  ret i64 %res
}
define internal i1 @t2_defined(%Slot %s) {
  %t = extractvalue %Slot %s, 0
  %d = icmp ne i8 %t, 0
  ret i1 %d
}
define internal double @t2_slot_num(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str ]
int:
  %di = sitofp i64 %v to double
  ret double %di
num:
  %dn = bitcast i64 %v to double
  ret double %dn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %ds = call double @t2_str_num(%Str %sv)
  ret double %ds
undef:
  ret double 0.0
}
define internal i64 @t2_slot_i64(%Slot %s) {
  %d = call double @t2_slot_num(%Slot %s)
  %i = fptosi double %d to i64
  ret i64 %i
}
define internal %Str @t2_slot_str(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str ]
int:
  %si = call %Str @t2_i64_str(i64 %v)
  ret %Str %si
num:
  %dn = bitcast i64 %v to double
  %sn = call %Str @t2_num_str(double %dn)
  ret %Str %sn
str:
  %p = inttoptr i64 %v to %Str*
  %ss = load %Str, %Str* %p
  ret %Str %ss
undef:
  %e = call %Str @t2_str(i8* null, i64 0)
  ret %Str %e
}
define internal i1 @t2_truth_i64(i64 %v) {
  %b = icmp ne i64 %v, 0
  ret i1 %b
}
define internal i1 @t2_truth_num(double %v) {
  %b = fcmp une double %v, 0.0
  ret i1 %b
}
define internal i1 @t2_truth_str(%Str %s) {
entry:
  %n = extractvalue %Str %s, 1
  %empty = icmp eq i64 %n, 0
  br i1 %empty, label %no, label %one
one:
  %is1 = icmp eq i64 %n, 1
  br i1 %is1, label %check, label %yes
check:
  %p = extractvalue %Str %s, 0
  %c = load i8, i8* %p
  %zero = icmp eq i8 %c, 48
  br i1 %zero, label %no, label %yes
yes:
  ret i1 1
no:
  ret i1 0
}
define internal i1 @t2_truth_slot(%Slot %s) {
entry:
  %t = extractvalue %Slot %s, 0
  %v = extractvalue %Slot %s, 1
  switch i8 %t, label %undef [ i8 1, label %int
                               i8 2, label %num
                               i8 3, label %str ]
int:
  %bi = icmp ne i64 %v, 0
  ret i1 %bi
num:
  %d = bitcast i64 %v to double
  %bn = fcmp une double %d, 0.0
  ret i1 %bn
str:
  %p = inttoptr i64 %v to %Str*
  %sv = load %Str, %Str* %p
  %bs = call i1 @t2_truth_str(%Str %sv)
  ret i1 %bs
undef:
  ret i1 0
}
LL

1;
