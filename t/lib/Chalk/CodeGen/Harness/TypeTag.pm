# ABOUTME: Canonical type-tag contract for the typed-compare oracle (G2+).
# ABOUTME: Single source of truth for infer_tag (declared values) and tag_live_value (live values).
package Chalk::CodeGen::Harness::TypeTag;

use 5.42.0;
use utf8;

use Scalar::Util qw(looks_like_number);
use builtin      qw(is_bool);
no warnings 'experimental::builtin';

# ---------------------------------------------------------------------------
# infer_tag($string_or_undef) -> $tagged_string
#
# Tags a DECLARED string value from a behavior block (is_bool not available).
# Rules:
#   undef                              -> 'Undef:'
#   already carries a type prefix      -> pass through unchanged
#   empty string                       -> 'Str:'  (not 'Bool:' — cannot distinguish)
#   looks_like_number with decimal     -> sprintf('Num:%g', $val)
#   looks_like_number                  -> "Int:$val"
#   else                               -> "Str:$val"
#
# This is the declared-value oracle: it handles the corpus behavior-block
# 'return:' values that were historically plain untagged strings.
# ---------------------------------------------------------------------------
sub infer_tag {
    my ($val) = @_;
    return 'Undef:' unless defined $val;

    # Already tagged: pass through unchanged.
    return $val if $val =~ /^(?:Bool:|Int:|Num:|Str:|Undef:)/;

    # Empty string declared as "" — could be Str or Bool:false. We cannot
    # distinguish here; treat as Str: so that only properly-tagged Bool: behavior
    # blocks match a Bool:false perl result.
    return 'Str:' if $val eq '';

    if (looks_like_number($val)) {
        # Non-finite: perl stringifies Inf/-Inf/NaN (capitalized). Detect by the
        # canonical face so that declared "Inf" or "NaN" tags correctly as Num:.
        if ($val =~ /^Inf$/i)  { return 'Num:Inf'  }
        if ($val =~ /^-Inf$/i) { return 'Num:-Inf' }
        if ($val =~ /^NaN$/i)  { return 'Num:NaN'  }
        if ($val =~ /\./) {
            return sprintf('Num:%g', $val);
        }
        return "Int:$val";
    }
    return "Str:$val";
}

# ---------------------------------------------------------------------------
# tag_live_value($scalar) -> $tagged_string
#
# Tags a LIVE Perl value (is_bool available). This is the canonical live-value
# oracle rule.
#
# Rules (checked in order):
#   is_bool true          -> 'Bool:1'
#   is_bool false         -> 'Bool:'
#   undef                 -> 'Undef:'
#   looks_like_number
#     with decimal        -> sprintf('Num:%g', $val)
#     without             -> "Int:$val"
#   else                  -> "Str:$val"
# ---------------------------------------------------------------------------
sub tag_live_value {
    my ($val) = @_;

    if (is_bool($val)) {
        return 'Bool:' . ($val ? '1' : '');
    }
    unless (defined $val) {
        return 'Undef:';
    }
    # Non-finite numerics: perl stringifies these as Inf/-Inf/NaN (capitalized).
    # looks_like_number returns true for Inf/NaN (no decimal point), which would
    # mis-tag them as Int:. Detect and tag as Num: with the perl canonical face.
    if (looks_like_number($val)) {
        my $str = "$val";  # stringify via perl to get the canonical face
        if ($str =~ /^Inf$/i)  { return 'Num:Inf'  }
        if ($str =~ /^-Inf$/i) { return 'Num:-Inf' }
        if ($str =~ /^NaN$/i)  { return 'Num:NaN'  }
        if ($val =~ /\./) {
            return sprintf('Num:%g', $val);
        }
        return "Int:$val";
    }
    return "Str:$val";
}

1;
