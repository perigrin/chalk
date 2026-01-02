# ABOUTME: ClassDef IR node organizing class structure for XS generation
# ABOUTME: Contains class name, Field nodes, method FunctionDefs, parent class
use 5.42.0;
use experimental qw(class);
use utf8;
use Scalar::Util qw(blessed refaddr);

class Chalk::IR::Node::ClassDef {
    field $class_name :param :reader;
    field $fields :param :reader = [];
    field $methods :param :reader = [];
    field $parent_class :param :reader = undef;
    field $source_info :param :reader = undef;
    field $overload_mappings :param :reader = {};  # operator => method_name map
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method op() { 'ClassDef' }

    method field_index($name) {
        for my $f ($fields->@*) {
            return $f->index if $f->name eq $name;
        }
        return undef;
    }

    # Dynamically compute inputs from fields and methods
    method inputs() {
        my @inputs;
        for my $f ($fields->@*) {
            push @inputs, $f->id if blessed($f) && $f->can('id');
        }
        for my $m ($methods->@*) {
            push @inputs, $m->id if blessed($m) && $m->can('id');
        }
        return \@inputs;
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'ClassDef',
            inputs => $self->inputs,
            attributes => {
                class_name   => $class_name,
                parent_class => $parent_class,
                field_count  => scalar($fields->@*),
                method_count => scalar($methods->@*),
            },
        };
    }

    # Compatibility methods for code expecting Base methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    method compute() {
        return Chalk::IR::Type::Top->top();
    }

    method idealize() {
        return;
    }

    method record_transform(@args) {
        return;
    }

    method get_transform_chain() {
        return [$transform_chain->@*];
    }
}

1;
