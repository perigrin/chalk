# ABOUTME: An LLVM instruction of T2's graph: op, type, inputs, attr, its SSA name. Each
# ABOUTME: op is a subclass Chalk::Target::LLVM::Node::<Op> (Node/*.pm, by family) whose to_ll prints it.
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

    # Each op is a subclass (Node::<op>, in Node/*.pm, by family) whose
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

require Chalk::Target::LLVM::Node::Arrays;
require Chalk::Target::LLVM::Node::Calls;
require Chalk::Target::LLVM::Node::Hashes;
require Chalk::Target::LLVM::Node::Memory;
require Chalk::Target::LLVM::Node::Mop;
require Chalk::Target::LLVM::Node::Regex;
require Chalk::Target::LLVM::Node::Strings;
require Chalk::Target::LLVM::Node::System;
require Chalk::Target::LLVM::Node::Tie;
require Chalk::Target::LLVM::Node::Values;

1;
