# ABOUTME: Chalk::Target::LLVM::Node's op classes, one per LLVM op, each printing its own
# ABOUTME: line of .ll (to_ll): the program's world: %ENV, print, exit, END blocks, files and the directory.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Target::LLVM::Node::Env :isa(Chalk::Target::LLVM::Node) {
    method to_ll () {
        my %a = $self->attr->%*;
        my $len = do { use bytes; length $a{key} };
        return $self->name . ' = call %Slot @t2_env(' . $self->_gep($len, $a{id}) . ')';
    }
}
class Chalk::Target::LLVM::Node::FtDir :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_ftdir') } }
class Chalk::Target::LLVM::Node::Chdir :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_call('%Slot @t2_chdir') } }
class Chalk::Target::LLVM::Node::Print :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { $self->_void( '@t2_' . ( ( $self->attr->{fd} // 1 ) == 2 ? 'eprint' : 'print' ) ) }
}
class Chalk::Target::LLVM::Node::Exit :isa(Chalk::Target::LLVM::Node) { method to_ll () { $self->_void('@t2_exit') } }
class Chalk::Target::LLVM::Node::AtExit :isa(Chalk::Target::LLVM::Node) {
    method to_ll () { 'call void @t2_atexit(void ()* ' . $self->attr->{fn} . ')' }
}
class Chalk::Target::LLVM::Node::RunEnds :isa(Chalk::Target::LLVM::Node) { method to_ll () { 'call void @t2_run_ends()' } }

1;
