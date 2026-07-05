# ABOUTME: Guards the Ref(Object) -> Str repr inference (class-simple, ref($obj)).
# ABOUTME: ref($obj) loads with a Str repr (the class name), not undef (-> Int miscompile).

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# Load the B::SoN JSON for a snippet and return the repr of the Ref node in
# main::corpus_case.
sub ref_repr ($body, @classes) {
    my $src = "package main;\nsub corpus_case { $body }\n";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $pkgs = join(',', 'package=main', map { "package=$_" } @classes);
    my $json = qx($PERL -I$SON -MO=SoN,json,$pkgs $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    my ($graphs, $mop) = from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return undef;
    my ($ref) = grep { $_->operation eq 'Ref' } $g->nodes->@*;
    return $ref ? ($ref->representation // '<undef>') : '<no Ref>';
}

subtest 'ref($obj) loads with a Str repr (the class name)' => sub {
    # ref() on a class instance yields the class name (a Str). The Ref node must
    # carry a Str repr so the return epilogue takes the Str path -- an undef repr
    # defaults to Int and truncates the class-name pointer (a silent miscompile).
    my $src = <<'PL';
use feature 'class'; no warnings 'experimental::class';
class Empty { }
my $e = Empty->new;
ref($e)
PL
    # split the class out the way the corpus runner does: the class body is a
    # separate section, the driver calls new + ref.
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh <<'PL'; close $fh;
use feature 'class'; no warnings 'experimental::class';
class Empty { }
package main;
sub corpus_case { my $e = Empty->new; ref($e) }
PL
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main,package=Empty $tmp 2>/dev/null);
    my ($graphs, $mop) = from_json($json);
    my $g = $graphs->{'main::corpus_case'};
    my ($ref) = grep { $_->operation eq 'Ref' } $g->nodes->@*;
    ok(defined $ref, 'has a Ref node') or return;
    is($ref->representation, 'Str', 'Ref(Object) carries a Str repr');
};

subtest 'Ref over a non-Object stays untyped (teeth)' => sub {
    # Only Ref(Object) is the class-name Str case. Ref over a plain scalar (the \
    # operator, or ref() on a non-object) is NOT stamped Str by this rule -- it
    # stays untyped (an honest GAP), so a wrong repr does not leak in.
    is(ref_repr('my $x = 5; \\$x'), '<undef>',
        'Ref(scalar) (the \\ operator) is not stamped Str');
};

done_testing();
