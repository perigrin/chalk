# ABOUTME: Sea of Nodes IR node representation for Chalk compiler
# ABOUTME: Represents a single node in the IR graph with operation type, inputs, and attributes
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

# Preload all polymorphic node classes for from_hash() factory
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::NE;
use Chalk::IR::Node::GE;
use Chalk::IR::Node::LE;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Stop;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Reference;
use Chalk::IR::Node::ArrayValue;
use Chalk::IR::Node::HashValue;
use Chalk::IR::Node::ArrayGet;
use Chalk::IR::Node::ArraySet;
use Chalk::IR::Node::HashGet;
use Chalk::IR::Node::HashSet;

class Chalk::IR::Node {
    field $id             :param :reader;
    field $op             :param :reader;
    field $inputs         :param :reader;
    field $attributes     :param :reader;
    field $source_info    :param :reader = undef;
    field $transform_chain :param :reader = undef;

    method to_hash() {
        return {
            id              => $id,
            op              => $op,
            inputs          => $inputs,
            attributes      => $attributes,
            source_info     => $source_info,
            transform_chain => $transform_chain,
        };
    }

    # Get formatted source location string for error messages
    method source_location() {
        return undef unless $source_info;
        return $source_info->to_string();
    }

    # Record a transformation and return a new node with updated chain
    # Support both calling styles for backward compatibility:
    # 1. Positional: record_transform($operation, $name, context => $desc)
    # 2. Named:      record_transform(operation => $op, rule_name => $name, description => $desc)
    method record_transform(@args) {
        my ($operation, $rule_name, %opts);

        if (@args >= 2 && !ref($args[0]) && !ref($args[1]) && $args[0] !~ qr/^(operation|rule_name|description|context|source_node)$/) {
            # Positional style: first two args are scalars, not named params
            ($operation, $rule_name, %opts) = @args;
        } else {
            # Named parameter style
            %opts = @args;
            $operation = $opts{operation};
            $rule_name = $opts{rule_name} // $opts{name};  # Accept both 'rule_name' and 'name'
            # Accept both 'description' and 'context' for the description field
            $opts{context} //= $opts{description};
        }

        my $description = $opts{context} // $opts{description} // undef;

        # Create transform record
        my $transform = {
            operation      => $operation,
            rule_name      => $rule_name,
            description    => $description,
            timestamp      => time(),
            source_node_id => $id,
        };

        # Build new chain: copy existing + new transform
        my $new_chain = $transform_chain ? [$transform_chain->@*] : [];
        push $new_chain->@*, $transform;

        # Return new node with updated chain (immutable pattern)
        return ref($self)->new(
            id              => $id,
            op              => $op,
            inputs          => $inputs,
            attributes      => $attributes,
            source_info     => $source_info,
            transform_chain => $new_chain,
        );
    }

    # Placeholder for peephole optimization - returns self by default
    # Polymorphic node subclasses (Phi, Region, etc.) override this
    method peephole($graph = undef) {
        return $self;
    }

    # Subsume: replace this node with a replacement node in all users
    # Maintains immutability through recursive clone-and-propagate
    #
    # When called as $old->subsume($replacement, $graph):
    #   - Tells all users of $old to replace $old with $replacement in their inputs
    #
    # When called as $user->subsume($replacement, $graph, $target):
    #   - Clones $user with $target replaced by $replacement in inputs
    #   - Adds cloned node to graph
    #   - Recursively tells $user's users to switch to the clone
    #
    # Returns: nothing (modifies graph in place)
    method subsume($replacement, $graph, $target = undef) {
        if (!defined $target) {
            # Initial call: tell all my users to replace me with $replacement
            my @user_ids = $graph->get_uses($id)->@*;
            for my $user_id (@user_ids) {
                my $user = $graph->get_node($user_id);
                next unless $user;
                $user->subsume($replacement, $graph, $self);
            }
        } else {
            # Clone self with $target replaced by $replacement in inputs
            my @new_inputs = map {
                $_ eq $target->id ? $replacement->id : $_
            } $inputs->@*;

            # Update attributes that contain _id references
            my %new_attrs;
            my @attr_keys = keys($attributes->%*);
            for my $key (@attr_keys) {
                my $val = $attributes->{$key};
                if ($key =~ m/_id$/ && defined $val && $val eq $target->id) {
                    $new_attrs{$key} = $replacement->id;
                } else {
                    $new_attrs{$key} = $val;
                }
            }

            my $new_self = ref($self)->new(
                id              => $id . '_subsumed_' . time() . '_' . int(rand(1000)),
                op              => $op,
                inputs          => \@new_inputs,
                attributes      => \%new_attrs,
                source_info     => $source_info,
                transform_chain => $transform_chain,
            );
            $graph->add_node($new_self);

            # Now tell MY users to switch to $new_self
            $self->subsume($new_self, $graph);
        }
        return;
    }

    # Get formatted transformation history for debugging
    method transform_history() {
        return undef unless $transform_chain && $transform_chain->@*;

        my @lines;
        for my $transform ($transform_chain->@*) {
            my $line = sprintf(
                "%s: %s",
                $transform->{operation},
                $transform->{rule_name} // 'unknown'
            );
            if ($transform->{description}) {
                $line .= " - $transform->{description}";
            }
            push @lines, $line;
        }

        return join("\n", @lines);
    }

    # Factory method: create polymorphic node from hash representation
    # Used by GVN to reconstruct nodes while preserving polymorphic types
    sub from_hash($class, $hash) {
        my $op = $hash->{op};
        my $id = $hash->{id};
        my $inputs = $hash->{inputs};
        my $attrs = $hash->{attributes} // {};

        # Map op to polymorphic class
        my %op_to_class = (
            Start    => 'Chalk::IR::Node::Start',
            Constant => 'Chalk::IR::Node::Constant',
            Add      => 'Chalk::IR::Node::Add',
            Subtract => 'Chalk::IR::Node::Subtract',
            Multiply => 'Chalk::IR::Node::Multiply',
            Divide   => 'Chalk::IR::Node::Divide',
            Negate   => 'Chalk::IR::Node::Negate',
            Not      => 'Chalk::IR::Node::Not',
            GT       => 'Chalk::IR::Node::GT',
            LT       => 'Chalk::IR::Node::LT',
            EQ       => 'Chalk::IR::Node::EQ',
            NE       => 'Chalk::IR::Node::NE',
            GE       => 'Chalk::IR::Node::GE',
            LE       => 'Chalk::IR::Node::LE',
            If       => 'Chalk::IR::Node::If',
            Region   => 'Chalk::IR::Node::Region',
            Phi      => 'Chalk::IR::Node::Phi',
            Proj     => 'Chalk::IR::Node::Proj',
            Return     => 'Chalk::IR::Node::Return',
            Stop       => 'Chalk::IR::Node::Stop',
            Loop       => 'Chalk::IR::Node::Loop',
            Reference  => 'Chalk::IR::Node::Reference',
            ArrayValue => 'Chalk::IR::Node::ArrayValue',
            HashValue  => 'Chalk::IR::Node::HashValue',
            ArrayGet   => 'Chalk::IR::Node::ArrayGet',
            ArraySet   => 'Chalk::IR::Node::ArraySet',
            HashGet    => 'Chalk::IR::Node::HashGet',
            HashSet    => 'Chalk::IR::Node::HashSet',
        );

        my $node_class = $op_to_class{$op};

        # Ops that can be safely constructed from hash (no node operands required)
        # These only take scalar attributes, not node references
        my %safe_for_polymorphic = (
            Constant => 1,  # takes value, type
            Start    => 1,  # takes function_name, params
        );

        # For unknown ops or ops that require node operands, create generic node
        # V2 polymorphic nodes for binary ops (Add, Multiply, etc.) require actual
        # node objects for their operands, which we can't provide from a hash
        if (!$node_class || !$safe_for_polymorphic{$op}) {
            return $class->new(
                id              => $id,
                op              => $op,
                inputs          => $inputs,
                attributes      => $attrs,
                source_info     => $hash->{source_info},
                transform_chain => $hash->{transform_chain},
            );
        }

        # Safe to create polymorphic node - these only take scalar attributes
        my %params;

        # Add source_info if present
        if ($hash->{source_info}) {
            $params{source_info} = $hash->{source_info};
        }

        # Add attributes as constructor parameters
        # Parser compat: keys() requires parentheses around argument
        my @attr_keys = keys($attrs->%*);
        for my $key (@attr_keys) {
            $params{$key} = $attrs->{$key};
        }

        # Create polymorphic node - will die on failure (no fallback)
        return $node_class->new(%params);
    }
}

1;
