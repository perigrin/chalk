# ABOUTME: Struct promotion peephole optimizer — detects hashes with known key sets and rewrites to structs.
# ABOUTME: Pass 1 (analyze): collects schemas. Pass 2 (rewrite): replaces IR nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;

class Chalk::Bootstrap::Optimizer::StructPromotion {

    # Set of compiled class names — used by escape analysis
    field $compiled_classes = {};

    # Per-field usage tracking for C type inference
    # var_key => { field_name => { integer_ctx => bool } }
    field $field_usage = {};

    # Analyze all parsed classes and detect promotable hash schemas.
    # Input: arrayref of { class_name, ir } hashes (one per compiled class).
    # Output: hashref of { schema_name => { fields => [...], constructor_sites => [...], access_sites => [...] } }
    method analyze($parsed_classes) {
        my %var_schemas;     # "$class::$method::$var" => { keys => {}, non_promotable => bool }

        # Build compiled-class set for escape analysis
        $compiled_classes = {};
        for my $info ($parsed_classes->@*) {
            $compiled_classes->{$info->{class_name}} = true;
        }

        $field_usage = {};

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

                my $is_public = ($method_name !~ /^_/);

                $self->_analyze_method_body(
                    $class_name, $method_name, $method_body,
                    \%var_schemas, $is_public,
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

            # Infer C types from field usage across all variables in this schema
            my @fields;
            my $var_keys = $key_set_groups{$key_string};
            for my $fname (@field_names) {
                my $is_iv = false;
                for my $vk ($var_keys->@*) {
                    if (exists $field_usage->{$vk}
                        && exists $field_usage->{$vk}{$fname}
                        && $field_usage->{$vk}{$fname}{integer_ctx}) {
                        $is_iv = true;
                    }
                }
                push @fields, {
                    name   => $fname,
                    c_type => $is_iv ? 'IV' : 'SV *',
                };
            }

            $schemas{$schema_name} = {
                fields            => \@fields,
                constructor_sites => [],
                access_sites      => [],
                source_vars       => $var_keys,
            };
        }

        return \%schemas;
    }

    # Walk a method body and detect hash construction + key accumulation patterns.
    method _analyze_method_body($class_name, $method_name, $body, $var_schemas, $is_public) {
        my $var_prefix = "${class_name}::${method_name}";

        for my $stmt ($body->@*) {
            next unless defined $stmt;
            $self->_walk_stmt($var_prefix, $stmt, $var_schemas);
        }

        # Escape analysis: check for hash variables returned from public methods
        # or passed as arguments to method calls on potentially uncompiled objects.
        for my $stmt ($body->@*) {
            next unless defined $stmt;
            $self->_check_escapes($var_prefix, $stmt, $var_schemas, $is_public);
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

            if (defined $op_node && $op_node isa Chalk::Bootstrap::IR::Node::Constant) {
                my $op_val = $op_node->value();

                if ($op_val eq '=') {
                    $self->_check_subscript_access($var_prefix, $left, $var_schemas);

                    # Type inference: if RHS is integer constant, mark field as integer
                    if (defined $left
                        && $left isa Chalk::Bootstrap::IR::Node::Constructor
                        && $left->class() eq 'SubscriptExpr') {
                        $self->_infer_field_type($var_prefix, $left, $right, $var_schemas);
                    }
                }

                # Arithmetic operators mark both operands as integer context
                my %arith_ops = map { $_ => 1 } qw(+ - * / % < > <= >= == != <=>);
                if (exists $arith_ops{$op_val}) {
                    $self->_mark_integer_context($var_prefix, $left, $var_schemas);
                    $self->_mark_integer_context($var_prefix, $right, $var_schemas);
                }
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

    # Escape analysis: check if hash variables escape to uncompiled code.
    # A hash escapes if:
    #   1. Returned from a public method (callable by uncompiled code)
    #   2. Passed as an argument to a method call on an object that may not be compiled
    method _check_escapes($var_prefix, $node, $var_schemas, $is_public) {
        return unless defined $node;
        return unless $node isa Chalk::Bootstrap::IR::Node::Constructor;

        my $class = $node->class();

        # ReturnStmt in a public method — hash escapes
        if ($class eq 'ReturnStmt' && $is_public) {
            my $value = $node->inputs()->[0];
            if (defined $value
                && $value isa Chalk::Bootstrap::IR::Node::Constant
                && $value->const_type() eq 'variable') {
                my $var_key = "${var_prefix}::${\$value->value()}";
                if (exists $var_schemas->{$var_key}) {
                    $var_schemas->{$var_key}{non_promotable} = true;
                }
            }
            return;
        }

        # MethodCallExpr — check if any hash variable is passed as an argument.
        # If the invocant is $self, the call stays in compiled code (same class).
        # Otherwise, conservatively assume the target might be uncompiled.
        if ($class eq 'MethodCallExpr') {
            my $invocant = $node->inputs()->[0];
            my $is_self  = (defined $invocant
                && $invocant isa Chalk::Bootstrap::IR::Node::Constant
                && $invocant->const_type() eq 'variable'
                && $invocant->value() eq '$self');

            unless ($is_self) {
                my $args = $node->inputs()->[2];
                if (defined $args && ref($args) eq 'ARRAY') {
                    for my $arg ($args->@*) {
                        if (defined $arg
                            && $arg isa Chalk::Bootstrap::IR::Node::Constant
                            && $arg->const_type() eq 'variable') {
                            my $var_key = "${var_prefix}::${\$arg->value()}";
                            if (exists $var_schemas->{$var_key}) {
                                $var_schemas->{$var_key}{non_promotable} = true;
                            }
                        }
                    }
                }
            }
        }

        # Walk children recursively
        my $inputs = $node->inputs();
        for my $input ($inputs->@*) {
            next unless defined $input;
            if (ref($input) eq 'ARRAY') {
                for my $child ($input->@*) {
                    $self->_check_escapes($var_prefix, $child, $var_schemas, $is_public);
                }
            } else {
                $self->_check_escapes($var_prefix, $input, $var_schemas, $is_public);
            }
        }
    }

    # Type inference: infer C type for a field from its assigned value.
    method _infer_field_type($var_prefix, $subscript_node, $rhs, $var_schemas) {
        my $target = $subscript_node->inputs()->[0];
        my $index  = $subscript_node->inputs()->[1];
        my $style  = $subscript_node->inputs()->[2];

        return unless defined $style
            && $style isa Chalk::Bootstrap::IR::Node::Constant
            && $style->value() eq 'hash';

        return unless defined $target
            && $target isa Chalk::Bootstrap::IR::Node::Constant
            && $target->const_type() eq 'variable';

        return unless defined $index
            && $index isa Chalk::Bootstrap::IR::Node::Constant
            && $index->const_type() eq 'string';

        my $var_key    = "${var_prefix}::${\$target->value()}";
        my $field_name = $index->value();

        return unless exists $var_schemas->{$var_key};

        # If RHS is an integer constant, mark field as integer context
        if (defined $rhs
            && $rhs isa Chalk::Bootstrap::IR::Node::Constant
            && $rhs->const_type() eq 'integer') {
            $field_usage->{$var_key}{$field_name}{integer_ctx} = true;
        }
    }

    # Mark a SubscriptExpr node's field as used in integer context (arithmetic).
    method _mark_integer_context($var_prefix, $node, $var_schemas) {
        return unless defined $node;
        return unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        return unless $node->class() eq 'SubscriptExpr';

        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2];

        return unless defined $style
            && $style isa Chalk::Bootstrap::IR::Node::Constant
            && $style->value() eq 'hash';

        return unless defined $target
            && $target isa Chalk::Bootstrap::IR::Node::Constant
            && $target->const_type() eq 'variable';

        return unless defined $index
            && $index isa Chalk::Bootstrap::IR::Node::Constant
            && $index->const_type() eq 'string';

        my $var_key    = "${var_prefix}::${\$target->value()}";
        my $field_name = $index->value();

        return unless exists $var_schemas->{$var_key};

        $field_usage->{$var_key}{$field_name}{integer_ctx} = true;
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
