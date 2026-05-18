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
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::Stringify;
use Chalk::IR::Node::VarDecl;
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

my %DATA_CLASSES = map { $_ => "Chalk::IR::Node::$_" } qw(
    Constant Phi
    Add Subtract Multiply Divide Modulo Power Concat
    NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
    StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
    And Or BitAnd BitOr BitXor LeftShift RightShift
    Assign Repeat Match NotMatch DefinedOr Xor Range Yada IsaOp
    Not Negate Complement Defined UnaryPlus Ref Length
    PadAccess FieldAccess StashAccess Subscript Slice
    Call HashRef ArrayRef Interpolate AnonSub
    RegexMatch RegexSubst TryCatch
    PostfixDeref CompoundAssign BacktickExpr Stringify VarDecl
    TernaryExpr StructRef StructFieldAccess
    ExpressionList
);

my %CFG_CLASSES = map { $_ => "Chalk::IR::Node::$_" } qw(
    Start Return Unwind If Proj Region Loop
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

    method make($op_name, %args) {
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
}
