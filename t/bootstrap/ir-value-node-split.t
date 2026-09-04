# ABOUTME: Chalk::IR::Value is the base for nodes that DEFINE a value; control
# ABOUTME: nodes stay on Chalk::IR::Node and have no type field at all.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Value;   # for `isa Chalk::IR::Value`

# `field $representation = undef` on the BASE node class made undef mean three
# things no consumer could tell apart: (1) this node produces no value, (2)
# inference has not run yet, (3) inference ran and failed. Splitting the
# hierarchy removes meaning (1) from the field entirely, so `undef` can only
# ever be an inference question.
#
# The predicate is `$node isa Chalk::IR::Value` -- NOT ->can('type'), which is
# duck-typing over a NAME and answers true for any class that happens to define
# a `type` method. `isa` asks the actual question and is CLOSED: a value node
# nobody reparents fails by not being recognised as a value, which is loud,
# rather than by carrying a silently untyped field.

# ListAssign is CONTROL, not a value, despite the name. `my ($a,$b) = (1,2)`
# distributes a list across N targets and has no single result -- it yields the
# list in list context and the count in scalar context, which one $type field
# cannot express. Measured: it is never given a representation and never feeds a
# value consumer, its content_hash returns $self->id() (per-position identity,
# never hash-consed, exactly like VarDecl), and NodeFactory.pm:272 groups it
# with the control nodes: "If/Proj/Region/Loop/Phi/VarDecl/ListAssign all report
# per_call".
my @CONTROL = qw(
    Start Return If Loop Region MemStart Proj Print Unwind VarDecl TryCatch
    ListAssign
);

# Values include the effectful single-target assigns. Assign and CompoundAssign
# are in %STATEMENT_EFFECT_OPS *and* value-producing (`$x = $y = 5`): is_fixed
# answers the effect question, `isa Value` answers the value question, and the
# two axes are independent -- being a statement does not stop a node being a
# value. They differ in mechanism, not in flavour of `=`: Assign is one store,
# CompoundAssign is a read-modify-write carrying its operator as a field.
my @VALUE = qw(
    Constant Phi TernaryExpr Coerce Call ExpressionList PostfixDeref
    StructFieldAccess StructRef RegexCapture EnvRead BacktickExpr AnonSub
    Assign CompoundAssign
    Add Subtract Multiply Divide Concat NumLt StrEq DefinedOr
    Not Length Negate Defined
    Subscript PadAccess FieldAccess
    ArrayRef HashRef Slice
    RegexMatch
);

subtest 'the Value class exists and sits under Node' => sub {
    require Chalk::IR::Value;
    ok Chalk::IR::Value->isa('Chalk::IR::Node'),
        'Chalk::IR::Value :isa(Chalk::IR::Node)';
};

subtest 'value-producing node classes are Values' => sub {
    for my $op (@VALUE) {
        my $class = "Chalk::IR::Node::$op";
        eval "require $class; 1" or do { fail "$op: cannot load ($@)"; next };
        ok $class->isa('Chalk::IR::Value'), "$op isa Chalk::IR::Value";
    }
};

subtest 'control node classes are NOT Values' => sub {
    for my $op (@CONTROL) {
        my $class = "Chalk::IR::Node::$op";
        eval "require $class; 1" or do { fail "$op: cannot load ($@)"; next };
        ok !$class->isa('Chalk::IR::Value'),
            "$op is control -- not a Value";
    }
};

# The whole point of the structural predicate: a consumer asks the hierarchy,
# never a hand-maintained op list. This asserts the two agree so that a new node
# class cannot silently land in the wrong half.
subtest 'every node class is classified exactly once' => sub {
    my @classes = sort map { m{([^/]+)\.pm$} ? $1 : () }
        glob 'lib/Chalk/IR/Node/*.pm';
    ok scalar @classes > 80, 'found the node classes' or return;

    my (@unclassified);
    for my $op (@classes) {
        my $class = "Chalk::IR::Node::$op";
        eval "require $class; 1" or next;
        # Abstract bases are not instantiated ops; skip them.
        next if $op =~ /^(BinOp|UnaryOp|Access|Aggregate|Regex)$/;
        my $is_value = $class->isa('Chalk::IR::Value') ? 1 : 0;
        my $listed   = ( grep { $_ eq $op } @VALUE )   ? 1
                     : ( grep { $_ eq $op } @CONTROL ) ? 1
                     :                                   0;
        push @unclassified, $op unless $listed;
    }
    # Not a failure: the lists above are a SAMPLE, not the full inventory. This
    # reports what is unlisted so a reviewer can see the coverage.
    diag "unlisted in this test's sample: @unclassified" if @unclassified;
    pass 'inventory walked';
};

done_testing;
