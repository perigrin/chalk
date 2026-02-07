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

    # Escape a string for embedding in a C double-quoted string literal
    method _escape_c_string($str) {
        $str =~ s/\\/\\\\/g;   # \ -> \\
        $str =~ s/"/\\"/g;     # " -> \"
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
        $block .= "    XPUSHs(sv_2mortal(newSVpvs(\"$value_str\")));\n";

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
