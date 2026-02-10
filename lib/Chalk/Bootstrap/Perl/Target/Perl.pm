# ABOUTME: Walks Perl IR (Program/UseDecl/ClassDecl/MethodDecl/etc) and emits Perl source.
# ABOUTME: Generates feature class code that is behaviorally equivalent to the original.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Perl::Target::Perl :isa(Chalk::Bootstrap::Target) {

    method generate($ir) {
        die "generate() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        return $self->_emit_program($ir);
    }

    method generate_distribution($ir) {
        # For Perl target, return a single file mapping
        my $code = $self->generate($ir);

        # Extract class name from the IR to determine file path
        my $stmts = $ir->inputs()->[0];
        my $class_name;
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'ClassDecl') {
                $class_name = $stmt->inputs()->[0]->value();
                last;
            }
        }

        if (defined $class_name) {
            my $path = $class_name;
            $path =~ s{::}{/}g;
            return { "lib/$path.pm" => $code };
        }

        return { 'output.pm' => $code };
    }

    method _emit_program($node) {
        my $stmts = $node->inputs()->[0];
        my @lines;
        for my $stmt ($stmts->@*) {
            my $line = $self->_emit_node($stmt);
            push @lines, $line if defined $line;
        }
        return join("\n", @lines) . "\n";
    }

    method _emit_node($node) {
        return undef unless defined $node;

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            return $self->_emit_constant($node);
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();
            if ($class eq 'Program')    { return $self->_emit_program($node); }
            if ($class eq 'UseDecl')    { return $self->_emit_use_decl($node); }
            if ($class eq 'ClassDecl')  { return $self->_emit_class_decl($node); }
            if ($class eq 'MethodDecl') { return $self->_emit_method_decl($node); }
            if ($class eq 'ReturnStmt') { return $self->_emit_return_stmt($node); }
            if ($class eq 'DieCall')    { return $self->_emit_die_call($node); }
            die "Unknown Constructor class: $class";
        }

        die "Unknown IR node type: " . ref($node);
    }

    method _emit_constant($node) {
        my $value = $node->value();
        return "'" . $self->_escape_single_quote($value) . "'";
    }

    method _emit_use_decl($node) {
        my $module = $node->inputs()->[0];
        my $args   = $node->inputs()->[1];

        my $module_name = $module->value();

        # Version strings don't get quoted
        if ($module_name =~ /^v?[0-9]/) {
            if (defined $args) {
                my @arg_strs = map { $self->_emit_node($_) } $args->@*;
                return "use $module_name " . join(', ', @arg_strs) . ";";
            }
            return "use $module_name;";
        }

        if (defined $args) {
            my @arg_strs = map { $self->_emit_node($_) } $args->@*;
            return "use $module_name " . join(', ', @arg_strs) . ";";
        }

        return "use $module_name;";
    }

    method _emit_class_decl($node) {
        my $name   = $node->inputs()->[0]->value();
        my $parent = $node->inputs()->[1];
        my $body   = $node->inputs()->[2];

        my $decl = "class $name";
        if (defined $parent) {
            $decl .= " :isa(${\$parent->value()})";
        }
        $decl .= " {";

        my @lines = ($decl);
        for my $item ($body->@*) {
            my $code = $self->_emit_node($item);
            if (defined $code) {
                # Indent body by 4 spaces
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";

        return join("\n", @lines);
    }

    method _emit_method_decl($node) {
        my $name   = $node->inputs()->[0]->value();
        my $params = $node->inputs()->[1];
        my $body   = $node->inputs()->[2];

        my $sig = '(' . join(', ', map { $_->value() } $params->@*) . ')';
        my $decl = "method $name$sig {";

        my @lines = ($decl);
        for my $item ($body->@*) {
            my $code = $self->_emit_node($item);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";

        return join("\n", @lines);
    }

    method _emit_return_stmt($node) {
        my $value = $node->inputs()->[0];
        return "return " . $self->_emit_node($value) . ";";
    }

    method _emit_die_call($node) {
        my $args = $node->inputs()->[0];
        my @arg_strs = map { $self->_emit_node($_) } $args->@*;
        return "die " . join(', ', @arg_strs) . ";";
    }

    method _escape_single_quote($str) {
        $str =~ s/\\/\\\\/g;
        $str =~ s/'/\\'/g;
        return $str;
    }
}
