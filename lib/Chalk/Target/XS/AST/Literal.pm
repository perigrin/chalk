# ABOUTME: XS AST node representing literal values (integers, floats, strings)
# ABOUTME: Emits the literal value with appropriate formatting for C code
use 5.42.0;
use experimental qw(class);

class Chalk::Target::XS::AST::Literal :isa(Chalk::Target::XS::AST::Node) {
    field $value :param :reader;
    field $c_type :param = undef;  # C type from IR (IV, NV, SV*, etc.)

    method emit() {
        # Handle undef as empty string
        return '""' unless defined $value;

        # Use c_type to determine formatting when available
        # Numeric types: IV (integer), NV (floating point)
        # String types: SV*, or any non-numeric type
        my $is_numeric = 0;
        if (defined $c_type) {
            $is_numeric = ($c_type eq 'IV' || $c_type eq 'NV');
        } else {
            # Fallback: check if value looks numeric (for backward compatibility)
            # This handles cases where Literal is created without IR type info
            $is_numeric = ($value =~ /\A-?(?:\d+\.?\d*|\d*\.?\d+)\z/);
        }

        if ($is_numeric) {
            return "$value";
        } else {
            # String formatting: escape special characters for C string literals
            my $escaped = $value;
            $escaped =~ s/\\/\\\\/g;  # Escape backslashes first
            $escaped =~ s/"/\\"/g;    # Escape double quotes
            $escaped =~ s/\n/\\n/g;   # Escape newlines
            $escaped =~ s/\t/\\t/g;   # Escape tabs
            return qq("$escaped");
        }
    }
}

1;
