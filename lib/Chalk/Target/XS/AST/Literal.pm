# ABOUTME: XS AST node representing literal values (integers, floats, strings)
# ABOUTME: Emits the literal value with appropriate formatting for C code
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::Literal :isa(Chalk::Target::XS::AST::Node) {
    field $value :param :reader;
    field $c_type :param :reader;  # C type from IR (IV, NV, SV*, etc.) - required

    method emit() {
        # Handle undef as empty string wrapped in newSVpvn for SV* types
        unless (defined $value) {
            return $c_type =~ /^SV\b/ ? 'newSVpvn("", 0)' : '""';
        }

        # Determine formatting based on c_type from IR type system
        # Numeric types: IV (integer), NV (floating point), bool
        # String/SV types: SV*, AV*, HV*, CV*, etc.
        my $is_numeric = ($c_type eq 'IV' || $c_type eq 'NV' || $c_type eq 'bool');

        if ($is_numeric) {
            return "$value";
        } else {
            # String formatting: escape special characters for C string literals
            my $escaped = $value;
            $escaped =~ s/\\/\\\\/g;  # Escape backslashes first
            $escaped =~ s/"/\\"/g;    # Escape double quotes
            $escaped =~ s/\n/\\n/g;   # Escape newlines
            $escaped =~ s/\t/\\t/g;   # Escape tabs

            # For Perl SV types, wrap in newSVpv() to create proper SV*
            # For C string types (char*), use bare quoted string
            if ($c_type =~ /^SV\b/) {
                return qq(newSVpv("$escaped", 0));
            } else {
                return qq("$escaped");
            }
        }
    }
}

1;
