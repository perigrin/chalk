# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): the run-time MOP: bless, a reference's class and type, stashes, @ISA, method resolution.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Bless :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_bless') } }
class Chalk::Target::LLVM::Node::ClassOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_class_of') } }
class Chalk::Target::LLVM::Node::RefType :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_reftype') } }
class Chalk::Target::LLVM::Node::MopUniversal :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_universal_setup()' } }
class Chalk::Target::LLVM::Node::MopVar :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_mop_var(' . $self->_args($self->inputs->@*) . ', %Slot* ' . $self->attr->{global} . ')' }
}
class Chalk::Target::LLVM::Node::MopClass :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_mop_class') } }
class Chalk::Target::LLVM::Node::MopIsa :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_mop_isa') } }
class Chalk::Target::LLVM::Node::MopIsaArr :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_mop_isa_arr') } }
class Chalk::Target::LLVM::Node::MopIsaSet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_mop_isa_set') } }
class Chalk::Target::LLVM::Node::MopDef :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_mop_def(' . $self->_args($self->inputs->@*) . ', i8* bitcast (%Slot (%Array*)* ' . $self->attr->{fn} . '_w to i8*))' }
}
class Chalk::Target::LLVM::Node::MResolve :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call i8* @t2_mresolve(' . $self->_args($self->inputs->@*) . ', i8 ' . $self->attr->{mode} . ')' }
}
class Chalk::Target::LLVM::Node::MCall :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($nm, @in) = ($self->name, $self->inputs->@*);
        return "$nm.f = bitcast i8* " . $in[0]->name . " to %Slot (%Array*)*\n  $nm = call %Slot $nm.f(%Array* " . $in[1]->name . ')';
    }
}

1;
