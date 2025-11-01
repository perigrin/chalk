# ABOUTME: Heap-as-closure abstraction for mutable storage in functional IR
# ABOUTME: Implements immutable heap operations (alloc, read, write) using closures
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Heap {
    # Returns empty heap closure (no allocated cells)
    sub empty_heap($class) {
        return sub {
            return { storage => {}, next_addr => 0 };
        };
    }

    # Allocates new cell, returns (new_heap, address)
    sub heap_alloc($class, $heap, $value) {
        my $state = $heap->();
        my $addr = "heap:" . $state->{next_addr};

        my $new_storage = { %{$state->{storage}}, $addr => $value };
        my $new_next = $state->{next_addr} + 1;

        my $new_heap = sub {
            return { storage => $new_storage, next_addr => $new_next };
        };

        return ($new_heap, $addr);
    }

    # Reads value at address, returns undef if not allocated
    sub heap_read($class, $heap, $address) {
        my $state = $heap->();
        return $state->{storage}->{$address};
    }

    # Writes value to address, returns new heap
    sub heap_write($class, $heap, $address, $value) {
        my $state = $heap->();

        # Only write if address exists
        return $heap unless exists $state->{storage}->{$address};

        my $new_storage = { %{$state->{storage}}, $address => $value };

        return sub {
            return { storage => $new_storage, next_addr => $state->{next_addr} };
        };
    }
}

1;
