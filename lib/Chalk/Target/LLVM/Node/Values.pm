# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): constants, arithmetic, comparisons, truth, conversions between representations, phis.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Const :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, %a) = ($self->type, $self->name, $self->attr->%*);
        return "$nm = add i64 0, " . ( 0 + $a{value} ) if $ty eq 'i64';
        return "$nm = fadd double 0.0, " . Chalk::Target::LLVM::Printer::_double($a{value}) if $ty eq 'double';
        return "$nm = add i1 0, " . ( $a{value} ? 1 : 0 ) if $ty eq 'i1';
        die "T2: a constant of $ty";
    }
}
class Chalk::Target::LLVM::Node::ConstStr :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my %a = $self->attr->%*; $self->name . ' = call %Str @t2_str(' . $self->_cstr($a{value}, $a{id}) . ')' }
}
class Chalk::Target::LLVM::Node::Arith :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, @in) = ($self->type, $self->name, $self->inputs->@*);
        my %a = $self->attr->%*;
        my %fop = (add => 'fadd', sub => 'fsub', mul => 'fmul', div => 'fdiv');
        my $o = $ty eq 'double' ? $fop{ $a{op} } : $a{op};
        return "$nm = $o $ty " . $in[0]->name . ', ' . $in[1]->name;
    }
}
class Chalk::Target::LLVM::Node::Cmp :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($nm, @in) = ($self->name, $self->inputs->@*);
        my %a = $self->attr->%*;
        my $t = $in[0]->type;
        my $o = $t eq 'double' ? "fcmp o$a{op}" : 'icmp ' . ( { eq => 'eq', ne => 'ne' }->{ $a{op} } // "s$a{op}" );
        $o = 'fcmp une' if $t eq 'double' && $a{op} eq 'ne';
        return "$nm = $o $t " . $in[0]->name . ', ' . $in[1]->name;
    }
}
class Chalk::Target::LLVM::Node::Undef :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_slot(i8 0, i64 0)' }
}
class Chalk::Target::LLVM::Node::Numify :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_numify') } }
class Chalk::Target::LLVM::Node::IntOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_int') } }
class Chalk::Target::LLVM::Node::Rand :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_rand') } }
class Chalk::Target::LLVM::Node::SlotStep :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_' . $self->attr->{op}) } }
class Chalk::Target::LLVM::Node::SlotArith :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_' . $self->attr->{op}) } }
class Chalk::Target::LLVM::Node::Mod :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call i64 @t2_mod(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::Div :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call double @t2_div(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::Select :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my @in = $self->inputs->@*; $self->name . ' = select i1 ' . $in[0]->name . ', ' . $self->_args( @in[ 1, 2 ] ) }
}
class Chalk::Target::LLVM::Node::SlotNeg :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_neg') } }
class Chalk::Target::LLVM::Node::Defined :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_defined') } }
class Chalk::Target::LLVM::Node::Truth :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %f = ('i64' => 't2_truth_i64', double => 't2_truth_num', '%Str' => 't2_truth_str', '%Slot' => 't2_truth_slot');
        return $self->_call( 'i1 @' . $f{ $self->inputs->[0]->type } );
    }
}
# A conversion between representations: an LLVM cast, or the runtime's.
class Chalk::Target::LLVM::Node::Convert :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, %a) = ($self->type, $self->name, $self->attr->%*);
        my $f = $Chalk::Target::LLVM::Printer::CONVERT{"$a{from}>$ty"} // die "T2: no conversion $a{from} -> $ty";
        return "$nm = $f $a{from} " . $self->inputs->[0]->name . " to $ty" if $f =~ /\A(?:sitofp|zext|fptosi)\z/;
        return $self->_call("$ty \@$f");
    }
}
class Chalk::Target::LLVM::Node::Phi :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, @in) = ($self->type, $self->name, $self->inputs->@*);
        my %a = $self->attr->%*;
        return "$nm = phi $ty " . join(', ', map { '[ ' . $in[$_]->name . ", %$a{from}[$_]{label} ]" } 0 .. $#in);
    }
}
# A sub's argument: named by its function's header, never a line of its own.
class Chalk::Target::LLVM::Node::Arg :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { die 'T2: cannot print ' . $self->op }
}

1;
