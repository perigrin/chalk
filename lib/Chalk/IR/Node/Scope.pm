# ABOUTME: Immutable ScopeNode for Sea of Nodes IR - maintains symbol tables for lexical scoping
# ABOUTME: Returns new Scope instances instead of mutating; supports branch merging with Phi creation
use 5.42.0;
use experimental qw(class builtin);
use utf8;
use Scalar::Util qw(refaddr);

class Chalk::IR::Node::Scope {
    # Immutable Scope - all "mutation" methods return new Scope instances

    field $bindings :param :reader = {};        # { var_name => node }
    field $current_control :param :reader = undef;
    field $parent :param :reader = undef;       # Parent scope for nested lookups
    field $loop_node :param :reader = undef;    # Loop node for lazy phi creation (Issue #246)

    method id() { refaddr($self) }

    ADJUST {
        # Deep copy bindings to ensure immutability
        $bindings = { $bindings->%* };
    }

    method op() { 'Scope' }

    # Immutable: return new Scope with added binding
    # If we're in a loop and assigning to a phi, update the phi's backedge
    method with_binding($name, $node) {
        my %new_bindings = ($bindings->%*, $name => $node);

        # If we're in a loop scope and the current binding is a Phi, update its backedge
        if ($loop_node && exists $bindings->{$name}) {
            my $current = $bindings->{$name};
            if (ref($current) && blessed($current) && $current->can('op') && $current->op eq 'Phi') {
                # Add the new value as the backedge input to the phi
                push $current->inputs->@*, $node->id;
            }
        }

        return Chalk::IR::Node::Scope->new(
            bindings        => \%new_bindings,
            current_control => $current_control,
            parent          => $parent,
            loop_node       => $loop_node,
        );
    }

    # Immutable: return new Scope with updated control
    method with_control($new_control) {
        return Chalk::IR::Node::Scope->new(
            bindings        => $bindings,
            current_control => $new_control,
            parent          => $parent,
            loop_node       => $loop_node,
        );
    }

    # Immutable: return new child Scope (for entering blocks)
    method child_scope() {
        return Chalk::IR::Node::Scope->new(
            bindings        => {},
            current_control => $current_control,
            parent          => $self,
            loop_node       => $loop_node,
        );
    }

    # Enter a loop - marks all current variables with sentinels for lazy phi creation
    # Per Simple Chapter 8: sentinel values trigger phi creation on lookup
    method enter_loop($loop) {
        my %loop_bindings;

        # Mark all bindings with sentinel (this scope itself)
        # When lookup encounters a sentinel, it will create a phi lazily
        for my $name (keys $self->all_bindings->%*) {
            $loop_bindings{$name} = $self;  # Sentinel = the Scope itself
        }

        return Chalk::IR::Node::Scope->new(
            bindings        => \%loop_bindings,
            current_control => $loop->id,
            parent          => $self,
            loop_node       => $loop,
        );
    }

    # Check if a value is a sentinel (the scope marking a lazy phi location)
    method is_sentinel($value) {
        return 0 unless defined $value;
        return 0 unless ref($value);
        return 0 unless blessed($value);
        return $value->isa('Chalk::IR::Node::Scope');
    }

    # Exit a loop - replaces any remaining sentinels with parent values
    method exit_loop() {
        my %exit_bindings;

        for my $name (keys $bindings->%*) {
            my $value = $bindings->{$name};
            if ($self->is_sentinel($value)) {
                # Sentinel not accessed - get original value from parent
                $exit_bindings{$name} = $value->lookup($name);
            } else {
                # Either a phi was created or value was set directly
                $exit_bindings{$name} = $value;
            }
        }

        return Chalk::IR::Node::Scope->new(
            bindings        => \%exit_bindings,
            current_control => $current_control,
            parent          => $parent,
            loop_node       => undef,  # No longer in a loop
        );
    }

    # Look up a variable, searching from this scope up through parents
    # If we find a sentinel, create a phi lazily
    method lookup($name) {
        if (exists $bindings->{$name}) {
            my $value = $bindings->{$name};

            # Check for sentinel (lazy phi marker)
            if ($self->is_sentinel($value)) {
                # Lazy phi creation - get initial value from sentinel scope
                my $init_value = $value->lookup($name);

                # Create Phi node with loop as region
                my $phi = Chalk::IR::Node->new(
                    id     => "phi_${name}_" . $loop_node->id,
                    op     => 'Phi',
                    inputs => [$loop_node->id, $init_value->id],  # [region, init] - backedge TBD
                    attributes => { var_name => $name },
                );

                # Replace sentinel with phi (mutation for efficiency)
                $bindings->{$name} = $phi;

                return $phi;
            }

            return $value;
        }
        if ($parent) {
            return $parent->lookup($name);
        }
        return undef;
    }

    # Merge two scopes, creating Phi nodes for variables that differ
    # Used for both branch merging (if/else) and loop merging (while)
    # $scope_a and $scope_b are the two scopes to merge
    # $control_node is the Region or Loop node that owns the Phi nodes
    method merge_scopes($scope_a, $scope_b, $control_node) {
        use Chalk::IR::Node::Phi;

        my %merged = $bindings->%*;  # Start with current (pre-merge) bindings

        # Get all variable names from both scopes
        my %all_vars;
        $all_vars{$_} = 1 for keys %{$scope_a->all_bindings};
        $all_vars{$_} = 1 for keys %{$scope_b->all_bindings};

        for my $var (keys %all_vars) {
            # $ctrl is control flow, not data - just copy, don't create Phi
            # Per Simple Chapter 7: "The control input is just copied"
            next if $var eq '$ctrl';

            my $val_a = $scope_a->lookup($var);
            my $val_b = $scope_b->lookup($var);

            # Skip if variable doesn't exist in both scopes
            next unless defined($val_a) && defined($val_b);

            # Check if values differ (by ID)
            my $id_a = ref($val_a) && blessed($val_a) && $val_a->can('id') ? $val_a->id : "$val_a";
            my $id_b = ref($val_b) && blessed($val_b) && $val_b->can('id') ? $val_b->id : "$val_b";

            if ($id_a ne $id_b) {
                # Values differ - create Phi
                # Get the region ID (control_node is the Region/Loop object)
                my $region_id = ref($control_node) && blessed($control_node) && $control_node->can('id')
                    ? $control_node->id
                    : $control_node;
                my $phi = Chalk::IR::Node::Phi->new(
                    region_id => $region_id,
                    inputs => [$region_id, $val_a, $val_b],
                );
                $merged{$var} = $phi;
            } else {
                # Values same - use either one
                $merged{$var} = $val_a;
            }
        }

        # Bind $ctrl to the merge control node (Region/Loop)
        # Per Simple Chapter 7: "The control input is just copied" (not Phi'd)
        $merged{'$ctrl'} = $control_node;

        return Chalk::IR::Node::Scope->new(
            bindings        => \%merged,
            current_control => $control_node,
            parent          => $parent,
            loop_node       => $loop_node,
        );
    }

    # Return all bindings (including from parent scopes)
    method all_bindings() {
        my %all = $parent ? $parent->all_bindings->%* : ();
        %all = (%all, $bindings->%*);
        return \%all;
    }

    # Return only this scope's bindings (not parents)
    method local_bindings() {
        return { $bindings->%* };
    }

    method depth() {
        return $parent ? $parent->depth + 1 : 1;
    }

    method inputs() {
        # Return node IDs as inputs for graph traversal
        return [
            map { ref($_) && blessed($_) && $_->can('id') ? $_->id : $_ }
            values $bindings->%*
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
