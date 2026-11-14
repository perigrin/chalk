# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): calls, code values and their captured cells, the call's context, die and eval frames, caller.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Call :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->_call('%Slot ' . $self->attr->{fn}) }
}
class Chalk::Target::LLVM::Node::Die :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_die') } }
class Chalk::Target::LLVM::Node::DieMsg :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_die_msg') } }
class Chalk::Target::LLVM::Node::DieUnwind :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_die_unwind') } }
class Chalk::Target::LLVM::Node::SetErr :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_set_err') } }
class Chalk::Target::LLVM::Node::EvalEnter :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_eval_enter()' } }
class Chalk::Target::LLVM::Node::EvalLeave :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_eval_leave()' } }
class Chalk::Target::LLVM::Node::ClearDying :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'store i1 0, i1* @t2_dying' } }
class Chalk::Target::LLVM::Node::IsDying :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = load i1, i1* @t2_dying' } }
class Chalk::Target::LLVM::Node::EnvNew :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot** @t2_env_new') } }
class Chalk::Target::LLVM::Node::EnvSet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_env_set') } }
class Chalk::Target::LLVM::Node::EnvGet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot* @t2_env_get') } }
class Chalk::Target::LLVM::Node::CodeNew :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        return $self->name . ' = call %Slot @t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* ' . $self->attr->{fn} . '_cw to i8*), '
            . $self->_args($self->inputs->@*) . ')';
    }
}
class Chalk::Target::LLVM::Node::CallCode :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($nm, @in) = ($self->name, $self->inputs->@*);
        return "$nm.e = call %Slot** \@t2_code_env(%Slot " . $in[0]->name . ")\n  $nm.p = call i8* \@t2_code_fn(%Slot " . $in[0]->name
            . ")\n  $nm.f = bitcast i8* $nm.p to %Slot (%Array*, %Slot**)*\n  $nm = call %Slot $nm.f(%Array* " . $in[1]->name . ", %Slot** $nm.e)";
    }
}
class Chalk::Target::LLVM::Node::SaveArgs :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_save_args(i32 %argc, i8** %argv)' } }
class Chalk::Target::LLVM::Node::GetWant :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = load i1, i1* @t2_want' } }
class Chalk::Target::LLVM::Node::SetWant :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'store i1 ' . $self->inputs->[0]->name . ', i1* @t2_want' }
}
class Chalk::Target::LLVM::Node::Argv :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Array* @t2_argv()' } }
class Chalk::Target::LLVM::Node::CodeOfFn :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        return $self->name . ' = call %Slot @t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* @t2_stash_tramp to i8*), %Slot** bitcast (%Slot (%Array*)* '
            . $self->attr->{fn} . '_w to %Slot**))';
    }
}
class Chalk::Target::LLVM::Node::FramePush :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_frame_push') } }
class Chalk::Target::LLVM::Node::FramePop :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_frame_pop()' } }
class Chalk::Target::LLVM::Node::Caller :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_caller') } }
class Chalk::Target::LLVM::Node::CallerPkg :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_caller_pkg') } }

1;
