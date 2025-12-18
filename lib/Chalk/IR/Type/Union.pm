# ABOUTME: Union type representing multiple possible types at a program point
# ABOUTME: Used at control flow merge points (Phi nodes) and uncertain contexts

use 5.42.0;
use experimental qw(class);
use utf8;
use Scalar::Util qw(refaddr);

class Chalk::IR::Type::Union {
    field $members :param :reader;  # ArrayRef of type objects

    ADJUST {
        # Flatten nested unions
        my @flat;
        for my $member ($members->@*) {
            if ($member isa Chalk::IR::Type::Union) {
                push @flat, $member->members->@*;
            } else {
                push @flat, $member;
            }
        }

        # Deduplicate by ref (same type object)
        my %seen;
        $members = [ grep { !$seen{refaddr($_)}++ } @flat ];
    }

    # Check if this union contains a specific type
    method contains($type) {
        for my $member ($members->@*) {
            return 1 if refaddr($member) == refaddr($type);
            # Also check if types are equivalent by class
            return 1 if ref($member) eq ref($type);
        }
        return 0;
    }

    # Meet operation - intersection with another type
    method meet($other) {
        # If other is one of our members, narrow to it
        if ($self->contains($other)) {
            return $other;
        }

        # If other is a union, find common members
        if ($other isa Chalk::IR::Type::Union) {
            my @common;
            for my $my_member ($members->@*) {
                push @common, $my_member if $other->contains($my_member);
            }
            return Chalk::IR::Type::Bottom->bottom() if @common == 0;
            return $common[0] if @common == 1;
            return Chalk::IR::Type::Union->new(members => \@common);
        }

        # No overlap
        return Chalk::IR::Type::Bottom->bottom();
    }

    # Join operation - union with another type
    method join($other) {
        if ($other isa Chalk::IR::Type::Union) {
            return Chalk::IR::Type::Union->new(
                members => [$members->@*, $other->members->@*]
            );
        }
        return Chalk::IR::Type::Union->new(members => [$members->@*, $other]);
    }

    # Union is never constant (even if all members are)
    method is_constant() { return 0; }

    # Union is never top or bottom
    method is_top() { return 0; }
    method is_bottom() { return 0; }

    # String representation for debugging
    method to_string() {
        my @names = map { ref($_) =~ s/.*:://r } $members->@*;
        return join(' | ', @names);
    }
}

1;
