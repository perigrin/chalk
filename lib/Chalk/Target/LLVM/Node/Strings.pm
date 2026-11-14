# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): string operations through the runtime: concat, compare, case, length, substr, index, join.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Concat :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_concat') } }
class Chalk::Target::LLVM::Node::StrCmp :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_strcmp') } }
class Chalk::Target::LLVM::Node::StrCase :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_strcase') } }
class Chalk::Target::LLVM::Node::StrLen :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = extractvalue %Str ' . $self->inputs->[0]->name . ', 1' }
}
class Chalk::Target::LLVM::Node::SlotLength :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_length') } }
class Chalk::Target::LLVM::Node::Join :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_join') } }
class Chalk::Target::LLVM::Node::Substr :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_substr') } }
class Chalk::Target::LLVM::Node::SubstrRep :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_substr_rep') } }
class Chalk::Target::LLVM::Node::Index :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_index') } }

1;
