# ABOUTME: Data class representing a single B::Concise operation (op).
# ABOUTME: Stores op name, arity, type info, flags, and private flags with rendering and comparison.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::ConciseOp {
    field $name      :param :reader;   # 'enter', 'const', 'padsv_store', etc.
    field $arity     :param :reader;   # '0', '1', '2', '@', ';', '$', '#'
    field $type_info :param :reader = undef;  # 'IV 42', 'PV "hello"', '$x'
    field $flags     :param :reader = '';
    field $private   :param :reader = '';      # '/LVINTRO', '/BARE'

    # Render in a format similar to B::Concise -exec output
    method to_string() {
        my $str = "<$arity>  $name";
        if (defined $type_info) {
            $str .= "[$type_info]";
        }
        if ($private ne '') {
            $str .= " $private";
        }
        return $str;
    }

    # Normalized key for structural comparison.
    # Includes op name, arity, type category (IV/NV/PV for const ops),
    # variable sigil, and private flags. Ignores general flags.
    method structural_key() {
        my $key = "$name:$arity";
        if (defined $type_info) {
            # For const ops, extract just the type prefix (IV, NV, PV)
            if ($name eq 'const' && $type_info =~ /^(IV|NV|PV)\b/) {
                $key .= ":$1";
            } else {
                $key .= ":$type_info";
            }
        }
        if ($private ne '') {
            $key .= ":$private";
        }
        return $key;
    }
}
