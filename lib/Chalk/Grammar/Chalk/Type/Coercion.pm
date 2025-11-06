# ABOUTME: Implementation of type coercion rules (to Num, to Str, to Bool)
# ABOUTME: Provides formal coercion functions per latent type spec (Issue #74 Phase 4)

use 5.042;
use experimental qw(class);

class Chalk::Grammar::Chalk::Type::Coercion {
    use Scalar::Util qw(looks_like_number refaddr);
    use Chalk::Type::Exception;
    use Chalk::Type::Num;
    use Chalk::Type::Str;

    # Numeric coercion: to_num
    # Per spec: numbers stay, valid numeric strings parse, invalid to 0, refs to address
    method to_num($value, $source_type) {
        # Undef coerces to 0
        if (blessed($source_type) eq 'Chalk::Grammar::Chalk::Type::Undef') {
            return 0;
        }

        return 0 unless defined $value;

        # Numbers remain unchanged (Int <: Num via is_subtype_of, not Perl isa)
        # Check by type name since our type hierarchy uses is_subtype_of not Perl inheritance
        my $type_name = blessed($source_type);
        if ($type_name eq 'Chalk::Grammar::Chalk::Type::Int' ||
            $type_name eq 'Chalk::Grammar::Chalk::Type::Num') {
            return $value;
        }

        # Strings coerce to numbers (but not Num types, which we handled above)
        if (blessed($source_type) eq 'Chalk::Grammar::Chalk::Type::Str') {
            # Valid numeric strings parse
            if (looks_like_number($value)) {
                return $value + 0;  # Force numeric context
            }
            # Invalid strings to 0 (with warning about information loss)
            my $target = Chalk::Type::Num->new();
            my $msg = "non-numeric string coerced to 0";
            my $warning = Chalk::Type::Exception->information_loss_warning(
                $source_type, $target, $value, $msg
            );
            warn $warning;
            return 0;
        }

        # References coerce to memory addresses
        # Check by type name prefix since our Ref types use is_subtype_of not Perl inheritance
        if ($type_name =~ qr/^Chalk::Type::(?:Ref|.*Ref|Object)$/) {
            return refaddr($value);
        }

        my $target = Chalk::Type::Num->new();
        my $exception = Chalk::Type::Exception->type_coercion_error($source_type, $target, $value, "numeric coercion");
        $exception->throw();
    }

    # String coercion: to_str
    # Per spec: strings stay, numbers stringify, refs show type+address, undef to empty
    method to_str($value, $source_type) {
        # Undef coerces to empty string
        if (blessed($source_type) eq 'Chalk::Grammar::Chalk::Type::Undef') {
            return "";
        }

        return "" unless defined $value;

        # Strings, Nums, and Ints all stringify
        # Since Num <: Str in our lattice, all these can be stringified
        my $type_name = blessed($source_type);
        if ($type_name eq 'Chalk::Grammar::Chalk::Type::Str' ||
            $type_name eq 'Chalk::Grammar::Chalk::Type::Num' ||
            $type_name eq 'Chalk::Grammar::Chalk::Type::Int') {
            return "$value";  # Stringify to ensure string context
        }

        # References stringify to TYPE(0x...)
        # Check by type name prefix since our Ref types use is_subtype_of not Perl inheritance
        if ($type_name =~ qr/^Chalk::Type::(?:Ref|.*Ref|Object)$/) {
            # Let Perl handle reference stringification
            return "$value";
        }

        my $target = Chalk::Type::Str->new();
        my $exception = Chalk::Type::Exception->type_coercion_error($source_type, $target, $value, "string coercion");
        $exception->throw();
    }

    # Boolean coercion: to_bool
    # Per spec: 0, empty string, undef are falsy; all else truthy
    method to_bool($value, $source_type) {
        # Undef is falsy
        return 0 unless defined $value;

        # Use Perl's native boolean context
        # In Perl, these are falsy: undef, 0, '', "0"
        # Everything else is truthy
        return $value ? 1 : 0;
    }
}
