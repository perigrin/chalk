# ABOUTME: Pins that a :reader accessor's synthesized body carries the field's type.
# ABOUTME: Box::v reads $v through a PadAccess; the type is in the MOP either way.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Serialize::JSON;

# A `field $v :param :reader` produces TWO ways to read the same field:
#
#   method get { return $v }   ->  graph Box::get, a FieldAccess
#   $box->v                    ->  graph Box::v,   a PadAccess
#
# Same field, same known type, different node kind -- and the loader's typing
# rule (_stamp_field_access_reprs) was only ever written for FieldAccess. So
# the accessor body reached the end of the analysis pipeline untyped while the
# explicit method did not.
#
# That is condition 1 of slice 5 (docs/plans/2026-08-24-loader-analysis-pipeline.md):
# every Value node carries a stamp. Measured over eight programs, PadAccess was
# 3 of 3 untyped -- not a sample of a large population, the whole of it.
#
# The type is not in doubt at any point: the MOP records `field $v type=Int`
# before either graph is walked. Nothing had to be inferred here, only carried.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = "$ENV{HOME}/dev/perl5-son/lib";

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
    # The MOP rides on the graphs; sorted for a deterministic choice.
    my $mop = %$graphs ? $graphs->{ (sort keys %$graphs)[0] }->mop : undef;
    return ($graphs, $mop);
}

my ($graphs, $mop) = load_program(<<'PROG');
class Box { field $v :param :reader; method get { return $v } }
print Box->new(v => 7)->get, "\n";
PROG

skip_all 'producer did not emit JSON for the class program' unless $graphs;

subtest 'the field type is known before either graph is walked' => sub {
    my ($box) = grep { $_->name eq 'Box' } $mop->classes;
    ok $box, 'the MOP has class Box';
    my ($f) = $box->fields;
    is $f->type, 'Int', 'field $v is Int in the MOP -- nothing to infer';
};

subtest 'the explicit method body is typed (it always was)' => sub {
    my ($fa) = grep { $_->operation eq 'FieldAccess' }
        $graphs->{'Box::get'}->nodes->@*;
    ok $fa, 'Box::get reads the field through a FieldAccess';
    is $fa->stamp, 'Int', 'and it carries the field type';
};

subtest 'the :reader accessor body is typed too' => sub {
    # THE REGRESSION THIS FILE EXISTS FOR.
    my $g = $graphs->{'Box::v'};
    ok $g, 'the synthesized accessor graph exists';

    my ($pa) = grep { $_->operation eq 'PadAccess' } $g->nodes->@*;
    ok $pa, 'Box::v reads the field through a PadAccess';
    is $pa->stamp, 'Int',
        'and it carries the SAME field type the FieldAccess does';
};

subtest 'no Value node in the accessor graph is left untyped' => sub {
    # Condition 1, stated over the one graph this change is about. A control
    # node legitimately has no stamp; a Value node must have one.
    require Chalk::IR::Value;
    my @untyped = grep { $_ isa Chalk::IR::Value && !defined $_->stamp }
        $graphs->{'Box::v'}->nodes->@*;
    is [map { $_->operation } @untyped], [],
        'every Value node in Box::v is typed';
};

done_testing;
