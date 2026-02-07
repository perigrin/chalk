# ABOUTME: XS code emitter that walks IR nodes and produces XS source.
# ABOUTME: Generates .xs file with XSUBs that construct grammar rules via call_method.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Target;
use Chalk::Bootstrap::Target::XS::AST::Preamble;
use Chalk::Bootstrap::Target::XS::AST::Module;
use Chalk::Bootstrap::Target::XS::AST::CompositeNode;
use Chalk::Bootstrap::Target::XS::AST::VarDecl;
use Chalk::Bootstrap::Target::XS::AST::Statement;

class Chalk::Bootstrap::Target::XS :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader = 'Chalk::Grammar::BNF::Rules';
    field $sym_counter = 0;
    field $expr_counter = 0;

    # Escape a string for embedding in a C double-quoted string literal
    method _escape_c_string($str) {
        $str =~ s/\\/\\\\/g;   # \ -> \\
        $str =~ s/"/\\"/g;     # " -> \"
        $str =~ s/\n/\\n/g;    # newline -> \n
        $str =~ s/\t/\\t/g;    # tab -> \t
        $str =~ s/\r/\\r/g;    # carriage return -> \r
        $str =~ s/\0/\\0/g;    # null byte -> \0
        return $str;
    }

    # Strip / delimiters from terminal regex values
    method _strip_terminal_delimiters($value) {
        if ($value =~ m{^/(.*)/$}) {
            return $1;
        }
        return $value;
    }

    # Emit a C expression for an IR Constant node
    method _emit_constant($node) {
        my $value = $node->value();
        my $escaped = $self->_escape_c_string($value);
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
        my $value_str = ($type_str eq 'terminal')
            ? $self->_escape_c_string($self->_strip_terminal_delimiters($raw_value))
            : $self->_escape_c_string($raw_value);

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
        if ($type_str eq 'terminal') {
            my $len = length($value_str);
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

        my $var_decl = Chalk::Bootstrap::Target::XS::AST::VarDecl->new(
            type => 'SV *',
            name => $var_name,
        );
        my $stmt = Chalk::Bootstrap::Target::XS::AST::Statement->new(code => $block);

        return [$var_decl, $stmt];
    }

    # Emit AST nodes for a Constructor:Expression IR node (one alternative)
    # Returns arrayref of AST nodes (VarDecl + Statements)
    method _emit_expression($expr_node, $var_name) {
        my @nodes;

        # VarDecl for the expression AV
        push @nodes, Chalk::Bootstrap::Target::XS::AST::VarDecl->new(
            type => 'AV *',
            name => $var_name,
        );

        # Initialize the AV
        push @nodes, Chalk::Bootstrap::Target::XS::AST::Statement->new(
            code => "$var_name = newAV();",
        );

        # Emit each symbol and push onto the expression AV
        my $elements = $expr_node->inputs()->[0];
        for my $sym ($elements->@*) {
            my $sym_name = "sym_$sym_counter";
            $sym_counter++;

            my $sym_nodes = $self->_emit_symbol($sym, $sym_name);
            push @nodes, $sym_nodes->@*;

            push @nodes, Chalk::Bootstrap::Target::XS::AST::Statement->new(
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
        push @nodes, Chalk::Bootstrap::Target::XS::AST::VarDecl->new(
            type => 'AV *', name => 'expressions',
        );
        push @nodes, Chalk::Bootstrap::Target::XS::AST::VarDecl->new(
            type => 'SV *', name => 'rule',
        );

        # Initialize expressions AV
        push @nodes, Chalk::Bootstrap::Target::XS::AST::Statement->new(
            code => 'expressions = newAV();',
        );

        # Emit each expression (alternative) and push as ref onto expressions
        for my $expr ($expressions->@*) {
            my $expr_name = "expr_$expr_counter";
            $expr_counter++;

            my $expr_nodes = $self->_emit_expression($expr, $expr_name);
            push @nodes, $expr_nodes->@*;

            push @nodes, Chalk::Bootstrap::Target::XS::AST::Statement->new(
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

        push @nodes, Chalk::Bootstrap::Target::XS::AST::Statement->new(code => $block);

        # RETVAL assignment
        push @nodes, Chalk::Bootstrap::Target::XS::AST::Statement->new(
            code => 'RETVAL = rule;',
        );

        return \@nodes;
    }

    method generate($ir) {
        die "generate() requires an arrayref of IR rules"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        my $preamble = Chalk::Bootstrap::Target::XS::AST::Preamble->new();
        my $module = Chalk::Bootstrap::Target::XS::AST::Module->new(
            module  => $module_name,
            package => $module_name,
        );

        my $composite = Chalk::Bootstrap::Target::XS::AST::CompositeNode->new(
            children => [$preamble, $module],
        );

        return $composite->emit();
    }
}
