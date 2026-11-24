# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): arrays and argument lists through the runtime.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::NewArray :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Array* @t2_new_array()' } }
class Chalk::Target::LLVM::Node::APush :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_apush') } }
class Chalk::Target::LLVM::Node::AUnshift :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aunshift') } }
class Chalk::Target::LLVM::Node::ArgsFrom :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_args_from') } }
class Chalk::Target::LLVM::Node::ArgsMin :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_args_min(%Array* ' . $self->inputs->[0]->name . ', i64 ' . $self->attr->{n} . ')' }
}
class Chalk::Target::LLVM::Node::ArgsMax :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_args_max(%Array* ' . $self->inputs->[0]->name . ', i64 ' . $self->attr->{n} . ')' }
}
class Chalk::Target::LLVM::Node::ArgsPairs :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_args_pairs(%Array* ' . $self->inputs->[0]->name . ', i64 ' . $self->attr->{n} . ')' }
}
class Chalk::Target::LLVM::Node::ASort :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call %Array* @t2_asort(' . $self->_args($self->inputs->@*) . ", i1 $a{num}, i1 $a{desc})";
    }
}
class Chalk::Target::LLVM::Node::ASortBy :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call %Array* @t2_asort_by(' . $self->_args($self->inputs->@*) . ", %Slot ()* $a{fn}, %Slot* $a{ga}, %Slot* $a{gb})";
    }
}
class Chalk::Target::LLVM::Node::CmpEnv :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_cmp_env_at(i64 ' . $self->attr->{index} . ')' }
}
class Chalk::Target::LLVM::Node::ARev :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_arev') } }
class Chalk::Target::LLVM::Node::AAssign :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aassign') } }
class Chalk::Target::LLVM::Node::AUnshiftL :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aunshiftl') } }
class Chalk::Target::LLVM::Node::AAppend :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aappend') } }
class Chalk::Target::LLVM::Node::APushIf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_apush_if') } }
class Chalk::Target::LLVM::Node::OneOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_one_of') } }
class Chalk::Target::LLVM::Node::ARef :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_aref') } }
class Chalk::Target::LLVM::Node::ADeref :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_aderef') } }
# The whole hash read through a reference where perl may die: strict refs
# and the site its message names, as constants (t2_hderef_whole).
class Chalk::Target::LLVM::Node::HDerefWhole :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call %Slot @t2_hderef_whole(' . $self->_args($self->inputs->@*) . ", i1 $a{strict}, " . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
# The whole array read through a reference where perl may die: strict refs
# and the site its message names, as constants (t2_aderef_whole).
class Chalk::Target::LLVM::Node::ADerefWhole :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call %Array* @t2_aderef_whole(' . $self->_args($self->inputs->@*) . ", i1 $a{strict}, " . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::ADerefR :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_aderef_r') } }
class Chalk::Target::LLVM::Node::ASet :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return 'call void @t2_aset(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::ALen :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_alen') } }
class Chalk::Target::LLVM::Node::AGet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_aget') } }
class Chalk::Target::LLVM::Node::AShift :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_ashift') } }
class Chalk::Target::LLVM::Node::APop :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_apop') } }
class Chalk::Target::LLVM::Node::AExists :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_aexists') } }
class Chalk::Target::LLVM::Node::ASlice :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_aslice') } }
class Chalk::Target::LLVM::Node::ARange :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_range') } }
class Chalk::Target::LLVM::Node::ARangeSlots :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_range_slots') } }
class Chalk::Target::LLVM::Node::ASetLen :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aset_len') } }

# @_, AN ARRAY OF ALIASES (the runtime's t2_new_args): an alias put there as
# it is, an array's elements each aliased, an element alias of an array's or
# a hash's element, a fresh cell holding a temporary.
class Chalk::Target::LLVM::Node::NewArgs :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Array* @t2_new_args()' } }
class Chalk::Target::LLVM::Node::APushAlias :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_apush_alias') } }
class Chalk::Target::LLVM::Node::AAppendAlias :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aappend_alias') } }
class Chalk::Target::LLVM::Node::ElvA :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_elv_a') } }
class Chalk::Target::LLVM::Node::ElvH :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_elv_h') } }
class Chalk::Target::LLVM::Node::ElvAViv :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_elv_a_viv') } }
class Chalk::Target::LLVM::Node::ElvHViv :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_elv_h_viv') } }
class Chalk::Target::LLVM::Node::ASliceAlias :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_aslice_alias') } }
class Chalk::Target::LLVM::Node::HSliceAlias :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hslice_alias') } }
class Chalk::Target::LLVM::Node::Fresh :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_fresh') } }
# AN ELEMENT REFERENCE (`\$a[i]`): the element's cell, the array made one of
# aliases (t2_aelem_ref); perl's die before the start names where. `\(@a)`:
# a list of one to each element.
class Chalk::Target::LLVM::Node::AElemRef :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call %Slot @t2_aelem_ref(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::AElemRefs :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_aelem_refs') } }
# A HASH ELEMENT REFERENCE (`\$h{k}`): the element's cell, the hash made one of
# cells (t2_helem_ref), the key made where it is not there.
class Chalk::Target::LLVM::Node::HElemRef :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_helem_ref') } }
# A READ THROUGH AN ELEMENT REFERENCE, passed to a sub: @_ holds the cell (t2_alias_of).
class Chalk::Target::LLVM::Node::AliasOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_alias_of') } }
# $_ ALIASED (topic_alias): the value an alias stands for now (t2_alias_val),
# and a store through it (t2_alias_store: perl's die on a read-only one).
class Chalk::Target::LLVM::Node::AliasVal :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_alias_val') } }
class Chalk::Target::LLVM::Node::AliasStore :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . '.d = call i1 @t2_alias_store(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}

class Chalk::Target::LLVM::Node::ARepeat :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_arepeat') } }

1;
