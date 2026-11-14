# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): hashes through the runtime.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::HNew :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Slot @t2_hnew()' } }
class Chalk::Target::LLVM::Node::HSet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_hset') } }
class Chalk::Target::LLVM::Node::HGet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_hget') } }
class Chalk::Target::LLVM::Node::HExists :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_hexists') } }
class Chalk::Target::LLVM::Node::HDelete :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_hdelete') } }
class Chalk::Target::LLVM::Node::HFromArray :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_hfroma') } }
class Chalk::Target::LLVM::Node::HCount :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_hcount') } }
class Chalk::Target::LLVM::Node::HKeys :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hkeys') } }
class Chalk::Target::LLVM::Node::HPairs :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hpairs') } }
class Chalk::Target::LLVM::Node::HValues :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hvalues') } }
class Chalk::Target::LLVM::Node::HDerefR :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_hderef_r') } }
class Chalk::Target::LLVM::Node::HAssign :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_hassign') } }

1;
