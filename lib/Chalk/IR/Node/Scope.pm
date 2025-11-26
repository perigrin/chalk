# ABOUTME: Immutable ScopeNode for Sea of Nodes IR - maintains symbol tables for lexical scoping
# ABOUTME: Returns new Scope instances instead of mutating; supports branch merging with Phi creation
use 5.42.0;
use experimental qw(class builtin);
use utf8;
use Scalar::Util 'refaddr';

class Chalk::IR::Node::Scope {
    # Immutable Scope - all "mutation" methods return new Scope instances

    field $bindings :param :reader = {};        # { var_name => node }
    field $current_control :param :reader = undef;
    field $parent :param :reader = undef;       # Parent scope for nested lookups
    field $id :reader;

    ADJUST {
        # Generate ID using object address
        $id = 'scope_' . refaddr($self);
        # Deep copy bindings to ensure immutability
        $bindings = { %$bindings };
    }

    method op() { 'Scope' }

    # Immutable: return new Scope with added binding
    method with_binding($name, $node) {
        return Chalk::IR::Node::Scope->new(
            bindings        => { %$bindings, $name => $node },
            current_control => $current_control,
            parent          => $parent,
        );
    }

    # Immutable: return new Scope with updated control
    method with_control($new_control) {
        return Chalk::IR::Node::Scope->new(
            bindings        => $bindings,
            current_control => $new_control,
            parent          => $parent,
        );
    }

    # Immutable: return new child Scope (for entering blocks)
    method child_scope() {
        return Chalk::IR::Node::Scope->new(
            bindings        => {},
            current_control => $current_control,
            parent          => $self,
        );
    }

    # Look up a variable, searching from this scope up through parents
    method lookup($name) {
        if (exists $bindings->{$name}) {
            return $bindings->{$name};
        }
        if ($parent) {
            return $parent->lookup($name);
        }
        return undef;
    }

    # Merge two branch scopes, creating Phi nodes for differing variables
    method merge_branches($scope_a, $scope_b, $region) {
        use Chalk::IR::Node::Phi;

        my %merged = %$bindings;  # Start with current (pre-branch) bindings

        # Get all variable names from both branch scopes
        my %all_vars;
        $all_vars{$_} = 1 for keys %{$scope_a->all_bindings};
        $all_vars{$_} = 1 for keys %{$scope_b->all_bindings};

        for my $var (keys %all_vars) {
            my $val_a = $scope_a->lookup($var);
            my $val_b = $scope_b->lookup($var);

            # Skip if variable doesn't exist in both branches
            next unless defined($val_a) && defined($val_b);

            # Check if values differ (by ID)
            my $id_a = ref($val_a) && $val_a->can('id') ? $val_a->id : "$val_a";
            my $id_b = ref($val_b) && $val_b->can('id') ? $val_b->id : "$val_b";

            if ($id_a ne $id_b) {
                # Values differ - create Phi
                my $phi = Chalk::IR::Node::Phi->new(
                    region => $region,
                    inputs => [$val_a, $val_b],
                );
                $merged{$var} = $phi;
            } else {
                # Values same - use either one
                $merged{$var} = $val_a;
            }
        }

        return Chalk::IR::Node::Scope->new(
            bindings        => \%merged,
            current_control => $region,
            parent          => $parent,
        );
    }

    # Merge loop body scope, creating Phi nodes for loop-carried values
    method merge_loop($body_scope, $loop_node) {
        use Chalk::IR::Node::Phi;

        my %merged = %$bindings;  # Start with current (pre-loop) bindings

        # Get all variable names from body scope
        my %all_vars;
        $all_vars{$_} = 1 for keys %{$body_scope->all_bindings};

        for my $var (keys %all_vars) {
            my $pre_loop_value = $self->lookup($var);
            my $body_value = $body_scope->lookup($var);

            # Skip if variable doesn't exist in both scopes
            next unless defined($pre_loop_value) && defined($body_value);

            # Check if values differ (by ID)
            my $id_pre = ref($pre_loop_value) && $pre_loop_value->can('id')
                ? $pre_loop_value->id : "$pre_loop_value";
            my $id_body = ref($body_value) && $body_value->can('id')
                ? $body_value->id : "$body_value";

            if ($id_pre ne $id_body) {
                # Values differ - create Phi for loop-carried value
                my $phi = Chalk::IR::Node::Phi->new(
                    region => $loop_node,
                    inputs => [$pre_loop_value, $body_value],
                );
                $merged{$var} = $phi;
            } else {
                # Values same - use either one
                $merged{$var} = $pre_loop_value;
            }
        }

        return Chalk::IR::Node::Scope->new(
            bindings        => \%merged,
            current_control => $loop_node,
            parent          => $parent,
        );
    }

    # Return all bindings (including from parent scopes)
    method all_bindings() {
        my %all = $parent ? %{$parent->all_bindings} : ();
        %all = (%all, %$bindings);
        return \%all;
    }

    # Return only this scope's bindings (not parents)
    method local_bindings() {
        return { %$bindings };
    }

    method depth() {
        return $parent ? $parent->depth + 1 : 1;
    }

    method inputs() {
        # Return node IDs as inputs for graph traversal
        return [
            map { ref($_) && $_->can('id') ? $_->id : $_ }
            values %$bindings
        ];
    }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Scope',
            inputs => $self->inputs,
            attributes => {
                depth    => $self->depth,
                bindings => $self->all_bindings,
            },
        };
    }

    method execute() {
        return $self;
    }
}

1;
