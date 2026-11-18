#!/usr/bin/env perl
# ABOUTME: Guard: the MOP is the bottom layer -- nothing under lib/Chalk/MOP uses, requires or calls
# ABOUTME: into the IR, the parser, the grammar or a target; they depend on it, never the reverse.

use 5.42.0;
use lib 't/lib';
use Test::Chalk;
use File::Find;

# perigrin (2026-11-15): "We need to invert those dependencies." A program
# that makes one Chalk::MOP::Class at run time pulled in 157 graphs -- the
# Graph, the node factory, every IR node class, the parser's Bindings --
# because the MOP constructed and inspected them. A method's body is opaque
# to the MOP: the compiler hands it one.
my $UPPER = qr/Chalk::(?:IR|Bootstrap|Grammar|Target|CodeGen)\b/;
my $DEPENDS = qr{
    \b(?:use|require) \s+ $UPPER         # use Chalk::IR::Graph; require Chalk::Bootstrap::...
  | $UPPER (?: ::\w+ )* (?: -> | :: \w+ \s* \( )   # Chalk::IR::Graph->new, Chalk::Grammar::...::f(...)
}x;

my @hits;
my @files = ('lib/Chalk/MOP.pm');
find( { no_chdir => 1, wanted => sub { push @files, $_ if /\.pm\z/ } }, 'lib/Chalk/MOP' );
for my $f (sort @files) {
    open my $fh, '<:utf8', $f or die "$f: $!";
    while ( my $l = <$fh> ) {
        next if $l =~ /^\s*#/;   # (a comment may name the layers above)
        push @hits, "$f:$.: " . ( $l =~ s/^\s+//r =~ s/\s+\z//r ) if $l =~ $DEPENDS;
    }
}
ok( scalar @files > 1, 'the MOP\'s files were found' );
is( scalar @hits, 0, 'the MOP depends on nothing above it' ) or diag join "\n", @hits;

# The guard sees what it is for.
like( q{use Chalk::IR::Graph;}, $DEPENDS, 'it sees a use' );
like( q{field $g = Chalk::IR::Graph->new;}, $DEPENDS, 'a constructor call' );
like( q{Chalk::Grammar::Perl::TypeLibrary::is_subtype($a, $b)}, $DEPENDS, 'a qualified call' );
unlike( q{use Chalk::MOP::Sub;}, $DEPENDS, 'not the MOP\'s own' );

done_testing;
