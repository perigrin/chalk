# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): the program's world: %ENV, print, exit, END blocks, files and the directory.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Env :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $len = Chalk::Target::LLVM::Printer::byte_length($a{key});
        return $self->name . ' = call %Slot @t2_env(' . $self->_gep($len, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::FtDir :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_ftdir') } }
class Chalk::Target::LLVM::Node::FtIs :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_ftis') } }
class Chalk::Target::LLVM::Node::Time :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->name . ' = call i64 @t2_time()' } }
class Chalk::Target::LLVM::Node::Chdir :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_chdir') } }
class Chalk::Target::LLVM::Node::Print :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->_void( '@t2_' . ( ( $self->attr->{fd} // 1 ) == 2 ? 'eprint' : 'print' ) ) }
}
class Chalk::Target::LLVM::Node::Exit :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_exit') } }
class Chalk::Target::LLVM::Node::AtExit :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_atexit(void ()* ' . $self->attr->{fn} . ')' }
}
# A STOP AT RUN TIME (exit 255, the message to STDERR) where a condition T2
# cannot answer at build time fails: refused there, never answered wrong.
class Chalk::Target::LLVM::Node::StopUnless :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_stop_unless') } }
class Chalk::Target::LLVM::Node::RunEnds :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_run_ends()' } }

# IN-MEMORY HANDLES (t2_fh_*): a handle is a %Slot, undef where none is open.
class Chalk::Target::LLVM::Node::FhROpen :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_fh_ropen') } }
class Chalk::Target::LLVM::Node::FhWOpen :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_fh_wopen(' . $self->_args($self->inputs->@*) . ', i1 ' . ( $self->attr->{trunc} ? 1 : 0 ) . ')' }
}
class Chalk::Target::LLVM::Node::FhData :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_fh_data') } }
class Chalk::Target::LLVM::Node::FhReadline :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_fh_readline') } }
class Chalk::Target::LLVM::Node::FhReadlines :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_fh_readlines') } }
class Chalk::Target::LLVM::Node::FhEof :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_fh_eof') } }
class Chalk::Target::LLVM::Node::FhClose :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_fh_close') } }
class Chalk::Target::LLVM::Node::FhPrint :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_fh_print') } }
class Chalk::Target::LLVM::Node::PrintSel :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('i1 @t2_print_sel') } }
class Chalk::Target::LLVM::Node::FhSelect :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_select_fh(' . $self->_args($self->inputs->@*) . ', i1 ' . ( $self->attr->{used} ? 1 : 0 ) . ')' }
}
class Chalk::Target::LLVM::Node::SelectName :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->name . ' = call %Slot @t2_select_name(' . $self->_args($self->inputs->@*) . ', i1 ' . ( $self->attr->{used} ? 1 : 0 ) . ')' }
}

class Chalk::Target::LLVM::Node::Glob :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Array* @t2_glob') } }

class Chalk::Target::LLVM::Node::Qx :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Str @t2_qx') } }

class Chalk::Target::LLVM::Node::LocalTime :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my $fn = $self->type eq '%Str' ? '%Str @t2_localtime_str' : '%Array* @t2_localtime_list';
        return $self->name . " = call $fn(" . $self->_args($self->inputs->@*) . ')';
    }
}

1;
