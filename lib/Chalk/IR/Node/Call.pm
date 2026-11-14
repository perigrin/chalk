# ABOUTME: Method, subroutine, or builtin call node in the Chalk IR.
# ABOUTME: Carries dispatch kind (method/sub/builtin) and callee name.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;
use Chalk::Grammar::Perl::TypeLibrary;   # a builtin's signature
use Chalk::Grammar::Perl::BuiltinTable;  # its facts the signatures lack

class Chalk::IR::Node::Call :isa(Chalk::IR::Value) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;

    # paren_form: true when the source used the parens-bounded call form
    # (e.g., `push(@arr, $x)`) rather than the bare list-op form
    # (e.g., `push @arr, $x`). Threaded from CallExpression alt 0 (paren
    # form) at parse time; defaults to false for backward compatibility
    # with the many sites that construct Call without setting it.
    # Consumed by the ExpressionList reify in Perl/Actions.pm: a bare
    # list-builtin call (paren_form false) absorbs the remaining list items
    # into its args; a paren-form call does not.
    field $paren_form :param :reader = false;

    # Resolved callee handle (Chalk::MOP::Method or Chalk::MOP::Sub).
    # Per Phase 4, CallExpression resolves the symbolic name via
    # $mop->find_method() and stores the metaobject reference here so
    # codegen can read the callee's graph/params/return-type directly
    # without going through the symbol table at emit time.
    # May be undef for builtins or unresolved calls (still uses $name).
    #
    # Not part of content_hash: the SAME call signature (same dispatch,
    # name, inputs) should hash-cons to a single node regardless of
    # whether its target has been resolved yet. Resolution is a late
    # decoration applied by ClassBlock's post-pass after all methods
    # in scope have been registered on the MOP.
    field $target :param :reader = undef;

    # param_names: for Call(name='new'), the ordered list of :param field names
    # matching inputs[1..N]. Mirrors the New node's param_names field.
    # Empty/undef for non-constructor calls.
    field $param_names :param :reader = [];

    # class_name: the statically-known class for method-dispatch calls
    # (constructors included). Class structure is compile-time context, not
    # dataflow — the backend resolves this name against a registry built
    # from the sealed MOP; no metadata object rides as a node input
    # (docs/plans/2026-06-11-llvm-reads-mop-directly.md). Undef for
    # builtins/subs and for calls whose class is not statically known.
    field $class_name :param :reader = undef;
    # Set by Analysis for a method on what a `class` method returning $self
    # returned (_class_of_self_chains).
    method set_class_name($c) { $class_name = $c; return }

    # The CALLSITE's own context: 'void', 'scalar', 'list', or undef.
    #
    # UNDEF IS A REAL STATE, NOT MISSING DATA. perl leaves entersub's context
    # slot empty for a call in LAST-OPERAND position, because that context
    # arrives at runtime from the caller's frame:
    #
    #   sub f { return (9, g()) }   g's entersub is `KS` -- bare K
    #   my $s = f();                f's entersub is `sKS`
    #   my @l = f();                f's entersub is `lKS`
    #
    # That is the same fact that makes `wantarray` a runtime function. A
    # consumer treating undef as "the producer said nothing" gets the
    # last-operand case backwards, so the two must stay distinguishable.
    #
    # Not part of content_hash: the same call in scalar and list context is
    # the same call, and its context is a per-use decoration -- the same
    # reasoning that keeps control_in out of the hash (Node.pm:42).
    field $want :param :reader = undef;
    # A per-context copy of a sub sets its returned call's context: the call
    # takes its caller's, which the copy is for (Serialize::JSON CONTEXT_COPY).
    method set_want($w) { $want = $w; return $self }

    # `&name` with no parens: the callee runs on the CALLER's @_ rather than
    # a list of its own. In the hash: `&f` and `f()` are different calls.
    field $shares_args :param :reader = 0;

    # Whether the last input is the MEMORY version this call follows rather
    # than an argument (B::SoN `memory_input`). Not identity: the inputs are.
    field $memory_input :param :reader = 0;

    # A FOLDED sort's comparison kind and direction. perl folds the standard
    # comparators into flags on the op (OPpSORT_NUMERIC, OPpSORT_DESCEND), so
    # by the time a producer sees `sort { $a <=> $b }` the block is GONE and
    # what remains is the decision. Without these, three different programs are
    # one node:
    #
    #   sort { $a <=> $b } (3,1,2)   perl 1
    #   sort { $b <=> $a } (3,1,2)   perl 3
    #   sort (3,1,2)                 perl 1   -- STRING compare, not numeric
    #
    # Bare `sort` defaulting to a string compare is the case that breaks
    # ordinary code rather than an edge case: `sort (10, 9, 100)` is
    # `10 100 9`. Lowering sort without these would silently miscompile two of
    # the three.
    #
    # Only a folded `sort` carries them; every other Call leaves them undef.
    field $sort_cmp   :param :reader = undef;   # 'numeric' | 'string'
    field $sort_order :param :reader = undef;   # 'ascending' | 'descending'
    # A comparator perl does not fold: its graph's name, the package of the
    # $a/$b it reads, and (Analysis) the metaobject over that graph.
    field $sort_cmp_body :param :reader = undef;
    field $sort_package  :param :reader = undef;
    field $sort_cmp_sub  :reader = undef;
    method set_sort_cmp_sub($s) { $sort_cmp_sub = $s; return }


    method operation() { 'Call' }

    # memory_operand -> the memory version it follows (its last input), where
    # it has one (memory_input).
    method memory_operand() { return $memory_input ? $self->inputs->[-1] : undef }

    # A MEMORY VERSION where it runs as a statement (pinned): the callee may
    # store anything.
    method is_memory_version() { return $self->is_pinned }
    method staleness_kind() { 'opaque' }

    # FIXED: may do anything, including I/O and aborting
    method is_fixed() { return true }

    method content_hash() {
        return join('|', 'Call',
            "dispatch_kind=$dispatch_kind",
            "name=$name",
            (defined $class_name ? "class_name=$class_name" : ()),
            ($paren_form ? "paren_form=1" : ()),
            ($shares_args ? "shares_args=1" : ()),
            $self->_serialize_inputs());
    }

    # Late-binding setter for the resolved callee. Used by ClassBlock's
    # Phase 4 post-pass once the MOP has every class's methods registered.
    method set_target($mop_method) {
        $target = $mop_method;
        return;
    }


    # A call of a sub no one defines, which runs its package's AUTOLOAD
    # (Analysis): the full name perl puts in $AUTOLOAD first, or undef.
    field $autoloads :reader = undef;
    method set_autoloads($v) { $autoloads = $v; return }

    # A CALL'S SITE (B::SoN's): its statement's file, line and package --
    # what `caller` answers in the callee, and what perl's message names
    # where no class answers a method.
    field $file :reader = undef;
    field $line :reader = undef;
    field $site_package :reader = undef;
    method set_site($f, $l, $p = undef) { ($file, $line, $site_package) = ($f, $l, $p); return }

    # AN XS CALLEE (B::SoN's xs): there is no Perl source to compile it from.
    field $xs :reader = 0;
    method set_xs($v) { $xs = $v ? 1 : 0; return }

    # The block eval whose body this call is in (B::SoN's eval_id), or
    # undef: the callee's own die names no eval.
    field $eval_id :reader = undef;

    method set_eval_id($v) {
        $eval_id = $v;
        return;
    }

    # ---------------------------------------------------------------------
    # PERL'S FACTS ABOUT A BUILTIN, asked of the Call of one: from its
    # signature (Chalk::Grammar::Perl::TypeLibrary) or, for a fact the
    # signatures lack, the table beside them (BuiltinTable) -- so no backend
    # keeps a list of builtins. A call of a sub answers no (undef for
    # result_type): its name is the sub's, not the builtin's.
    # ---------------------------------------------------------------------

    method is_builtin() { return ( $dispatch_kind // '' ) eq 'builtin' ? 1 : 0 }

    # is_sub_call -> true for a call of a sub: named (direct), a method, or
    # through a code value (indirect).
    method is_sub_call() { return ( $dispatch_kind // '' ) =~ /\A(?:direct|method|indirect)\z/ ? 1 : 0 }

    # result_type -> the type the builtin returns, or undef.
    method result_type() {
        return undef unless $self->is_builtin;
        my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin( $name // '' );
        return $sig ? $sig->{return_type} : Chalk::Grammar::Perl::BuiltinTable::fact( $name, 'return_type' );
    }

    # returns_string -> true for a builtin whose value is a string.
    method returns_string() { return ( $self->result_type // '' ) eq 'Str' ? 1 : 0 }

    # mutates_array -> true for a builtin that changes the array it is given
    # first (push, pop, shift, unshift, splice): its signature takes the Array
    # itself there, not a list of it.
    method mutates_array() {
        return 0 unless $self->is_builtin;
        my $sig = Chalk::Grammar::Perl::TypeLibrary::get_builtin( $name // '' ) or return 0;
        return ( ( $sig->{arg_types} // [] )->[0] // '' ) eq 'Array' ? 1 : 0;
    }

    # changes_case -> true for lc, uc, lcfirst, ucfirst.
    method changes_case() { return $self->is_builtin && Chalk::Grammar::Perl::BuiltinTable::fact( $name, 'changes_case' ) ? 1 : 0 }

    # is_tie_builtin -> true for tie, tied, untie: each of a variable's tie.
    method is_tie_builtin() { return $self->is_builtin && Chalk::Grammar::Perl::BuiltinTable::fact( $name, 'tie' ) ? 1 : 0 }

    # takes_a_list -> true for a builtin whose operands (after its first, for
    # push's array, join's separator, a format) are a LIST: what it is given
    # there is in list context.
    method takes_a_list() { return $self->is_builtin && Chalk::Grammar::Perl::BuiltinTable::fact( $name, 'list_args' ) ? 1 : 0 }

    # makes_a_string -> a builtin that returns a string makes one.
    method makes_a_string() { return $self->returns_string }
}
