# ABOUTME: Chalk grammar with semantic actions for IR generation
# ABOUTME: Defines grammar rules that build Sea of Nodes IR during parsing

use 5.42.0;
use experimental qw(class);

use Chalk::Grammar;

# Pre-load all Chalk grammar rule classes for static compilation
# (These need to be loaded before grammar construction, not dynamically)
use Chalk::Grammar::Chalk::Rule::ArithmeticOp;
use Chalk::Grammar::Chalk::Rule::Assignment;
use Chalk::Grammar::Chalk::Rule::Block;
use Chalk::Grammar::Chalk::Rule::BreakStatement;
use Chalk::Grammar::Chalk::Rule::BuiltinOp;
use Chalk::Grammar::Chalk::Rule::ComparisonOp;
use Chalk::Grammar::Chalk::Rule::ConcatenationOp;
use Chalk::Grammar::Chalk::Rule::ConditionalKeyword;
use Chalk::Grammar::Chalk::Rule::ConditionalStatement;
use Chalk::Grammar::Chalk::Rule::ContinueStatement;
use Chalk::Grammar::Chalk::Rule::Expression;
use Chalk::Grammar::Chalk::Rule::ExpressionList;
use Chalk::Grammar::Chalk::Rule::FunctionCall;
use Chalk::Grammar::Chalk::Rule::Identifier;
use Chalk::Grammar::Chalk::Rule::LexicalDeclarator;
use Chalk::Grammar::Chalk::Rule::ListOp;
use Chalk::Grammar::Chalk::Rule::Literal;
use Chalk::Grammar::Chalk::Rule::LogicalOp;
use Chalk::Grammar::Chalk::Rule::MethodCall;
use Chalk::Grammar::Chalk::Rule::Number;
use Chalk::Grammar::Chalk::Rule::Postfix;
use Chalk::Grammar::Chalk::Rule::Program;
use Chalk::Grammar::Chalk::Rule::QualifiedIdentifier;
use Chalk::Grammar::Chalk::Rule::RangeOp;
use Chalk::Grammar::Chalk::Rule::ReferenceConstructor;
use Chalk::Grammar::Chalk::Rule::ReturnStatement;
use Chalk::Grammar::Chalk::Rule::ScalarVar;
use Chalk::Grammar::Chalk::Rule::Statement;
use Chalk::Grammar::Chalk::Rule::StatementList;
use Chalk::Grammar::Chalk::Rule::String;
use Chalk::Grammar::Chalk::Rule::Ternary;
use Chalk::Grammar::Chalk::Rule::Unary;
use Chalk::Grammar::Chalk::Rule::UseStatement;
use Chalk::Grammar::Chalk::Rule::Variable;
use Chalk::Grammar::Chalk::Rule::VariableDeclaration;
use Chalk::Grammar::Chalk::Rule::WhileStatement;
use Chalk::Grammar::Chalk::Rule::WS_ELEMENT;
use Chalk::Grammar::Chalk::Rule::WS_OPT;
use Chalk::Grammar::Chalk::Rule::YaddaYadda;

class Chalk::Grammar::Chalk {
    field $grammar :reader;

    ADJUST {
        # This will be populated with chalk.bnf rules + semantic actions
        # For now, just initialize the structure
        $grammar = Chalk::Grammar->new(
            rules => {
                # Semantic action rules will be added here
                ReturnStatement => [
                    # return constant
                    Chalk::Grammar::Chalk::Rule::ReturnStatement->new(
                        lhs => 'ReturnStatement',
                        rhs => ['return', 'WS_OPT', 'Expression']
                    ),
                ],
            }
        );
    }
}

1;
