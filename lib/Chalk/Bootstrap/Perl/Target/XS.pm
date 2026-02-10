# ABOUTME: Walks Perl IR and emits XS/C code with bless-based OO wrapper.
# ABOUTME: Generates .xs, .pm stub, and Build.PL for Tier A pure data classes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Perl::Target::XS :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader;

    ADJUST {
        die "Invalid module name: $module_name"
            unless $module_name =~ /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
    }

    method generate($ir) {
        die "generate() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        return $self->_emit_xs($ir);
    }

    method generate_distribution($ir) {
        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $pm_path = $self->_module_path_prefix() . '.pm';

        return {
            $xs_path   => $self->_emit_xs($ir),
            $pm_path   => $self->_emit_pm_stub($ir),
            'Build.PL' => $self->_emit_build_pl(),
        };
    }

    # Convert module name to file path prefix
    method _module_path_prefix() {
        my $path = $module_name;
        $path =~ s{::}{/}g;
        return "lib/$path";
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

    # Escape a string for C double-quoted literal
    method _escape_c_string($str) {
        $str =~ s/\\/\\\\/g;
        $str =~ s/"/\\"/g;
        $str =~ s/\n/\\n/g;
        $str =~ s/\t/\\t/g;
        $str =~ s/\r/\\r/g;
        $str =~ s/\0/\\0/g;
        $str =~ s/([^\x20-\x7E])/sprintf("\\x%02x", ord($1))/ge;
        return $str;
    }

    # Emit the .xs file
    method _emit_xs($ir) {
        my $class_decl = $self->_find_class_decl($ir);
        my @lines;

        # XS preamble
        push @lines, '#include "EXTERN.h"';
        push @lines, '#include "perl.h"';
        push @lines, '#include "XSUB.h"';
        push @lines, '';
        push @lines, "MODULE = $module_name  PACKAGE = $module_name";
        push @lines, '';

        if (defined $class_decl) {
            my $body = $class_decl->inputs()->[2];
            for my $item ($body->@*) {
                if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'FieldDecl') {
                    my @reader_lines = $self->_emit_xs_field_reader($item)->@*;
                    if (@reader_lines) {
                        push @lines, @reader_lines;
                        push @lines, '';
                    }
                } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'MethodDecl') {
                    push @lines, $self->_emit_xs_method($item)->@*;
                    push @lines, '';
                }
            }
        }

        return join("\n", @lines) . "\n";
    }

    # Emit a single XSUB for a MethodDecl
    method _emit_xs_method($method_decl) {
        my $name   = $method_decl->inputs()->[0]->value();
        my $params = $method_decl->inputs()->[1];
        my $body   = $method_decl->inputs()->[2];

        my @lines;

        # Determine return type and body
        my $body_item = $body->[0];
        my $returns_value = (defined $body_item
            && $body_item isa Chalk::Bootstrap::IR::Node::Constructor
            && $body_item->class() eq 'ReturnStmt');
        my $dies = (defined $body_item
            && $body_item isa Chalk::Bootstrap::IR::Node::Constructor
            && $body_item->class() eq 'DieCall');

        if ($returns_value) {
            my $value = $body_item->inputs()->[0];

            if ($value isa Chalk::Bootstrap::IR::Node::Constructor
                    && $value->class() eq 'InterpolatedString') {
                # Interpolated string: emit C string concatenation
                push @lines, $self->_emit_xs_interp_return($name, $value)->@*;
            } else {
                my $str = $self->_escape_c_string($value->value());
                push @lines, 'SV *';
                push @lines, "${name}(self, ...)";
                push @lines, '    SV *self';
                push @lines, '  CODE:';
                push @lines, "    RETVAL = newSVpvs(\"$str\");";
                push @lines, '  OUTPUT:';
                push @lines, '    RETVAL';
            }
        } elsif ($dies) {
            my $args = $body_item->inputs()->[0];
            my $msg = '';
            if (ref($args) eq 'ARRAY' && $args->@*) {
                $msg = $self->_escape_c_string($args->[0]->value());
            }

            # Build XS parameter list
            my @xs_params = ('SV *self');
            for my $p ($params->@*) {
                my $pname = $p->value();
                $pname =~ s/^\$//;
                push @xs_params, "SV *$pname";
            }

            push @lines, 'void';
            push @lines, "${name}(" . join(', ', @xs_params) . ")";
            for my $p (@xs_params) {
                push @lines, "    $p";
            }
            push @lines, '  CODE:';
            push @lines, "    croak(\"$msg\");";
        } else {
            # Fallback: void method
            push @lines, 'void';
            push @lines, "${name}(self)";
            push @lines, '    SV *self';
            push @lines, '  CODE:';
            push @lines, '    /* empty */';
        }

        return \@lines;
    }

    # Emit an XSUB field reader for a FieldDecl with :reader attribute
    method _emit_xs_field_reader($field_decl) {
        my $name_node = $field_decl->inputs()->[0];
        my $attrs     = $field_decl->inputs()->[1];

        # Only emit reader if :reader attribute present
        my $has_reader = false;
        if (ref($attrs) eq 'ARRAY') {
            for my $attr ($attrs->@*) {
                if ($attr->inputs()->[0]->value() eq 'reader') {
                    $has_reader = true;
                    last;
                }
            }
        }
        return [] unless $has_reader;

        my $var_name = $name_node->value();
        $var_name =~ s/^\$//;  # Strip sigil for hash key and method name
        my $escaped_key = $self->_escape_c_string($var_name);

        my @lines;
        push @lines, 'SV *';
        push @lines, "${var_name}(self)";
        push @lines, '    SV *self';
        push @lines, '  CODE:';
        push @lines, '    {';
        push @lines, '        HV *hash = (HV*)SvRV(self);';
        push @lines, "        SV **svp = hv_fetch(hash, \"$escaped_key\", " . length($var_name) . ", 0);";
        push @lines, '        RETVAL = (svp && *svp) ? SvREFCNT_inc(*svp) : &PL_sv_undef;';
        push @lines, '    }';
        push @lines, '  OUTPUT:';
        push @lines, '    RETVAL';

        return \@lines;
    }

    # Emit an XSUB that returns an InterpolatedString via C string concatenation.
    # Variables are read from the blessed hash via hv_fetch.
    method _emit_xs_interp_return($method_name, $interp_node) {
        my $parts = $interp_node->inputs()->[0];
        my @lines;

        push @lines, 'SV *';
        push @lines, "${method_name}(self)";
        push @lines, '    SV *self';
        push @lines, '  CODE:';
        push @lines, '    {';
        push @lines, '        HV *hash = (HV*)SvRV(self);';

        # Declare SV* variables for each field reference
        my %seen_vars;
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                next if $seen_vars{$var}++;
                my $escaped = $self->_escape_c_string($var);
                push @lines, "        SV **${var}_svp = hv_fetch(hash, \"$escaped\", " . length($var) . ", 0);";
            }
        }

        # Build the result SV by concatenation
        my $first = true;
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                if ($first) {
                    push @lines, "        RETVAL = newSVsv(${var}_svp ? *${var}_svp : &PL_sv_undef);";
                    $first = false;
                } else {
                    push @lines, "        sv_catsv(RETVAL, ${var}_svp ? *${var}_svp : &PL_sv_undef);";
                }
            } else {
                my $lit = $self->_escape_c_string($part->value());
                if ($first) {
                    push @lines, "        RETVAL = newSVpvs(\"$lit\");";
                    $first = false;
                } else {
                    push @lines, "        sv_catpvs(RETVAL, \"$lit\");";
                }
            }
        }

        push @lines, '    }';
        push @lines, '  OUTPUT:';
        push @lines, '    RETVAL';

        return \@lines;
    }

    # Emit the .pm stub (bless-based OO with XSLoader)
    method _emit_pm_stub($ir) {
        my $class_decl = $self->_find_class_decl($ir);
        my $parent;
        if (defined $class_decl) {
            my $parent_node = $class_decl->inputs()->[1];
            $parent = $parent_node->value() if defined $parent_node;
        }

        my @lines;
        push @lines, "# Generated by Chalk::Bootstrap compiler";
        push @lines, "package $module_name;";
        push @lines, 'use strict;';
        push @lines, 'use warnings;';
        push @lines, 'use XSLoader;';

        if (defined $parent) {
            push @lines, "our \@ISA = ('$parent');";
        }

        push @lines, "our \$VERSION = '0.01';";
        push @lines, '';
        push @lines, 'sub new {';
        push @lines, '    my ($class, %args) = @_;';
        push @lines, '    return bless \%args, $class;';
        push @lines, '}';
        push @lines, '';
        push @lines, "XSLoader::load(__PACKAGE__, \$VERSION);";
        push @lines, '';
        push @lines, '1;';

        return join("\n", @lines) . "\n";
    }

    # Emit Build.PL
    method _emit_build_pl() {
        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $lib_path = $self->_module_path_prefix();
        return qq[use Module::Build;

Module::Build->new(
    module_name    => '$module_name',
    dist_version   => '0.01',
    needs_compiler => 1,
    xs_files       => { '$xs_path'
                        => '$lib_path' },
)->create_build_script;
];
    }
}
