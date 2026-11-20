# ABOUTME: The ref() type-reader operation node in the Chalk IR.
# ABOUTME: Unary data node taking a reference and producing its type/class name (a Str).
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::UnaryOp;

class Chalk::IR::Node::RefType :isa(Chalk::IR::Node::UnaryOp) {
    method operation() { 'RefType' }

    # memory_operand -> the memory version it reads the class at: its second
    # input, where B::SoN gives one (a bless is the version after it).
    method memory_operand() { return $self->inputs->@* > 1 ? $self->inputs->[1] : undef }
    method reads_class() { return 1 }
    method staleness_kind() { 'transparent' }
    sub identity_kind { 'hash_consed' }
    method op_str()    { 'ref' }
}
