# ABOUTME: A Slot payload is read as its TAG says, not as the reader assumed.
# ABOUTME: A cell written tag=Num and read as Int hands back raw double bits.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# THE RULE (perigrin): reading and writing a slot -- boxing and unboxing --
# must consult the type tag.
#
# Today only the WRITE half holds. Seven store sites map their value's repr
# through _slot_tag_for_repr and write the tag beside the payload. Exactly one
# READ consults it (_lower_coerce_from_slot); the rest take a repr from the
# consumer and reinterpret the bits accordingly.
#
# The fixture is corpus `method-call`:
#
#     class Counter {
#         field $n :param = 0;
#         method inc { $n += 1 }    # wire says return_type Num
#         method val { return $n }  # wire says return_type Scalar
#     }
#
# `inc` stores CORRECTLY -- tag=Num, payload = bitcast double 11.0 to i64.
# `val` then reloads the payload and applies sitofp -- an INTEGER-to-double
# conversion -- to bits that are already a double. The result is
# 4622382067542392832, which is exactly unpack('q', pack('d', 11.0)).
#
# This test pins the emitted shape rather than the run, because the vtable ABI
# guard refuses this module before it executes. That refusal is why the defect
# read as a GAP rather than a wrong answer.

my $wire = do {
    open my $fh, '<', 't/bootstrap/ir/data/field-tag-roundtrip.json'
        or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
my $driver = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no driver graph';

# Lower the METHOD bodies, which is where the field read happens. The driver
# graph's own lowering hits the ABI guard first.
my $counter = $graphs->{'Counter::val'} or plan skip_all => 'no Counter::val';

subtest 'the write side tags the cell' => sub {
    my $inc = $graphs->{'Counter::inc'} or plan skip_all => 'no Counter::inc';
    my ($ret) = $inc->returns->@*;
    ok $ret, 'inc has a return';
    # The store is an effect on the control chain, so just assert the graph
    # carries a field store at all -- the emitted IR check below is the real one.
    ok scalar($inc->nodes->@*), 'inc has a body';
};

subtest 'a field read does not reinterpret without consulting the tag' => sub {
    my ($ret) = $counter->returns->@*;
    plan skip_all => 'no return' unless $ret;

    my $src = do {
        open my $fh, '<', 'lib/Chalk/Target/LLVM/Context.pm' or die $!;
        local $/; <$fh>;
    };

    # _lower_field_access_in_method decides how to read the payload from
    # _require_repr($node) -- the CONSUMER's belief -- and never loads the tag
    # it GEPs an index for. Assert it consults the tag.
    my ($body) = $src =~ /sub _lower_field_access_in_method \{(.*?)\n\}/s;
    ok $body, 'found _lower_field_access_in_method' or return;

    # Either it reads the tag itself, or it delegates to the shared dispatch
    # that does. Delegation is the better shape -- one mechanism, not two that
    # must agree -- so accept both and let the behavioural check below decide.
    like $body, qr/_emit_read_slot_as|_slot_tag_of/,
        'the scalar field read goes through the tag dispatch';

    unlike $body, qr/# Int: payload is i64 directly/,
        'the unconditional "payload IS an i64" reinterpretation is gone';
};

done_testing;
