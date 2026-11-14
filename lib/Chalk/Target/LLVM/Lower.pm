# ABOUTME: The LLVM target's T2 entry: lower_program checks a program is T2's, builds it
# ABOUTME: (Chalk::Target::LLVM::Builder), prints it (Printer); $PATH says which path it took.
use 5.42.0;
use utf8;

package Chalk::Target::LLVM::Lower;

use Scalar::Util qw(blessed refaddr);
use Chalk::Target::LLVM::Builder;
use Chalk::Target::LLVM::Printer;

# lower_program($return_node) -> the module's text, or undef when the program
# is not slice 1's.
# $PATH: which path the last lower_program took -- { path => 't2' }, or
# { path => 'fallback', why => T2's reason } -- read by whoever lowered (the
# pipeline puts it on its unit), so a corpus can count T2's share.
our $PATH;
sub lower_program {
    my ($class, $ret, %opt) = @_;
    my $b = bless { blocks => [], cur => undef, memo => {}, strs => {}, mop => $opt{mop} }, 'Chalk::Target::LLVM::Builder';
    # AN EVAL OR A TRY anywhere in the program (the whole program: a sub's own
    # nodes do not show its caller's try)
    $b->{has_eval} = scalar grep { $_->can('eval_id') && defined $_->eval_id || $_->operation eq 'TryCatch' }
        Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    # A CALL print TAKES THROUGH A COERCE is in list context (print's list);
    # the Coerce lists no consumer, so it is found from the Print.
    # AN ARRAY OR HASH FIELD is a list wherever a list is asked (B::SoN stamps
    # its FieldAccess Scalar: `join "", @s` joined its count, "1" for "p").
    local %Chalk::Target::LLVM::Builder::LIST_FIELD = map { ( refaddr($_) => 1 ) }
        grep { $_->operation eq 'FieldAccess' && ( ( eval { $b->field_of($_) } )[1] // '$' ) =~ /\A[@%]\z/ }
        Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    # (want=list too: a Coerce before print is also a scalar's -- `my $n = f();
    # print $n` is the call, coerced, B::SoN having folded $n -- 45 for 2)
    local %Chalk::Target::LLVM::Builder::PRINTED = map { ( refaddr( $_->inputs->[0] ) => 1 ) }
        grep { $_->operation eq 'Coerce' && blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'Call'
               && ( $_->inputs->[0]->can('want') ? $_->inputs->[0]->want // '' : '' ) eq 'list' }
        map { grep { blessed($_) } $_->inputs->@* }
        grep { $_->operation eq 'Print' } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    # caller ANYWHERE: each call of a sub pushes its site, for caller to read.
    local $Chalk::Target::LLVM::Builder::FRAMES = scalar grep {
        $_->operation eq 'Call' && ( $_->dispatch_kind // '' ) eq 'builtin' && ( $_->name // '' ) eq 'caller'
    } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
    my $ok = eval {
        # A LIST ASSIGN TO AN ARRAY OR HASH (which takes the rest of the list)
        # is not T2's, ON THE CHAIN OR NOT: one B::SoN left floating was never
        # made, and its array read empty (`my ($f, @rest) = ...`: "1 " for "1 2 3").
        Chalk::Target::LLVM::Builder::out('a list assignment to an array or hash') if grep {
            my $a = $_;
            $a->operation eq 'Assign' && $a->can('targets') && defined $a->targets
                # (`my ($c, @x) = @_` is T2's: the arguments, taken by place)
                && !( blessed( $a->inputs->[-1] ) && $a->inputs->[-1]->operation eq 'ArgsSource' )
                && grep { blessed($_) && ( $_->operation eq 'PadAccess' && ( $_->sigil // '' ) =~ /\A[\@%]\z/
                                           || $_->operation =~ /\A(?:ArrayLiteral|HashLiteral|EntryDef)\z/ && ( $_->can('sigil') ? $_->sigil // '' : '' ) ne '$' ) }
                         $a->inputs->@[ 0 .. $a->targets - 1 ]
        } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
        # A SCALAR DEREF where a reference T2 does not make may reach it (to an
        # element, `\(@a)`, `\$_[0]`): refused, not stopped at run time. T2
        # makes one to a `my` scalar kept in memory, an array's, a hash's.
        Chalk::Target::LLVM::Builder::out('a scalar deref where a reference T2 does not make may reach it')
            if ( grep { $_->operation eq 'PostfixDeref' && ( $_->sigil // '' ) eq '$' && !$_->alias_element } Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret) )
            && grep { $_->operation eq 'Ref' && !( ( $_->stamp // '' ) =~ /\A(?:ArrayRef|HashRef)\z/
                          || $_->is_alias_ref
                          || blessed( $_->inputs->[0] ) && $_->inputs->[0]->operation eq 'PadAccess' && ( $_->inputs->[0]->sigil // '' ) eq '$' && $_->inputs->[0]->is_location ) }
                     Chalk::Target::LLVM::Builder::_all_nodes($opt{mop}, $ret);
        $b->build($ret); 1 };
    unless ($ok) { $PATH = { path => 'fallback', why => ( $@ =~ s/\n.*//sr ) }; return undef }
    # A PRINTING FAILURE (a conversion T2 lacks) falls back too: it escaped
    # as a death, a GAP where the fallback had lowered it (pvm 140).
    my $ir = eval { Chalk::Target::LLVM::Printer::print_module($b) };
    $PATH = defined $ir ? { path => 't2' } : { path => 'fallback', why => 'T2 printing: ' . ( $@ =~ s/\n.*//sr ) };
    return $ir;
}

1;
