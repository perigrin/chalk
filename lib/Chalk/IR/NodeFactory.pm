# ABOUTME: Factory for Chalk IR nodes with hash consing for data nodes.
# ABOUTME: make() deduplicates data nodes by content hash; make_cfg() creates unique CFG nodes.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;
use Chalk::IR::Node::Modulo;
use Chalk::IR::Node::Power;
use Chalk::IR::Node::Concat;
use Chalk::IR::Node::NumEq;
use Chalk::IR::Node::NumNe;
use Chalk::IR::Node::NumLt;
use Chalk::IR::Node::NumGt;
use Chalk::IR::Node::NumLe;
use Chalk::IR::Node::NumGe;
use Chalk::IR::Node::NumCmp;
use Chalk::IR::Node::StrEq;
use Chalk::IR::Node::StrNe;
use Chalk::IR::Node::StrLt;
use Chalk::IR::Node::StrGt;
use Chalk::IR::Node::StrLe;
use Chalk::IR::Node::StrGe;
use Chalk::IR::Node::StrCmp;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::BitAnd;
use Chalk::IR::Node::BitOr;
use Chalk::IR::Node::BitXor;
use Chalk::IR::Node::LeftShift;
use Chalk::IR::Node::RightShift;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::Repeat;
use Chalk::IR::Node::Match;
use Chalk::IR::Node::NotMatch;
use Chalk::IR::Node::DefinedOr;
use Chalk::IR::Node::Xor;
use Chalk::IR::Node::Range;
use Chalk::IR::Node::Yada;
use Chalk::IR::Node::IsaOp;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::Complement;
use Chalk::IR::Node::Defined;
use Chalk::IR::Node::UnaryPlus;
use Chalk::IR::Node::Ref;
use Chalk::IR::Node::Length;
use Chalk::IR::Node::Slice;
use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::FieldAccess;
use Chalk::IR::Node::StashAccess;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::RegexCapture;
use Chalk::IR::Node::EnvRead;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::Stringify;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::ListAssign;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::StructRef;
use Chalk::IR::Node::StructFieldAccess;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::ExpressionList;
use Chalk::IR::Node::Coerce;

my %DATA_CLASSES = map { $_ => "Chalk::IR::Node::$_" } qw(
    Constant Phi
    Add Subtract Multiply Divide Modulo Power Concat
    NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
    StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
    And Or BitAnd BitOr BitXor LeftShift RightShift
    Assign Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp
    Not Negate Complement Defined UnaryPlus Ref Length
    PadAccess FieldAccess StashAccess Subscript Slice
    Call HashRef ArrayRef
    Interpolate AnonSub
    RegexMatch RegexSubst RegexCapture EnvRead TryCatch
    PostfixDeref CompoundAssign BacktickExpr Stringify VarDecl ListAssign
    TernaryExpr StructRef StructFieldAccess
    ExpressionList
    Start Return Unwind
    Coerce
);

# CFG ops that are NEVER hash-consed via make_cfg (each call allocates fresh).
# Start/Return/Unwind appear in %DATA_CLASSES too — they are hash-consed when
# constructed via make() (legacy Bootstrap API shape) but allocated fresh
# when constructed via make_cfg() (every call gets a unique cfg_counter id).
# Callers picking between the two pick by semantic intent: make() for shared
# entry/exit/sentinel positions, make_cfg() for per-statement control nodes.
my %CFG_CLASSES = map { $_ => "Chalk::IR::Node::$_" } qw(
    Start Return Unwind If Proj Region Loop
);

# Ops that have CFG semantics (per-position identity, never hash-consed
# by content) but are constructed via make() rather than make_cfg().
# Mirrors Bootstrap::IR::NodeFactory's %CFG_OPS. Start/Return/Unwind are
# NOT in this set — they go through the hash-cons path in make() to
# match Bootstrap's permissive-make-of-Start behavior.
my %ROUTED_CFG = map { $_ => 1 } qw(If Proj Region Phi Loop);

# Per-op input-keyword mapping. Mirrors Bootstrap's %INPUT_SPECS:
# Actions.pm passes named params (control => ..., condition => ...,
# value => ...) and make() translates those into inputs => [...] in the
# order listed. Applies to both ROUTED_CFG ops and hash-consed CFG-like
# ops (Return/Unwind), so callers can use either inputs => [...] or
# named-keyword shape — typed factory handles both.
my %INPUT_SPECS = (
    If     => ['control', 'condition'],
    Proj   => ['source'],
    Region => ['controls'],
    Loop   => ['entry_ctrl', 'backedge_ctrl'],
    Return => ['value'],   # though Actions uses inputs => [$ctrl, $val]
    Unwind => ['value'],
    # Phi has its own handler at make() top
);

class Chalk::IR::NodeFactory {
    field %cache;
    field $cfg_counter = 0;

    method _register_consumers($node, %args) {
        my $inputs = $args{inputs} // [];
        for my $input ($inputs->@*) {
            next unless defined $input;
            if ( ref($input) eq 'ARRAY' ) {
                for my $elem ($input->@*) {
                    next unless defined $elem;
                    $elem->add_consumer($node);
                }
            }
            else {
                $input->add_consumer($node);
            }
        }
    }

    # Permissive node construction. Accepts both data ops (hash-consed by
    # content) and CFG-routed ops (If/Proj/Region/Phi/Loop — allocated
    # fresh per call with a counter-suffixed id, mirroring Bootstrap's
    # %CFG_OPS shape). This matches Bootstrap::IR::NodeFactory::make()'s
    # behavior so Actions.pm can route every call through the typed
    # factory without distinguishing between make() and make_cfg() shapes.
    method make($op_name, %args) {
        # Phi has historical CFG-style identity in Bootstrap (never
        # deduplicated) but Chalk::IR::Node::Phi takes `region` as a
        # named :param and the values arrayref as `inputs`. Bootstrap's
        # legacy call shape passes `region => ..., values => ...` — keep
        # that shape working here.
        if ($op_name eq 'Phi') {
            my $class = $DATA_CLASSES{Phi};
            my $region = delete $args{region};
            my $values = delete $args{values};
            $cfg_counter++;
            my $id = "Phi#${cfg_counter}";
            my $node = $class->new(
                id     => $id,
                region => $region,
                inputs => (defined $values ? $values : []),
                %args,
            );
            # Register consumers from the values arrayref AND the region.
            # The region is a use-def input even though it's tracked as a
            # named field rather than via inputs() — Bootstrap's
            # %INPUT_SPECS treats it the same way.
            if (defined $region) {
                $region->add_consumer($node);
            }
            if (defined $values) {
                for my $el ($values->@*) {
                    next unless defined $el;
                    $el->add_consumer($node);
                }
            }
            $cache{$id} = $node;
            return $node;
        }

        # Routed-CFG ops: allocated fresh, never hash-consed. They have
        # CFG semantics (distinct positions in control flow) but used to
        # be constructed via Bootstrap::make() rather than make_cfg.
        # Treat them like make_cfg() for identity, like make() for caller
        # convenience.
        # Translate Bootstrap's named-input keywords into inputs => [...]
        # in declared order. Applies to any op with an INPUT_SPECS entry;
        # callers using inputs => [...] directly pass through unchanged.
        # Mirrors Bootstrap::IR::NodeFactory::make's behavior.
        if (exists $INPUT_SPECS{$op_name} && !exists $args{inputs}) {
            my @inputs;
            for my $name ($INPUT_SPECS{$op_name}->@*) {
                push @inputs, delete $args{$name};
            }
            $args{inputs} = \@inputs;
        }

        if (exists $ROUTED_CFG{$op_name}) {
            my $class = $CFG_CLASSES{$op_name}
                or die "Unknown CFG node operation: $op_name";
            $cfg_counter++;
            my $id = "${op_name}#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # VarDecl is a statement-position side-effect node with per-position
        # (counter) identity, like Return/Unwind: two textually-identical
        # declarations in different control positions are distinct nodes,
        # each carrying its own control_in decoration. Allocate a fresh id
        # per call; never hash-cons by content.
        if ($op_name eq 'VarDecl') {
            my $class = $DATA_CLASSES{VarDecl};
            $cfg_counter++;
            my $id = "VarDecl#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # ListAssign has the same per-position identity semantics as VarDecl:
        # each list declaration occupies a distinct control position.
        if ($op_name eq 'ListAssign') {
            my $class = $DATA_CLASSES{ListAssign};
            $cfg_counter++;
            my $id = "ListAssign#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # Call(dispatch_kind='method') has per-call identity: construction
        # (name='new') is a malloc side effect, and ANY method call is a
        # statement-position side effect whose repetitions are distinct
        # ($obj->advance(); $obj->advance();). This restores pu parity — the
        # pre-convergence MethodCall node had per-call identity; narrowing it
        # to name='new' during R3 was a regression (branch-review I1).
        # Builtin/sub Calls keep content hash-consing (pu behavior; the
        # broader statement-identity design is tracked with the cache/identity
        # family follow-up).
        if ($op_name eq 'Call'
            && ($args{dispatch_kind} // '') eq 'method')
        {
            my $class = $DATA_CLASSES{$op_name}
                or die "Unknown node operation: $op_name";
            $cfg_counter++;
            my $id = "${op_name}#${cfg_counter}";
            my $node = $class->new( id => $id, %args );
            $self->_register_consumers($node, %args);
            $cache{$id} = $node;
            return $node;
        }

        # Assign over a Subscript/FieldAccess lvalue is an element/field STORE — a
        # side effect that occupies a distinct control position. Like the deleted
        # ArrayWrite/HashWrite/FieldWrite nodes (and VarDecl/ListAssign), two
        # textually-identical stores in sequence are distinct side effects: each
        # carries its own control_in, which is excluded from the content hash.
        # Without per-call identity, two `$a[0]=v` (or `$field=v`) statements with
        # identical lvalue+rhs would hash-cons to one node, silently dropping a
        # store. A plain scalar-rebind Assign (lhs = PadAccess/VarDecl) is
        # value-producing, not an aggregate store, and keeps content hash-consing.
        if ($op_name eq 'Assign') {
            my $lhs = ($args{inputs} && ref $args{inputs} eq 'ARRAY') ? $args{inputs}[0] : undef;
            my $lhs_op = (defined $lhs && ref $lhs && $lhs->can('operation'))
                ? $lhs->operation : '';
            if ($lhs_op eq 'Subscript' || $lhs_op eq 'FieldAccess') {
                my $class = $DATA_CLASSES{Assign}
                    or die "Unknown node operation: Assign";
                $cfg_counter++;
                my $id = "Assign#${cfg_counter}";
                my $node = $class->new( id => $id, %args );
                $self->_register_consumers($node, %args);
                $cache{$id} = $node;
                return $node;
            }
        }

        my $class = $DATA_CLASSES{$op_name}
            or die "Unknown data node operation: $op_name";

        # Create a temp node to compute content_hash
        my $tmp = $class->new( id => '_tmp', %args );
        my $hash = $tmp->content_hash();

        # Return cached node if one exists with this hash
        return $cache{$hash} if exists $cache{$hash};

        # On miss: re-create with content hash as id
        my $node = $class->new( id => $hash, %args );
        $self->_register_consumers($node, %args);
        $cache{$hash} = $node;
        return $node;
    }

    method make_cfg($op_name, %args) {
        my $class = $CFG_CLASSES{$op_name}
            or die "Unknown CFG node operation: $op_name";

        $cfg_counter++;
        my $id = "${op_name}#${cfg_counter}";
        my $node = $class->new( id => $id, %args );
        $self->_register_consumers($node, %args);
        return $node;
    }

    # Cache inspection / mutation API used by passes that walk the
    # full set of constructed data nodes (e.g. DCE). Mirrors the
    # Bootstrap factory's interface so passes can operate on either.
    # Cache keys are content_hash strings (same as each node's id()).
    method all_node_ids() {
        return [keys %cache];
    }

    method get_node($id) {
        return $cache{$id};
    }

    method remove_node($id) {
        my $node = delete $cache{$id};
        return defined $node ? 1 : 0;
    }

    method node_count() {
        return scalar keys %cache;
    }
}
