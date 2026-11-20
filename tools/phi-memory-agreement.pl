#!/usr/bin/perl
# ABOUTME: Counts the Phis where Phi::is_memory (read from the inputs) and the wire's own
# ABOUTME: `memory` flag disagree, over B::SoN wire files; the wire v2 plan's stage 0 check.
#
#   perl -Ilib -It/lib tools/phi-memory-agreement.pl [-v] WIRE.json ...  (or a list on stdin)
#
# WHY. Wire v2 deletes Phi::is_memory and takes the flag (plan stage 6). Any
# Phi the two tell differently today is a wire whose lowering would change
# that day: a B::SoN flag bug to fix first, or a guess here that was wrong.
# Exit 1 when there is one. A wire the loader refuses is counted, not read.
use v5.42.0;
use Scalar::Util qw(blessed);
use Chalk::IR::Serialize::JSON;
use Chalk::IR::Analysis;

my $verbose = @ARGV && $ARGV[0] eq '-v' ? shift : 0;
my @files   = @ARGV ? @ARGV : map { chomp; $_ } <STDIN>;
my %n       = map { $_ => 0 } qw(wires refused graphs phis flagged agree flag_only guess_only);
for my $file (@files) {
    my $json = do { local ( @ARGV, $/ ) = $file; <> };
    next unless length( $json // '' );
    $n{wires}++;
    my $graphs = eval { Chalk::IR::Serialize::JSON::from_json($json) } or do { $n{refused}++; next };
    for my $name ( sort keys %$graphs ) {
        $n{graphs}++;
        for my $phi ( grep { $_->operation eq 'Phi' } Chalk::IR::Analysis::_all_graph_nodes( $graphs->{$name} ) ) {
            my ( $flag, $guess ) = ( $phi->memory ? 1 : 0, $phi->is_memory ? 1 : 0 );
            $n{phis}++;
            $n{flagged} += $flag;
            my $k = $flag == $guess ? 'agree' : $flag ? 'flag_only' : 'guess_only';
            $n{$k}++;
            say join "\t", $k, $file, $name, 'Phi#' . $phi->id,
                join( ',', map { blessed($_) ? $_->operation : '-' } $phi->inputs->@* )
                if $verbose && $k ne 'agree';
        }
    }
}
say join ' ', map { "$_=$n{$_}" } qw(wires refused graphs phis flagged agree flag_only guess_only);
exit( $n{flag_only} + $n{guess_only} ? 1 : 0 );
