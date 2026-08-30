# ABOUTME: A container's element repr is the join of its initializers AND every
# ABOUTME: store into it -- not the initializers alone.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use JSON::PP;
use File::Temp qw(tempfile);
use Chalk::IR::Serialize::JSON ();
use Chalk::IR::Analysis ();
use Scalar::Util qw(blessed);

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON" unless -f "$SON/B/SoN.pm";
plan skip_all => "perl 5.42 not found"         unless -x $PERL;

# `_element_repr` reads a container's LITERAL INITIALIZERS and nothing else.
# A store that changes the element type is invisible to it, so the container
# keeps the initializers' repr and a later read interprets the stored bits at
# the wrong type.
#
# The backend already knows this and refuses rather than miscompiling --
# Context.pm's Assign(Array-lvalue) arm excludes Str/Num with the comment
# "the container's element repr is inferred from its literal initializers
# only, so a type-changing store would read back at the old repr. Until the
# element-type inference joins stores as well as literals, this must stay a
# GAP." This test is that "until".

sub load ($src) {
    my ($fh, $tmp) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $tmp 2>/dev/null);
    return undef unless $json =~ /\S/;
    return scalar eval { Chalk::IR::Serialize::JSON::from_json($json) };
}

sub subscript_reprs ($graphs) {
    my @r;
    for my $gn (sort keys %$graphs) {
        for my $n (Chalk::IR::Analysis::_all_graph_nodes($graphs->{$gn})) {
            next unless blessed($n) && $n->can('operation');
            push @r, $n->representation // 'undef'
                if $n->operation eq 'Subscript';
        }
    }
    return @r;
}

subtest 'a Str store widens the element repr the READ sees' => sub {
    my $g = load(qq{use 5.42.0;\nmy \@arr=(1,2); \$arr[0]="hello"; print \$arr[0];\n})
        or plan skip_all => 'B::SoN produced no JSON';

    my @reprs = subscript_reprs($g);
    ok(scalar @reprs, 'the program has Subscript nodes to check');

    # The READ after the store must not claim Int: the slot holds a Str.
    # (The lvalue Subscript may legitimately still read Int -- it is the
    # store's destination, not the value.)
    ok((grep { $_ eq 'Str' } @reprs),
       'at least one Subscript carries the widened Str repr')
        or diag("subscript reprs: @reprs");
};

subtest 'the element join reaches the backend' => sub {
    # The behavioural half: with the join in place the Assign(Array-lvalue)
    # GAP no longer fires for a Str store. Until then this is the honest
    # refusal the guard's comment describes.
    my $g = load(qq{use 5.42.0;\nmy \@arr=(1,2); \$arr[0]="hello"; print \$arr[0];\n})
        or plan skip_all => 'B::SoN produced no JSON';
    my $entry = $g->{'main::__PROGRAM__'} or plan skip_all => 'no entry graph';
    my @rets = grep { $_->operation eq 'Return' }
               Chalk::IR::Analysis::_all_graph_nodes($entry);
    plan skip_all => 'no Return' unless @rets;

    require Chalk::Target::LLVM;
    my $err;
    eval { Chalk::Target::LLVM->lower($rets[-1]); 1 } or $err = $@;
    unlike($err // '', qr/cannot be stored in an i64 Slot payload/,
           'the Str store lowers rather than GAPping on the element repr');
};

done_testing;
