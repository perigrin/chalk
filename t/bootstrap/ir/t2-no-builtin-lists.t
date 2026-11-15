#!/usr/bin/env perl
# ABOUTME: Guard: the LLVM target keeps no inline list of builtin names. Perl's facts about a
# ABOUTME: builtin are the IR's (Call methods over BuiltinTable/TypeLibrary); T2 asks them.

use 5.42.0;
use utf8;
use Test::More;
use File::Find;

# A BUILTIN-NAME ALTERNATION: a call's name (->name, or a $name taken from
# one) matched against /\A(?:a|b|...)\z/. Such a set says something about the
# builtins it names -- that is a Perl fact, and lives on T1's side
# (Chalk::Grammar::Perl::BuiltinTable, read through Chalk::IR::Node::Call).
# What T2 itself can make of a builtin is ONE named table, not a regex at a
# use site.
my $NAME_ALT = qr{
    (?: ->name \s* (?: // \s* (?: '' | q\{\} ) \s* \) )?   # a call's name, ( $c->name // '' )
      | \$name\b )                                        # or a $name taken from one
    \s* =~ \s* / \\A \( \?: [a-z_]+ \|                    # matched against an alternation of names
}x;

# Context.pm and ElaboratedContext.pm are being deleted (the fallback T2 retires).
my %EXEMPT = map { ( "lib/Chalk/Target/LLVM/$_" => 1 ) } qw(Context.pm ElaboratedContext.pm);

my @hits;
find( { no_chdir => 1, wanted => sub {
    return unless /\.pm\z/ && !$EXEMPT{$_};
    open my $fh, '<:utf8', $_ or die "$_: $!";
    while ( my $l = <$fh> ) {
        push @hits, "$_:$.: " . ( $l =~ s/^\s+//r =~ s/\s+\z//r ) if $l =~ $NAME_ALT;
    }
} }, 'lib/Chalk/Target/LLVM' );

is( scalar @hits, 0, 'no builtin-name alternation in lib/Chalk/Target/LLVM' )
    or diag join "\n", @hits;

# The guard sees what it is for (a pattern that matched nothing would pass anything).
like( q{( $u->name // '' ) =~ /\A(?:push|unshift|join)\z/}, $NAME_ALT, 'the guard sees a name alternation' );
like( q{$name =~ /\A(?:open|close)\z/}, $NAME_ALT, 'and one over a $name' );
unlike( q{$f =~ /\A(?:sitofp|zext|fptosi)\z/}, $NAME_ALT, 'an LLVM opcode set is not a builtin list' );
unlike( q{( $u->dispatch_kind // '' ) =~ /\A(?:method|indirect)\z/}, $NAME_ALT, 'nor a dispatch kind' );

done_testing;
