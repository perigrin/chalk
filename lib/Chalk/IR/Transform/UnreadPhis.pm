# ABOUTME: T1 -- removes the value Phis no live node reads, so no backend makes a merge
# ABOUTME: of values nothing uses (a try/catch statement's value, a dead loop variable).
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed refaddr);

class Chalk::IR::Transform::UnreadPhis {
    # How many Phis the last run() removed.
    field $removed :reader = 0;

    # run($graph) -> $graph
    #
    # A SCALAR VALUE PHI IS LIVE when a node of the graph's component that is
    # no Phi reads it, a live Phi does, or anything names it a consumer. The
    # component walks back from what the graph holds, so it never holds a Phi
    # nothing reads; a backend found one anyway through its Region's consumers
    # and made it -- a try/catch statement's value, the try arm's last
    # statement, refused as a value read past the eval's end though nothing
    # read it (stevan/curly brainfuck.pl). A dead one is unlinked: from its
    # Region's consumers and from each input's. Memory Phis are versions, and
    # so are an aggregate's (Array, Hash, List): the builder finds those by
    # the variable, with no node reading them -- removed, `@a = ()` each pass
    # kept the last pass's elements. Both stay.
    method run ($graph) {
        $removed = 0;
        my @nodes = $graph->component;
        my %in_graph = map { refaddr($_) => 1 } @nodes;
        my @phis = grep { $_->operation eq 'Phi' && !$_->memory } map {
            my $r = $_;
            grep { blessed($_) && $_->operation eq 'Phi' && blessed( $_->region ) && refaddr( $_->region ) == refaddr($r) }
                ( $r->consumers // [] )->@*
        } grep { $_->operation =~ /\A(?:Region|Loop)\z/ } @nodes;
        return $graph unless @phis;
        my %live;
        my @q = grep { blessed($_) && $_->operation eq 'Phi' }
                map  { $_->inputs->@* } grep { $_->operation ne 'Phi' } @nodes;
        while ( defined( my $p = shift @q ) ) {
            next if $live{ refaddr($p) }++;
            push @q, grep { blessed($_) && $_->operation eq 'Phi' } $p->inputs->@*;
        }
        my %seen;
        for my $p ( grep { !$seen{ refaddr($_) }++ } @phis ) {
            next if $live{ refaddr($p) } || $in_graph{ refaddr($p) } || ( $p->consumers // [] )->@*;
            next if _aggregate($p);
            $_->remove_consumer($p) for grep { blessed($_) } $p->region, $p->inputs->@*;
            $removed++;
        }
        return $graph;
    }

    # _aggregate($phi) -> true for a merge of an aggregate: stamped one, or
    # with an input that is one (an array or a hash, a literal or a read)
    sub _aggregate ($p) {
        my $agg = qr/\A(?:Array|Hash|List)/;
        return 1 if ( $p->stamp // '' ) =~ $agg;   # static type
        return 1 if grep { blessed($_) && ( ( $_->stamp // '' ) =~ $agg || $_->operation =~ /\A(?:ArrayLiteral|HashLiteral)\z/ ) } $p->inputs->@*;   # static type
        return 0;
    }
}

1;
