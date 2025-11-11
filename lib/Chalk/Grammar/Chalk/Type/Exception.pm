# ABOUTME: Exception class for type-related errors in the Chalk type system
# ABOUTME: Provides detailed, user-friendly error messages for type mismatches and coercion failures

package Chalk::Grammar::Chalk::Type::Exception;
use 5.042;
use experimental qw(class);

# Helper functions for creating type exceptions

sub type_coercion_error($source_type, $target_type, $value = undef, $context = undef) {
    my $msg = "Cannot coerce value from " . $source_type->name() . " to " . $target_type->name();
    return Chalk::Grammar::Chalk::Type::Exception->new(
        message => $msg,
        source_type => $source_type,
        target_type => $target_type,
        value => $value,
        context => $context
    );
}

sub type_mismatch_error($expected_type, $actual_type, $context = undef) {
    my $msg = "Type mismatch: expected " . $expected_type->name() . ", got " . $actual_type->name();
    return Chalk::Grammar::Chalk::Type::Exception->new(
        message => $msg,
        source_type => $actual_type,
        target_type => $expected_type,
        context => $context
    );
}

sub information_loss_warning($source_type, $target_type, $value, $context = undef) {
    my $msg = "Warning: information loss in coercion from " .
              $source_type->name() . " to " . $target_type->name();

    if (defined($value)) {
        my $value_str = defined($value) ? "'$value'" : 'undef';
        $msg .= " (value: $value_str)";
    }

    if (defined($context)) {
        $msg .= " in context: $context";
    }

    return $msg;
}

sub invalid_list_assignment_error($target_sigil) {
    my $msg = "Cannot assign List to variable with sigil '$target_sigil'. " . "List can only be assigned to arrays (\@) or hashes (%)";
    return Chalk::Grammar::Chalk::Type::Exception->new(
        message => $msg,
        context => "list assignment"
    );
}

sub membership_failure_error($type, $value, $reason = undef) {
    my $msg = "Value does not belong to type " . $type->name();

    if (defined($reason)) {
        $msg .= ": $reason";
    }

    return Chalk::Grammar::Chalk::Type::Exception->new(
        message => $msg,
        target_type => $type,
        value => $value,
        context => "type membership check"
    );
}

class Chalk::Grammar::Chalk::Type::Exception {
    field $message :param :reader;
    field $source_type :param :reader = undef;
    field $target_type :param :reader = undef;
    field $value :param :reader = undef;
    field $context :param :reader = undef;

    method as_string() {
        my $msg = $message;

        if (defined($source_type) && defined($target_type)) {
            $msg .= "\n  Source type: " . $source_type->name();
            $msg .= "\n  Target type: " . $target_type->name();
        }

        if (defined($value)) {
            my $value_str = defined($value) ? "'$value'" : 'undef';
            $msg .= "\n  Value: $value_str";
        }

        if (defined($context)) {
            $msg .= "\n  Context: $context";
        }

        return $msg;
    }

    method throw() {
        die $self->as_string();
    }
}
