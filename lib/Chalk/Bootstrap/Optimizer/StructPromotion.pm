# ABOUTME: Struct promotion peephole optimizer — detects hashes with known key sets and rewrites to structs.
# ABOUTME: Pass 1 (analyze): collects schemas. Pass 2 (rewrite): replaces IR nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::Node;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::Subscript;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::Program;

class Chalk::Bootstrap::Optimizer::StructPromotion {

    # Set of compiled class names — used by escape analysis
    field $compiled_classes = {};

    # Per-field usage tracking for C type inference
    # var_key => { field_name => { integer_ctx => bool } }
    field $field_usage = {};

    # Top-level entry point: analyze schemas, then rewrite IR.
    # Input: arrayref of { class_name, ir, ... } hashes.
    # Returns: (rewritten_classes, schemas) in list context.
    method run($parsed_classes) {
        my $schemas = $self->analyze($parsed_classes);

        if (!keys $schemas->%*) {
            # No promotable schemas — return input unchanged
            return ($parsed_classes, $schemas);
        }

        my $rewritten = $self->rewrite($parsed_classes, $schemas);
        return ($rewritten, $schemas);
    }

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

            my $body = $class_decl->body();
            next unless defined $body && ref($body) eq 'ARRAY';

            for my $item ($body->@*) {
                my ($method_name, $method_body);
                if ($item isa Chalk::IR::MethodInfo) {
                    $method_name = $item->name();
                    $method_body = $item->body();
                } elsif ($item isa Chalk::IR::SubInfo) {
                    $method_name = $item->name();
                    $method_body = $item->body();
                } else {
                    next;
                }

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
        return unless $node isa Chalk::IR::Node;

        # Pattern 1: VarDecl with HashRefExpr initializer (empty or literal)
        if ($node isa Chalk::IR::Node::VarDecl) {
            my $variable    = $node->inputs()->[0];
            my $initializer = $node->inputs()->[1];

            if (defined $initializer
                && $initializer isa Chalk::IR::Node::HashRef) {

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
        if ($node isa Chalk::IR::Node::BinOp) {
            my $op_node = $node->inputs()->[0];
            my $left    = $node->inputs()->[1];
            my $right   = $node->inputs()->[2];

            if (defined $op_node && $op_node isa Chalk::Bootstrap::IR::Node::Constant) {
                my $op_val = $op_node->value();

                if ($op_val eq '=') {
                    $self->_check_subscript_access($var_prefix, $left, $var_schemas);

                    # Type inference: if RHS is integer constant, mark field as integer
                    if (defined $left
                        && $left isa Chalk::IR::Node::Subscript) {
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
        if ($node isa Chalk::IR::Node::Subscript) {
            $self->_check_subscript_access($var_prefix, $node, $var_schemas);
            return;
        }

        # Walk children of any other IR node
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
        return unless $node isa Chalk::IR::Node::Subscript;

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

        # Return CFG node in a public method — returned value may escape.
        if ($node isa Chalk::IR::Node::Return && $is_public) {
            my $value = $node->inputs()->[1];  # inputs[0]=control, inputs[1]=value
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

        my $class = $node->class();

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
        return unless $node isa Chalk::IR::Node::Subscript;

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

    # Pass 2: Rewrite IR nodes for validated schemas.
    # Input: parsed_classes arrayref, schemas hashref from analyze().
    # Output: rewritten parsed_classes arrayref (shallow copies with new IR).
    method rewrite($parsed_classes, $schemas) {
        my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

        # Build reverse map: var_key → schema_name
        my %var_to_schema;
        for my $sname (sort keys $schemas->%*) {
            my $svars = $schemas->{$sname}{source_vars};
            for my $vk ($svars->@*) {
                $var_to_schema{$vk} = $sname;
            }
        }

        # Build schema field-name lookup: schema_name → [field_name, ...]
        my %schema_fields;
        for my $sname (sort keys $schemas->%*) {
            $schema_fields{$sname} = [
                map { $_->{name} } $schemas->{$sname}{fields}->@*
            ];
        }

        my @result;
        for my $info ($parsed_classes->@*) {
            my $class_name = $info->{class_name};
            my $ir         = $info->{ir};

            my $class_decl = $self->_find_class_decl($ir);
            unless (defined $class_decl) {
                push @result, { $info->%* };
                next;
            }

            my $body = $class_decl->body();
            unless (defined $body && ref($body) eq 'ARRAY') {
                push @result, { $info->%* };
                next;
            }

            # Check if any promoted var belongs to this class
            my $class_has_promoted = false;
            for my $vk (sort keys %var_to_schema) {
                if ($vk =~ /^\Q$class_name\E::/) {
                    $class_has_promoted = true;
                    last;
                }
            }

            unless ($class_has_promoted) {
                push @result, { $info->%* };
                next;
            }

            my @new_body;
            for my $item ($body->@*) {
                # Handle MethodInfo metadata structs
                if ($item isa Chalk::IR::MethodInfo) {
                    my $method_name = $item->name();
                    my $method_body = $item->body();
                    my $var_prefix  = "${class_name}::${method_name}";

                    my $method_has_promoted = false;
                    for my $vk (sort keys %var_to_schema) {
                        if ($vk =~ /^\Q$var_prefix\E::/) {
                            $method_has_promoted = true;
                            last;
                        }
                    }

                    unless ($method_has_promoted && defined $method_body
                        && ref($method_body) eq 'ARRAY') {
                        push @new_body, $item;
                        next;
                    }

                    my $new_method_body = $self->_rewrite_method_body(
                        $factory, $var_prefix, $method_body,
                        \%var_to_schema, \%schema_fields,
                    );
                    push @new_body, Chalk::IR::MethodInfo->new(
                        name        => $item->name(),
                        params      => $item->params(),
                        return_type => $item->return_type(),
                        body        => $new_method_body,
                        graph       => $item->graph(),
                    );
                    next;
                }

                # Handle SubInfo metadata structs
                if ($item isa Chalk::IR::SubInfo) {
                    my $method_name = $item->name();
                    my $method_body = $item->body();
                    my $var_prefix  = "${class_name}::${method_name}";

                    my $method_has_promoted = false;
                    for my $vk (sort keys %var_to_schema) {
                        if ($vk =~ /^\Q$var_prefix\E::/) {
                            $method_has_promoted = true;
                            last;
                        }
                    }

                    unless ($method_has_promoted && defined $method_body
                        && ref($method_body) eq 'ARRAY') {
                        push @new_body, $item;
                        next;
                    }

                    my $new_method_body = $self->_rewrite_method_body(
                        $factory, $var_prefix, $method_body,
                        \%var_to_schema, \%schema_fields,
                    );
                    push @new_body, Chalk::IR::SubInfo->new(
                        name   => $item->name(),
                        params => $item->params(),
                        scope  => $item->scope(),
                        body   => $new_method_body,
                        graph  => $item->graph(),
                    );
                    next;
                }

                push @new_body, $item;
            }

            # Rebuild class declaration with new body.
            my $new_class;
            {
                # Partition new body into fields/methods/subs for structured access
                my (@fields, @methods, @subs);
                for my $item (@new_body) {
                    if ($item isa Chalk::IR::FieldInfo)  { push @fields,  $item; }
                    elsif ($item isa Chalk::IR::MethodInfo) { push @methods, $item; }
                    elsif ($item isa Chalk::IR::SubInfo)    { push @subs,    $item; }
                }
                $new_class = Chalk::IR::ClassInfo->new(
                    name    => $class_decl->name(),
                    parent  => $class_decl->parent(),
                    fields  => \@fields,
                    methods => \@methods,
                    subs    => \@subs,
                    body    => \@new_body,
                );
            }

            # Rebuild Program
            my $new_program = $factory->make('Constructor',
                class      => 'Program',
                statements => [$new_class],
            );

            push @result, {
                $info->%*,
                ir => $new_program,
            };
        }

        return \@result;
    }

    # Rewrite a method body: replace hash construct + assign patterns with StructRef,
    # and replace SubscriptExpr on promoted vars with FieldAccess.
    method _rewrite_method_body($factory, $var_prefix, $body, $var_to_schema, $schema_fields) {
        # First pass: collect assignment values for each promoted var.
        # Pattern: VarDecl($var, HashRefExpr([])) followed by BinaryExpr('=', SubscriptExpr($var, key), val)
        my %promoted_vars;   # var_name => schema_name
        my %field_values;    # var_name => { field_name => value_node }
        my %to_remove;       # index => true (assignment statements to remove)

        for (my $i = 0; $i < scalar($body->@*); $i++) {
            my $stmt = $body->[$i];
            next unless defined $stmt && $stmt isa Chalk::IR::Node;

            # Detect VarDecl with empty HashRefExpr
            if ($stmt isa Chalk::IR::Node::VarDecl) {
                my $var_node    = $stmt->inputs()->[0];
                my $initializer = $stmt->inputs()->[1];

                next unless defined $initializer
                    && $initializer isa Chalk::IR::Node::HashRef;

                my $var_name = $var_node->value();
                my $var_key  = "${var_prefix}::${var_name}";

                if (exists $var_to_schema->{$var_key}) {
                    $promoted_vars{$var_name} = $var_to_schema->{$var_key};
                    $field_values{$var_name}  = {};
                }
            }

            # Detect assignment: $var->{key} = val
            if ($stmt isa Chalk::IR::Node::BinOp) {
                my $op_node = $stmt->inputs()->[0];
                next unless defined $op_node
                    && $op_node isa Chalk::Bootstrap::IR::Node::Constant
                    && $op_node->value() eq '=';

                my $left = $stmt->inputs()->[1];
                next unless defined $left
                    && $left isa Chalk::IR::Node::Subscript;

                my $target = $left->inputs()->[0];
                next unless defined $target
                    && $target isa Chalk::Bootstrap::IR::Node::Constant
                    && $target->const_type() eq 'variable';

                my $var_name = $target->value();
                next unless exists $promoted_vars{$var_name};

                my $index = $left->inputs()->[1];
                next unless defined $index
                    && $index isa Chalk::Bootstrap::IR::Node::Constant
                    && $index->const_type() eq 'string';

                my $field_name = $index->value();
                my $rhs = $stmt->inputs()->[2];

                $field_values{$var_name}{$field_name} = $rhs;
                $to_remove{$i} = true;
            }
        }

        # Second pass: build new statements
        my @new_body;
        for (my $i = 0; $i < scalar($body->@*); $i++) {
            # Skip removed assignment statements
            next if $to_remove{$i};

            my $stmt = $body->[$i];

            # Replace VarDecl(HashRefExpr) with VarDecl(StructRef)
            if (defined $stmt
                && $stmt isa Chalk::IR::Node::VarDecl) {

                my $var_node = $stmt->inputs()->[0];
                my $var_name = $var_node->value();

                if (exists $promoted_vars{$var_name}) {
                    my $schema_name = $promoted_vars{$var_name};
                    my $field_names = $schema_fields->{$schema_name};

                    # Build field value array in schema field order
                    my @field_vals;
                    for my $fname ($field_names->@*) {
                        push @field_vals, $field_values{$var_name}{$fname};
                    }

                    my $schema_node = $factory->make('Constant',
                        const_type => 'string',
                        value      => $schema_name,
                    );

                    my $struct_ref = $factory->make('Constructor',
                        class  => 'StructRef',
                        schema => $schema_node,
                        fields => \@field_vals,
                    );

                    my $new_var_decl = $factory->make('Constructor',
                        class       => 'VarDecl',
                        variable    => $var_node,
                        initializer => $struct_ref,
                    );

                    push @new_body, $new_var_decl;
                    next;
                }
            }

            # Rewrite any SubscriptExpr on promoted vars to FieldAccess
            my $rewritten = $self->_rewrite_node(
                $factory, $var_prefix, $stmt,
                \%promoted_vars, $var_to_schema, $schema_fields,
            );
            push @new_body, $rewritten;
        }

        return \@new_body;
    }

    # Recursively rewrite a single IR node, replacing SubscriptExpr → FieldAccess
    # on promoted variables.
    method _rewrite_node($factory, $var_prefix, $node, $promoted_vars, $var_to_schema, $schema_fields) {
        return $node unless defined $node;
        return $node unless $node isa Chalk::IR::Node;

        # Replace SubscriptExpr on promoted var with FieldAccess
        if ($node isa Chalk::IR::Node::Subscript) {
            my $target = $node->inputs()->[0];
            my $index  = $node->inputs()->[1];
            my $style  = $node->inputs()->[2];

            if (defined $style
                && $style isa Chalk::Bootstrap::IR::Node::Constant
                && $style->value() eq 'hash'
                && defined $target
                && $target isa Chalk::Bootstrap::IR::Node::Constant
                && $target->const_type() eq 'variable'
                && exists $promoted_vars->{$target->value()}
                && defined $index
                && $index isa Chalk::Bootstrap::IR::Node::Constant
                && $index->const_type() eq 'string') {

                my $schema_name = $promoted_vars->{$target->value()};
                my $schema_node = $factory->make('Constant',
                    const_type => 'string',
                    value      => $schema_name,
                );

                return $factory->make('Constructor',
                    class      => 'FieldAccess',
                    schema     => $schema_node,
                    field_name => $index,
                    target     => $target,
                );
            }
        }

        # Recursively rewrite inputs
        my $inputs = $node->inputs();
        my @new_inputs;
        my $changed = false;

        for my $input ($inputs->@*) {
            if (!defined $input) {
                push @new_inputs, undef;
            } elsif (ref($input) eq 'ARRAY') {
                my @new_array;
                for my $child ($input->@*) {
                    my $new_child = $self->_rewrite_node(
                        $factory, $var_prefix, $child,
                        $promoted_vars, $var_to_schema, $schema_fields,
                    );
                    push @new_array, $new_child;
                    $changed = true if !defined $child || !defined $new_child
                        || refaddr($new_child) != refaddr($child);
                }
                push @new_inputs, \@new_array;
            } else {
                my $new_input = $self->_rewrite_node(
                    $factory, $var_prefix, $input,
                    $promoted_vars, $var_to_schema, $schema_fields,
                );
                push @new_inputs, $new_input;
                $changed = true if refaddr($new_input) != refaddr($input);
            }
        }

        # If nothing changed, return original node
        return $node unless $changed;

        # Rebuild the Constructor node with new inputs
        # Use the INPUT_SPECS to map positional inputs back to named params
        return $self->_rebuild_constructor($factory, $node, \@new_inputs);
    }

    # Rebuild a Constructor node with new inputs, preserving class and attributes.
    method _rebuild_constructor($factory, $original, $new_inputs) {
        my $class = $original->class();

        # Map input positions back to named parameters using INPUT_SPECS knowledge.
        # This is the inverse of NodeFactory's make() parameter separation.
        my %input_specs = (
            'Program'        => ['statements'],
            'ClassDecl'      => ['name', 'parent', 'body'],
            'MethodDecl'     => ['name', 'params', 'body', 'return_type'],
            'SubDecl'        => ['name', 'params', 'body', 'scope'],
            'VarDecl'        => ['variable', 'initializer'],
            'BinaryExpr'     => ['op', 'left', 'right'],
            'UnaryExpr'      => ['op', 'operand'],
            'SubscriptExpr'  => ['target', 'index', 'style'],
            'MethodCallExpr' => ['invocant', 'method_name', 'args'],
            'BuiltinCall'    => ['name', 'args'],
            'HashRefExpr'    => ['pairs'],
            'ArrayRefExpr'   => ['elements'],
            'TernaryExpr'    => ['condition', 'true_expr', 'false_expr'],
            'PostfixDerefExpr' => ['target', 'sigil'],
            'CompoundAssign' => ['op', 'target', 'value'],
            'FieldDecl'      => ['name', 'attributes', 'default_value'],
            'AnonSubExpr'    => ['params', 'body'],
            'RegexMatch'     => ['target', 'pattern', 'flags'],
            'RegexSubst'     => ['target', 'pattern', 'replacement', 'flags'],
            'TryCatchStmt'   => ['try_body', 'catch_var', 'catch_body'],
            'InterpolatedString' => ['parts'],
            'BacktickExpr'   => ['command'],
            'StructRef'      => ['schema', 'fields'],
            'FieldAccess'    => ['schema', 'field_name', 'target'],
        );

        my $names = $input_specs{$class};
        unless ($names) {
            # Unknown class — return original
            return $original;
        }

        my %params = (class => $class);
        for my $i (0 .. $#{$names}) {
            $params{$names->[$i]} = $new_inputs->[$i];
        }

        return $factory->make('Constructor', %params);
    }

    # Find the ClassDecl or ClassInfo node in the IR tree.
    # Returns ClassInfo if available, falls back to Constructor:ClassDecl.
    method _find_class_decl($ir) {
        return unless defined $ir;

        # Chalk::IR::Program — walk its classes list
        if ($ir isa Chalk::IR::Program) {
            for my $stmt ($ir->classes()->@*) {
                return $stmt if $stmt isa Chalk::IR::ClassInfo;
            }
            return;
        }

        # Direct ClassInfo match (for calls with a class node directly)
        return $ir if $ir isa Chalk::IR::ClassInfo;

        return;
    }
}
