# ABOUTME: The loader replays the wire's sub records into MOP::Sub metaobjects.
# ABOUTME: Sub-level facts come from the MOP, never from scanning the graph.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use lib 'lib', 't/lib';
use Chalk::IR::Serialize::JSON;

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

plan skip_all => "perl 5.42 not found at $PERL" unless -x $PERL;
plan skip_all => "perl5-son not found at $SON"  unless -f "$SON/B/SoN.pm";

my $dir = tempdir(CLEANUP => 1);

# Compile $src through the producer, then load it the way the backend does.
# Returns the sealed MOP (from_json's second return value).
sub mop_for ($src, $name, %opt) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $filter = $opt{no_filter} ? '' : ',package=main';
    my $json = qx{$PERL -I$SON -MO=SoN,json$filter $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
    my $mop = (values %$graphs)[0]->mop;
    return $mop;
}

sub sub_named ($mop, $class, $name) {
    return undef unless defined $mop;
    my $cls = $mop->for_class($class) or return undef;
    my ($s) = grep { $_->name eq $name } $cls->subs;
    return $s;
}

subtest 'a file-level sub becomes a MOP::Sub on class main' => sub {
    my $mop = mop_for('sub f { 42 } print f(), "\n";', 'plain');
    ok defined $mop, 'the loader built a MOP';
    my $s = sub_named($mop, 'main', 'f');
    ok defined $s, 'sub f is a MOP::Sub under main' or return;
    isa_ok $s, 'Chalk::MOP::Sub';
    ok defined $s->graph, 'the sub carries its loaded graph';
};

# The whole point of the channel: these come from the WIRE, not from a scan of
# the graph. uses_args in particular cannot be recovered reliably -- `@_` has
# three IR spellings and vanishes entirely for `my ($a,$b) = @_`.
subtest 'sub metadata survives the replay' => sub {
    my $mop = mop_for('sub f { my $n = shift; $n+1 } print f(1), "\n";', 'meta');
    my $s = sub_named($mop, 'main', 'f');
    ok defined $s, 'sub f present' or return;
    ok $s->uses_args, 'uses_args is true for a shift-using callee';
    is_deeply $s->params, [], 'params replayed';

    my $mop2 = mop_for('sub g { 42 } print g(), "\n";', 'meta2');
    my $s2 = sub_named($mop2, 'main', 'g');
    ok defined $s2, 'sub g present' or return;
    ok !$s2->uses_args, 'uses_args is false for a callee that never reads @_';
};

# THE 1b CLASSIFICATION, folded in from 1a's review. A `method` carries an
# implicit invocant and a `sub` does not, so they must land in different
# metaobjects. The producer knows: CvFLAGS & CVf_METHOD.
subtest 'method and sub are distinguished in the MOP' => sub {
    my $mop = mop_for(<<'PERL', 'cls', no_filter => 1);
use feature 'class';
no warnings 'experimental::class';
class Widget { field $n :param = 0; method get { $n } sub helper { 7 } }
print Widget->new(n => 1)->get, "\n";
PERL
    my $cls = $mop && $mop->for_class('Widget');
    ok defined $cls, 'Widget is in the MOP' or return;

    my %m = map { $_->name => 1 } $cls->methods;
    my %s = map { $_->name => 1 } $cls->subs;

    ok $m{get},    'method get is a MOP::Method';
    ok !$s{get},   'method get is NOT also a MOP::Sub';
    ok $s{helper}, 'plain sub helper is a MOP::Sub';
    ok !$m{helper},'plain sub helper is NOT a MOP::Method';
};

done_testing;
