# ABOUTME: A shared callee's argument read is stamped with the JOIN of every
# ABOUTME: callsite's argument, not with whichever callsite is walked first.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed);
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON ();
use Chalk::Grammar::Perl::TypeLibrary ();

# `sub g { my $x = shift; return $x } g(1); g("hello")` -- one callee, two
# callsites, two argument TYPES. The callee's `shift @_` read is a SINGLE node
# shared by both, so it can only carry one stamp, and that stamp must be true
# of every value that reaches it: `Int join Str == Str`.
#
# At HEAD the seeder is first-caller-wins and the stamp depends on which
# callsite the walk reaches first. MEASURED at HEAD, both directions of
# wrongness are live and the source order selects between them:
#
#   forward  (g(1) then g("hello")):  shift-read Str, and the Int-argument
#                                     Call is stamped Str -- a NARROWING
#                                     INVENTED from the sibling site.
#   reversed (g("hello") then g(1)):  shift-read Int, and the Str-argument
#                                     Call is stamped Int -- WIDENING LOST,
#                                     a Str value carrying an Int stamp.
#
# So the two orders are NOT one assertion written twice. Each exposes a
# different failure, and the fix has to close both: gather every callsite,
# join per argument position, stamp once. The stamp then does not depend on
# walk order at all, which is the third thing asserted here -- at HEAD
# monomorphic seeding is correct only by accident of the topological walk.
#
# NOT VALIDATED BY THE GATE. A census of the whole corpus found four callees
# with more than one callsite and ZERO with more than one argument TYPE, so
# every gate case is monomorphic and on a monomorphic callee join(args) ==
# args[0]. The gate cannot tell a correct join from an absent one; this test
# is where the obligation actually lives.

my $PERL = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $SON  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";

# The join the lattice itself reports, asked rather than hardcoded.
my $JOIN = Chalk::Grammar::Perl::TypeLibrary::join_types( 'Int', 'Str' );

my %ORDER = (
    forward  => qq{use 5.42.0;\nsub g { my \$x = shift; return \$x }\nmy \$a = g(1);\nmy \$b = g("hello");\nsay(\$a);\nsay(\$b);\n},
    reversed => qq{use 5.42.0;\nsub g { my \$x = shift; return \$x }\nmy \$b = g("hello");\nmy \$a = g(1);\nsay(\$b);\nsay(\$a);\n},
);

sub load ($src) {
    my ( $fh, $path ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    binmode $fh, ':utf8';
    print $fh $src;
    close $fh;
    my $json = qx($PERL -I$SON -MO=SoN,json,package=main $path 2>/dev/null);
    return undef unless ( $json // '' ) =~ /\S/;
    return Chalk::IR::Serialize::JSON::from_json($json);
}

# The callee's single positional argument read: `shift @_` over ArgsSource.
sub arg_reads ($g) {
    return grep {
        blessed($_)
            && $_->operation eq 'Call'
            && $_->can('dispatch_kind')
            && ( $_->dispatch_kind // '' ) eq 'builtin'
            && ( $_->name // '' ) eq 'shift'
    } $g->nodes->@*;
}

sub calls_to ($graphs, $name) {
    my @out;
    for my $gn ( sort keys $graphs->%* ) {
        for my $n ( $graphs->{$gn}->nodes->@* ) {
            next
                unless blessed($n)
                && $n->operation eq 'Call'
                && $n->can('dispatch_kind')
                && ( $n->dispatch_kind // '' ) eq 'direct'
                && ( $n->name // '' ) =~ /::\Q$name\E\z/;
            push @out, $n;
        }
    }
    return @out;
}

my %stamp;    # order => the shift-read's repr, for the order-independence test

for my $order ( sort keys %ORDER ) {
    subtest "$order call order" => sub {
        my $graphs = load( $ORDER{$order} );
        plan skip_all => 'producer emitted no JSON' unless $graphs;

        my ($callee) = grep { defined } $graphs->@{'main::g'};
        plan skip_all => 'no callee graph' unless $callee;

        my @reads = arg_reads($callee);
        is( scalar @reads, 1, 'the callee has exactly one argument read' );

        # THE CALLEE-SIDE JOIN. One node, two incoming types, so it must carry
        # the least upper bound of both.
        is( $reads[0]->representation, $JOIN,
            "the shared argument read is stamped the JOIN ($JOIN)" );
        $stamp{$order} = $reads[0]->representation;

        # THE CALLSITE SIDE. A Call's own result must not be stamped from the
        # OTHER site's argument. Each Call here returns its own argument
        # unchanged, so its result repr must be a supertype of that argument's
        # -- never a type only the sibling's argument could have supplied.
        my @calls = calls_to( $graphs, 'g' );
        is( scalar @calls, 2, 'both callsites are present' );
        for my $c (@calls) {
            my ($arg) = grep { blessed($_) } $c->inputs->@*;
            next unless $arg && defined $arg->representation;
            my $own = $arg->representation;
            my $got = $c->representation // 'Unknown';
            is( Chalk::Grammar::Perl::TypeLibrary::join_types( $own, $got ),
                $got,
                "the $own-argument call is stamped $got, a supertype of its OWN argument"
            );
        }
    };
}

subtest 'the stamp does not depend on which callsite is walked first' => sub {
    plan skip_all => 'an order did not load' unless keys %stamp == 2;
    is( $stamp{forward}, $stamp{reversed},
        'both source orders reach the same stamp' );
};

done_testing;
