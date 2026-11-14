# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): tie and its family.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::TieArray :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tie_array') } }
class Chalk::Target::LLVM::Node::TieHash :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tie_hash') } }
class Chalk::Target::LLVM::Node::TiedA :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tied') } }
class Chalk::Target::LLVM::Node::TiedH :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tied_h') } }
class Chalk::Target::LLVM::Node::UntieA :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_untie') } }
class Chalk::Target::LLVM::Node::UntieH :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_untie_h') } }

1;
