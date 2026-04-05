# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Extends Chalk::Bootstrap::IR::Node for migration compat; adds stamp, compat_class, content_hash.
use 5.42.0;
use utf8;
use experimental 'class';

# Migration bridge: inheriting from the old base class ensures typed nodes
# pass `isa Chalk::Bootstrap::IR::Node` checks (283 sites across 6 files).
# This inheritance is removed in Phase 5 when those checks are migrated.
use Chalk::Bootstrap::IR::Node;

class Chalk::IR::Node :isa(Chalk::Bootstrap::IR::Node) {
    # Fields added beyond the old base class
    field $stamp        :param :reader = undef;
    field $compat_class :param :reader = undef;

    # Override operation() — subclasses still must implement
    method operation() {
        die ref($self) . " must implement operation()";
    }

    method class() {
        return $compat_class if defined $compat_class;
        return $self->operation();
    }

    method content_hash() {
        my $op = $self->operation();
        my @parts;
        for my $input ($self->inputs()->@*) {
            if (!defined $input) {
                push @parts, 'undef';
            } elsif (ref($input) eq 'ARRAY') {
                my @ids = map { defined($_) ? $_->id() : 'undef' } $input->@*;
                push @parts, '[' . join(',', @ids) . ']';
            } else {
                push @parts, $input->id();
            }
        }
        return $op . '|' . join('|', @parts);
    }
}
