# ABOUTME: XS AST node representing literal values (integers, floats, strings)
# ABOUTME: Emits the literal value with appropriate formatting for C code
use 5.42.0;
use experimental qw(class);
use Scalar::Util ();

class Chalk::Target::XS::AST::Literal :isa(Chalk::Target::XS::AST::Node) {
    field $value :param :reader;

    method emit() {
        # Handle undef as empty string
        return '""' unless defined $value;

        # If value is a number, emit as-is
        # If value is a string, emit with double quotes and escape special characters
        if (Scalar::Util::looks_like_number($value)) {
            return "$value";
        } else {
            # Escape special characters for C string literals
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
