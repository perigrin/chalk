# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): the run-time MOP: bless, a reference's class and type, stashes, @ISA, method resolution.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Bless :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_bless') } }
class Chalk::Target::LLVM::Node::ClassOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_class_of') } }
class Chalk::Target::LLVM::Node::RefType :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_reftype') } }
class Chalk::Target::LLVM::Node::ReferentType :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_referent_type') } }
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
# a sub by its package and name from the run-time stash (t2_sub_find): its wrapper, or perl's die.
class Chalk::Target::LLVM::Node::SubFind :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i8* @t2_sub_find') } }
class Chalk::Target::LLVM::Node::MResolve :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call i8* @t2_mresolve(' . $self->_args($self->inputs->@*) . ', i8 ' . $self->attr->{mode} . ')' }
}
class Chalk::Target::LLVM::Node::MCall :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($nm, @in) = ($self->name, $self->inputs->@*);
        return "$nm.f = bitcast i8* " . $in[0]->name . " to %Slot (%Array*)*\n  $nm = call %Slot $nm.f(%Array* " . $in[1]->name . ')';
    }
}

# A SPECIAL CONTAINER'S METAOBJECT, a MOP object (Chalk::Impl::*): installed
# on its hash at start-up -- no tie (tied is false).
class Chalk::Target::LLVM::Node::MopHash :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_mop_hash') } }
# THE HANDLER TABLE warn and die ask: %SIG's hash, held where the runtime finds it.
class Chalk::Target::LLVM::Node::SigTable :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_sig_set') } }
class Chalk::Target::LLVM::Node::IsaOp :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_isa_op') } }
class Chalk::Target::LLVM::Node::DynName :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_dyn_name') } }

1;
