# ABOUTME: The implementation layer: Perl classes in lib/Chalk/Impl that chalk compiles into a
# ABOUTME: program as a special container's metaobject (%SIG's, %INC's) -- their wire, cached, and linked in.
use 5.42.0;
use utf8;

package Chalk::Impl;

use Digest::SHA qw(sha256_hex);
use File::Basename qw(dirname);
use File::Spec;
use File::Path qw(make_path);
use JSON::PP ();
use Scalar::Util ();
use Chalk::IR::Node::EntryDef;

# docs/plans/2026-11-15-perls-special-hashes-have-mop-metaobjects.md, step 1:
# an Impl class is compiled by the same path as a program -- B::SoN's wire,
# chalk's loader, T2 -- and held to the same gates. Chalk, not the program's
# wire, owns it: B::SoN runs over its file once, and its wire is kept until the
# file changes. A program that uses the container it backs gets it linked in;
# one that does not gets nothing.

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $DIR = File::Spec->catdir( dirname(__FILE__), 'Impl' );
my %WIRE;   # class -> its decoded wire, this process

# THE MODULES BUILT INTO CHALK (perigrin: strict and warnings are built into
# the system): a use or a require of one always succeeds, loads no file, and
# enters it in the module registry (%INC's metaobject).
my %BUILT_IN = map { ( $_ => 1 ) } qw(strict.pm warnings.pm);

# THE MODULES WHOSE FILES LOAD NO OTHER (perl's pragmas strict, warnings,
# utf8, feature): a program that loads only these has an %INC chalk knows
# whole -- perl starts with it empty.
my %LOADS_NO_OTHER = map { ( $_ => 1 ) } qw(strict.pm warnings.pm utf8.pm feature.pm);

# loads_no_other($name) -> true for a module whose file loads no other.
sub loads_no_other ($name) { return $LOADS_NO_OTHER{ inc_key($name) } ? 1 : 0 }

# inc_key($name) -> %INC's key for a module named either way (Foo::Bar or
# Foo/Bar.pm); a file by its path (t/test.pl) as it is.
sub inc_key ($name) { return $name =~ m{[./]} ? $name : join( '/', split /::/, $name ) . '.pm' }

# is_built_in($name) -> true for a module built into chalk.
sub is_built_in ($name) { return $BUILT_IN{ inc_key($name) } ? 1 : 0 }

# perl_may_warn($nodes) -> why perl may raise warnings of its own in the
# program loaded last (whose nodes, all of them, are given), or undef: a
# `use warnings`, a `use VERSION` of 5.35 or later, $^W, a module B::SoN
# followed (its own code may turn them on). Chalk raises none of perl's own
# warnings, so a __WARN__ handler there would miss calls perl makes.
#
# perl's warning switches are B::SoN's `dowarn`: -X turns every warning off
# (`use warnings` too), -W every one on (`no warnings` too), -w (or a
# compile-time $^W) those no `use warnings` decides. A wire that does not say
# them is refused by name.
#
# Where warnings may be on but every handler the program can store in
# $SIG{__WARN__} does nothing, stored before anything else runs
# (warn_handlers_do_nothing), whether perl calls one changes nothing: undef.
# $root is the main program's Return.
sub perl_may_warn ($root, @nodes) {
    my $sw = $Chalk::IR::Serialize::JSON::DOWARN
        // return "the wire does not say perl's warning switches (-w, -W, -X)";
    return undef if $sw->{all_off};
    my $why = $sw->{all_on} ? '-W'
        : $Chalk::IR::Serialize::JSON::USED_MODULES{warnings} ? 'use warnings'
        : ( grep { $_ >= 5.035 } keys %Chalk::IR::Serialize::JSON::USED_VERSIONS ) ? 'a use VERSION of 5.35 or later'
        : %Chalk::IR::Serialize::JSON::FOLLOWED ? 'a module compiled in'
        : $sw->{on} ? '-w or $^W'
        : ( grep { $_->operation eq 'EntryDef' && ( $_->symbol // '' ) eq "\cW" } @nodes ) ? '$^W'
        : return undef;
    return undef if warn_handlers_do_nothing($root, @nodes);
    return $why;
}

# warn_handlers_do_nothing($root, @nodes) -> true where every handler the
# program (main's Return, and all of its nodes) can put in $SIG{__WARN__} is a
# sub whose body does nothing (`sub { }`): each use of %SIG is an element of a
# constant key, and each store into `__WARN__` -- a `local` puts back what was
# there -- is of such a sub, AND IS THE FIRST THING THE PROGRAM DOES (main's
# control chain starts with it; no BEGIN or END block runs code): perl's own
# warning before the store goes to STDERR, where chalk writes none. Anything
# else (a store after another effect or in a sub, another key's name made at
# run time, %SIG read or referred to whole, a handler with a body, a module
# compiled in that may set one where the wire does not show) is no proof:
# false.
sub warn_handlers_do_nothing ($root, @nodes) {
    return 0 if %Chalk::IR::Serialize::JSON::FOLLOWED;
    return 0 if @Chalk::IR::Serialize::JSON::PHASE_GRAPHS;
    require Chalk::IR::Graph;
    my @start = grep { $_->operation eq 'Start' } Chalk::IR::Graph::own_nodes($root);
    return 0 unless @start == 1;
    my $start = $start[0];
    my %empty_op = map { ( $_ => 1 ) } qw(Start Return Constant MemStart);
    my $does_nothing = sub ($v) {
        return 0 unless Scalar::Util::blessed($v) && $v->operation eq 'AnonSub' && !grep { Scalar::Util::blessed($_) } $v->inputs->@*;
        my $sub = $v->sub;
        return 0 unless Scalar::Util::blessed($sub) && $sub->can('graph') && $sub->graph;
        return !grep { !$empty_op{ $_->operation } } $sub->graph->component;
    };
    for my $sig (grep { $_->operation eq 'EntryDef' && ( $_->metaobject_class // '' ) eq 'Chalk::Impl::SIG' } @nodes) {
        for my $el (grep { Scalar::Util::blessed($_) } ( $sig->consumers // [] )->@*) {
            my ($h, $k) = $el->inputs->@*;
            return 0 unless $el->operation eq 'Subscript' && Scalar::Util::refaddr($h) == Scalar::Util::refaddr($sig)
                && Scalar::Util::blessed($k) && $k->operation eq 'Constant' && defined $k->value;
            next unless $k->value eq '__WARN__';
            for my $u (grep { Scalar::Util::blessed($_) } ( $el->consumers // [] )->@*) {
                my ($t, $v) = $u->inputs->@*;
                next if $u->operation eq 'Assign' && Scalar::Util::refaddr($t) == Scalar::Util::refaddr($el) && $does_nothing->($v)
                    && Scalar::Util::blessed( $u->control_in ) && Scalar::Util::refaddr( $u->control_in ) == Scalar::Util::refaddr($start);
                return 0;
            }
        }
    }
    return 1;
}

# file_of($class) -> the file an Impl class is written in.
sub file_of ($class) {
    my ($leaf) = $class =~ /\AChalk::Impl::(\w+)\z/ or die "Chalk::Impl: no Impl class $class\n";
    return File::Spec->catfile( $DIR, "$leaf.pm" );
}

# wire($class) -> the class's wire (decoded), B::SoN's translation of its file:
# made once per content of the file, kept in a cache directory.
sub wire ($class) {
    return $WIRE{$class} if $WIRE{$class};
    my $file = file_of($class);
    open my $fh, '<:raw', $file or die "GAP: $class, the metaobject of a container the program uses, has no file ($file)\n";
    my $src = do { local $/; <$fh> };
    close $fh;
    my $son = File::Spec->catfile( $SON, 'B', 'SoN.pm' );
    die "GAP: $class cannot be compiled in: B::SoN is not at $SON (set PERL5_SON_LIB)\n" unless -f $son;
    my $key = sha256_hex( $src, ( stat $son )[9] // 0 );
    my $cache = File::Spec->catdir( File::Spec->tmpdir, "chalk-impl-$<" );
    my $path  = File::Spec->catfile( $cache, "$class-$key.json" =~ s/::/-/gr );
    my $json;
    if ( open my $in, '<:raw', $path ) { local $/; $json = <$in>; close $in }
    unless ( defined $json && length $json ) {
        $json = qx($^X -I$SON -MO=-q,SoN,json,package=$class $file 2>/dev/null);
        die "GAP: $class cannot be compiled in: B::SoN gave no wire for $file\n" unless $? == 0 && $json =~ /\S/;
        make_path($cache);
        my $tmp = "$path.$$";
        if ( open my $out, '>:raw', $tmp ) { print $out $json; close $out; rename $tmp, $path }
    }
    return $WIRE{$class} = JSON::PP->new->decode($json);
}

# needed($data) -> the Impl classes a program's wire needs: those whose
# container one of the graphs it may run names.
sub needed ($data) {
    my %need;
    # (a followed module's sub the program never reaches is no use of one)
    require Chalk::IR::Serialize::JSON;
    my $m = $data->{methods} // {};
    my @run = Chalk::IR::Serialize::JSON::_reachable_methods( $m, $data->{classes} // {}, $data->{refused} // {} );
    my @graphs = ( ( map { $m->{$_} } @run ), ( $data->{phase_blocks} // [] )->@* );
    for my $g (@graphs) {
        my $ns = $g->{nodes} // [];
        for my $n ( ref $ns eq 'HASH' ? values %$ns : @$ns ) {
            next unless ( $n->{op} // '' ) eq 'EntryDef';
            my $f = $n->{fields} // {};
            my $c = Chalk::IR::Node::EntryDef::metaobject_class_of( $f->{sigil}, $f->{symbol} ) or next;
            $need{$c} = 1;
        }
    }
    return sort keys %need;
}

# link_json($json) -> the program's wire with the Impl classes it needs linked
# in (their subs and their class records), or $json itself where it needs none.
sub link_json ($json) {
    # (a cheap look first: a wire naming no special container is not decoded twice)
    my @names = Chalk::IR::Node::EntryDef::metaobject_classes();
    my %sym = map { ( ( $_ =~ /(\w+)\z/ )[0] => 1 ) } @names;
    return $json unless grep { $json =~ /"symbol"\s*:\s*"\Q$_\E"/ } keys %sym;
    my $data = JSON::PP->new->decode($json);
    my @need = needed($data) or return $json;
    for my $class (@need) {
        my $w = wire($class);
        # ITS OWN BEGIN BLOCKS may only be `use`s (a pragma, a version): an
        # Impl class runs nothing at compile time.
        for my $p ( ( $w->{phase_blocks} // [] )->@* ) {
            my @eff = grep {
                my $op = $_->{op} // '';
                $op !~ /\A(?:Start|Constant|MemStart|Return)\z/
                    && !( $op eq 'Call' && ( ( $_->{fields} // {} )->{name} // '' ) =~ /\A(?:require|import|unimport|VERSION)\z/ )
            } ( $p->{nodes} // [] )->@*;
            die "GAP: $class has a $p->{phase} block of its own (an Impl class runs nothing at compile time)\n" if @eff;
        }
        die "GAP: the program defines $class, which is chalk's own (the metaobject of a container it uses)\n"
            if ( $data->{classes} // {} )->{$class} || grep { /\A\Q$class\E::/ } keys +( $data->{methods} // {} )->%*;
        die "GAP: B::SoN refused part of $class: " . join( '; ', map { "$_: $w->{refused}{$_}" } sort keys $w->{refused}->%* ) . "\n"
            if $w->{refused} && $w->{refused}->%*;
        my %m = ( $w->{methods} // {} )->%*;
        $data->{methods}{$_} = $m{$_} for keys %m;
        $data->{classes}{$class} = $w->{classes}{$class} or die "GAP: B::SoN gave no class record for $class\n";
    }
    return JSON::PP->new->canonical->encode($data);
}

1;
