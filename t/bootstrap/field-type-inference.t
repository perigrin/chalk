# ABOUTME: Guards the constructor-argument field-type inference (019f0597).
# ABOUTME: Int/Str :param fields infer their type; Num (mis-typing risk) does NOT.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# Produce a JSON for a one-field class constructed with the given literal, load
# it, and return the field's inferred type (or undef).
sub field_type_for ($class, $field, $literal) {
    my $src = <<"PL";
use feature 'class';
no warnings 'experimental::class';
class $class { field \$$field :param; method get { \$$field } }
package main;
sub corpus_case { my \$o = $class->new($field => $literal); \$o->get }
PL
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=$class $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    my ($graphs, $mop) = from_json($json);
    return undef unless $mop;
    my ($cls) = grep { $_->name eq $class } $mop->classes;
    return undef unless $cls;
    my ($f) = grep { $_->param_name eq $field } $cls->fields;
    return $f ? $f->type : undef;
}

subtest 'a Str :param field infers Str from the constructor arg' => sub {
    is(field_type_for('FStr', 'v', q{"hi"}), 'Str',
        'Str construction types the field Str');
};

subtest 'an Int :param field infers Int from the constructor arg' => sub {
    is(field_type_for('FInt', 'v', '42'), 'Int',
        'Int construction types the field Int');
};

subtest 'a Num-literal :param field is NOT inferred (would mis-lower)' => sub {
    # `new(v => 3.0)` gives the arg a Num repr, but perl treats 3.0 as the
    # integer 3; typing the field Num lowers an i64 value into a double slot
    # (malformed IR). The inference must skip Num and leave the field untyped
    # (an honest GAP), matching the constant-default path's Num refusal.
    is(field_type_for('FNum', 'v', '3.0'), undef,
        'Num construction does NOT type the field (stays an honest GAP)');
};

done_testing();
