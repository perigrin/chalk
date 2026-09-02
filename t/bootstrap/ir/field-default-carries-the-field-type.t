# ABOUTME: Pins that a field default graph's value node carries the field's declared type.
# ABOUTME: An aggregate default arrives stamped Unknown; the field's own type is what resolves it.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Serialize::JSON;

# A field default rides on the wire as its OWN graph (`Bag::__DEFAULT_0`),
# whose Return value is the default expression. The producer stamps that value
# where it can -- a `field $n = 0` default arrives as `Constant :Int`.
#
# It cannot stamp an AGGREGATE one. Measured on the pinned producer, the
# `[10,20,30]` of `field $items = [10,20,30]` arrives as
# `ArrayLiteral :Unknown`, while the identical `[10,20,30]` in an ordinary
# graph arrives as `ArrayLiteral :ArrayRef`. That is not an oversight: ONE
# ArrayLiteral op builds both `[1,2,3]` (a reference) and `my @a = (1,2,3)` (a
# plain array), so the op name does not name the type and %_SEED_REPR
# deliberately refuses to guess from it (Analysis.pm:131).
#
# In a field default the ambiguity is already resolved, and not by inference:
# the field's DECLARED type says which of the two this is. The wire carries it
# on the field record (`"type" : "ArrayRef"`) before either graph is walked.
#
# So this is forward inference from a declaration onto its initializer, and it
# is the shape backward inference is allowed to take: filling a genuine HOLE
# (`Unknown`, where the producer explicitly declined) from an AUTHORITATIVE
# source, never preempting one. Without it the default node reaches the backend
# with no representation and Target::LLVM reports
# "Call(new).default.field ... NO representation".

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# Same exclusion list the corpus gate uses (ProgramRunner). Without it the wire
# carries the producer's own internals and the counts describe perl, not Chalk.
my $PKG_EXCLUDE = join(',', map { "not_package=$_" } qw(
    SoN B JSON Carp Config Exporter DynaLoader List Scalar
    overload overloading warnings strict utf8 bytes feature
));

sub load_program ($body) {
    require File::Temp;
    my ($fh, $tmp) = File::Temp::tempfile(SUFFIX => '.pl', UNLINK => 1);
    print {$fh} "use 5.42.0;\nuse feature 'class';\n"
              . "no warnings 'experimental::class';\n$body\n";
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,$PKG_EXCLUDE $tmp 2>/dev/null);
    return unless $json =~ /\S/;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = %$graphs ? $graphs->{ (sort keys %$graphs)[0] }->mop : undef;
    return ($graphs, $mop);
}

# default_value_of($mop, $class, $field) — the node a default graph returns,
# reached the way Target::LLVM reaches it: off the MOP's field record.
sub default_value_of ($mop, $class_name, $field_name) {
    my ($cls) = grep { $_->name eq $class_name } $mop->classes;
    return unless $cls;
    my ($f) = grep { $_->name eq $field_name } $cls->fields;
    return unless $f;
    return ($f, $f->default_value);
}

subtest 'an aggregate default carries the field type' => sub {
    my ($graphs, $mop) = load_program(<<'PROG');
class Bag { field $items = [10, 20, 30]; method first { $items->[0] } }
print Bag->new->first, "\n";
PROG
    skip_all 'producer did not emit JSON for the class program' unless $graphs;

    my ($f, $dv) = default_value_of($mop, 'Bag', '$items');
    ok $f, 'the MOP has field $items on class Bag';
    is $f->type, 'ArrayRef', 'the field is declared ArrayRef -- the source of truth';
    ok $dv, 'the field has a default value node';
    is $dv->operation, 'ArrayLiteral', 'the default is an aggregate literal';

    # THE REGRESSION THIS FILE EXISTS FOR. Unstamped here means the LLVM
    # backend's _require_repr rejects it as "Call(new).default.field ... NO
    # representation".
    is $dv->representation, 'ArrayRef',
        'the default node carries the field type, not Unknown';
};

subtest 'a scalar default the producer already typed is NOT overwritten' => sub {
    # The other direction of the same rule: fill a hole, never preempt a
    # source. Here the producer's `Constant :Int` is STRICTLY BETTER than the
    # field record's weaker `Scalar`, so the field type must not be stamped
    # over it -- Int is i64 and Scalar is a %Slot, and crossing those is the
    # representational break that a type-sound-but-provenance-free stamp makes.
    my ($graphs, $mop) = load_program(<<'PROG');
class Counter { field $n = 0; method get { $n } }
print Counter->new->get, "\n";
PROG
    skip_all 'producer did not emit JSON for the class program' unless $graphs;

    my ($f, $dv) = default_value_of($mop, 'Counter', '$n');
    ok $dv, 'the field has a default value node';
    is $dv->operation, 'Constant', 'the default is a scalar constant';
    is $dv->representation, 'Int',
        'the producer answer survives -- it is narrower than the field record';
};

done_testing;
