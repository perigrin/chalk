# ABOUTME: Struct promotion peephole optimizer — detects hashes with known key sets and rewrites to structs.
# ABOUTME: Pass 1 (analyze): collects schemas. Pass 2 (rewrite): replaces IR nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed);

use Chalk::Bootstrap::Optimizer::Pass;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::StructRef;
use Chalk::IR::Node::StructFieldAccess;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::Program;
use Chalk::MOP;

class Chalk::Bootstrap::Optimizer::StructPromotion
    :isa(Chalk::Bootstrap::Optimizer::Pass)
{

    # Set of compiled class names — used by escape analysis
    field $compiled_classes = {};

    # Per-field usage tracking for C type inference
    # var_key => { field_name => { integer_ctx => bool } }
    field $field_usage = {};

    # Typed factory for direct node construction. Replaces the Shim
    # path which is being retired in Phase 6.
    field $typed;
    ADJUST { $typed = Chalk::IR::NodeFactory->new }

    method name()  { return 'StructPromotion' }
    method scope() { return 'mop' }

    # Top-level entry point. Polymorphic on input:
    #   - Chalk::MOP: Phase 5 contract. Schemas are attached as a side
    #     structure accessible via $mop->struct_promotion_schemas.
    #     Returns the MOP (no rewriting yet - rewrite_mop is a follow-up
    #     once MOP carries enough body shape to be rewritten in place).
    #   - arrayref of { class_name, ir } hashes: legacy contract.
    #     Returns (rewritten, schemas) in list context, $rewritten in
    #     scalar context.
    method run($input) {
        if (defined($input) && blessed($input) && $input isa Chalk::MOP) {
            return $self->_run_mop($input);
        }
        return $self->_run_legacy($input);
    }

    method _run_mop($mop) {
        # Walk MOP::Class entities directly — no ClassInfo synthesis.
        # Schemas are attached as a side structure on the MOP.
        my $schemas = $self->_analyze_mop($mop);
        $mop->set_struct_promotion_schemas($schemas) if keys $schemas->%*;
        return $mop;
    }

    method _run_legacy($parsed_classes) {
        my $schemas = $self->analyze($parsed_classes);

        if (!keys $schemas->%*) {
            # No promotable schemas — return input unchanged
            return ($parsed_classes, $schemas);
        }

        my $rewritten = $self->rewrite($parsed_classes, $schemas);
        return ($rewritten, $schemas);
    }

    # MOP-driven analyze: walk MOP::Class entities directly without
    # synthesizing ClassInfo/MethodInfo wrappers. Reuses the per-method
    # detection logic via _analyze_method_body (which operates on a
    # body arrayref — same shape as MOP::Method.body today).
    #
    # When MOP::Method.body is retired in Phase 6 alongside this
    # migration, the input source switches from $method->body to
    # walking $method->graph (the IR side-effect chain). For now we
    # keep reading body so this commit is purely a synthesis-layer
    # removal, not a body-vs-graph swap.
    method _analyze_mop($mop) {
        my %var_schemas;

        # Build compiled-class set for escape analysis.
        $compiled_classes = {};
        for my $cls ($mop->classes()) {
            next if $cls->name eq 'main';
            $compiled_classes->{$cls->name} = true;
        }

        $field_usage = {};

        for my $cls ($mop->classes()) {
            next if $cls->name eq 'main';
            my $class_name = $cls->name;

            for my $method ($cls->methods) {
                my $method_name = $method->name;
                my $method_body = $method->body;
                next unless defined $method_body && ref($method_body) eq 'ARRAY';

                my $is_public = ($method_name !~ /^_/);
                $self->_analyze_method_body(
                    $class_name, $method_name, $method_body,
                    \%var_schemas, $is_public,
                );
            }

            for my $sub ($cls->subs) {
                my $sub_name = $sub->name;
                my $sub_body = $sub->body;
                next unless defined $sub_body && ref($sub_body) eq 'ARRAY';

                my $is_public = ($sub_name !~ /^_/);
                $self->_analyze_method_body(
                    $class_name, $sub_name, $sub_body,
                    \%var_schemas, $is_public,
                );
            }
        }

        return $self->_finalize_schemas(\%var_schemas);
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

        return $self->_finalize_schemas(\%var_schemas);
    }

    # Common post-processing for both analyze() (legacy parsed-classes
    # input) and _analyze_mop() (MOP-shaped input). Both populate
    # %var_schemas and $field_usage the same way; the schema unification
    # logic is identical from there on.
    method _finalize_schemas($var_schemas) {
        # Unify schemas: group variables by key set, assign schema names
        my %key_set_groups;  # sorted_key_string => [var_key, ...]
        for my $var_key (sort keys $var_schemas->%*) {
            my $info = $var_schemas->{$var_key};
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
            my $variable    = $node->name();
            my $initializer = $node->init();

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
                            && $key_node isa Chalk::IR::Node::Constant
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

            if (defined $op_node && $op_node isa Chalk::IR::Node::Constant) {
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
            && $style isa Chalk::IR::Node::Constant
            && $style->value() eq 'hash';

        # Target must be a variable
        return unless defined $target
            && $target isa Chalk::IR::Node::Constant
            && $target->const_type() eq 'variable';

        my $var_name = $target->value();
        my $var_key  = "${var_prefix}::${var_name}";

        # Only track variables already known as hash constructors
        return unless exists $var_schemas->{$var_key};

        # Check if key is a literal string
        if (defined $index
            && $index isa Chalk::IR::Node::Constant
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
            my $value = $node->value;  # inputs[0]=value; control is in control_in
            if (defined $value
                && $value isa Chalk::IR::Node::Constant
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
        if ($node isa Chalk::IR::Node::Call
                && $node->dispatch_kind eq 'method') {
            my $invocant = $node->inputs()->[0];
            my $is_self  = (defined $invocant
                && $invocant isa Chalk::IR::Node::Constant
                && $invocant->const_type() eq 'variable'
                && $invocant->value() eq '$self');

            unless ($is_self) {
                my $args = $node->inputs()->[2];
                if (defined $args && ref($args) eq 'ARRAY') {
                    for my $arg ($args->@*) {
                        if (defined $arg
                            && $arg isa Chalk::IR::Node::Constant
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
            && $style isa Chalk::IR::Node::Constant
            && $style->value() eq 'hash';

        return unless defined $target
            && $target isa Chalk::IR::Node::Constant
            && $target->const_type() eq 'variable';

        return unless defined $index
            && $index isa Chalk::IR::Node::Constant
            && $index->const_type() eq 'string';

        my $var_key    = "${var_prefix}::${\$target->value()}";
        my $field_name = $index->value();

        return unless exists $var_schemas->{$var_key};

        # If RHS is an integer constant, mark field as integer context
        if (defined $rhs
            && $rhs isa Chalk::IR::Node::Constant
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
            && $style isa Chalk::IR::Node::Constant
            && $style->value() eq 'hash';

        return unless defined $target
            && $target isa Chalk::IR::Node::Constant
            && $target->const_type() eq 'variable';

        return unless defined $index
            && $index isa Chalk::IR::Node::Constant
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
        my $factory = $typed;

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

            # Rebuild Program as typed Chalk::IR::Program
            my $new_program = Chalk::IR::Program->new(
                classes => [$new_class],
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
                my $var_node    = $stmt->name();
                my $initializer = $stmt->init();

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
                    && $op_node isa Chalk::IR::Node::Constant
                    && $op_node->value() eq '=';

                my $left = $stmt->inputs()->[1];
                next unless defined $left
                    && $left isa Chalk::IR::Node::Subscript;

                my $target = $left->inputs()->[0];
                next unless defined $target
                    && $target isa Chalk::IR::Node::Constant
                    && $target->const_type() eq 'variable';

                my $var_name = $target->value();
                next unless exists $promoted_vars{$var_name};

                my $index = $left->inputs()->[1];
                next unless defined $index
                    && $index isa Chalk::IR::Node::Constant
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

                my $var_node = $stmt->name();
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

                    my $struct_ref = $typed->make('StructRef',
                        inputs       => [$schema_node, \@field_vals],
                    );

                    my $new_var_decl = $typed->make('VarDecl',
                        inputs       => [$stmt->control(), $var_node, $struct_ref],
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
                && $style isa Chalk::IR::Node::Constant
                && $style->value() eq 'hash'
                && defined $target
                && $target isa Chalk::IR::Node::Constant
                && $target->const_type() eq 'variable'
                && exists $promoted_vars->{$target->value()}
                && defined $index
                && $index isa Chalk::IR::Node::Constant
                && $index->const_type() eq 'string') {

                my $schema_name = $promoted_vars->{$target->value()};
                my $schema_node = $factory->make('Constant',
                    const_type => 'string',
                    value      => $schema_name,
                );

                return $typed->make('StructFieldAccess',
                    inputs       => [$schema_node, $index, $target],
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

    # Rebuild a typed computation node with new inputs, preserving the
    # original node's operation() (the typed class name) and any
    # node-specific attributes (e.g. Call.dispatch_kind, AnonSub params).
    # Calls the typed factory directly - no Shim involvement.
    method _rebuild_constructor($factory, $original, $new_inputs) {
        my $op = $original->operation();

        # Most node classes accept just inputs + compat_class as
        # constructor params. A few (Call, AnonSub, etc.) carry typed
        # fields that we must forward explicitly so the rebuilt node
        # behaves identically.
        my %extra;
        if ($op eq 'Call' && $original->can('dispatch_kind')) {
            $extra{dispatch_kind} = $original->dispatch_kind;
            $extra{name}          = $original->name;
            $extra{paren_form}    = $original->paren_form
                if $original->can('paren_form');
        }
        my $compat = $original->can('compat_class')
            ? $original->compat_class : undef;
        return $typed->make($op,
            inputs => $new_inputs,
            (defined $compat ? (compat_class => $compat) : ()),
            %extra,
        );
    }

    # Find the ClassInfo node from an IR tree root.
    # Accepts a Chalk::IR::Program or a direct Chalk::IR::ClassInfo.
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
