# ABOUTME: A Slot-repr value is ONE %Slot aggregate, not a def-bit plus a side table.
# ABOUTME: The two halves must travel together, so a merge cannot desynchronize them.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::Target::LLVM::Context;

# %Slot is { i1 defined, i64 payload } -- the cell for a value that may be
# absent (an out-of-bounds element read, a missing hash key).
#
# It was represented as its DEFINED BIT ALONE: the node's cached SSA ref was
# the i1, and the i64 payload lived in a side table (`_slot_payload`) keyed by
# that ref. Two problems with that, and the second is the one that bites:
#
#   - A consumer that took the cached ref and forgot the lookup used a
#     defined-bit where a value belonged. Three `// die` guards existed
#     specifically to catch that having happened.
#   - The table is keyed by an SSA REF STRING, and SSA numbering is per-graph.
#     `%1` in one graph is not `%1` in another -- the same string-keyed-cache
#     shape that has produced silent cross-graph miscompiles here before.
#
# And a phi could not merge it: merging the def-bit leaves the payload behind,
# so both producer sites emitted TWO parallel phis by hand and re-linked them
# in the table. That duplication is the tell -- LLVM's type system will hold a
# pair together if you let it, which is exactly what `%Str` already does for
# its own (ptr, len) pair.
#
# So a Slot value is now a real first-class aggregate: built with insertvalue,
# merged with ONE phi, read with extractvalue. This file pins the properties
# that make it safe, at the level the backend can be asked about them.

# Everything the context emitted, as one string. Instructions live in
# {blocks}[N]{insts}; there is no accessor, and adding one to production for a
# test's convenience would be the wrong direction.
sub emitted ($ctx) {
    return join "\n", map { ( $_->{insts} // [] )->@* }
        ( $ctx->{blocks} // [] )->@*;
}

subtest '%Slot is a value type, not a pointer' => sub {
    # The distinction that motivated the change. As `%Slot*` a merge would
    # combine POINTERS, requiring storage that outlives the merge and leaving
    # the halves rewritable through a stale pointer. As a value the pair is
    # atomic and needs no allocation.
    is Chalk::Target::LLVM::Context::_repr_to_llvm_type('Slot'), '%Slot',
        'Slot lowers to the aggregate BY VALUE';
};

subtest 'the aggregate carries both halves' => sub {
    my $ctx = Chalk::Target::LLVM::Context->new;

    my $slot = $ctx->_build_slot('i1 true', '%pay', 'Opaque', 'test');
    like emitted($ctx), qr/insertvalue/,
        'a Slot is CONSTRUCTED, not tracked alongside';

    # EVERY field must be written. A build that set only some would leave the
    # rest poison -- undef in LLVM's sense, not perl's. Counted against the
    # declared field list rather than a literal, so a field added without a
    # matching insertvalue turns this red instead of shipping a poison field.
    my @inserts = emitted($ctx) =~ /insertvalue/g;
    my $nfields = scalar(Chalk::Target::LLVM::Context::_slot_fields());
    is scalar(@inserts), $nfields,
        "all $nfields declared fields are inserted";
};

subtest 'the halves are read back off the aggregate' => sub {
    my $ctx = Chalk::Target::LLVM::Context->new;
    my $def = $ctx->_slot_defined_bit('%s');
    my $pay = $ctx->_slot_payload_of('%s');

    # Asserted against _slot_idx, NOT a literal: a literal here would keep
    # passing while production drifted to a different index, which is the
    # failure mode this whole naming scheme exists to prevent.
    my $i_def = Chalk::Target::LLVM::Context::_slot_idx('defined');
    my $i_pay = Chalk::Target::LLVM::Context::_slot_idx('payload');
    like emitted($ctx), qr/extractvalue %Slot %s, $i_def\b/,
        'the defined bit is read at the named defined index';
    like emitted($ctx), qr/extractvalue %Slot %s, $i_pay\b/,
        'the payload is read at the named payload index';
    isnt $def, $pay, 'they are distinct SSA values';
};

subtest 'the side table is gone' => sub {
    # THE POINT OF THE CHANGE. A surviving side table means a surviving way to
    # desynchronize the pair, so its absence is the invariant worth pinning --
    # not merely that the new helpers exist.
    ok !Chalk::Target::LLVM::Context->can('slot_payload_for'),
        'slot_payload_for is retired';

    my $ctx = Chalk::Target::LLVM::Context->new;
    ok !exists $ctx->{_slot_payload},
        'no _slot_payload side table on the context';
};

done_testing;
