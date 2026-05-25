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
use Chalk::Bootstrap::Scope;

class Chalk::MOP::Class {
    field $name        :param :reader;
    field $superclass  :param :reader = undef;
    field $parent_name :param :reader = undef;
    field $mop         :param :reader;
    field @fields;
    field @methods;
    field @subs;
    field @imports;
    field @adjust_blocks;
    field $scope :reader = Chalk::Bootstrap::Scope->new;
    field @class_scope_vars;
    field @use_constants;

    method fields()        { return @fields }
    method methods()       { return @methods }
    method subs()          { return @subs }
    method imports()       { return @imports }
    method adjust_blocks() { return @adjust_blocks }
    method class_scope_vars() { return @class_scope_vars }
    method use_constants() { return @use_constants }

    method declare_field($field_name, %opts) {
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
        my $method = Chalk::MOP::Method->new(
            name  => $method_name,
            class => $self,
            %opts,
        );
        push @methods, $method;
        return $method;
    }

    method declare_sub($sub_name, %opts) {
        my $sub = Chalk::MOP::Sub->new(
            name  => $sub_name,
            class => $self,
            %opts,
        );
        push @subs, $sub;
        return $sub;
    }

    method declare_import($module, %opts) {
        # Deduplicate: return existing import if the same module is already registered.
        # Earley parse ambiguity can cause semantic actions to fire multiple times.
        for my $existing (@imports) {
            return $existing if $existing->module() eq $module;
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
        my $adjust = Chalk::MOP::Phaser::Adjust->new(
            class           => $self,
            source_position => scalar(@adjust_blocks),
            %opts,
        );
        push @adjust_blocks, $adjust;
        return $adjust;
    }

    method declare_class_scope_var($vardecl_node) {
        # $vardecl_node is a Chalk::IR::Node::VarDecl already merged
        # into its upstream graph by Actions.pm. We do NOT merge it
        # into a class-side graph here — no class graph exists in this
        # commit (see Phase 7c-prep design Risk #2). Record in the
        # insertion-ordered list (for codegen iteration) and bind the
        # name in $scope (for lookup-by-name semantics).
        push @class_scope_vars, $vardecl_node;
        my $name = $vardecl_node->name->value;
        $scope = $scope->define($name, $vardecl_node);
        return $vardecl_node;
    }

    method declare_use_constant($name, $value_node) {
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
