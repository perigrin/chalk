# ABOUTME: IR node for accessing a package (stash) variable in the Sea of Nodes graph.
# ABOUTME: Represents reads of package globals like $Foo::bar or %Foo::.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::EntryDef :isa(Chalk::IR::Node::Access) {
    field $package :param :reader = '';

    # `symbol` is the BARE identifier -- 'g', never '$g'. perl's own terms, from
    # Symbol.pm: qualify turns unqualified SYMBOL NAMES into qualified VARIABLE
    # NAMES, and qualify("x") is "main::x" with no sigil, because the symbol
    # table is sigil-free and the sigil selects a slot within the glob.
    field $symbol  :param :reader = '';

    # THE SIGIL IS PART OF THE IDENTITY, and it is REQUIRED -- there is no
    # sensible default.
    #
    # `_` alone names THREE different things in perl: the scalar `$_`, the
    # argument array `@_`, and the bareword `_` filetest handle (`-f _`, which
    # reuses the last stat buffer). A name-only identity hash-consed the first
    # two into ONE node -- measured, a single EntryDef(_) fed both a
    # `shift @_` Call and a RegexMatch subject. The same applies to any stash
    # holding one name under two sigils: `$g` and `@g` are unrelated variables.
    #
    # No default, deliberately: a default lets a construction site omit the
    # sigil and still hash-cons, which is exactly how the collision hid. A
    # sigil-less variable lookup should be impossible to express.
    field $sigil      :param :reader;

    method operation() { 'EntryDef' }

    # memory_operand -> a package scalar's read reads at its input's version.
    method memory_operand() { return $self->is_package_scalar ? $self->inputs->[0] : undef }
    sub identity_kind { q(hash_consed) }

    # The qualified spelling, composed in ONE place -- see the note on
    # PadAccess::name. This is the variable's name WITHOUT its package;
    # `_pkg_*_global_name` consumers pass `package` alongside it.
    method name() { $sigil . $symbol }

    method content_hash() {
        return join('|', 'EntryDef', "package=$package",
            "sigil=$sigil", "symbol=$symbol", $self->_serialize_inputs());
    }

    # PERL'S OWN NAMES, by sigil: each has a meaning of perl's (the program's
    # arguments, its environment, its filehandles, a package's @ISA, ...), so
    # it is not one of the program's variables -- read elsewhere, or refused.
    # Only names a word could spell: punctuation ($/, $", $@) is perl's by its
    # spelling. NOT `$_` (B::SoN spells a foreach's aliasing as stores to it,
    # the element written back, its value restored after), nor `$a` and `$b`
    # (a sort sets them before each call of its comparator): those are package
    # scalars like any other here.
    my @AGGREGATES_OWN = qw(ISA ARGV ARGVOUT ENV INC SIG STDIN STDOUT STDERR _);
    my %PERLS_OWN = (
        '$' => { map { ( $_ => 1 ) } qw(ARGV ENV INC STDIN STDOUT STDERR 0 AUTOLOAD) },
        '@' => { map { ( $_ => 1 ) } @AGGREGATES_OWN },
        '%' => { map { ( $_ => 1 ) } @AGGREGATES_OWN },
    );

    # is_perls_own -> true for a name perl gives a meaning of its own at this
    # sigil.
    method is_perls_own() { return $PERLS_OWN{ $sigil // '' }{ $symbol // '' } ? 1 : 0 }

    # PERL'S SPECIAL SCALARS OF THE RUN (perlvar), by their spelling (`$^W`
    # is the symbol "\x17"): what each is when the program starts.
    #   $^W  the warnings switch: 1 under -w, else 0
    #   $^O  the name of the operating system perl was built for
    #   $^T  the time the program started, in seconds since the epoch
    #   $^   the top-of-page format name of the selected output handle
    #        ("STDOUT_TOP" for STDOUT)
    my %SPECIAL_SCALAR = ( "\x17" => 'warnings_switch', "\x0f" => 'os_name', "\x14" => 'start_time', '^' => 'format_top_name' );

    # special_scalar -> which of perl's special scalars of the run this is
    # (a key of %SPECIAL_SCALAR's values), or undef.
    method special_scalar() {
        return undef unless ( $sigil // '' ) eq '$' && ( $package // 'main' ) eq 'main';
        return $SPECIAL_SCALAR{ $symbol // '' };
    }

    # PERL'S SPECIAL HASHES WHOSE METAOBJECT IS A MOP OBJECT
    # (docs/plans/2026-11-15-perls-special-hashes-have-mop-metaobjects.md):
    # a container like any other, its operations answered by an instance of
    # the class chalk compiles in for it (lib/Chalk/Impl/*.pm). Not a tie:
    # there is no tie object, and `tied` is false, as in perl. perl puts these
    # names in main whatever package names them.
    my %METAOBJECT_CLASS = ( '%' => { SIG => 'Chalk::Impl::SIG', INC => 'Chalk::Impl::INC' } );

    # metaobject_class_of($sigil, $symbol) -> the class whose instance is the
    # metaobject of perl's container of that name, or undef (a sub, for the
    # wire, before a node exists).
    #
    # A STASH (`%main::`, `%Foo::`) is a hash whose metaobject is its
    # package's Chalk::MOP::Class -- the compiler's own description of the
    # package, carried into the run: its symbols are the stash's keys.
    sub metaobject_class_of ($sg, $sym) {
        return 'Chalk::MOP::Class' if ( $sg // '' ) eq '%' && ( $sym // '' ) =~ /\A\w+(?:::\w+)*::\z/;
        return $METAOBJECT_CLASS{ $sg // '' }{ $sym // '' };
    }

    # metaobject_classes -> every class a special container's metaobject is.
    sub metaobject_classes () { return sort( ( map { values %$_ } values %METAOBJECT_CLASS ), 'Chalk::MOP::Class' ) }

    # metaobject_package -> the package a stash describes (`main` for
    # `%main::`), undef for a container that is no stash.
    method metaobject_package() { return ( $sigil // '' ) eq '%' && ( $symbol // '' ) =~ /\A(\w+(?:::\w+)*)::\z/ ? $1 : undef }

    # metaobject_class -> this container's metaobject class (a MOP object), or undef.
    method metaobject_class() { return metaobject_class_of( $sigil, $symbol ) }

    # values_are_only_truths -> true where what a key holds is perl's own, not
    # the program's: %INC's values are paths in perl's file system. Whether a
    # module is loaded is the registry's to answer; the path is not.
    # A stash's values are globs, whose slots are the stash's: only their truth
    # (the symbol is there) is answered.
    method values_are_only_truths() { return ( $sigil // '' ) eq '%' && ( ( $symbol // '' ) eq 'INC' || defined $self->metaobject_package ) ? 1 : 0 }

    # is_package_scalar -> true for A PACKAGE SCALAR (`our $g`, `$::s`,
    # `$P::v`): one global every sub reads and writes. $@ is one too (the
    # runtime's: die sets it).
    method is_package_scalar() {
        return ( $sigil // '' ) eq '$'
            && ( ( $symbol // '' ) =~ /\A[A-Za-z_]\w*\z/ && !$self->is_perls_own || ( $symbol // '' ) eq '@' );
    }

    # is_package_aggregate -> true for A PACKAGE ARRAY OR HASH read by name
    # (`our @a`, `%P::h`) -- not perl's own (@ISA, @ARGV, %ENV, @INC, %SIG,
    # @_, a stash `%main::`, a punctuation name): each of those has its own
    # meaning.
    method is_package_aggregate() {
        return ( $sigil // '' ) =~ /\A[\@%]\z/
            && ( $symbol // '' ) =~ /\A[A-Za-z_]\w*\z/
            && !$self->is_perls_own;
    }

    # is_argv -> true for @ARGV: the program's arguments.
    method is_argv() {
        return ( $sigil // '' ) eq '@' && ( $symbol // '' ) eq 'ARGV' && ( $package // 'main' ) eq 'main';
    }

    # is_isa_array -> true for a package's @ISA: its parents (whose, package says).
    method is_isa_array() { return ( $sigil // '' ) eq '@' && ( $symbol // '' ) eq 'ISA' }

    # qualified_name -> the variable's name with its package, no sigil
    # ("main::x"): a package of none is main's.
    method qualified_name() { return ( $package // 'main' ) . '::' . $symbol }
}
