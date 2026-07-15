# ABOUTME: Metadata struct for a class declaration.
# ABOUTME: Stores name, parent, fields, methods, subs, and all body items in order.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::ClassInfo {
    field $name      :param :reader;
    field $parent    :param :reader = undef;
    field $fields    :param :reader = [];
    field $methods   :param :reader = [];
    field $subs      :param :reader = [];
    field $body      :param :reader = [];

    # parent_ci: optional reference to the parent ClassInfo object.
    # When set, the LLVM registry scanner uses it to populate the parent's
    # registry entry without requiring the parent to appear as a graph input.
    # This is necessary for :isa inheritance where the parent class is declared
    # separately and referenced by name.
    field $parent_ci :param :reader = undef;

    # adjusts: ordered list of adjust-body node lists (parallel to ADJUST blocks).
    # Each entry is an arrayref of IR nodes representing the ADJUST body statements.
    # Used by the LLVM backend to emit ADJUST construction code (field writes etc.)
    # after the :param fields are bound during New lowering.
    field $adjusts :param :reader = [];

    # Content-based ID for use in NodeFactory hash-cons keys.
    # ClassInfo objects may appear as inputs inside hash-consed nodes,
    # so they must be addressable by id.
    # Fields may be FieldInfo objects (have id()) or MOP::Field objects (use name).
    # The R3-added parent_ci and adjusts fields MUST participate: two ClassInfos
    # that differ only in their resolved parent object, or only in their ADJUST
    # body statements, are semantically distinct, and a shared id would let a
    # hash-cons key silently dedup one away (dropping the different adjusts).
    # parent_ci is keyed by the parent's NAME (not its full id()) to avoid deep /
    # potentially cyclic recursion through the parent's own body.
    method id() {
        my $parent_str  = defined $parent ? $parent : 'undef';
        my $fields_str  = join(',', map { $_->can('id') ? $_->id() : ref($_).':'.$_->name } $fields->@*);
        my $methods_str = join(',', map { $_->can('id') ? $_->id() : ref($_).':'.$_->name } $methods->@*);
        my $subs_str    = join(',', map { $_->can('id') ? $_->id() : ref($_).':'.$_->name } $subs->@*);
        my $pci_str     = defined $parent_ci
            ? ($parent_ci->can('name') ? $parent_ci->name : "$parent_ci")
            : 'undef';
        my $adjusts_str = join(';', map {
            join(',', map { $_->can('id') ? $_->id() : "$_" } $_->@*)
        } $adjusts->@*);
        return "ClassInfo:$name:$parent_str:[$fields_str]:[$methods_str]:[$subs_str]"
             . ":pci=$pci_str:adj=[$adjusts_str]";
    }

    # No-op: ClassInfo does not participate in the use-def chain.
    method add_consumer($consumer) {
        return;
    }
}
