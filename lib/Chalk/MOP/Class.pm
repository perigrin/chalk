# ABOUTME: Compile-time metaobject for a class declaration.
# ABOUTME: Owns fields, methods, subs, imports, and ADJUST blocks declared on this class.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::MOP::Class {
    field $name       :param :reader;
    field $superclass :param :reader = undef;
    field $mop        :param :reader;
    field @fields;
    field @methods;
    field @subs;
    field @imports;
    field @adjust_blocks;

    method fields()        { return @fields }
    method methods()       { return @methods }
    method subs()          { return @subs }
    method imports()       { return @imports }
    method adjust_blocks() { return @adjust_blocks }

    method declare_field($field_name, %opts) {
        require Chalk::MOP::Field;
        my $field = Chalk::MOP::Field->new(
            name  => $field_name,
            class => $self,
            %opts,
        );
        push @fields, $field;
        return $field;
    }

    method declare_method($method_name, %opts) {
        require Chalk::MOP::Method;
        my $method = Chalk::MOP::Method->new(
            name  => $method_name,
            class => $self,
            %opts,
        );
        push @methods, $method;
        return $method;
    }

    method declare_sub($sub_name, %opts) {
        require Chalk::MOP::Sub;
        my $sub = Chalk::MOP::Sub->new(
            name  => $sub_name,
            class => $self,
            %opts,
        );
        push @subs, $sub;
        return $sub;
    }

    method declare_import($module, %opts) {
        require Chalk::MOP::Import;
        my $import = Chalk::MOP::Import->new(
            module => $module,
            class  => $self,
            %opts,
        );
        push @imports, $import;
        return $import;
    }

    method declare_adjust(%opts) {
        require Chalk::MOP::Phaser::Adjust;
        my $adjust = Chalk::MOP::Phaser::Adjust->new(
            class           => $self,
            source_position => scalar(@adjust_blocks),
            %opts,
        );
        push @adjust_blocks, $adjust;
        return $adjust;
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
