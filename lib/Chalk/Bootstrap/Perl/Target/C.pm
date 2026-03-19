# ABOUTME: Walks Perl IR and emits native C code for each class method.
# ABOUTME: Generates a .c implementation file and a .h header file per class.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Perl::Target::C {
    field $module_name :param :reader;
    field $field_map;          # hashref: field name => index (set during _analyze_class)
    field $field_sigils;       # hashref: field name => sigil ($, @, %) (set during _analyze_class)
    field %_cfg_lookup;        # IR node refaddr => cfg_state entry, built by generate_c_files
    field $_return_context = false;  # true when emitting a method body that returns a value
    field $_loop_depth = 0;          # nesting depth inside loops (suppresses bare-return detection)
    field $_class_methods;     # hashref: name => { returns => bool, params => \@param_names }
    field $_regex_counter = 0; # monotonic counter for unique regex static variable names
    field $_regex_statics;     # arrayref of { var, pat } for lazy-compiled REGEXP* statics
    field %_class_scope_vars;  # var_name => { sigil, init, static_name } for class-level lexicals
    field %_class_subs;        # sub_name => { params => [...], is_sub => 1 } for class-scope sub declarations
    field %_use_constants;     # constant_name => numeric_value from `use constant { ... }` declarations
    field @_anon_sub_helpers;  # accumulated static C functions for anonymous subs
    field $_anon_sub_counter = 0;  # monotonic counter for unique anonymous sub names
    field $_current_slug = '';     # class-derived identifier prefix for collision avoidance
    field @_exported_functions;    # list of exported C function names
    field @_skipped_methods;       # list of method names that could not be compiled
    field @_anon_sub_registrations; # list of { name => ..., c_name => ... } for anon sub registration
    field $_sa;                    # stored SemanticAction for emit_from_cfg_state access
    field $_ctx;                   # stored Context for emit_from_cfg_state access
    field $_param_fields;          # hashref: field_name => 1 for :param fields (type varies per instance)

    ADJUST {
        die "Invalid module name: $module_name"
            unless $module_name =~ /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
    }

    # Derive a short lowercase slug from a class name for identifier namespacing.
    # Takes the last component of a qualified name and lowercases it.
    # e.g., "Chalk::Bootstrap::Earley" => "earley", "SlugTest" => "slugtest"
    method _class_slug($class_name) {
        my ($last) = $class_name =~ /(?:.*::)?(\w+)$/;
        return lc($last // $class_name);
    }

    # Map a TypeInference return type to a C type for C output.
    # Conservative: all non-void types emit SV*. Extension point for
    # future typed returns (Int => IV, Num => NV, etc.).
    my sub _xs_c_type_for($ti_type) {
        return 'void' if !defined $ti_type || $ti_type eq 'Void';
        return 'SV *';
    }

    # Extract ClassDecl from Program IR
    method _find_class_decl($ir) {
        my $stmts = $ir->inputs()->[0];
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'ClassDecl') {
                return $stmt;
            }
        }
        return undef;
    }

    # Build field index map from ClassDecl IR.
    # Returns hashref mapping field name (without sigil) to integer index.
    # Fields are numbered in declaration order starting from 0.
    method _build_field_index_map($class_decl) {
        my $body = $class_decl->inputs()->[2];
        my %field_map;
        my %sigils;
        my %params;
        my $index = 0;

        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'FieldDecl') {
                my $name_node = $item->inputs()->[0];
                my $field_name = $name_node->value();
                my ($sigil) = $field_name =~ /^([\$\@\%])/;
                $field_name =~ s/^[\$\@\%]//;  # Strip sigil
                $field_map{$field_name} = $index++;
                $sigils{$field_name} = $sigil // '$';
                # Detect :param attribute — these fields vary per instance
                my $attrs = $item->inputs()->[1];
                if (ref($attrs) eq 'ARRAY') {
                    for my $attr ($attrs->@*) {
                        my $attr_name = $attr->inputs()->[0]->value();
                        if ($attr_name eq 'param') {
                            $params{$field_name} = 1;
                        }
                    }
                }
            }
        }

        $field_sigils = \%sigils;
        $_param_fields = \%params;
        return \%field_map;
    }

    # Build CFG state lookup table by walking the Context tree.
    # Maps IR node refaddr to cfg_state entry for control-flow-aware emission.
    # First-found wins: parent rules that wire body expressions take priority.
    # $cfg_snapshot is an optional hashref mapping Context refaddr to cfg_state,
    # pre-built at parse time. When provided, it is used instead of $sa->cfg_state()
    # which may have been wiped by subsequent parses (shared class-scope lexical).
    method _build_cfg_lookup($sa, $ctx, $cfg_snapshot = undef) {
        my @stack = ($ctx);
        while (@stack) {
            my $node = pop @stack;
            my $state = defined $cfg_snapshot
                ? $cfg_snapshot->{refaddr($node)}
                : $sa->cfg_state($node);
            if (defined $state && (defined $state->{if_node} || defined $state->{loop} || defined $state->{try_node})) {
                my $ir_node = $node->extract();
                if (defined $ir_node && ref($ir_node) && !exists $_cfg_lookup{refaddr($ir_node)}) {
                    $_cfg_lookup{refaddr($ir_node)} = $state;
                }
                # For try/catch, also register by try_node refaddr. The Context
                # extract() may return undef or ARRAY (stale-value merge), but
                # the TryCatchStmt Constructor in state->{try_node} is what
                # appears as VarDecl init in the IR tree.
                if (defined $state->{try_node} && ref($state->{try_node})
                        && !exists $_cfg_lookup{refaddr($state->{try_node})}) {
                    $_cfg_lookup{refaddr($state->{try_node})} = $state;
                }
            }
            push @stack, reverse $node->children()->@*;
        }
        return;
    }

    # Pre-scan all methods and subs in the class body to build $_class_methods.
    # Also populates %_class_subs for class-scope sub declarations.
    # Returns hashref: name => { returns => bool, params => [...], is_sub => bool, ... }
    method _scan_class_methods($class_decl) {
        my $body = $class_decl->inputs()->[2];
        my %methods;

        # Collect all MethodDecl and SubDecl nodes from the class body.
        # SubDecl may be mis-parented as VarDecl initializer due to parser
        # ambiguity (e.g., `my %_cache; sub _intern(...)` parsed as one unit).
        # Recurse one level into VarDecl initializers to find these.
        my @items_to_scan;
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            push @items_to_scan, $item;
            # Check VarDecl initializer for mis-parented SubDecl
            if ($item->class() eq 'VarDecl') {
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'SubDecl') {
                    push @items_to_scan, $init;
                }
            }
        }

        for my $item (@items_to_scan) {
            my $class = $item->class();
            next unless $class eq 'MethodDecl' || $class eq 'SubDecl';

            my $name   = $item->inputs()->[0]->value();
            my $params = $item->inputs()->[1];

            my @param_names;
            for my $p ($params->@*) {
                my $pname = $p->value();
                $pname =~ s/^[\$\@\%]//;
                push @param_names, $pname;
            }

            my $entry = {
                returns => true,
                params  => \@param_names,
            };

            # Track subs separately so the emitter knows they lack $self
            if ($class eq 'SubDecl') {
                $entry->{is_sub} = true;
                $entry->{class_name} = $class_decl->inputs()->[0]->value();
                # SubDecl inputs: [name, params, body, scope]
                my $scope_node = $item->inputs()->[3];
                $entry->{scope} = defined $scope_node ? $scope_node->value() : 'package';
                $_class_subs{$name} = $entry;
            }

            $methods{$name} = $entry;
        }

        # Scan FieldDecl nodes for :reader attributes — these auto-generate
        # accessor methods that can be called via direct dispatch.
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor
                && $item->class() eq 'FieldDecl';
            my $attrs = $item->inputs()->[1];
            next unless ref($attrs) eq 'ARRAY';
            my $has_reader = false;
            for my $attr ($attrs->@*) {
                if ($attr->inputs()->[0]->value() eq 'reader') {
                    $has_reader = true;
                    last;
                }
            }
            if ($has_reader) {
                my $fname = $item->inputs()->[0]->value();
                $fname =~ s/^[\$\@\%]//;  # Strip sigil
                $methods{$fname} //= {
                    returns    => true,
                    params     => [],
                    is_reader  => true,
                };
            }
        }

        return \%methods;
    }

    # Extract all class-level analysis from the IR without emitting any code.
    # Populates: $_current_slug, $field_map, $field_sigils, $_class_methods,
    # %_class_subs, %_class_scope_vars, %_use_constants.
    method _analyze_class($ir) {
        my $class_decl = $self->_find_class_decl($ir);
        return unless defined $class_decl;

        # Set the current class slug for identifier namespacing
        my $class_name = $class_decl->inputs()->[0]->value();
        $_current_slug = $self->_class_slug($class_name);

        # Build field map once and store it for use throughout code generation
        $field_map = $self->_build_field_index_map($class_decl);

        # Pre-scan methods to build $_class_methods for direct call optimization
        $_class_methods = $self->_scan_class_methods($class_decl);

        my $body = $class_decl->inputs()->[2];

        # Collect class-scope variable metadata from ALL VarDecl items in class body.
        # These are compiled as static C variables, initialized at module load time.
        %_class_scope_vars = ();
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            if ($item->class() eq 'VarDecl') {
                my $raw_var = $item->inputs()->[0]->value();
                my $sigil = substr($raw_var, 0, 1);
                my $var = $raw_var;
                $var =~ s/^[\$\@\%]//;
                my $init = $item->inputs()->[1];
                # Skip VarDecl whose init is a SubDecl (those are sub definitions)
                next if defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                    && $init->class() eq 'SubDecl';
                # Skip VarDecl for variables that are fields (ADJUST assigns them,
                # but they're already handled by the field map)
                next if defined $field_map && exists $field_map->{$var};
                $_class_scope_vars{$var} = {
                    sigil       => $sigil,
                    init        => $init,
                    static_name => "_csv_${_current_slug}_${var}",
                };
            }
        }

        # Extract `use constant { NAME => value, ... }` declarations.
        # Constants are inlined as numeric literals in the generated C,
        # since C doesn't have Perl's constant sub mechanism.
        %_use_constants = ();
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            next unless $item->class() eq 'UseDecl';
            my $mn = $item->inputs()->[0];
            next unless defined $mn && $mn->value() eq 'constant';
            my $args = $item->inputs()->[1];
            next unless defined $args && ref($args) eq 'ARRAY';
            my $hash_expr = $args->[0];
            next unless $hash_expr isa Chalk::Bootstrap::IR::Node::Constructor
                     && $hash_expr->class() eq 'HashRefExpr';
            my $pairs = $hash_expr->inputs()->[0];
            next unless defined $pairs && ref($pairs) eq 'ARRAY';
            for (my $i = 0; $i < $pairs->@*; $i += 2) {
                my $key_node = $pairs->[$i];
                my $val_node = $pairs->[$i + 1];
                next unless $key_node isa Chalk::Bootstrap::IR::Node::Constant;
                next unless $val_node isa Chalk::Bootstrap::IR::Node::Constant;
                my $kv = $key_node->value();
                my $vv = $val_node->value();
                # Only inline numeric constant values
                if ($vv =~ /^-?[0-9]+$/) {
                    $_use_constants{$kv} = $vv;
                }
            }
        }

        return;
    }

    # Generate C source and header files from a Perl IR tree.
    # Stores $sa and $ctx for use by emission methods that need cfg_state.
    # Returns hashref: { files => { "slug.c" => ..., "slug.h" => ... },
    #                    exported_functions => [...],
    #                    skipped_methods => [...],
    #                    anon_sub_registrations => [...] }
    method generate_c_files($ir, $sa, $ctx) {
        $_sa  = $sa;
        $_ctx = $ctx;

        %_cfg_lookup = ();
        if (defined $sa) {
            $self->_build_cfg_lookup($sa, $ctx);
        }

        $self->_analyze_class($ir);

        my $slug = $_current_slug;

        return {
            files => {
                "${slug}.c" => '',
                "${slug}.h" => '',
            },
            exported_functions   => [],
            skipped_methods      => [],
            anon_sub_registrations => [],
        };
    }
}
