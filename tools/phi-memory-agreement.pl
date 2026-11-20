#!/usr/bin/perl
# ABOUTME: Counts the Phis where chalk's inference of a memory Phi (WireUpgrade's, from the
# ABOUTME: inputs) and the wire's own `memory` flag disagree; the wire v2 plan's stage 0 check.
#
#   perl -Ilib -It/lib tools/phi-memory-agreement.pl [-v] WIRE.json ...  (or a list on stdin)
#
# WHY. Wire v2 deletes Phi::is_memory and takes the flag (plan stage 6). Any
# Phi the two tell differently today is a wire whose lowering would change
# that day: a B::SoN flag bug to fix first, or a guess here that was wrong.
# Exit 1 when there is one. A wire the loader refuses is counted, not read.
#
# SINCE STAGE 2 the inference is Chalk::IR::Serialize::WireUpgrade's, run on
# a v1 wire as it is loaded (the loaded Phi's `memory` is the inference), so
# the wire's own flag is read from the wire before the upgrade.
use v5.42.0;
use Scalar::Util qw(refaddr);
use JSON::PP ();
use Chalk::IR::Serialize::JSON;
use Chalk::IR::Serialize::WireUpgrade;

my $verbose = @ARGV && $ARGV[0] eq '-v' ? shift : 0;
my @files   = @ARGV ? @ARGV : map { chomp; $_ } <STDIN>;
my %n       = map { $_ => 0 } qw(wires refused graphs phis flagged agree flag_only guess_only);
for my $file (@files) {
    my $json = do { local ( @ARGV, $/ ) = $file; <> };
    next unless length( $json // '' );
    $n{wires}++;
    my $graphs = eval { Chalk::IR::Serialize::JSON::from_json($json) } or do { $n{refused}++; next };
    my $data = JSON::PP->new->utf8->decode($json);
    next unless ( $data->{version} // 1 ) == 1;
    # (the wire's flag, by the node's own hash: the upgrade renumbers ids)
    my %flag = map { ( refaddr($_) => ( ( $_->{fields} // {} )->{memory} ? 1 : 0 ) ) }
        grep { $_->{op} eq 'Phi' } map { ( $_->{nodes} // [] )->@* } values +( $data->{methods} // {} )->%*;
    Chalk::IR::Serialize::WireUpgrade::upgrade($data);
    for my $name ( sort grep { $graphs->{$_} } keys +( $data->{methods} // {} )->%* ) {
        $n{graphs}++;
        for my $phi ( grep { $_->{op} eq 'Phi' } ( $data->{methods}{$name}{nodes} // [] )->@* ) {
            my ( $flag, $guess ) = ( $flag{ refaddr($phi) }, ( $phi->{fields} // {} )->{memory} ? 1 : 0 );
            $n{phis}++;
            $n{flagged} += $flag;
            my $k = $flag == $guess ? 'agree' : $flag ? 'flag_only' : 'guess_only';
            $n{$k}++;
            say join "\t", $k, $file, $name, "Phi#$phi->{id}" if $verbose && $k ne 'agree';
        }
    }
}
say join ' ', map { "$_=$n{$_}" } qw(wires refused graphs phis flagged agree flag_only guess_only);
exit( $n{flag_only} + $n{guess_only} ? 1 : 0 );
