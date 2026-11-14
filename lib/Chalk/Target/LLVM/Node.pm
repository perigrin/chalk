# ABOUTME: An LLVM instruction of T2's graph: op, type, inputs, attr, its SSA name. Each
# ABOUTME: op is a subclass Chalk::Target::LLVM::Node::<Op> (below) whose to_ll prints it.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

# ONE CLASS PER LLVM OP: each Node subclass prints its own line (or
# lines) with to_ll. The builder's `_n(op => 'X', ...)` makes a
# Node::X, so an op without a class dies where it is made, by name.
# Most are a call of the runtime: `_call` (a value) or `_void`, over the
# node's inputs.

class Chalk::Target::LLVM::Node {
    field $op     :param :reader;
    field $type   :param :reader;           # i64 | double | i1 | %Str | %Slot | void
    field $inputs :param :reader = [];
    field $attr   :param :reader = {};
    field $name   :reader;                  # its SSA name, given by the printer
    method set_name ($n) { $name = $n }

    # Each op is a subclass (Node::<op>, below) whose
    # to_ll is its line of .ll. What they share: nodes as `type name`
    # arguments; a call of the runtime over the inputs, for a value or
    # not; a string constant @s<id> as an i8*, and with its length.
    method _args (@n) { join ', ', map { $_->type . ' ' . $_->name } @n }
    method _call ($sig) { "$name = call $sig(" . $self->_args($inputs->@*) . ')' }
    method _void ($fn) { "call void $fn(" . $self->_args($inputs->@*) . ')' }
    method _gep ($len, $id) { "i8* getelementptr ([" . ( $len + 1 ) . " x i8], [" . ( $len + 1 ) . " x i8]* \@s$id, i64 0, i64 0)" }
    method _cstr ($s, $id) { my $len = do { use bytes; length $s }; $self->_gep($len, $id) . ", i64 $len" }

    # A node of its op's class: Node::<op>. An op with no class is refused
    # here, by name, rather than printed as nothing.
    sub _n {
        my %a = @_;
        my $class = 'Chalk::Target::LLVM::Node::' . ( $a{op} // '' );
        die 'T2: no class for the op ' . ( $a{op} // '(none)' ) . "\n"
            unless $a{op} && $a{op} =~ /\A\w+\z/ && $class->isa('Chalk::Target::LLVM::Node');
        return $class->new(@_);
    }
}

class Chalk::Target::LLVM::Node::Const :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, %a) = ($self->type, $self->name, $self->attr->%*);
        return "$nm = add i64 0, " . ( 0 + $a{value} ) if $ty eq 'i64';
        return "$nm = fadd double 0.0, " . Chalk::Target::LLVM::Printer::_double($a{value}) if $ty eq 'double';
        return "$nm = add i1 0, " . ( $a{value} ? 1 : 0 ) if $ty eq 'i1';
        die "T2: a constant of $ty";
    }
}
class Chalk::Target::LLVM::Node::ConstStr :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my %a = $self->attr->%*; $self->name . ' = call %Str @t2_str(' . $self->_cstr($a{value}, $a{id}) . ')' }
}
class Chalk::Target::LLVM::Node::Env :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $len = do { use bytes; length $a{key} };
        return $self->name . ' = call %Slot @t2_env(' . $self->_gep($len, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::Arith :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, @in) = ($self->type, $self->name, $self->inputs->@*);
        my %a = $self->attr->%*;
        my %fop = (add => 'fadd', sub => 'fsub', mul => 'fmul', div => 'fdiv');
        my $o = $ty eq 'double' ? $fop{ $a{op} } : $a{op};
        return "$nm = $o $ty " . $in[0]->name . ', ' . $in[1]->name;
    }
}
class Chalk::Target::LLVM::Node::Cmp :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($nm, @in) = ($self->name, $self->inputs->@*);
        my %a = $self->attr->%*;
        my $t = $in[0]->type;
        my $o = $t eq 'double' ? "fcmp o$a{op}" : 'icmp ' . ( { eq => 'eq', ne => 'ne' }->{ $a{op} } // "s$a{op}" );
        $o = 'fcmp une' if $t eq 'double' && $a{op} eq 'ne';
        return "$nm = $o $t " . $in[0]->name . ', ' . $in[1]->name;
    }
}
class Chalk::Target::LLVM::Node::Undef :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_slot(i8 0, i64 0)' }
}
class Chalk::Target::LLVM::Node::Call :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->_call('%Slot ' . $self->attr->{fn}) }
}
class Chalk::Target::LLVM::Node::Alloca :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my $nm = $self->name;
        return "$nm = alloca %Slot  ; my " . $self->attr->{name} . "\n  store %Slot zeroinitializer, %Slot* $nm";
    }
}
class Chalk::Target::LLVM::Node::HeapCell :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot* @t2_cell_new()  ; my ' . $self->attr->{name} . ', captured' }
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
class Chalk::Target::LLVM::Node::Load :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = load %Slot, %Slot* ' . $self->inputs->[0]->name }
}
class Chalk::Target::LLVM::Node::Numify :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_numify') } }
class Chalk::Target::LLVM::Node::IntOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_int') } }
class Chalk::Target::LLVM::Node::FtDir :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_ftdir') } }
class Chalk::Target::LLVM::Node::Chdir :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_chdir') } }
class Chalk::Target::LLVM::Node::Rand :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_rand') } }
class Chalk::Target::LLVM::Node::Store :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my @in = $self->inputs->@*; 'store %Slot ' . $in[0]->name . ', %Slot* ' . $in[1]->name }
}
class Chalk::Target::LLVM::Node::SlotStep :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_' . $self->attr->{op}) } }
class Chalk::Target::LLVM::Node::SlotArith :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_' . $self->attr->{op}) } }
class Chalk::Target::LLVM::Node::Mod :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call i64 @t2_mod(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
# A scalar deref of a string: its message and package as constants.
class Chalk::Target::LLVM::Node::SDeref :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $at = $self->_cstr($a{msg}, $a{id}) . ', ' . $self->_cstr($a{pk}, $a{pkid});
        return $self->name . ' = call %Slot @t2_sderef(' . $self->_args($self->inputs->@*) . ", i1 $a{strict}, $at)";
    }
}
class Chalk::Target::LLVM::Node::SStore :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $at = $self->_cstr($a{msg}, $a{id}) . ', ' . $self->_cstr($a{pk}, $a{pkid});
        return 'call void @t2_sstore(' . $self->_args($self->inputs->@*) . ", i1 $a{strict}, $at)";
    }
}
class Chalk::Target::LLVM::Node::SRef :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_sref(%Slot* ' . $self->inputs->[0]->name . ')' }
}
class Chalk::Target::LLVM::Node::SCell :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my ($nm, $p) = ($self->name, $self->inputs->[0]->name); "$nm.p = extractvalue %Slot $p, 1\n  $nm = inttoptr i64 $nm.p to %Slot*" }
}
class Chalk::Target::LLVM::Node::Div :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        return $self->name . ' = call double @t2_div(' . $self->_args($self->inputs->@*) . ', ' . $self->_cstr($a{msg}, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::Concat :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_concat') } }
class Chalk::Target::LLVM::Node::StrCmp :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_strcmp') } }
class Chalk::Target::LLVM::Node::StrCase :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_strcase') } }
class Chalk::Target::LLVM::Node::StrLen :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = extractvalue %Str ' . $self->inputs->[0]->name . ', 1' }
}
class Chalk::Target::LLVM::Node::SlotLength :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_length') } }
class Chalk::Target::LLVM::Node::NewArray :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Array* @t2_new_array()' } }
class Chalk::Target::LLVM::Node::HNew :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Slot @t2_hnew()' } }
class Chalk::Target::LLVM::Node::SaveArgs :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_save_args(i32 %argc, i8** %argv)' } }
class Chalk::Target::LLVM::Node::GetWant :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = load i1, i1* @t2_want' } }
class Chalk::Target::LLVM::Node::SetWant :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'store i1 ' . $self->inputs->[0]->name . ', i1* @t2_want' }
}
class Chalk::Target::LLVM::Node::Select :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { my @in = $self->inputs->@*; $self->name . ' = select i1 ' . $in[0]->name . ', ' . $self->_args( @in[ 1, 2 ] ) }
}
# A package variable, by its global.
class Chalk::Target::LLVM::Node::GLoad :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = load %Slot, %Slot* ' . $self->attr->{global} }
}
class Chalk::Target::LLVM::Node::GHash :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_ghash(%Slot* ' . $self->attr->{global} . ')' }
}
class Chalk::Target::LLVM::Node::GArray :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Array* @t2_garray(%Slot* ' . $self->attr->{global} . ')' }
}
class Chalk::Target::LLVM::Node::GAddr :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = getelementptr %Slot, %Slot* ' . $self->attr->{global} . ', i64 0' }
}
class Chalk::Target::LLVM::Node::GStore :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'store %Slot ' . $self->inputs->[0]->name . ', %Slot* ' . $self->attr->{global} }
}
class Chalk::Target::LLVM::Node::Argv :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call %Array* @t2_argv()' } }
class Chalk::Target::LLVM::Node::Bless :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_bless') } }
class Chalk::Target::LLVM::Node::CodeOfFn :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        return $self->name . ' = call %Slot @t2_code_new(i8* bitcast (%Slot (%Array*, %Slot**)* @t2_stash_tramp to i8*), %Slot** bitcast (%Slot (%Array*)* '
            . $self->attr->{fn} . '_w to %Slot**))';
    }
}
class Chalk::Target::LLVM::Node::QrMatch :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_qr_match') } }
class Chalk::Target::LLVM::Node::PosUpdate :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my @in = $self->inputs->@*;
        return 'call void @t2_pos_update(%Slot ' . $in[0]->name . ', %Slot* ' . $in[1]->name . ', %Slot* ' . $in[2]->name
            . ', i1 ' . ( $self->attr->{keep} ? 1 : 0 ) . ')';
    }
}
class Chalk::Target::LLVM::Node::ClassOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_class_of') } }
class Chalk::Target::LLVM::Node::RefType :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_reftype') } }
# The MOP, built at start.
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
# Hashes.
class Chalk::Target::LLVM::Node::HSet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_hset') } }
class Chalk::Target::LLVM::Node::HGet :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_hget') } }
class Chalk::Target::LLVM::Node::HExists :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_hexists') } }
class Chalk::Target::LLVM::Node::HDelete :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_hdelete') } }
class Chalk::Target::LLVM::Node::HFromArray :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_hfroma') } }
class Chalk::Target::LLVM::Node::HCount :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_hcount') } }
class Chalk::Target::LLVM::Node::HKeys :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hkeys') } }
class Chalk::Target::LLVM::Node::HPairs :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hpairs') } }
class Chalk::Target::LLVM::Node::HValues :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_hvalues') } }
# Arrays and argument lists.
class Chalk::Target::LLVM::Node::APush :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_apush') } }
class Chalk::Target::LLVM::Node::AUnshift :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aunshift') } }
class Chalk::Target::LLVM::Node::ArgsFrom :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_args_from') } }
class Chalk::Target::LLVM::Node::ArgsMin :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_args_min(%Array* ' . $self->inputs->[0]->name . ', i64 ' . $self->attr->{n} . ')' }
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
class Chalk::Target::LLVM::Node::HDerefR :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_hderef_r') } }
class Chalk::Target::LLVM::Node::ARev :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_arev') } }
class Chalk::Target::LLVM::Node::AAssign :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aassign') } }
class Chalk::Target::LLVM::Node::HAssign :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_hassign') } }
class Chalk::Target::LLVM::Node::AUnshiftL :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aunshiftl') } }
# tie and its family.
class Chalk::Target::LLVM::Node::TieArray :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tie_array') } }
class Chalk::Target::LLVM::Node::TieHash :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tie_hash') } }
class Chalk::Target::LLVM::Node::TiedA :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tied') } }
class Chalk::Target::LLVM::Node::TiedH :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_tied_h') } }
class Chalk::Target::LLVM::Node::UntieA :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_untie') } }
class Chalk::Target::LLVM::Node::UntieH :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_untie_h') } }
class Chalk::Target::LLVM::Node::AAppend :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aappend') } }
class Chalk::Target::LLVM::Node::APushIf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_apush_if') } }
class Chalk::Target::LLVM::Node::OneOf :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_one_of') } }
class Chalk::Target::LLVM::Node::ARef :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_aref') } }
class Chalk::Target::LLVM::Node::ADeref :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_aderef') } }
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
class Chalk::Target::LLVM::Node::Join :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_join') } }
# Output, exit, END blocks, caller's frames.
class Chalk::Target::LLVM::Node::Print :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->_void( '@t2_' . ( ( $self->attr->{fd} // 1 ) == 2 ? 'eprint' : 'print' ) ) }
}
class Chalk::Target::LLVM::Node::Exit :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_exit') } }
class Chalk::Target::LLVM::Node::AtExit :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_atexit(void ()* ' . $self->attr->{fn} . ')' }
}
class Chalk::Target::LLVM::Node::RunEnds :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_run_ends()' } }
class Chalk::Target::LLVM::Node::FramePush :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_frame_push') } }
class Chalk::Target::LLVM::Node::FramePop :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_frame_pop()' } }
class Chalk::Target::LLVM::Node::Caller :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_caller') } }
class Chalk::Target::LLVM::Node::CallerPkg :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_caller_pkg') } }
# Strings, numbers and references through the runtime.
class Chalk::Target::LLVM::Node::Substr :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_substr') } }
class Chalk::Target::LLVM::Node::SubstrRep :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_substr_rep') } }
class Chalk::Target::LLVM::Node::SlotNeg :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_slot_neg') } }
class Chalk::Target::LLVM::Node::KindOfRef :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_kind_of_ref') } }
class Chalk::Target::LLVM::Node::AExists :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_aexists') } }
class Chalk::Target::LLVM::Node::ASetLen :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_aset_len') } }
class Chalk::Target::LLVM::Node::Index :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i64 @t2_index') } }
class Chalk::Target::LLVM::Node::Defined :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_defined') } }
class Chalk::Target::LLVM::Node::Truth :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %f = ('i64' => 't2_truth_i64', double => 't2_truth_num', '%Str' => 't2_truth_str', '%Slot' => 't2_truth_slot');
        return $self->_call( 'i1 @' . $f{ $self->inputs->[0]->type } );
    }
}
# A conversion between representations: an LLVM cast, or the runtime's.
class Chalk::Target::LLVM::Node::Convert :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, %a) = ($self->type, $self->name, $self->attr->%*);
        my $f = $Chalk::Target::LLVM::Printer::CONVERT{"$a{from}>$ty"} // die "T2: no conversion $a{from} -> $ty";
        return "$nm = $f $a{from} " . $self->inputs->[0]->name . " to $ty" if $f =~ /\A(?:sitofp|zext|fptosi)\z/;
        return $self->_call("$ty \@$f");
    }
}
class Chalk::Target::LLVM::Node::Phi :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my ($ty, $nm, @in) = ($self->type, $self->name, $self->inputs->@*);
        my %a = $self->attr->%*;
        return "$nm = phi $ty " . join(', ', map { '[ ' . $in[$_]->name . ", %$a{from}[$_]{label} ]" } 0 .. $#in);
    }
}
# A sub's argument: named by its function's header, never a line of its own.
class Chalk::Target::LLVM::Node::Arg :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { die 'T2: cannot print ' . $self->op }
}


1;
