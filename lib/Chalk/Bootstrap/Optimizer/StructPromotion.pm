# ABOUTME: Struct promotion peephole optimizer — detects hashes with known key sets and rewrites to structs.
# ABOUTME: Pass 1 (analyze): collects schemas. Pass 2 (rewrite): replaces IR nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;

class Chalk::Bootstrap::Optimizer::StructPromotion {

    # Analyze all parsed classes and detect promotable hash schemas.
    # Input: arrayref of { class_name, ir } hashes (one per compiled class).
    # Output: hashref of { schema_name => { fields => [...], constructor_sites => [...], access_sites => [...] } }
    method analyze($parsed_classes) {
        my %var_schemas;     # "$class::$method::$var" => { keys => {}, non_promotable => bool }
        my %schema_registry; # sorted_key_string => { name => ..., fields => [...], ... }

        for my $info ($parsed_classes->@*) {
            my $class_name = $info->{class_name};
            my $ir         = $info->{ir};

            my $class_decl = $self->_find_class_decl($ir);
            next unless defined $class_decl;

            my $body = $class_decl->inputs()->[2];
            next unless defined $body && ref($body) eq 'ARRAY';

            for my $item ($body->@*) {
                next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
                next unless $item->class() eq 'MethodDecl' || $item->class() eq 'SubDecl';

                my $method_name = $item->inputs()->[0]->value();
                my $method_body = $item->inputs()->[2];
                next unless defined $method_body && ref($method_body) eq 'ARRAY';

                $self->_analyze_method_body(
                    $class_name, $method_name, $method_body, \%var_schemas,
                );
            }
        }

        # Unify schemas: group variables by key set, assign schema names
        my %key_set_groups;  # sorted_key_string => [var_key, ...]
        for my $var_key (sort keys %var_schemas) {
            my $info = $var_schemas{$var_key};
            next if $info->{non_promotable};

            my @keys = sort keys $info->{keys}->%*;
            next unless @keys;  # empty key set — nothing to promote

            my $key_string = join(',', @keys);
            push $key_set_groups{$key_string}->@*, $var_key;
        }

        my %schemas;
        my $schema_counter = 0;
        for my $key_string (sort keys %key_set_groups) {
            $schema_counter++;
            my @field_names = split /,/, $key_string;

            # Generate schema name from key hash
            my $schema_name = "struct_${schema_counter}_t";

            my @fields;
            for my $fname (@field_names) {
                push @fields, {
                    name   => $fname,
                    c_type => 'SV *',  # default, refined by type inference later
                };
            }

            $schemas{$schema_name} = {
                fields            => \@fields,
                constructor_sites => [],
                access_sites      => [],
                source_vars       => $key_set_groups{$key_string},
            };
        }

        return \%schemas;
    }

    # Walk a method body and detect hash construction + key accumulation patterns.
    method _analyze_method_body($class_name, $method_name, $body, $var_schemas) {
        my $var_prefix = "${class_name}::${method_name}";

        for my $stmt ($body->@*) {
            next unless defined $stmt;
            $self->_walk_stmt($var_prefix, $stmt, $var_schemas);
        }
    }

    # Recursively walk an IR statement/expression to detect hash patterns.
    method _walk_stmt($var_prefix, $node, $var_schemas) {
        return unless defined $node;
        return unless $node isa Chalk::Bootstrap::IR::Node::Constructor;

        my $class = $node->class();

        # Pattern 1: VarDecl with HashRefExpr initializer (empty or literal)
        if ($class eq 'VarDecl') {
            my $variable    = $node->inputs()->[0];
            my $initializer = $node->inputs()->[1];

            if (defined $initializer
                && $initializer isa Chalk::Bootstrap::IR::Node::Constructor
                && $initializer->class() eq 'HashRefExpr') {

                my $var_name = $variable->value();
                my $var_key  = "${var_prefix}::${var_name}";

                $var_schemas->{$var_key} //= {
                    keys           => {},
                    non_promotable => false,
                };

                # If hash literal has pairs, extract keys
                my $pairs = $initializer->inputs()->[0];
                if (defined $pairs && ref($pairs) eq 'ARRAY') {
                    for (my $i = 0; $i < scalar($pairs->@*); $i += 2) {
                        my $key_node = $pairs->[$i];
                        if (defined $key_node
                            && $key_node isa Chalk::Bootstrap::IR::Node::Constant
                            && $key_node->const_type() eq 'string') {
                            $var_schemas->{$var_key}{keys}{$key_node->value()} = true;
                        } else {
                            # Non-literal key in hash literal
                            $var_schemas->{$var_key}{non_promotable} = true;
                        }
                    }
                }
            }
            return;
        }

        # Pattern 2: BinaryExpr assignment with SubscriptExpr target
        if ($class eq 'BinaryExpr') {
            my $op_node = $node->inputs()->[0];
            my $left    = $node->inputs()->[1];
            my $right   = $node->inputs()->[2];

            if (defined $op_node
                && $op_node isa Chalk::Bootstrap::IR::Node::Constant
                && $op_node->value() eq '=') {

                $self->_check_subscript_access($var_prefix, $left, $var_schemas);
            }

            # Walk both sides for nested patterns
            $self->_walk_stmt($var_prefix, $left, $var_schemas);
            $self->_walk_stmt($var_prefix, $right, $var_schemas);
            return;
        }

        # Pattern 3: Direct SubscriptExpr read access
        if ($class eq 'SubscriptExpr') {
            $self->_check_subscript_access($var_prefix, $node, $var_schemas);
            return;
        }

        # Walk children of any other Constructor node
        my $inputs = $node->inputs();
        for my $input ($inputs->@*) {
            next unless defined $input;
            if (ref($input) eq 'ARRAY') {
                for my $child ($input->@*) {
                    $self->_walk_stmt($var_prefix, $child, $var_schemas);
                }
            } else {
                $self->_walk_stmt($var_prefix, $input, $var_schemas);
            }
        }
    }

    # Check a SubscriptExpr node for hash key access and accumulate keys.
    method _check_subscript_access($var_prefix, $node, $var_schemas) {
        return unless defined $node;
        return unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        return unless $node->class() eq 'SubscriptExpr';

        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2];

        # Only hash subscripts
        return unless defined $style
            && $style isa Chalk::Bootstrap::IR::Node::Constant
            && $style->value() eq 'hash';

        # Target must be a variable
        return unless defined $target
            && $target isa Chalk::Bootstrap::IR::Node::Constant
            && $target->const_type() eq 'variable';

        my $var_name = $target->value();
        my $var_key  = "${var_prefix}::${var_name}";

        # Only track variables already known as hash constructors
        return unless exists $var_schemas->{$var_key};

        # Check if key is a literal string
        if (defined $index
            && $index isa Chalk::Bootstrap::IR::Node::Constant
            && $index->const_type() eq 'string') {
            $var_schemas->{$var_key}{keys}{$index->value()} = true;
        } else {
            # Dynamic key — mark non-promotable
            $var_schemas->{$var_key}{non_promotable} = true;
        }
    }

    # Find the ClassDecl node in the IR tree.
    method _find_class_decl($ir) {
        return unless defined $ir;
        return unless $ir isa Chalk::Bootstrap::IR::Node::Constructor;

        if ($ir->class() eq 'ClassDecl') {
            return $ir;
        }

        if ($ir->class() eq 'Program') {
            my $stmts = $ir->inputs()->[0];
            if (defined $stmts && ref($stmts) eq 'ARRAY') {
                for my $stmt ($stmts->@*) {
                    my $found = $self->_find_class_decl($stmt);
                    return $found if defined $found;
                }
            }
        }

        return;
    }
}
