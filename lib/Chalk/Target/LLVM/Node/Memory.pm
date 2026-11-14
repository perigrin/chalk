# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): variables kept in memory, scalar references and package variables by their global.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Alloca :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my $nm = $self->name;
        return "$nm = alloca %Slot  ; my " . $self->attr->{name} . "\n  store %Slot zeroinitializer, %Slot* $nm";
    }
}
class Chalk::Target::LLVM::Node::HeapCell :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot* @t2_cell_new()  ; my ' . $self->attr->{name} . ', captured' }
}
class Chalk::Target::LLVM::Node::Load :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = load %Slot, %Slot* ' . $self->inputs->[0]->name }
}
class Chalk::Target::LLVM::Node::Store :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my @in = $self->inputs->@*; 'store %Slot ' . $in[0]->name . ', %Slot* ' . $in[1]->name }
}
# A scalar deref of a string: its message and package as constants.
class Chalk::Target::LLVM::Node::SDeref :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $at = $self->_cstr($a{msg}, $a{id}) . ', ' . $self->_cstr($a{pk}, $a{pkid});
        return $self->name . ' = call %Slot @t2_sderef(' . $self->_args($self->inputs->@*) . ", i1 $a{strict}, $at)";
    }
}
class Chalk::Target::LLVM::Node::SStore :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $at = $self->_cstr($a{msg}, $a{id}) . ', ' . $self->_cstr($a{pk}, $a{pkid});
        return 'call void @t2_sstore(' . $self->_args($self->inputs->@*) . ", i1 $a{strict}, $at)";
    }
}
class Chalk::Target::LLVM::Node::SRef :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_sref(%Slot* ' . $self->inputs->[0]->name . ')' }
}
class Chalk::Target::LLVM::Node::SCell :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my ($nm, $p) = ($self->name, $self->inputs->[0]->name); "$nm.p = extractvalue %Slot $p, 1\n  $nm = inttoptr i64 $nm.p to %Slot*" }
}
# A package variable, by its global.
class Chalk::Target::LLVM::Node::GLoad :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = load %Slot, %Slot* ' . $self->attr->{global} }
}
class Chalk::Target::LLVM::Node::GHash :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_ghash(%Slot* ' . $self->attr->{global} . ')' }
}
class Chalk::Target::LLVM::Node::GArray :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Array* @t2_garray(%Slot* ' . $self->attr->{global} . ')' }
}
class Chalk::Target::LLVM::Node::GAddr :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = getelementptr %Slot, %Slot* ' . $self->attr->{global} . ', i64 0' }
}
class Chalk::Target::LLVM::Node::GStore :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'store %Slot ' . $self->inputs->[0]->name . ', %Slot* ' . $self->attr->{global} }
}
class Chalk::Target::LLVM::Node::KindOfRef :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_kind_of_ref') } }

1;
