# ABOUTME: Chalk grammar with semantic actions for IR generation
# ABOUTME: Defines grammar rules that build Sea of Nodes IR during parsing

use 5.42.0;
use experimental qw(class);

use Chalk::Grammar;
use Chalk::Grammar::Chalk::Rule::ReturnStatement;
use Chalk::Grammar::Chalk::Rule::Expression;

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
