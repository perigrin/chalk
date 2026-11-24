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

class Chalk::Target::LLVM::Node::Chr :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_chr') } }
class Chalk::Target::LLVM::Node::PackC :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_pack_c') } }
class Chalk::Target::LLVM::Node::Ord :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_ord') } }
class Chalk::Target::LLVM::Node::StrRev :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_strrev') } }
class Chalk::Target::LLVM::Node::Repeat :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_repeat') } }
class Chalk::Target::LLVM::Node::Fmt :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_fmt') } }

class Chalk::Target::LLVM::Node::FormField :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Str @t2_form_field(' . $self->_args($self->inputs->@*) . ', i1 ' . ( $self->attr->{right} ? 1 : 0 ) . ')' }
}
class Chalk::Target::LLVM::Node::RTrim :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_rtrim') } }

class Chalk::Target::LLVM::Node::Chomp :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Str @t2_chomp(' . $self->_args($self->inputs->@*) . ', i1 ' . ( $self->attr->{chop} ? 1 : 0 ) . ')' }
}
class Chalk::Target::LLVM::Node::ChompN :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call i64 @t2_chomp_n(' . $self->_args($self->inputs->@*) . ', i1 ' . ( $self->attr->{chop} ? 1 : 0 ) . ')' }
}
class Chalk::Target::LLVM::Node::ChopChar :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_chop_char') } }
class Chalk::Target::LLVM::Node::UnpackC :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Array* @t2_unpack_c(%Str ' . $self->inputs->[0]->name . ', i64 ' . $self->attr->{n} . ')' }
}

1;
