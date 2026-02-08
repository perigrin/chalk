# ABOUTME: TypeInference semiring for keyword-vs-identifier disambiguation in Earley parsing.
# ABOUTME: Tags Identifier and QualifiedIdentifier scans matching bare keywords, rejects them at completion.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::TypeInference {
    # Callback: word => true if keyword, false otherwise
    field $keyword_check :param;

    method zero() {
        return { valid => false };
    }

    method one() {
        return { valid => true };
    }

    method is_zero($value) {
        return !$value->{valid};
    }

    method multiply($left, $right) {
        # Propagate zero
        return $self->zero() if $self->is_zero($left);
        return $self->zero() if $self->is_zero($right);

        # Propagate keyword_as_identifier from either child
        my $tagged = $left->{keyword_as_identifier} || $right->{keyword_as_identifier};

        return {
            valid => true,
            ($tagged ? (keyword_as_identifier => true) : ()),
        };
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $self->is_zero($left);
        return $left if $self->is_zero($right);
        return $left;
    }

    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $existing = $item->{value};

        # Propagate zero
        return $self->zero() if $self->is_zero($existing);

        my $rule_name = $item->{rule}->name();

        # Reject empty regex // and m// — these are the defined-or operator, not a regex
        if ($rule_name eq 'RegexLiteral'
            && $matched_text =~ m{^(?:m)?//[msixpodualngcer]*$})
        {
            return $self->zero();
        }

        # In Identifier context, check if the scanned text is a keyword
        if ($rule_name eq 'Identifier' && $keyword_check->($matched_text)) {
            return $self->multiply($existing, {
                valid                => true,
                keyword_as_identifier => true,
            });
        }

        # In QualifiedIdentifier context, reject bare keywords (no :: separator)
        if ($rule_name eq 'QualifiedIdentifier'
            && $matched_text !~ /::/
            && $keyword_check->($matched_text))
        {
            return $self->multiply($existing, {
                valid                => true,
                keyword_as_identifier => true,
            });
        }

        # Non-Identifier/QualifiedIdentifier or non-keyword: transparent
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return $self->zero() if $self->is_zero($value);

        my $rule_name = $item->{rule}->name();

        # Identifier or QualifiedIdentifier completion with keyword tag → reject
        if (($rule_name eq 'Identifier' || $rule_name eq 'QualifiedIdentifier')
            && $value->{keyword_as_identifier})
        {
            return $self->zero();
        }

        # Other rules: clear the flag and pass through
        return { valid => true };
    }
}
