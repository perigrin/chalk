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

    # is_package_scalar -> true for A PACKAGE SCALAR (`our $g`, `$::s`,
    # `$P::v`): one global every sub reads and writes. $@ is one too (the
    # runtime's: die sets it).
    method is_package_scalar() {
        return ( $sigil // '' ) eq '$'
            && ( ( $symbol // '' ) =~ /\A[A-Za-z_]\w*\z/ && !$self->is_perls_own || ( $symbol // '' ) eq '@' );
    }
}
