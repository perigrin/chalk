# ABOUTME: XS code emitter that walks IR nodes and produces XS source.
# ABOUTME: Generates .xs file with XSUBs that construct grammar rules via call_method.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;
use Chalk::Bootstrap::BNF::Target::XS::AST::Preamble;
use Chalk::Bootstrap::BNF::Target::XS::AST::Module;
use Chalk::Bootstrap::BNF::Target::XS::AST::CompositeNode;
use Chalk::Bootstrap::BNF::Target::XS::AST::VarDecl;
use Chalk::Bootstrap::BNF::Target::XS::AST::Statement;
use Chalk::Bootstrap::BNF::Target::XS::AST::XSUB;

class Chalk::Bootstrap::BNF::Target::XS :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader = 'Chalk::Grammar::BNF::Rules';
    # Per-rule scratch counters; reset at the start of each _emit_rule call
    field $sym_counter = 0;
    field $expr_counter = 0;

    ADJUST {
        die "Invalid module name: $module_name"
            unless $module_name =~ /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
    }

    # Escape a string for embedding in a C double-quoted string literal.
    # Handles all non-printable bytes via \xHH hex escapes.
    method _escape_c_string($str) {
        $str =~ s/\\/\\\\/g;   # \ -> \\
        $str =~ s/"/\\"/g;     # " -> \"
        $str =~ s/\n/\\n/g;    # newline -> \n
        $str =~ s/\t/\\t/g;    # tab -> \t
        $str =~ s/\r/\\r/g;    # carriage return -> \r
        $str =~ s/\0/\\0/g;    # null byte -> \0
        # All remaining non-printable bytes → \xHH
        $str =~ s/([^\x20-\x7E])/sprintf("\\x%02x", ord($1))/ge;
        return $str;
    }

    # Strip / delimiters from terminal regex values
    method _strip_terminal_delimiters($value) {
        if ($value =~ m{^/(.*)/$}) {
            return $1;
        }
        return $value;
    }

    # Emit a C expression for an IR Constant node.
    # Uses newSVpvn with pre-escape length when C escaping changes the byte count,
    # and newSVpvs when the value has no escape-sensitive characters.
    method _emit_constant($node) {
        my $value = $node->value();
        my $escaped = $self->_escape_c_string($value);
        if (length($escaped) != length($value)) {
            my $len = length($value);
            return "newSVpvn(\"$escaped\", $len)";
        }
        return "newSVpvs(\"$escaped\")";
    }

    # Emit AST nodes for a Constructor:Symbol IR node
    # Returns arrayref of [VarDecl, Statement] AST nodes
    method _emit_symbol($symbol_node, $var_name) {
        my $inputs = $symbol_node->inputs();
        my $type_const = $inputs->[0];
        my $value_const = $inputs->[1];
        my $quant_const = $inputs->[2];

        my $type_str = $type_const->value();

        # Strip / delimiters from terminal values, then C-escape
        my $raw_value = $value_const->value();
        my $stripped_value = ($type_str eq 'terminal')
            ? $self->_strip_terminal_delimiters($raw_value)
            : $raw_value;
        my $value_str = $self->_escape_c_string($stripped_value);

        # Build the call_method block
        my $block = "{\n";
        $block .= "    dSP;\n";
        $block .= "    ENTER; SAVETMPS;\n";
        $block .= "    PUSHMARK(SP);\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"Chalk::Grammar::Symbol\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"type\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"$type_str\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"value\")));\n";
        # Terminal regex values use newSVpvn with explicit length per spec §5.4
        # Length is computed on the pre-C-escaped value because the C compiler
        # interprets escape sequences (e.g. \\ → \), reducing byte count
        if ($type_str eq 'terminal') {
            my $len = length($stripped_value);
            $block .= "    XPUSHs(sv_2mortal(newSVpvn(\"$value_str\", $len)));\n";
        } else {
            $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"$value_str\")));\n";
        }

        # Optional quantifier args (check value, not node — node may exist with undef value)
        if (defined $quant_const && defined $quant_const->value()) {
            my $quant_str = $self->_escape_c_string($quant_const->value());
            $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"quantifier\")));\n";
            $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"$quant_str\")));\n";
        }

        $block .= "    PUTBACK;\n";
        $block .= "    call_method(\"new\", G_SCALAR);\n";
        $block .= "    SPAGAIN;\n";
        $block .= "    $var_name = SvREFCNT_inc(POPs);\n";
        $block .= "    PUTBACK;\n";
        $block .= "    FREETMPS; LEAVE;\n";
        $block .= "}";

        my $var_decl = Chalk::Bootstrap::BNF::Target::XS::AST::VarDecl->new(
            type => 'SV *',
            name => $var_name,
        );
        my $stmt = Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(code => $block);

        return [$var_decl, $stmt];
    }

    # Emit AST nodes for a Constructor:Expression IR node (one alternative)
    # Returns arrayref of AST nodes (VarDecl + Statements)
    method _emit_expression($expr_node, $var_name) {
        my @nodes;

        # VarDecl for the expression AV
        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::VarDecl->new(
            type => 'AV *',
            name => $var_name,
        );

        # Initialize the AV
        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(
            code => "$var_name = newAV();",
        );

        # Emit each symbol and push onto the expression AV
        my $elements = $expr_node->inputs()->[0];
        for my $sym ($elements->@*) {
            my $sym_name = "sym_$sym_counter";
            $sym_counter++;

            my $sym_nodes = $self->_emit_symbol($sym, $sym_name);
            push @nodes, $sym_nodes->@*;

            push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(
                code => "av_push($var_name, $sym_name);",
            );
        }

        return \@nodes;
    }

    # Emit AST nodes for a Constructor:Rule IR node
    # Returns arrayref of all AST nodes for the complete rule XSUB body
    method _emit_rule($rule_node) {
        my @nodes;

        # Reset counters per rule
        $sym_counter = 0;
        $expr_counter = 0;

        my $name_const = $rule_node->inputs()->[0];
        my $expressions = $rule_node->inputs()->[1];
        my $rule_name = $name_const->value();

        # VarDecls for top-level rule variables
        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::VarDecl->new(
            type => 'AV *', name => 'expressions',
        );
        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::VarDecl->new(
            type => 'SV *', name => 'rule',
        );

        # Initialize expressions AV
        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(
            code => 'expressions = newAV();',
        );

        # Emit each expression (alternative) and push as ref onto expressions
        for my $expr ($expressions->@*) {
            my $expr_name = "expr_$expr_counter";
            $expr_counter++;

            my $expr_nodes = $self->_emit_expression($expr, $expr_name);
            push @nodes, $expr_nodes->@*;

            push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(
                code => "av_push(expressions, newRV_noinc((SV *)$expr_name));",
            );
        }

        # call_method block for Rule construction
        my $escaped_name = $self->_escape_c_string($rule_name);
        my $block = "{\n";
        $block .= "    dSP;\n";
        $block .= "    ENTER; SAVETMPS;\n";
        $block .= "    PUSHMARK(SP);\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"Chalk::Grammar::Rule\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"name\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"$escaped_name\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"expressions\")));\n";
        $block .= "    XPUSHs(sv_2mortal(newRV_noinc((SV *)expressions)));\n";
        $block .= "    PUTBACK;\n";
        $block .= "    call_method(\"new\", G_SCALAR);\n";
        $block .= "    SPAGAIN;\n";
        $block .= "    rule = SvREFCNT_inc(POPs);\n";
        $block .= "    PUTBACK;\n";
        $block .= "    FREETMPS; LEAVE;\n";
        $block .= "}";

        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(code => $block);

        # RETVAL assignment
        push @nodes, Chalk::Bootstrap::BNF::Target::XS::AST::Statement->new(
            code => 'RETVAL = rule;',
        );

        return \@nodes;
    }

    # Wrap a Constructor:Rule IR node into an XSUB AST node
    method _emit_xsub($rule_node) {
        my $rule_name = $rule_node->inputs()->[0]->value();
        die "Invalid rule name for XS target: $rule_name"
            unless $rule_name =~ /^[A-Za-z_][A-Za-z_0-9]*$/;
        my $body_nodes = $self->_emit_rule($rule_node);

        return Chalk::Bootstrap::BNF::Target::XS::AST::XSUB->new(
            name   => $rule_name,
            params => ['SV *self'],
            body   => $body_nodes,
        );
    }

    method generate($ir) {
        die "generate() requires an arrayref of IR rules"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        my $preamble = Chalk::Bootstrap::BNF::Target::XS::AST::Preamble->new();
        my $module = Chalk::Bootstrap::BNF::Target::XS::AST::Module->new(
            module  => $module_name,
            package => $module_name,
        );

        my @children = ($preamble, $module);

        for my $rule ($ir->@*) {
            push @children, $self->_emit_xsub($rule);
        }

        my $composite = Chalk::Bootstrap::BNF::Target::XS::AST::CompositeNode->new(
            children => \@children,
        );

        return $composite->emit();
    }

    # Convert module name to file path (e.g. "Foo::Bar" → "lib/Foo/Bar")
    method _module_path_prefix() {
        my $path = $module_name;
        $path =~ s{::}{/}g;
        return "lib/$path";
    }

    # Generate .pm stub for XSLoader bootstrapping
    method _generate_pm_stub() {
        return qq[# Generated by Chalk::Bootstrap compiler — do not edit
package $module_name;
use 5.42.0;
use XSLoader;
our \$VERSION = '0.01';
XSLoader::load(__PACKAGE__, \$VERSION);
1;
];
    }

    # Generate Module::Build script
    method _generate_build_pl() {
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

    method generate_distribution($ir) {
        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $pm_path = $self->_module_path_prefix() . '.pm';

        return {
            $xs_path  => $self->generate($ir),
            $pm_path  => $self->_generate_pm_stub(),
            'Build.PL' => $self->_generate_build_pl(),
        };
    }
}
