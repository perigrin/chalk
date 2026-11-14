# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): a qr// value's match and pos() after a /g match.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::QrMatch :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_qr_match') } }
class Chalk::Target::LLVM::Node::PosUpdate :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my @in = $self->inputs->@*;
        return 'call void @t2_pos_update(%Slot ' . $in[0]->name . ', %Slot* ' . $in[1]->name . ', %Slot* ' . $in[2]->name
            . ', i1 ' . ( $self->attr->{keep} ? 1 : 0 ) . ')';
    }
}

1;
