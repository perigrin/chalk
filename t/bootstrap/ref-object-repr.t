# ABOUTME: Guards the RefType repr (class-simple, ref($obj)) and the ref()/\ node split.
# ABOUTME: ref($x) -> RefType :Str (always); the \ operator stays a distinct Ref node.

use 5.42.0;
use utf8;
use Test2::V0;
use File::Temp qw(tempfile);

use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON qw(from_json);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# Load the B::SoN JSON for a driver snippet (+ optional class sections) and
# return the loaded main::corpus_case graph's nodes.
sub load_nodes ($driver, $head = '', @classes) {
    my $src = "$head\npackage main;\nsub corpus_case { $driver }\n";
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src; close $fh;
    my $pkgs = join(',', 'package=main', map { "package=$_" } @classes);
    my $json = qx($PERL -I$SON -MO=SoN,json,$pkgs $tmp 2>/dev/null);
    return () unless $json =~ /\S/;
    my ($graphs, $mop) = from_json($json);
    my $g = $graphs->{'main::corpus_case'} or return ();
    return $g->nodes->@*;
}

subtest 'ref($obj) is a RefType stamped Str (the class name)' => sub {
    my @nodes = load_nodes(
        'my $e = Empty->new; ref($e)',
        "use feature 'class'; no warnings 'experimental::class';\nclass Empty { }",
        'Empty',
    );
    my ($rt) = grep { $_->operation eq 'RefType' } @nodes;
    ok(defined $rt, 'has a RefType node') or return;
    is($rt->representation, 'Str', 'RefType carries a Str repr');
    ok(!grep({ $_->operation eq 'Ref' } @nodes), 'no Ref node (that is the \\ operator)');
};

subtest 'ref() over a non-object is also a RefType :Str (not object-specific)' => sub {
    my @nodes = load_nodes('my $r = [1,2,3]; ref($r)');
    my ($rt) = grep { $_->operation eq 'RefType' } @nodes;
    ok(defined $rt, 'ref([...]) is a RefType') or return;
    is($rt->representation, 'Str', 'ref() is always Str regardless of operand');
};

subtest 'the \\ operator loads as a Ref, not a RefType (collision teeth)' => sub {
    # \(expr) is the reference constructor -- a Ref node, NEVER a RefType. This
    # is the split that prevents \(Empty->new) from lowering to the class name.
    my @nodes = load_nodes('my $x = 5; \\$x');
    ok(grep({ $_->operation eq 'Ref' } @nodes), '\\$x is a Ref node');
    ok(!grep({ $_->operation eq 'RefType' } @nodes), '\\$x is NOT a RefType');
};

done_testing();
