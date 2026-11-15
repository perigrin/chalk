# ABOUTME: Compile-time metaobject for a class declaration.
# ABOUTME: Owns fields, methods, subs, imports, and ADJUST blocks declared on this class.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::MOP::Field;
use Chalk::MOP::Method;
use Chalk::MOP::Sub;
use Chalk::MOP::Import;
use Chalk::MOP::Phaser::Adjust;

class Chalk::MOP::Class {
    field $name        :param :reader;
    field $superclass  :param :reader = undef;
    field $parent_name :param :reader = undef;
    field $mop         :param :reader;
    # A class of the class feature (`class Name { }`), told from a plain
    # package: one with no fields and no methods of its own (an empty
    # `class Child :isa(Base) { }`) is still a class whose `new` constructs.
    field $is_class    :param :reader = false;
    field @fields;
    field @methods;
    field @subs;
    field @imports;
    field @adjust_blocks;
    field @class_scope_vars;
    field @use_constants;

    # Sealed flag: set by Chalk::MOP::seal() when parse-time accumulation
    # ends. Every declare_* guards on it — the post-parse read surface
    # (what the LLVM backend's class registry is built from) must not
    # silently grow.
    field $sealed = false;

    method is_sealed() { return $sealed }
    method seal()      { $sealed = true; return }

    method _assert_unsealed($what) {
        die "Chalk::MOP::Class: $what on sealed class '$name' -- "
          . "construction ended at seal()" if $sealed;
        return;
    }

    method fields()        { return @fields }
    method methods()       { return @methods }
    method subs()          { return @subs }
    method imports()       { return @imports }
    method adjust_blocks() { return @adjust_blocks }
    method class_scope_vars() { return @class_scope_vars }
    method use_constants() { return @use_constants }

    # UNLOADED: a followed module's subs the program never reaches -- named in
    # its stash (can() answers by name), their bodies not loaded.
    field @unloaded;
    method unloaded() { return @unloaded }
    method declare_unloaded($sub_name) {
        $self->_assert_unsealed('declare_unloaded');
        push @unloaded, $sub_name;
        return;
    }

    # ITS SYMBOLS: what the package's stash holds, by name -- each a record of
    # the slots its glob fills (code, scalar, array, hash, io; code_from for
    # a sub imported from another package; package for a nested `Foo::`).
    # Names whose presence is not known (the toolchain made them before the
    # program compiled) are answered neither way; with no table given at all
    # (undef), nothing is claimed.
    field $symbols;
    field $symbols_unknown = {};

    method knows_symbols() { return defined $symbols ? true : false }

    method declare_symbols($table, $unknown) {
        $self->_assert_unsealed('declare_symbols');
        my %t;
        for my $n ( keys $table->%* ) { $t{$n} = $table->{$n} }
        $symbols = \%t;
        my %u;
        for my $n ( $unknown->@* ) { $u{$n} = 1 }
        $symbols_unknown = \%u;
        return;
    }

    # has_symbol($name) -> 1 there, 0 not there, undef not known.
    method has_symbol($n) {
        return undef unless defined $symbols && !$symbols_unknown->{$n};
        return exists $symbols->{$n} ? 1 : 0;
    }

    method symbol($n)     { return defined $symbols ? $symbols->{$n} : undef }
    method symbol_names() { return defined $symbols ? sort keys $symbols->%* : () }
    method symbols_unknown() { return sort keys $symbols_unknown->%* }

    # THE STASH IS THIS CLASS, SEEN AS A HASH (perigrin: a stash is a container
    # whose metaobject is its package's Class): `exists $Foo::{x}` asks it
    # whether the package has the symbol. An entry's value is a glob, whose
    # slots are the stash's: only its truth is answered (the compiler lets a
    # program read no more of it). A name the Class cannot answer, and a
    # change to the stash at run time, stop the program by name.
    method EXISTS($key) {
        my $has = $self->has_symbol($key);
        return $has if defined $has;
        return _refuse("whether ${name}:: holds $key (its presence is not known: the toolchain made it, or no symbol table was given)");
    }

    method FETCH($key) {
        my $has = $self->has_symbol($key);
        return $has ? 1 : undef if defined $has;
        return _refuse("whether ${name}:: holds $key (its presence is not known: the toolchain made it, or no symbol table was given)");
    }

    method STORE($key, $value) { return _refuse("a store into the stash ${name}:: (a change to the MOP at run time)") }
    method DELETE($key)        { return _refuse("a delete from the stash ${name}:: (a change to the MOP at run time)") }
    method CLEAR()             { return _refuse("the stash ${name}:: emptied or assigned whole (a change to the MOP at run time)") }
    method FIRSTKEY()          { return _refuse("the keys of the stash ${name}:: (perl's own names in it are not all known)") }
    method NEXTKEY($last)      { return _refuse("the keys of the stash ${name}:: (perl's own names in it are not all known)") }

    # _refuse($why): a question the stash does not answer, stopped by name.
    sub _refuse ($why) {
        print STDERR "chalk: refused at run time: $why\n";
        exit 255;
    }

    method declare_field($field_name, %opts) {
        $self->_assert_unsealed('declare_field');
        my $field = Chalk::MOP::Field->new(
            name    => $field_name,
            class   => $self,
            fieldix => scalar(@fields),
            %opts,
        );
        push @fields, $field;
        return $field;
    }

    method declare_method($method_name, %opts) {
        $self->_assert_unsealed('declare_method');
        my $method = Chalk::MOP::Method->new(
            name  => $method_name,
            class => $self,
            %opts,
        );
        push @methods, $method;
        return $method;
    }

    method declare_sub($sub_name, %opts) {
        $self->_assert_unsealed('declare_sub');
        my $sub = Chalk::MOP::Sub->new(
            name  => $sub_name,
            class => $self,
            %opts,
        );
        push @subs, $sub;
        return $sub;
    }

    method declare_import($module, %opts) {
        $self->_assert_unsealed('declare_import');
        # Deduplicate: return existing import if the same module is already registered
        # WITH the same keyword. Earley parse ambiguity can cause semantic actions to
        # fire multiple times — but `use warnings;` and `no warnings '...';` are
        # DIFFERENT declarations on the same module and must both survive.
        my $kw = $opts{keyword} // 'use';
        for my $existing (@imports) {
            return $existing
                if $existing->module() eq $module
                && ($existing->keyword() // 'use') eq $kw;
        }
        my $import = Chalk::MOP::Import->new(
            module => $module,
            class  => $self,
            %opts,
        );
        push @imports, $import;
        return $import;
    }

    method declare_adjust(%opts) {
        $self->_assert_unsealed('declare_adjust');
        my $adjust = Chalk::MOP::Phaser::Adjust->new(
            class           => $self,
            source_position => scalar(@adjust_blocks),
            %opts,
        );
        push @adjust_blocks, $adjust;
        return $adjust;
    }

    # declare_class_scope_var($decl): a class-level `my`, in order. The
    # declaration is the parser's node, opaque here; its name's binding is the
    # parser's to keep (Chalk::Bootstrap::Perl::Actions::class_bindings).
    method declare_class_scope_var($vardecl_node) {
        $self->_assert_unsealed('declare_class_scope_var');
        push @class_scope_vars, $vardecl_node;
        return $vardecl_node;
    }

    method declare_use_constant($name, $value_node) {
        $self->_assert_unsealed('declare_use_constant');
        # $name is a plain string (the constant name, no sigil).
        # $value_node is a Chalk::IR::Node::Constant (or similar IR node).
        # Returns a plain hashref entity, NOT a Chalk::MOP::UseConstant class
        # (YAGNI per Phase 7c-prep design — promote to a typed class when
        # state accumulates beyond {name, value}).
        my $entry = { name => $name, value => $value_node };
        push @use_constants, $entry;
        return $entry;
    }

    method find_method($search_name) {
        for my $m (@methods) {
            return $m if $m->name eq $search_name;
        }
        if (defined $superclass) {
            return $superclass->find_method($search_name);
        }
        return;
    }

    method ancestors() {
        my @chain;
        my $current = $superclass;
        while (defined $current) {
            push @chain, $current;
            $current = $current->superclass;
        }
        return @chain;
    }

    method all_nodes() {
        my @nodes;
        for my $owner (@methods, @subs) {
            next unless $owner->can('graph');
            my $g = $owner->graph;
            next unless defined $g;
            push @nodes, $g->nodes->@*;
        }
        return @nodes;
    }

    method resolve_adjust_blocks() {
        my @result;
        # Base-class-first order: ancestors in reverse, then self
        my @ancestor_chain = reverse $self->ancestors;
        for my $cls (@ancestor_chain) {
            push @result, $cls->adjust_blocks;
        }
        push @result, @adjust_blocks;
        return @result;
    }
}
