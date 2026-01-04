# ABOUTME: Utility functions for XS code generation
# ABOUTME: Provides C/C++ keyword sanitization and other XS helpers

use 5.42.0;
use experimental 'class';

class Chalk::Target::XS::Util {
    # C/C++ reserved keywords that must be sanitized
    # Based on C99/C11 and C++ standards
    my %C_KEYWORDS = map { $_ => 1 } qw(
        auto break case char const continue default do double else enum extern
        float for goto if inline int long register restrict return short signed
        sizeof static struct switch typedef union unsigned void volatile while
        _Bool _Complex _Imaginary
        alignas alignof and and_eq asm bitand bitor bool catch class compl
        const_cast constexpr decltype delete dynamic_cast explicit export false
        friend mutable namespace new noexcept not not_eq nullptr operator or
        or_eq private protected public reinterpret_cast static_assert static_cast
        template this throw true try typeid typename using virtual wchar_t xor xor_eq
    );

    # Sanitize a C identifier to avoid reserved keyword conflicts
    # Strategy: append underscore to keywords
    # Example: 'class' -> 'class_', 'new' -> 'new_'
    sub sanitize_c_identifier ($class, $name) {
        return $name unless exists $C_KEYWORDS{$name};
        return $name . '_';
    }

    # Strip Perl sigil and sanitize for use as C identifier
    # Example: '$class' -> 'class_', '$value' -> 'value'
    sub perl_to_c_identifier ($class, $perl_name) {
        my $bare = $perl_name;
        $bare =~ s/^\$//;  # Remove sigil
        return $class->sanitize_c_identifier($bare);
    }
}

1;
