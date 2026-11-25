#!/usr/bin/env perl
# ABOUTME: Guard (CLAUDE.md constraint 5): lib/ loads only Chalk's own modules and the
# ABOUTME: pragmas that compile to nothing at run time; each outside module left is named.

use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Find;

# THE PRAGMAS lib/ may say, and Chalk's own modules. Everything else lib/ loads
# must be listed below with why it is still there -- and the list only shrinks.
my %PRAGMA = map { ( $_ => 1 ) } qw(strict warnings utf8 feature experimental constant integer builtin);

# STILL LOADED, under review (perigrin, 2026-11-18). Each entry is a file and the
# module it loads; a file not listed here may load none of them.
my %KNOWN = (
    # the loader reads B::SoN's JSON wire until it moves to Sereal (Chalk::Loader::Sereal)
    'lib/Chalk/IR/Serialize/JSON.pm'  => [qw(JSON::PP Exporter)],
    'lib/Chalk/Impl.pm'               => [qw(JSON::PP File::Spec File::Path File::Basename Digest::SHA)],
    'lib/Chalk/IR/Graph/TypedInvariant.pm'    => [qw(Carp)],
    'lib/Chalk/Target/LLVM.pm'        => [qw(parent)],
    'lib/Chalk/Bootstrap/BNF/Target/XS.pm' => [qw(XSLoader)],
    'lib/Chalk/Bootstrap/Runtime.pm'  => [qw(DynaLoader Config)],
);

my %seen;    # "file module" => 1
find( { no_chdir => 1, wanted => sub {
    return unless /\.pm\z/;
    my $file = $File::Find::name;
    open my $fh, '<', $file or die "$file: $!";
    my $pod = 0;
    while ( my $line = <$fh> ) {
        $pod = 1 if $line =~ /\A=[a-z]/;
        $pod = 0, next if $line =~ /\A=cut/;
        next if $pod;
        last if $line =~ /\A__(?:END|DATA)__\b/;
        next unless $line =~ /\A\s*(?:use|require|no)\s+([A-Za-z][\w:]*)\s*(?:;|\(|qw\b|['"]|[\d.v]|->|\z)/;
        my $m = $1;
        next if $m =~ /\AChalk(?:::|\z)/ || $PRAGMA{$m};
        $seen{"$file $m"} = 1;
    }
} }, 'lib' );

my %known = map { my $f = $_; map { ( "$f $_" => 1 ) } $KNOWN{$f}->@* } keys %KNOWN;
my @outside = grep { !$known{$_} } sort keys %seen;
is_deeply( \@outside, [], 'lib/ loads no outside module but the listed ones' )
    or diag "outside modules:\n" . join "\n", map { "  $_" } @outside;

# The list only shrinks: an entry nothing loads any more is removed, not kept.
my @stale = grep { !$seen{$_} } sort keys %known;
is_deeply( \@stale, [], 'every listed module is still loaded (remove the ones that are not)' )
    or diag "no longer loaded:\n" . join "\n", map { "  $_" } @stale;

done_testing;
