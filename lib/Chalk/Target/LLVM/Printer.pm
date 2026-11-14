# ABOUTME: Prints T2's LLVM graph as a module's .ll text: its constants, globals, each
# ABOUTME: function's blocks (each node's to_ll), wrappers. It chooses nothing.
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Printer;

use Scalar::Util qw(refaddr);
use Chalk::Target::LLVM::Runtime;

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
    $_->set_name('%v' . $i++) for map { $_->{nodes}->@* } $bld->{blocks}->@*;
    my @L = ('; chalk T2: a graph typed in LLVM types, printed', Chalk::Target::LLVM::Runtime::prelude());
    my $strs = $bld->{strs};
    for my $s (sort { $strs->{$a} <=> $strs->{$b} } keys %$strs) {
        my $len = do { use bytes; length $s };
        push @L, sprintf('@s%d = private unnamed_addr constant [%d x i8] c"%s\00"', $strs->{$s}, $len + 1, _c($s));
    }
    push @L, "$_ = internal global %Slot zeroinitializer" for sort values +($bld->{globals} // {})->%*;
    # THE PROGRAM'S PACKAGE SCALARS BY NAME, for a string used as a reference
    # without strict refs (t2_symref).
    {
        my @add;
        my $n = 0;
        for my $name (sort grep { /\A[\w:]+::\w+\z/ && !/\Amy::/ } keys +($bld->{globals} // {})->%*) {
            my $len = do { use bytes; length $name };
            push @L, sprintf('@sym%d = private unnamed_addr constant [%d x i8] c"%s\00"', $n, $len + 1, $name);
            push @add, sprintf('  call void @t2_symtab_add(i8* getelementptr ([%d x i8], [%d x i8]* @sym%d, i64 0, i64 0), i64 %d, %%Slot* %s)', $len + 1, $len + 1, $n, $len, $bld->{globals}{$name});
            $n++;
        }
        push @L, 'define internal void @t2_symtab_init() {', @add, '  ret void', '}';
    }
    push @L, 'define i32 @main(i32 %argc, i8** %argv) {', _blocks($bld->{blocks}), '}', '';
    # AN END BLOCK'S atexit(3) ENTRY: void(), its function called.
    if ( my @x = +($bld->{atexit} // [])->@* ) {
        push @L, "define internal void \@x_$_() {", "  %r = call %Slot $x[$_ - 1]()", '  ret void', '}', '' for 1 .. @x;
    }
    # EACH SUB A FUNCTION: `%Slot (%Slot %a0, ...)`, its blocks printed alike.
    for my $fn (sort { $a->{name} cmp $b->{name} } values +($bld->{funcs} // {})->%*) {
        my $i = 0;
        $_->set_name('%v' . $i++) for map { $_->{nodes}->@* } $fn->{blocks}->@*;
        push @L, "define internal %Slot $fn->{name}(" . ( $fn->{closure} ? '%Array* %a0, %Slot** %env' : $fn->{list} ? '%Array* %a0' : join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) ) . ') {',
            _blocks($fn->{blocks}), '}', '';
        if ($fn->{closure}) {   # its code value's entry: a list context gets a list
            my @cn = $fn->{listret} ? ('  ret %Slot %r') : ('  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)', '  ret %Slot %rn');
            push @L, "define internal %Slot $fn->{name}_cw(%Array* %args, %Slot** %env) {", '  %w = load i1, i1* @t2_want',
                "  %r = call %Slot $fn->{name}(%Array* %args, %Slot** %env)", @cn, '}', '';
            next;
        }
        # ITS WRAPPER (a method's entry) gives a list context a reference to a
        # list: the sub's own (a list return), or one of its one value.
        my @norm = $fn->{listret} ? ('  ret %Slot %r') : ('  %rn = call %Slot @t2_list_of(%Slot %r, i1 %w)', '  ret %Slot %rn');
        if ($fn->{list}) {   # @_ already an %Array
            push @L, "define internal %Slot $fn->{name}_w(%Array* %args) {", '  %w = load i1, i1* @t2_want',
                "  %r = call %Slot $fn->{name}(%Array* %args)", @norm, '}', '';
            next;
        }
        # ITS WRAPPER, a method's entry: @_ as an %Array, each argument its
        # element (undef past the end). A signature's arity perl checks.
        push @L, "define internal %Slot $fn->{name}_w(%Array* %args) {", '  %w = load i1, i1* @t2_want';
        if ($fn->{signature}) {
            push @L, '  %n = call i64 @t2_alen(%Array* %args)', "  %ok = icmp eq i64 %n, $fn->{nargs}",
                '  br i1 %ok, label %call, label %bad', 'bad:',
                '  call void @t2_stop(i8* getelementptr ([68 x i8], [68 x i8]* @msg_arity, i64 0, i64 0), i64 67)',
                '  unreachable', 'call:';
        }
        push @L, "  %a$_ = call %Slot \@t2_aget(%Array* %args, i64 $_)" for 0 .. $fn->{nargs} - 1;
        push @L, "  %r = call %Slot $fn->{name}(" . join(', ', map { "%Slot %a$_" } 0 .. $fn->{nargs} - 1) . ')',
            @norm, '}', '';
    }
    return join("\n", @L);
}

sub _blocks {
    my ($blocks) = @_;
    my @L;
    for my $blk (@$blocks) {
        push @L, "$blk->{label}:";
        push @L, map { '  ' . $_->to_ll } $blk->{nodes}->@*;
        my ($k, @t) = +($blk->{term} // ['ret'])->@*;
        push @L, $k eq 'unreachable' ? '  unreachable'
               : $k eq 'ret'    ? '  ret i32 0'
               : $k eq 'retval' ? '  ret %Slot ' . $t[0]->name
               : $k eq 'br'     ? "  br label %$t[0]{label}"
               :                    "  br i1 " . $t[0]->name . ", label %$t[1]{label}, label %$t[2]{label}";
    }
    return @L;
}

sub _c { my $s = shift; $s =~ s/([^\x20-\x21\x23-\x5b\x5d-\x7e])/sprintf('\\%02X', ord $1)/ge; $s }

# A double's bits: a hex pattern as given (0x7FF0000000000000 is +Inf), else
# the value's -- which numifies "Inf" and "NaN" as perl does.
sub _double {
    my $v = shift;
    return uc($v) =~ s/^0X/0x/r if $v =~ /\A0x[0-9a-f]{16}\z/i;
    return '0x' . uc unpack('H16', pack('d>', 0 + $v));
}

1;
