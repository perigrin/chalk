# ABOUTME: Chalk grammar for parsing Modern Perl (5.42+) with class syntax
# ABOUTME: Based on Guacamole grammar structure with chalk-specific extensions
package Chalk::Grammar::Perl;
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use Exporter 'import';
use Chalk::Grammar;

our @EXPORT = qw($chalk_grammar);

our $chalk_grammar = Chalk::Grammar->build_grammar(
    auto_insert => ['WS_OPT'],
    rules => [

    # Program structure - adapted from original chalk grammar
    [ 'Program' => ['StatementList'],              1.0 ],
    [ 'Program' => [ 'StatementList', 'WS_OPT' ],  1.0 ],  # With trailing whitespace
    [ 'Program' => [ 'WS_OPT', 'StatementList' ], 1.0 ],  # With leading whitespace
    [ 'Program' => [ 'WS_OPT', 'StatementList', 'WS_OPT' ], 1.0 ],  # With both leading and trailing
    [ 'Program' => [ 'Shebang', 'StatementList' ], 2.0 ],
    [ 'Program' => [ 'Shebang', 'StatementList', 'WS_OPT' ], 2.0 ],  # Shebang with trailing whitespace
    [ 'Program' => [ 'Shebang', 'WS_OPT', 'StatementList' ], 2.0 ],  # Shebang with whitespace before statements
    [ 'Program' => [ 'Shebang', 'WS_OPT', 'StatementList', 'WS_OPT' ], 2.0 ],  # Shebang with both

  # Statement lists - adapted for chalk with reduced ambiguity
  # Prioritize simpler patterns to prevent parsing explosion
  # StatementList following Perl semicolon rules
  # Semicolons required between statements, optional for last statement in block
    [ 'StatementList' => [], 0.1 ],    # Empty statement list (for empty blocks)
    [ 'StatementList' => ['Statement'], 1.0 ]
    ,    # Single statement (last in block, no semicolon needed)
    [ 'StatementList' => ['BlockStatement'], 0.95 ],    # Single block statement
    [ 'StatementList' => [ 'Statement', ';', 'StatementList' ], 0.9 ]
    ,    # Statement + semicolon + more statements
    [ 'StatementList' => [ 'BlockStatement', 'StatementList' ], 0.8 ]
    ,    # Block + more statements
    [ 'StatementList' => [ 'LineStatement', 'StatementList' ], 0.7 ]
    ,    # Line + more

# BlockStatement - statements that contain blocks and don't need semicolons (following guacamole)
    [ 'BlockStatement' => ['ClassDecl'],   1.0 ],
    [ 'BlockStatement' => ['PackageDecl'], 1.0 ],
    [ 'BlockStatement' => ['MethodDecl'], 1.0 ]
    ,    # Full method definitions with blocks
    [ 'BlockStatement' => ['AdjustBlock'], 1.0 ]
    ,    # ADJUST blocks for class initialization
    [ 'BlockStatement' => ['SubroutineDecl'], 1.0 ]
    ,    # Subroutine declarations with blocks
    [ 'BlockStatement' => ['LoopStatement'],      1.0 ],  # Loop statements
    [ 'BlockStatement' => ['ConditionStatement'], 1.0 ],  # If/unless statements
    [ 'BlockStatement' => ['Comment'],            1.0 ],
    [ 'BlockStatement' => ['BeginBlock'],         1.0 ],  # BEGIN blocks
    [ 'BlockStatement' => ['EndBlock'],           1.0 ],   # END blocks
    [ 'BlockStatement' => ['Block'],              1.0 ],   # Bare blocks

  # Conditional statements (if/unless/while/until) - following guacamole pattern
    [ 'ConditionStatement' => ['IfStatement'],     1.0 ],
    [ 'ConditionStatement' => ['UnlessStatement'], 1.0 ],
    [ 'ConditionStatement' => ['ElsifStatement'],  1.0 ],

    # If statement rules with proper elsif chaining
    [ 'IfStatement' => [ 'if', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'IfStatement' => [ 'if', '(', 'Expression', ')', 'Block', 'ElsifChain' ], 1.0 ],
    [ 'IfStatement' => [ 'if', '(', 'Expression', ')', 'Block', 'else', 'Block' ], 1.0 ],
    [ 'IfStatement' => [ 'if', '(', 'Expression', ')', 'Block', 'ElsifChain', 'else', 'Block' ], 1.0 ],
    
    # Elsif chain can be one or more elsif blocks
    [ 'ElsifChain' => [ 'elsif', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'ElsifChain' => [ 'elsif', '(', 'Expression', ')', 'Block', 'ElsifChain' ], 1.0 ],

    # Standalone elsif statement (for backwards compatibility)
    [ 'ElsifStatement' => [ 'elsif', '(', 'Expression', ')', 'Block' ], 1.0 ],

    # Unless statement rules following guacamole ConditionUnlessExpr pattern
    [ 'UnlessStatement' => [ 'unless', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'UnlessStatement' => [ 'unless', '(', 'Expression', ')', 'Block', 'else', 'Block' ], 1.0 ],  # unless-else
    [ 'UnlessStatement' => [ 'unless', 'Expression' ], 1.0 ],    # Postfix form

    # Block structure for conditional statements
    [ 'Block' => [ '{', 'StatementList', '}' ], 1.0 ],
    [ 'Block' => [ '{', '}' ], 1.0 ],

    # ADJUST block for class initialization
    [ 'AdjustBlock' => [ 'ADJUST', 'Block' ], 1.0 ],
    [ 'BeginBlock'  => [ 'BEGIN', 'Block' ],  1.0 ],
    [ 'EndBlock'    => [ 'END', 'Block' ],    1.0 ],

    # Loop statements (following guacamole pattern)
    [ 'LoopStatement' => ['ForStatement'],   1.0 ],
    [ 'LoopStatement' => ['WhileStatement'], 1.0 ],

    # For statement - C-style and foreach style variations
    # C-style for loops: for (init; condition; increment) { ... }
    [ 'ForStatement' => [ 'for', '(', 'Expression', ';', 'Expression', ';', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'ForStatement' => [ 'for', '(', ';', 'Expression', ';', 'Expression', ')', 'Block' ], 1.0 ],  # No init
    [ 'ForStatement' => [ 'for', '(', 'Expression', ';', ';', 'Expression', ')', 'Block' ], 1.0 ],  # No condition
    [ 'ForStatement' => [ 'for', '(', 'Expression', ';', 'Expression', ';', ')', 'Block' ], 1.0 ],  # No increment
    [ 'ForStatement' => [ 'for', '(', ';', ';', ')', 'Block' ], 1.0 ],  # Infinite loop: for (;;)

    # Foreach style variations
    [
        'ForStatement' =>
          [ 'for', 'my', 'VariableBase', '(', 'Expression', ')', 'Block' ],
        1.0
    ],
    [ 'ForStatement' => [ 'foreach', 'my', 'VariableBase', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'ForStatement' => [ 'for', 'VariableBase', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'ForStatement' => [ 'foreach', 'VariableBase', '(', 'Expression', ')', 'Block' ], 1.0 ],

    # While statement - while ( condition ) { ... }
    [ 'WhileStatement' => [ 'while', '(', 'Expression', ')', 'Block' ], 1.0 ],

    # Statements - chalk specific with expression support
    [ 'Statement' => ['BaseStatement'], 1.0 ],

    # Base statements
    [ 'BaseStatement' => ['UseStatement'],     1.0 ],
    [ 'BaseStatement' => ['RequireStatement'], 1.0 ],    # Require statements
    [ 'BaseStatement' => ['EvalBlock'],        1.0 ],    # eval { ... } blocks
    [ 'BaseStatement' => ['FunctionCall'],     1.0 ],    # Function calls like print
    [ 'BaseStatement' => ['PrintExpr'],        1.0 ],
    [ 'BaseStatement' => [ 'PrintExpr', 'StatementModifier' ], 1.0 ],  # print with if/unless/etc
    [ 'BaseStatement' => ['PatternMatchStatement'], 1.0 ],  # Bare regex as statement
    [ 'BaseStatement' => ['DieExpr'],          1.0 ],
    [ 'BaseStatement' => ['WarnExpr'],         1.0 ],
    [ 'BaseStatement' => [ 'DieExpr', 'StatementModifier' ], 1.0 ],
    [ 'BaseStatement' => [ 'WarnExpr', 'StatementModifier' ], 1.0 ],
    [ 'BaseStatement' => ['BuiltinFunctionCall'], 0.1 ],  # Very low - prefer BlockLevelExpression
    [ 'BaseStatement' => [ 'BuiltinFunctionCall', 'StatementModifier' ], 1.0 ]
    ,    # But keep high for statement modifiers
    [ 'BaseStatement' => ['BlockLevelExpression'], 1.0 ],   # Block-level expression
    [ 'BaseStatement' => ['EllipsisStatement'],    1.0 ],   # Ellipsis (...)
    [ 'BaseStatement' => ['FieldDecl'],            1.0 ],   # Field declarations
    [ 'BaseStatement' => ['VariableDecl'],       1.0 ], # my/our/local declarations
    [ 'BaseStatement' => ['ReturnStatement'],    1.0 ], # Return statements
    [ 'BaseStatement' => ['SubroutineDecl'],     1.0 ], # Subroutine declarations
    [ 'BaseStatement' => ['ConditionStatement'], 1.0 ], # If/unless/while statements
    [ 'BaseStatement' => [ 'ReturnStatement', 'StatementModifier' ], 1.0 ]
    ,                                               # Return with modifier
    [ 'BaseStatement' => [ 'BlockLevelExpression', 'StatementModifier' ], 1.0 ]
    ,                                               # Expression with modifier
    [ 'BaseStatement' => [ 'ControlFlowStatement', 'StatementModifier' ], 1.0 ]
    ,                                               # Control flow with modifier

    # Line-terminated statements (don't require semicolons)
    [ 'LineStatement' => ['Shebang'], 1.0 ],
    [ 'LineStatement' => ['Comment'], 1.0 ],

    # Also allow comments directly as base statements (higher accessibility)
    [ 'BaseStatement' => ['Comment'], 1.0 ],

    # Class structure following guacamole PackageStatement pattern
    [
        'ClassDecl' => [ 'class', 'QualifiedIdentifier', 'Inheritance', 'Block' ],
        1.0
    ],
    [ 'ClassDecl' => [ 'class', 'QualifiedIdentifier', 'Block' ], 1.0 ],
    [ 'ClassDecl' => [ 'class', 'Identifier', 'Inheritance', 'Block' ], 0.9 ],
    [ 'ClassDecl' => [ 'class', 'Identifier', 'Block' ], 0.9 ],

    # Package declarations (traditional Perl OO)
    # With block - no semicolon needed (BlockStatement)
    [ 'PackageDecl' => [ 'package', 'QualifiedIdentifier', 'Block' ], 1.0 ],
    [ 'PackageDecl' => [ 'package', 'Identifier', 'Block' ], 0.9 ],

    # Without block - these need semicolons, so they're BaseStatements not BlockStatements
    [ 'BaseStatement' => [ 'package', 'QualifiedIdentifier' ], 1.0 ],
    [ 'BaseStatement' => [ 'package', 'Identifier' ], 0.9 ],

# Method declarations are identical to subroutine declarations (following guacamole)
    [ 'MethodDecl' => [ 'method', 'Identifier', 'SubDefinition' ], 1.0 ],
    [ 'MethodDecl' => [ 'method', 'Identifier' ], 1.0 ],   # Forward declaration

    # Subroutine declarations
    [ 'SubroutineDecl' => [ 'sub', 'Identifier', 'SubDefinition' ], 1.0 ],
    [ 'SubroutineDecl' => [ 'sub', 'Identifier' ], 1.0 ],  # Forward declaration
    [ 'SubroutineDecl' => [ 'my', 'sub', 'Identifier', 'SubDefinition' ], 1.0 ]
    ,                                                      # my sub
    [ 'SubroutineDecl' => [ 'my', 'sub', 'Identifier' ], 1.0 ]
    ,                                                      # my sub forward decl

    # SubDefinition from guacamole grammar
    [ 'SubDefinition' => [ 'SubSigsDefinition', 'Block' ], 1.0 ],
    [ 'SubDefinition' => ['Block'],                        1.0 ],

    # SubSigsDefinition is just a parenthetical expression
    [ 'SubSigsDefinition' => [ '(', 'Expression', ')' ], 1.0 ],
    [ 'SubSigsDefinition' => [ '(', ')' ], 1.0 ],

 # UseStatement - reordered with higher probabilities for more specific patterns
 # to reduce parsing ambiguity and prevent exponential explosion
    [
        'UseStatement' =>
          [ 'OpKeywordUse', 'ClassIdent', 'VersionExpr', 'Expression' ],
        0.9
    ],
    [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent', 'Expression' ],  0.8 ],
    [ 'UseStatement' => [ 'OpKeywordUse', 'VersionExpr' ],               0.7 ],
    [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent', 'VersionExpr' ], 0.6 ],
    [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent' ],                0.5 ],

    [ 'Inheritance' => [ ':isa(', 'ClassIdent', ')' ], 1.0 ],

    # Field declarations - simplified like Guacamole Modifier Variable pattern
    [ 'FieldDecl' => [ 'field', 'Variable', 'FieldAttributeList' ], 1.0 ],
    [ 'FieldDecl' => [ 'field', 'Variable' ], 1.0 ],

    # Variable declarations - my/our/local/state
    [ 'VariableDecl' => [ 'my', 'Variable', '=', 'Expression' ],    1.0 ],
    [ 'VariableDecl' => [ 'my', 'Variable' ],                       1.0 ],
    [ 'VariableDecl' => [ 'our', 'Variable', '=', 'Expression' ],   1.0 ],
    [ 'VariableDecl' => [ 'our', 'Variable' ],                      1.0 ],
    [ 'VariableDecl' => [ 'local', 'Variable', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'local', 'Variable' ],                    1.0 ],

# Local can also be used with any lvalue expression (hash elements, array elements, etc.)
    [ 'VariableDecl' => [ 'local', 'Expression', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'state', 'Variable',   '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'state', 'Variable' ], 1.0 ],

# Basic terminals - include newlines since comments/shebangs are line-oriented
# TODO: Allow inline comments within parameter lists and expressions, not just after complete statements
    [ 'Shebang' => [qr/#!.*$/m] ],
    [ 'Comment' => [qr/#.*$/m] ],    # Whitespace already consumed by WS/WS_OPT

    # Ellipsis statement
    [ 'EllipsisStatement' => ['Ellipsis'] ],
    [ 'Ellipsis'          => ['...'] ],

    # Return statements - following Guacamole OpKeywordReturnExpr pattern
    [ 'ReturnStatement' => [ 'return', 'Expression' ], 1.0 ],
    [ 'ReturnStatement' => ['return'],                 0.1 ],

    # Control flow statements - next, last, redo
    [ 'BaseStatement' => ['ControlFlowStatement'], 1.0 ],
    [ 'ControlFlowStatement' => ['next'], 1.0 ],
    [ 'ControlFlowStatement' => ['last'], 1.0 ],
    [ 'ControlFlowStatement' => ['redo'], 1.0 ],
    [ 'ControlFlowStatement' => [ 'next', 'Identifier' ], 1.0 ],  # next LABEL
    [ 'ControlFlowStatement' => [ 'last', 'Identifier' ], 1.0 ],  # last LABEL
    [ 'ControlFlowStatement' => [ 'redo', 'Identifier' ], 1.0 ],  # redo LABEL

    # Require statements - similar to UseStatement but simpler
    [ 'RequireStatement' => [ 'require', 'Expression' ], 1.0 ],

    # Statement modifiers - following Guacamole postfix patterns
    [ 'StatementModifier' => [ 'unless', 'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'if',     'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'while',  'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'until',  'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'for',     'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'foreach', 'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'when',    'Expression' ], 1.0 ],

    # Guacamole UseStatement components
    [ 'OpKeywordUse' => ['use'] ],
    [ 'ClassIdent'   => ['SubNameExpr'] ],

    # SubNameExpr and VersionExpr definitions (simplified for chalk)
    [ 'SubNameExpr' => ['Identifier'] ],
    [ 'SubNameExpr' => [ 'Identifier', 'PackageSeparator', 'SubNameExpr' ] ],
    [ 'VersionExpr' => [qr/v?(?:\d+\.?){1,3}/] ],

   # QLikeValue - qw() expressions and regex patterns matching Guacamole pattern
    [ 'QLikeValue' => [qr/qw\([^)]*\)/] ],                        # qw(...)
    [ 'QLikeValue' => [qr/qr\{[^}]*\}[a-z]*/] ],                  # qr{...}flags
    [ 'QLikeValue' => [qr/qr\/((?:[^\/]|(?<=\\)\/)*)\/[a-z]*/] ]
    ,                                              # qr/.../flags with escapes
    [ 'QLikeValue' => [qr/\/((?:[^\/\\]|\\.)*)\/[gimsxoac]*/] ],    # /.../flags with escapes
    [ 'QLikeValue' => [qr/m![^!]*![a-z]*/] ],     # m!...!flags
    [ 'QLikeValue' => [qr/m#[^#]*#[a-z]*/] ],     # m#...#flags
    [ 'QLikeValue' => [qr/m\|[^|]*\|[a-z]*/] ],   # m|...|flags
    [ 'QLikeValue' => [qr/`[^`]*`/] ],            # `backticks`

    # Substitution operators s/// with various delimiters (no curly braces - too ambiguous)
    [ 'QLikeValue' => [qr{s/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[msixpodualgcern]*}] ],  # s/.../.../ with escapes
    [ 'QLikeValue' => [qr{s\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[msixpodualgcern]*}] ],  # s|...|...| with escapes
    [ 'QLikeValue' => [qr{s!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![msixpodualgcern]*}] ],  # s!...!...! with escapes
    [ 'QLikeValue' => [qr{s#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[msixpodualgcern]*}] ],  # s#...#...# with escapes

    [ 'FieldAttributeList' => ['FieldAttribute'] ],
    [ 'FieldAttributeList' => [ 'FieldAttribute', 'FieldAttributeList' ] ],
    [ 'FieldAttribute'     => [':param'] ],
    [ 'FieldAttribute'     => [':reader'] ],

# Expression hierarchy - Full Guacamole hierarchy with probabilities emulating action => ::first
    [ 'Expression' => ['ExprNameOr'],                              0.8 ],
    [ 'ExprNameOr' => [ 'ExprNameOr', 'OpNameOr', 'ExprNameAnd' ], 0.8 ]
    ,                                              # First rule - higher prob
    [ 'ExprNameOr' => ['ExprNameAnd'], 0.3 ],      # Fallback - lower prob

# BlockLevelExpression - uses NonBraceExprAssignR to avoid brace ambiguity
# TODO: Allow bare Expressions without an explicit return as the last statement in a block
    [ 'BlockLevelExpression' => ['BlockLevelExprNameOr'], 1.0 ],
    [
        'BlockLevelExprNameOr' =>
          [ 'BlockLevelExprNameOr', 'OpNameOr', 'ExprNameAnd' ],
        0.8
    ],
    [ 'BlockLevelExprNameOr' => ['BlockLevelExprNameAnd'], 0.3 ],
    [
        'BlockLevelExprNameAnd' =>
          [ 'BlockLevelExprNameAnd', 'OpNameAnd', 'ExprNameNot' ],
        0.8
    ],
    [ 'BlockLevelExprNameAnd' => ['BlockLevelExprNameNot'],      0.3 ],
    [ 'BlockLevelExprNameNot' => [ 'OpNameNot', 'ExprNameNot' ], 0.8 ],
    [ 'BlockLevelExprNameNot' => ['NonBraceExprComma'],          0.3 ],

    # NonBraceExprAssignR - avoids consuming braces as hash refs
    [
        'NonBraceExprAssignR' =>
          [ 'NonBraceExprCond0', 'OpAssign', 'ExprAssignR' ],
        0.8
    ],
    [ 'NonBraceExprAssignR' => ['NonBraceExprCondR'], 0.3 ],

 # NonBrace conditional expressions need to go through the full precedence chain
    [
        'NonBraceExprCondR' => [
            'NonBraceExprRange0', 'OpTriThen',
            'ExprRangeR',         'OpTriElse',
            'ExprCondR'
        ],
        0.8
    ],
    [ 'NonBraceExprCondR' => ['NonBraceExprRangeR'], 0.3 ],
    [
        'NonBraceExprCond0' => [
            'NonBraceExprRange0', 'OpTriThen',
            'ExprRange0',         'OpTriElse',
            'ExprCond0'
        ],
        0.8
    ],
    [ 'NonBraceExprCond0' => ['NonBraceExprRange0'], 0.3 ],

    # NonBrace range and other precedence levels
    [
        'NonBraceExprRangeR' =>
          [ 'NonBraceExprLogOr0', 'OpRange', 'ExprLogOrR' ],
        0.8
    ],
    [ 'NonBraceExprRangeR' => ['NonBraceExprLogOrR'], 0.3 ],
    [
        'NonBraceExprRange0' =>
          [ 'NonBraceExprLogOr0', 'OpRange', 'ExprLogOr0' ],
        0.8
    ],
    [ 'NonBraceExprRange0' => ['NonBraceExprLogOr0'], 0.3 ],

# Continue through precedence chain: LogOr -> LogAnd -> BinOr -> BinAnd -> Eq -> Neq -> Shift -> Add -> Mul -> Regex -> Power -> Inc -> Arrow -> Value
    [ 'NonBraceExprLogOrR' => [ 'NonBraceExprLogOr0', 'OpLogOr', 'NonBraceExprLogAndR' ], 0.8 ],
    [ 'NonBraceExprLogOrR' => ['NonBraceExprLogAndR'], 0.3 ],
    [ 'NonBraceExprLogOr0' => [ 'NonBraceExprLogOr0', 'OpLogOr', 'NonBraceExprLogAnd0' ], 0.8 ],
    [ 'NonBraceExprLogOr0' => ['NonBraceExprLogAnd0'], 0.3 ],

    # NonBrace logical AND expressions
    [ 'NonBraceExprLogAndR' => [ 'NonBraceExprLogAnd0', 'OpLogAnd', 'NonBraceExprBinOrR' ], 0.8 ],
    [ 'NonBraceExprLogAndR' => ['NonBraceExprBinOrR'], 0.3 ],
    [ 'NonBraceExprLogAnd0' => [ 'NonBraceExprLogAnd0', 'OpLogAnd', 'NonBraceExprBinOr0' ], 0.8 ],
    [ 'NonBraceExprLogAnd0' => ['NonBraceExprBinOr0'], 0.3 ],

    # NonBrace binary OR expressions
    [ 'NonBraceExprBinOrR' => ['NonBraceExprBinAndR'], 0.3 ],
    [ 'NonBraceExprBinOr0' => ['NonBraceExprBinAnd0'], 0.3 ],

    # NonBrace binary AND expressions
    [ 'NonBraceExprBinAndR' => ['NonBraceExprEqR'], 0.3 ],
    [ 'NonBraceExprBinAnd0' => ['NonBraceExprEq0'], 0.3 ],

    # NonBrace equality expressions (this is what we were missing!)
    [
        'NonBraceExprEqR' =>
          [ 'NonBraceExprNeq0', 'OpEqual', 'NonBraceExprNeqR' ],
        0.8
    ],
    [ 'NonBraceExprEqR' => ['NonBraceExprNeqR'], 0.3 ],
    [
        'NonBraceExprEq0' =>
          [ 'NonBraceExprNeq0', 'OpEqual', 'NonBraceExprNeq0' ],
        0.8
    ],
    [ 'NonBraceExprEq0' => ['NonBraceExprNeq0'], 0.3 ],

    # NonBrace inequality expressions  
    [ 'NonBraceExprNeqR' => [ 'NonBraceExprShift0', 'OpInequal', 'NonBraceExprShiftR' ], 0.8 ],
    [ 'NonBraceExprNeqR' => ['NonBraceExprShiftR'], 0.3 ],
    [ 'NonBraceExprNeq0' => [ 'NonBraceExprShift0', 'OpInequal', 'NonBraceExprShift0' ], 0.8 ],
    [ 'NonBraceExprNeq0' => ['NonBraceExprShift0'], 0.3 ],

    # NonBrace shift expressions
    [ 'NonBraceExprShiftR' => [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAddR' ], 0.8 ],
    [ 'NonBraceExprShiftR' => ['NonBraceExprAddR'], 0.3 ],
    [ 'NonBraceExprShift0' => [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAdd0' ], 0.8 ],
    [ 'NonBraceExprShift0' => ['NonBraceExprAdd0'], 0.3 ],
    [ 'NonBraceExprShiftU' => [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAddU' ], 0.8 ],
    [ 'NonBraceExprShiftU' => ['NonBraceExprAddU'], 0.3 ],

    # NonBrace addition expressions  
    [ 'NonBraceExprAddR' => [ 'NonBraceExprAddU', 'OpAdd', 'NonBraceExprMulR' ], 0.8 ],
    [ 'NonBraceExprAddR' => [ 'NonBraceExprAddU', '.', 'NonBraceExprMulR' ], 0.8 ], 
    [ 'NonBraceExprAddR' => ['NonBraceExprMulR'], 0.3 ],
    [ 'NonBraceExprAdd0' => [ 'NonBraceExprAddU', 'OpAdd', 'NonBraceExprMul0' ], 0.8 ],
    [ 'NonBraceExprAdd0' => [ 'NonBraceExprAddU', '.', 'NonBraceExprMul0' ], 0.8 ],
    [ 'NonBraceExprAdd0' => ['NonBraceExprMul0'], 0.3 ],
    [ 'NonBraceExprAddU' => [ 'NonBraceExprAddU', 'OpAdd', 'NonBraceExprMulU' ], 0.8 ],
    [ 'NonBraceExprAddU' => [ 'NonBraceExprAddU', '.', 'NonBraceExprMulU' ], 0.8 ],
    [ 'NonBraceExprAddU' => ['NonBraceExprMulU'], 0.3 ],

    # NonBrace multiplication expressions
    [ 'NonBraceExprMulR' => [ 'NonBraceExprMulU', 'OpMulti', 'NonBraceExprRegexR' ], 0.8 ],
    [ 'NonBraceExprMulR' => ['NonBraceExprRegexR'], 0.3 ],
    [ 'NonBraceExprMul0' => [ 'NonBraceExprMulU', 'OpMulti', 'NonBraceExprRegex0' ], 0.8 ],
    [ 'NonBraceExprMul0' => ['NonBraceExprRegex0'], 0.3 ],
    [ 'NonBraceExprMulU' => [ 'NonBraceExprMulU', 'OpMulti', 'NonBraceExprRegexU' ], 0.8 ],
    [ 'NonBraceExprMulU' => ['NonBraceExprRegexU'], 0.3 ],

    # NonBrace regex expressions - ADD OpRegex support for print statements
    [ 'NonBraceExprRegexR' => [ 'NonBraceExprRegexU', 'OpRegex', 'NonBraceExprUnaryR' ], 0.8 ],
    [ 'NonBraceExprRegexR' => ['NonBraceExprUnaryR'], 0.3 ],
    [ 'NonBraceExprRegex0' => [ 'NonBraceExprRegexU', 'OpRegex', 'NonBraceExprUnary0' ], 0.8 ],
    [ 'NonBraceExprRegex0' => ['NonBraceExprUnary0'], 0.3 ],
    [ 'NonBraceExprRegexU' => [ 'NonBraceExprRegexU', 'OpRegex', 'NonBraceExprUnaryU' ], 0.8 ],
    [ 'NonBraceExprRegexU' => ['NonBraceExprUnaryU'], 0.3 ],

    # NonBrace unary expressions
    [ 'NonBraceExprUnaryR' => [ 'OpUnary', 'NonBraceExprUnaryR' ], 0.8 ],
    [ 'NonBraceExprUnaryR' => [ 'FileTestOp', 'NonBraceExprUnaryR' ], 0.8 ],
    [ 'NonBraceExprUnaryR' => ['NonBraceExprPowerR'], 0.3 ],
    [ 'NonBraceExprUnary0' => [ 'OpUnary', 'NonBraceExprUnary0' ], 0.8 ],
    [ 'NonBraceExprUnary0' => [ 'FileTestOp', 'NonBraceExprUnary0' ], 0.8 ],
    [ 'NonBraceExprUnary0' => ['NonBraceExprPower0'], 0.3 ],
    [ 'NonBraceExprUnaryU' => [ 'OpUnary', 'NonBraceExprUnaryU' ], 0.8 ],
    [ 'NonBraceExprUnaryU' => [ 'FileTestOp', 'NonBraceExprUnaryU' ], 0.8 ],
    [ 'NonBraceExprUnaryU' => ['NonBraceExprPowerU'], 0.3 ],

    # NonBrace power expressions
    [ 'NonBraceExprPowerR' => [ 'NonBraceExprIncU', 'OpPower', 'NonBraceExprUnaryR' ], 0.8 ],
    [ 'NonBraceExprPowerR' => ['NonBraceExprIncR'], 0.3 ],
    [ 'NonBraceExprPower0' => [ 'NonBraceExprIncU', 'OpPower', 'NonBraceExprUnary0' ], 0.8 ],
    [ 'NonBraceExprPower0' => ['NonBraceExprInc0'], 0.3 ],
    [ 'NonBraceExprPowerU' => [ 'NonBraceExprIncU', 'OpPower', 'NonBraceExprUnaryU' ], 0.8 ],
    [ 'NonBraceExprPowerU' => ['NonBraceExprIncU'], 0.3 ],

    # NonBrace increment expressions
    [ 'NonBraceExprIncR' => [ 'OpInc', 'NonBraceExprIncR' ], 0.8 ],
    [ 'NonBraceExprIncR' => [ 'NonBraceExprIncR', 'OpInc' ], 0.8 ],
    [ 'NonBraceExprIncR' => ['NonBraceExprArrowR'], 0.3 ],
    [ 'NonBraceExprInc0' => [ 'OpInc', 'NonBraceExprInc0' ], 0.8 ],
    [ 'NonBraceExprInc0' => [ 'NonBraceExprInc0', 'OpInc' ], 0.8 ],
    [ 'NonBraceExprInc0' => ['NonBraceExprArrow0'], 0.3 ],
    [ 'NonBraceExprIncU' => [ 'OpInc', 'NonBraceExprIncU' ], 0.8 ],
    [ 'NonBraceExprIncU' => [ 'NonBraceExprIncU', 'OpInc' ], 0.8 ],
    [ 'NonBraceExprIncU' => ['NonBraceExprArrowU'], 0.3 ],

    # NonBrace arrow expressions - use ArrowChain like regular ExprArrow* rules
    [ 'NonBraceExprArrowR' => [ 'NonBraceExprValueR', 'ArrowChain' ], 0.8 ],
    [ 'NonBraceExprArrowR' => ['NonBraceExprValueR'], 0.3 ],
    [ 'NonBraceExprArrow0' => [ 'NonBraceExprValue0', 'ArrowChain' ], 0.8 ],
    [ 'NonBraceExprArrow0' => ['NonBraceExprValue0'], 0.3 ],
    [ 'NonBraceExprArrowU' => [ 'NonBraceExprValueU', 'ArrowChain' ], 0.8 ],
    [ 'NonBraceExprArrowU' => ['NonBraceExprValueU'], 0.3 ],

    # NonBraceExprValue* rules
    [ 'NonBraceExprValueU' => ['NonBraceValue'],       1.0 ],
    [ 'NonBraceExprValueR' => ['NonBraceValue'],       0.8 ],
    [ 'NonBraceExprValueR' => ['BuiltinFunctionCall'], 0.6 ],  # Built-in functions for or/and contexts
    [ 'NonBraceExprValueR' => ['OpListKeywordExpr'],   0.5 ],
    [ 'NonBraceExprValueR' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'NonBraceExprValueR' => ['OpUnaryKeywordExpr'],  0.5 ],
    [ 'NonBraceExprValue0' => ['NonBraceValue'],       0.8 ],
    [ 'NonBraceExprValue0' => ['OpUnaryKeywordExpr'],  0.5 ],
    [ 'NonBraceValue'      => ['Variable'],            0.4 ],
    [ 'NonBraceValue'      => ['QualifiedIdentifier'], 0.4 ],  # Foo::Bar for method calls
    [ 'NonBraceValue'      => ['Identifier'],          0.3 ],  # Plain identifiers (lower priority)
    [ 'NonBraceValue'      => ['Number'],              0.3 ],
    [ 'NonBraceValue'      => ['UnaryExpression'],     0.3 ],
    [ 'NonBraceValue'      => ['QuotedString'],        0.3 ],

    # Unary expressions (for things like -1e10, !$flag, -d 't', etc.)
    [ 'UnaryExpression' => [ 'OpUnary', 'NonBraceValue' ], 1.0 ],
    [ 'UnaryExpression' => [ 'FileTestOp', 'NonBraceValue' ], 1.0 ],
    [ 'NonBraceValue'   => [ '(', 'Expression', ')' ],     0.3 ],
    [ 'NonBraceValue'   => ['ArrayRef'],                   0.3 ],
    [ 'NonBraceValue'   => ['HashRef'],                    0.3 ],  # Allow hash refs in push/etc
    [ 'NonBraceValue'   => ['FunctionCall'],               0.3 ],
    [ 'NonBraceValue'   => ['QLikeValue'],                 0.8 ],
    [ 'NonBraceValue'   => ['@'],                          0.3 ],
    [ 'NonBraceValue'   => ['FieldDecl'],                  0.3 ],

    [ 'ExprNameAnd' => [ 'ExprNameAnd', 'OpNameAnd', 'ExprNameNot' ], 0.8 ],
    [ 'ExprNameAnd' => ['ExprNameNot'],                               0.3 ],
    [ 'ExprNameNot' => [ 'OpNameNot', 'ExprNameNot' ],                0.8 ],
    [ 'ExprNameNot' => ['ExprComma'],                                 0.3 ],
    [ 'ExprComma'   => [ 'ExprAssignL', 'OpComma', 'ExprComma' ],     0.8 ]
    ,    # Comma list - higher prob
    [ 'ExprComma' => [ 'ExprAssignL', 'OpComma' ], 0.7 ], # Trailing comma
    [ 'ExprComma' => ['ExprAssignR'],              0.3 ], # Single item fallback
    [ 'ExprAssignR' => [ 'ExprCond0', 'OpAssign', 'ExprAssignR' ], 0.8 ],
    [ 'ExprAssignR' => ['ExprCondR'],                              0.3 ],
    [ 'ExprAssignL' => [ 'ExprCond0', 'OpAssign', 'ExprAssignL' ], 0.8 ],
    [ 'ExprAssignL' => ['OpAssignKeywordExpr'],                    0.5 ],
    [ 'ExprAssignL' => ['ExprCondL'],                              0.3 ],
    [
        'ExprCondR' => [ 'ExprRange0', '?', 'ExprRangeR', ':', 'ExprCondR' ],
        0.8
    ],
    [ 'ExprCondR' => ['ExprRangeR'], 0.3 ],
    [
        'ExprCondL' => [ 'ExprRange0', '?', 'ExprRangeL', ':', 'ExprCondL' ],
        0.8
    ],
    [ 'ExprCondL' => ['ExprRangeL'], 0.3 ],
    [
        'ExprCond0' => [ 'ExprRange0', '?', 'ExprRange0', ':', 'ExprCond0' ],
        0.8
    ],
    [ 'ExprCond0'  => ['ExprRange0'],                             0.3 ],
    [ 'ExprRangeR' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrR' ],  0.8 ],
    [ 'ExprRangeR' => ['ExprLogOrR'],                             0.3 ],
    [ 'ExprRangeL' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrL' ],  0.8 ],
    [ 'ExprRangeL' => ['ExprLogOrL'],                             0.3 ],
    [ 'ExprRange0' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOr0' ],  0.8 ],
    [ 'ExprRange0' => ['ExprLogOr0'],                             0.3 ],
    [ 'ExprLogOrR' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndR' ], 0.8 ],
    [ 'ExprLogOrR' => ['ExprLogAndR'],                            0.3 ],
    [ 'ExprLogOrL' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndL' ], 0.8 ],
    [ 'ExprLogOrL' => ['ExprLogAndL'],                            0.3 ],
    [ 'ExprLogOr0' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAnd0' ], 0.8 ],
    [ 'ExprLogOr0' => ['ExprLogAnd0'],                            0.3 ],

    # Continue the chain down to Value
    [ 'ExprLogAndR' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOrR' ], 0.8 ],
    [ 'ExprLogAndR' => [ 'ExprBinOrR', 'Comment' ],                0.7 ], # Expression with trailing comment
    [ 'ExprLogAndR' => ['ExprBinOrR'],                              0.3 ],
    [ 'ExprLogAndL' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOrL' ], 0.8 ],
    [ 'ExprLogAndL' => ['ExprBinOrL'],                              0.3 ],
    [ 'ExprLogAnd0' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOr0' ], 0.8 ],
    [ 'ExprLogAnd0' => ['ExprBinOr0'],                              0.3 ],

    [ 'ExprBinOrR' => [ 'ExprBinOr0', 'OpBinOr', 'ExprBinAndR' ], 0.8 ],
    [ 'ExprBinOrR' => ['ExprBinAndR'],                            0.3 ],
    [ 'ExprBinOrL' => [ 'ExprBinOr0', 'OpBinOr', 'ExprBinAndL' ], 0.8 ],
    [ 'ExprBinOrL' => ['ExprBinAndL'],                            0.3 ],
    [ 'ExprBinOr0' => [ 'ExprBinOr0', 'OpBinOr', 'ExprBinAnd0' ], 0.8 ],
    [ 'ExprBinOr0' => ['ExprBinAnd0'],                            0.3 ],

    [ 'ExprBinAndR' => [ 'ExprBinAnd0', '&', 'ExprEqR' ], 0.8 ],
    [ 'ExprBinAndR' => ['ExprEqR'],                       0.3 ],
    [ 'ExprBinAndL' => [ 'ExprBinAnd0', '&', 'ExprEqL' ], 0.8 ],
    [ 'ExprBinAndL' => ['ExprEqL'],                       0.3 ],
    [ 'ExprBinAnd0' => [ 'ExprBinAnd0', '&', 'ExprEq0' ], 0.8 ],
    [ 'ExprBinAnd0' => ['ExprEq0'],                       0.3 ],

    # Complete the missing expression hierarchy levels
    [ 'ExprEqR' => [ 'ExprNeq0', 'OpEqual', 'ExprNeqR' ], 0.8 ],
    [ 'ExprEqR' => ['ExprNeqR'],                          0.3 ],
    [ 'ExprEqL' => [ 'ExprNeq0', 'OpEqual', 'ExprNeqL' ], 0.8 ],
    [ 'ExprEqL' => ['ExprNeqL'],                          0.3 ],
    [ 'ExprEq0' => [ 'ExprNeq0', 'OpEqual', 'ExprNeq0' ], 0.8 ],
    [ 'ExprEq0' => ['ExprNeq0'],                          0.3 ],

    [ 'ExprNeqR' => [ 'ExprShift0', 'OpInequal', 'ExprShiftR' ], 0.8 ],
    [ 'ExprNeqR' => ['ExprShiftR'],                              0.3 ],
    [ 'ExprNeqL' => [ 'ExprShift0', 'OpInequal', 'ExprShiftL' ], 0.8 ],
    [ 'ExprNeqL' => ['ExprShiftL'],                              0.3 ],
    [ 'ExprNeq0' => [ 'ExprShift0', 'OpInequal', 'ExprShift0' ], 0.8 ],
    [ 'ExprNeq0' => ['ExprShift0'],                              0.3 ],

    [ 'ExprShiftR' => [ 'ExprShiftU', 'OpShift', 'ExprAddR' ], 0.8 ],
    [ 'ExprShiftR' => ['ExprAddR'],                            0.3 ],
    [ 'ExprShiftL' => [ 'ExprShiftU', 'OpShift', 'ExprAddL' ], 0.8 ],
    [ 'ExprShiftL' => ['ExprAddL'],                            0.3 ],
    [ 'ExprShift0' => [ 'ExprShiftU', 'OpShift', 'ExprAdd0' ], 0.8 ],
    [ 'ExprShift0' => ['ExprAdd0'],                            0.3 ],
    [ 'ExprShiftU' => [ 'ExprShiftU', 'OpShift', 'ExprAddU' ], 0.8 ],
    [ 'ExprShiftU' => ['ExprAddU'],                            0.3 ],

    [ 'ExprAddR' => [ 'ExprAddU', 'OpAdd', 'ExprMulR' ], 0.8 ],
    [ 'ExprAddR' => [ 'ExprAddU', '.', 'ExprMulR' ],     0.8 ],
    [ 'ExprAddR' => ['ExprMulR'],                        0.3 ],
    [ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ], 0.8 ],
    [ 'ExprAddL' => [ 'ExprAddU', '.', 'ExprMulL' ],     0.8 ],
    [ 'ExprAddL' => ['ExprMulL'],                        0.3 ],
    [ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ], 0.8 ],
    [ 'ExprAdd0' => [ 'ExprAddU', '.', 'ExprMul0' ],     0.8 ],
    [ 'ExprAdd0' => ['ExprMul0'],                        0.3 ],
    [ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ], 0.8 ],
    [ 'ExprAddU' => [ 'ExprAddU', '.', 'ExprMulU' ],     0.8 ],
    [ 'ExprAddU' => ['ExprMulU'],                        0.3 ],

    [ 'ExprMulR' => [ 'ExprMulU', 'OpMulti', 'ExprRegexR' ], 0.8 ],
    [ 'ExprMulR' => ['ExprRegexR'],                          0.3 ],
    [ 'ExprMulL' => [ 'ExprMulU', 'OpMulti', 'ExprRegexL' ], 0.8 ],
    [ 'ExprMulL' => ['ExprRegexL'],                          0.3 ],
    [ 'ExprMul0' => [ 'ExprMulU', 'OpMulti', 'ExprRegex0' ], 0.8 ],
    [ 'ExprMul0' => ['ExprRegex0'],                          0.3 ],
    [ 'ExprMulU' => [ 'ExprMulU', 'OpMulti', 'ExprRegexU' ], 0.8 ],
    [ 'ExprMulU' => ['ExprRegexU'],                          0.3 ],

    [ 'ExprRegexR' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryR' ], 0.8 ],
    [ 'ExprRegexR' => ['ExprUnaryR'],                            0.3 ],
    [ 'ExprRegexL' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprRegexL' => ['ExprUnaryL'],                            0.3 ],
    [ 'ExprRegex0' => [ 'ExprRegexU', 'OpRegex', 'ExprUnary0' ], 0.8 ],
    [ 'ExprRegex0' => ['ExprUnary0'],                            0.3 ],
    [ 'ExprRegexU' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryU' ], 0.8 ],
    [ 'ExprRegexU' => ['ExprUnaryU'],                            0.3 ],

    [ 'ExprUnaryR' => [ 'OpUnary', 'ExprUnaryR' ], 0.8 ],
    [ 'ExprUnaryR' => [ 'FileTestOp', 'ExprUnaryR' ], 0.8 ],
    [ 'ExprUnaryR' => ['ExprPowerR'],              0.3 ],
    [ 'ExprUnaryL' => [ 'OpUnary', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprUnaryL' => [ 'FileTestOp', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprUnaryL' => ['ExprPowerL'],              0.3 ],
    [ 'ExprUnary0' => [ 'OpUnary', 'ExprUnary0' ], 0.8 ],
    [ 'ExprUnary0' => [ 'FileTestOp', 'ExprUnary0' ], 0.8 ],
    [ 'ExprUnary0' => ['ExprPower0'],              0.3 ],
    [ 'ExprUnaryU' => [ 'OpUnary', 'ExprUnaryU' ], 0.8 ],
    [ 'ExprUnaryU' => [ 'FileTestOp', 'ExprUnaryU' ], 0.8 ],
    [ 'ExprUnaryU' => ['ExprPowerU'],              0.3 ],

    [ 'ExprPowerR' => [ 'ExprIncU', 'OpPower', 'ExprUnaryR' ], 0.8 ],
    [ 'ExprPowerR' => ['ExprIncR'],                            0.3 ],
    [ 'ExprPowerL' => [ 'ExprIncU', 'OpPower', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprPowerL' => ['ExprIncL'],                            0.3 ],
    [ 'ExprPower0' => [ 'ExprIncU', 'OpPower', 'ExprUnary0' ], 0.8 ],
    [ 'ExprPower0' => ['ExprInc0'],                            0.3 ],
    [ 'ExprPowerU' => [ 'ExprIncU', 'OpPower', 'ExprUnaryU' ], 0.8 ],
    [ 'ExprPowerU' => ['ExprIncU'],                            0.3 ],

    [ 'ExprIncR' => [ 'OpInc', 'ExprArrowR' ], 0.8 ],
    [ 'ExprIncR' => [ 'ExprArrowL', 'OpInc' ], 0.7 ],
    [ 'ExprIncR' => ['ExprArrowR'],            0.3 ],
    [ 'ExprIncL' => [ 'OpInc', 'ExprArrowL' ], 0.8 ],
    [ 'ExprIncL' => [ 'ExprArrowR', 'OpInc' ], 0.7 ],
    [ 'ExprIncL' => ['ExprArrowL'],            0.3 ],
    [ 'ExprInc0' => [ 'OpInc', 'ExprArrow0' ], 0.8 ],
    [ 'ExprInc0' => [ 'ExprArrowR', 'OpInc' ], 0.7 ],
    [ 'ExprInc0' => ['ExprArrow0'],            0.3 ],
    [ 'ExprIncU' => [ 'OpInc', 'ExprArrowU' ], 0.8 ],
    [ 'ExprIncU' => [ 'ExprArrowR', 'OpInc' ], 0.7 ],
    [ 'ExprIncU' => ['ExprArrowU'],            0.3 ],

    # Arrow expressions - eliminate left recursion to prevent parsing explosion
    [ 'ExprArrowR' => [ 'ExprValueR', 'ArrowChain' ], 0.8 ],
    [ 'ExprArrowR' => ['ExprValueR'],                 0.3 ],
    [ 'ExprArrowL' => [ 'ExprValueL', 'ArrowChain' ], 0.8 ],
    [ 'ExprArrowL' => ['ExprValueL'],                 0.3 ],
    [ 'ExprArrow0' => [ 'ExprValue0', 'ArrowChain' ], 0.8 ],
    [ 'ExprArrow0' => ['ExprValue0'],                 0.3 ],
    [ 'ExprArrowU' => [ 'ExprValueU', 'ArrowChain' ], 0.8 ],
    [ 'ExprArrowU' => ['ExprValueU'],                 0.3 ],

    # ArrowChain - right-recursive chain of arrow operations
    [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS', 'ArrowChain' ], 1.0 ],
    [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS' ], 0.8 ],  # Prefer continuing chain over terminating

    # Value rules - matching Guacamole ExprValue* rules exactly
    [ 'ExprValueU' => ['Value'],               1.0 ],
    [ 'ExprValue0' => ['Value'],               0.8 ],
    [ 'ExprValue0' => ['OpUnaryKeywordExpr'],  0.5 ],
    [ 'ExprValueL' => ['Value'],               0.8 ],
    [ 'ExprValueL' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'ExprValueL' => ['OpUnaryKeywordExpr'],  0.5 ],
    [ 'ExprValueR' => ['Value'],               0.8 ],
    [ 'ExprValueR' => ['OpListKeywordExpr'],   0.5 ],
    [ 'ExprValueR' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'ExprValueR' => ['OpUnaryKeywordExpr'],  0.5 ],

    # ArrowRHS - method calls, array/hash indexing, postfix dereferencing
    [ 'ArrowRHS' => ['Identifier'],                              0.5 ],
    [ 'ArrowRHS' => [ 'Identifier', '(', 'ParameterList', ')' ], 1.0 ],  # Match FunctionCall priority
    [ 'ArrowRHS' => [ 'Identifier', '(', ')' ],                  1.0 ],  # Match FunctionCall priority
    [ 'ArrowRHS' => [ '[', 'Expression', ']' ],                  0.3 ],
    [ 'ArrowRHS' => [ '{', 'Expression', '}' ],                  0.3 ],
    [ 'ArrowRHS' => ['PostfixDeref'], 0.3 ], # ->@*, ->%*, ->$* (postfix derefs)

    # Postfix dereferencing operators - atomic tokens
    [ 'PostfixDeref' => [qr/[@%\$]\*/] ],

    # Value rules - basic terminals needed for chalk
    [ 'Value' => ['Variable'],           0.4 ], # Now includes $hash{key}, @array[index]
    [ 'Value' => ['QualifiedIdentifier'], 0.4 ],  # Foo::Bar for method calls
    [ 'Value' => ['Identifier'],          0.3 ],  # Plain identifiers (lower priority)
    [ 'Value' => ['Number'],     0.3 ],
    [ 'Value' => ['QuotedString'],           0.3 ],
    [ 'Value' => [ '(', 'Expression', ')' ], 0.3 ],
    [ 'Value' => [ '(', ')' ],     0.3 ],    # Empty parentheses (empty list)
    [ 'Value' => ['ArrayRef'],     0.3 ],
    [ 'Value' => ['HashRef'],      0.3 ],
    [ 'Value' => ['FunctionCall'], 0.3 ],
    [ 'Value' => ['UnaryKeywordExpression'], 0.3 ],    # grep/map/sort etc.
    [ 'Value' => ['ExpressionBlock'],        0.3 ],    # { expr } blocks
    [ 'Value' => ['EvalBlock'],              0.3 ],    # eval { ... } blocks
    [ 'Value' => ['QLikeValue'],             0.8 ],
    [ 'Value' => ['DiamondExpr'],            0.3 ],    # <$fh> constructs
    [ 'Value' => ['@'],                      0.3 ],
    [ 'Value' => ['FieldDecl'],              0.3 ],
    [ 'Value' => ['VariableDecl'], 0.3 ], # my $var = expr as expression
    [ 'Value' => ['PrintExpr'],    0.3 ], # print statements without parentheses
    [ 'Value' => ['DieExpr'],      0.3 ], # die statements without parentheses
    [ 'Value' => ['WarnExpr'],     0.3 ], # warn statements without parentheses
    [ 'Value' => ['BuiltinFunctionCall'], 0.3 ], # Built-in function calls

    # Print expressions following guacamole OpKeywordPrintExpr pattern
    [ 'PrintExpr' => [ 'print', 'NonBraceExprComma' ], 1.0 ],   # print "string"
    [ 'PrintExpr' => ['print'],                        1.0 ],   # bare print
    
    # Print with filehandle: print FILEHANDLE "string"
    [ 'PrintExpr' => [ 'print', 'Identifier', 'NonBraceExprComma' ], 1.0 ],         # print FH "string"
    [ 'PrintExpr' => [ 'print', 'Identifier' ], 1.0 ],                              # print FH
    [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle', 'NonBraceExprComma' ], 1.0 ],  # print STDOUT "string"
    [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle' ], 1.0 ],                       # print STDOUT

    # Pattern match statements - bare regex as statement (implicit $_ =~ /.../ binding)
    [ 'PatternMatchStatement' => ['QLikeValue'], 1.0 ],

    # Die expressions following same pattern as PrintExpr
    [ 'DieExpr' => [ 'die', 'NonBraceExprComma' ], 1.0 ],    # die "string"
    [ 'DieExpr' => ['die'],                        1.0 ],    # bare die

    # Warn expressions following same pattern as DieExpr
    [ 'WarnExpr' => [ 'warn', 'NonBraceExprComma' ], 1.0 ],  # warn "string"
    [ 'WarnExpr' => ['warn'],                        1.0 ],  # bare warn

    # Built-in function calls (chdir, mkdir, etc.)
    [ 'BuiltinFunctionCall' => [ 'BuiltinFunction', 'NonBraceExprComma' ], 1.0 ],
    [ 'BuiltinFunctionCall' => [ 'BuiltinFunction' ], 1.0 ],
    [ 'BuiltinFunctionCall' => ['OpenExpr'], 1.0 ],  # Special handling for open
    [ 'BuiltinFunction' => [qr/chdir|mkdir|rmdir|unlink|chmod|chown|utime|rename|link|symlink|readlink|stat|lstat|sleep|exit|system|exec|fork|wait|waitpid|kill|alarm|umask|exists|defined|delete|ref|bless|tied|untie|tie|scalar|wantarray|caller|reset|undef|length|chr|ord|uc|lc|ucfirst|lcfirst|quotemeta|abs|int|sqrt|exp|log|sin|cos|atan2|rand|srand|time|localtime|gmtime|close|eof|tell|seek|truncate|fileno|flock|binmode|read|write|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|require/] ],

    # Open expressions with inline variable declarations
    # Two-argument open: open my $fh, "file" or open our $fh, "file"
    [ 'OpenExpr' => [ 'open', 'my', 'VariableBase', 'OpComma', 'NonBraceExprComma' ], 1.0 ],
    [ 'OpenExpr' => [ 'open', 'our', 'VariableBase', 'OpComma', 'NonBraceExprComma' ], 1.0 ],

    # Three-argument open with inline declarations: open my $fh, "<", $file
    [ 'OpenExpr' => [ 'open', 'my', 'VariableBase', 'OpComma', 'NonBraceExprComma', 'OpComma', 'NonBraceExprComma' ], 1.0 ],
    [ 'OpenExpr' => [ 'open', 'our', 'VariableBase', 'OpComma', 'NonBraceExprComma', 'OpComma', 'NonBraceExprComma' ], 1.0 ],

    # Standard open patterns (already working, kept for completeness)
    [ 'OpenExpr' => [ 'open', 'NonBraceExprComma' ], 1.0 ],

# NonBraceExprComma for print arguments (following guacamole OpListKeywordArgNonBrace)
    [
        'NonBraceExprComma' =>
          [ 'NonBraceExprAssignL', 'OpComma', 'NonBraceExprComma' ],
        0.8
    ],
    [ 'NonBraceExprComma' => [ 'NonBraceExprAssignL', 'OpComma' ], 0.7 ]
    ,                                                           # Trailing comma
    [ 'NonBraceExprComma' => ['NonBraceExprAssignR'], 0.3 ],    # Single item

    # NonBraceExprAssignL for left-associative assignments in print context
    [
        'NonBraceExprAssignL' =>
          [ 'NonBraceExprCond0', 'OpAssign', 'NonBraceExprAssignL' ],
        0.8
    ],
    [ 'NonBraceExprAssignL' => ['NonBraceExprCondL'], 0.3 ],

    # NonBraceExprCondL for conditional expressions in print context
    [
        'NonBraceExprCondL' => [
            'NonBraceExprRange0', 'OpTriThen',
            'NonBraceExprRangeL', 'OpTriElse',
            'NonBraceExprCondL'
        ],
        0.8
    ],
    [ 'NonBraceExprCondL' => ['NonBraceExprRangeL'], 0.3 ],

    # NonBraceExprRangeL for range expressions in print context
    [
        'NonBraceExprRangeL' =>
          [ 'NonBraceExprLogOr0', 'OpRange', 'NonBraceExprLogOrL' ],
        0.8
    ],
    [ 'NonBraceExprRangeL' => ['NonBraceExprLogOrL'], 0.3 ],

    # Continue chain for NonBrace left-associative expressions  
    [ 'NonBraceExprLogOrL'  => ['NonBraceExprLogAndL'], 0.3 ],
    [ 'NonBraceExprLogAndL' => ['NonBraceExprBinOrL'],  0.3 ],
    [ 'NonBraceExprBinOrL'  => ['NonBraceExprBinAndL'], 0.3 ],
    [ 'NonBraceExprBinAndL' => ['NonBraceExprEqL'],     0.3 ],
    [ 'NonBraceExprEqL'     => ['NonBraceExprNeqL'],    0.3 ],
    [ 'NonBraceExprNeqL' => [ 'NonBraceExprShift0', 'OpInequal', 'NonBraceExprShiftL' ], 0.8 ],
    [ 'NonBraceExprNeqL'    => ['NonBraceExprShiftL'],  0.3 ],
    
    # NonBrace shift expressions (left-associative)
    [ 'NonBraceExprShiftL' => [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAddL' ], 0.8 ],
    [ 'NonBraceExprShiftL' => ['NonBraceExprAddL'], 0.3 ],
    
    # NonBrace addition expressions (left-associative)
    [ 'NonBraceExprAddL' => [ 'NonBraceExprAddU', 'OpAdd', 'NonBraceExprMulL' ], 0.8 ],
    [ 'NonBraceExprAddL' => [ 'NonBraceExprAddU', '.', 'NonBraceExprMulL' ], 0.8 ],
    [ 'NonBraceExprAddL' => ['NonBraceExprMulL'], 0.3 ],
    
    # NonBrace multiplication expressions (left-associative)
    [ 'NonBraceExprMulL' => [ 'NonBraceExprMulU', 'OpMulti', 'NonBraceExprRegexL' ], 0.8 ],
    [ 'NonBraceExprMulL' => ['NonBraceExprRegexL'], 0.3 ],
    
    [ 'NonBraceExprRegexL' => [ 'NonBraceExprRegexU', 'OpRegex', 'NonBraceExprUnaryL' ], 0.8 ],
    [ 'NonBraceExprRegexL' => ['NonBraceExprUnaryL'], 0.3 ],
    [ 'NonBraceExprUnaryL'  => [ 'OpUnary', 'NonBraceExprUnaryL' ], 0.8 ],
    [ 'NonBraceExprUnaryL'  => [ 'FileTestOp', 'NonBraceExprUnaryL' ], 0.8 ],
    [ 'NonBraceExprUnaryL'  => ['NonBraceExprPowerL'],  0.3 ],
    [ 'NonBraceExprPowerL'  => ['NonBraceExprIncL'],    0.3 ],
    [ 'NonBraceExprIncL' => [ 'OpInc', 'NonBraceExprIncL' ], 0.8 ],      # Pre-increment
    [ 'NonBraceExprIncL' => [ 'NonBraceExprIncL', 'OpInc' ], 0.8 ],      # Post-increment  
    [ 'NonBraceExprIncL'    => ['NonBraceExprArrowL'],  0.3 ],
    [ 'NonBraceExprArrowL'  => ['NonBraceExprValueL'],  0.3 ],
    [ 'NonBraceExprValueL'  => ['NonBraceValue'],       0.8 ],

    # Add missing operators for ternary expressions
    [ 'OpTriThen' => ['?'] ],
    [ 'OpTriElse' => [':'] ],

    # Diamond expressions following guacamole pattern
    [ 'DiamondExpr' => ['Diamond'], 1.0 ],

    # Diamond operator: <$fh>, <STDIN>, <>, <try>
    [ 'Diamond' => [ '<', 'Variable',          '>' ], 1.0 ],
    [ 'Diamond' => [ '<', 'BuiltinFilehandle', '>' ], 1.0 ],
    [ 'Diamond' => [ '<', 'Identifier',        '>' ], 1.0 ],  # Bareword filehandles
    [ 'Diamond' => [ '<', '>' ], 1.0 ],    # Empty diamond <>

    # Built-in filehandles
    [ 'BuiltinFilehandle' => [qr/STDIN|STDOUT|STDERR|ARGV|ARGVOUT|DATA/] ],

    # Function calls following Guacamole SubCall pattern
    [
        'FunctionCall' => [ 'Identifier', '(', 'ParameterList', ')' ],
        1.0
    ],                                     # func(args)
    [ 'FunctionCall' => [ 'Identifier', '(', ')' ], 1.0 ],    # func()
    
    # Qualified function calls for package methods
    [ 'FunctionCall' => [ 'QualifiedIdentifier', '(', 'ParameterList', ')' ], 1.0 ], # pkg::func(args)  
    [ 'FunctionCall' => [ 'QualifiedIdentifier', '(', ')' ], 1.0 ],                 # pkg::func()

# Expression block for grep/map/sort - supports both single expressions and statement lists
    [ 'ExpressionBlock' => [ '{', 'Expression',    '}' ], 1.0 ],
    [ 'ExpressionBlock' => [ '{', 'StatementList', '}' ], 1.0 ],

    # Eval - supports both block and string/expression forms
    [ 'EvalBlock' => [ 'eval', 'Block' ], 1.0 ],       # eval { ... }
    [ 'EvalBlock' => [ 'eval', 'Expression' ], 1.0 ],  # eval 'string' or eval $expr

    # Unary keyword expressions following guacamole.pm OpKeyword*Expr patterns
    [
        'UnaryKeywordExpression' => [ 'grep', 'ExpressionBlock', 'Expression' ],
        1.0
    ],    # grep { ... } @list
    [ 'UnaryKeywordExpression' => [ 'grep', 'Expression' ], 1.0 ]
    ,     # grep EXPR, @list
    [
        'UnaryKeywordExpression' => [ 'all', 'ExpressionBlock', 'Expression' ],
        1.0
    ],    # all { ... } @list
    [
        'UnaryKeywordExpression' => [ 'any', 'ExpressionBlock', 'Expression' ],
        1.0
    ],    # any { ... } @list
    [
        'UnaryKeywordExpression' => [ 'map', 'ExpressionBlock', 'Expression' ],
        1.0
    ],    # map { ... } @list
    [
        'UnaryKeywordExpression' => [ 'sort', 'ExpressionBlock', 'Expression' ],
        1.0
    ],    # sort { ... } @list

    # Operators - basic ones needed for chalk
    # OpRegex needs longer match (!~) before shorter (=~)
    [ 'OpRegex'   => [qr/!~|=~/] ],  # Regex binding operators: !~ and =~
    [ 'OpComma'   => [qr/,|=>/] ],
    [ 'OpAssign'  => [qr/\+=|-=|\*=|\/=|%=|\/\/=|\|\|=|&&=|\.=|&=|\|=|\^=|<<=|>>=|=/] ],  # Assignment operators (compound before simple)
    [ 'OpArrow'   => ['->'] ],
    [ 'OpAdd'     => [qr/[+\-]/] ],
    [ 'OpMulti'   => [qr/[*\/]/] ],
    [ 'OpLogOr'   => [qr/\|\||\/\//] ],              # Logical or and defined-or
    [ 'OpLogAnd'  => [qr/&&/] ],
    [ 'OpNameOr'  => ['or'] ],
    [ 'OpNameAnd' => ['and'] ],
    [ 'OpNameNot' => ['not'] ],
    [ 'OpRange'   => ['..'] ],
    [ 'OpBinOr'   => [qr/[|^]/] ],
    [ 'OpEqual'   => [qr/==|!=|<=>|eq|ne|cmp|isa/] ],
    [ 'OpInequal' => [qr/<=|>=|<|>|lt|gt|le|ge/] ],
    [ 'OpShift'   => [qr/<<|>>/] ],
    [ 'OpUnary'   => [qr/[\\+\-]/] ],  # Removed ! and ~ to avoid conflict with !~
    [ 'OpUnary'   => ['!'] ],  # Define ! separately
    [ 'OpUnary'   => ['~'] ],  # Define ~ separately
    [ 'OpPower'   => ['**'] ],
    [ 'OpInc'     => [qr/\+\+|--/] ],

    # Terminal definitions for chalk - following guacamole.pm pattern
    # Variables with optional element sequences (subscripts)
    [ 'Variable' => [ 'VariableBase', 'ElemSeq0' ], 1.0 ],
    [ 'Variable' => ['VariableBase'], 0.9 ],    # Lower priority for base case

    # Base variable patterns (without subscripts) - all sigils in one rule
    [ 'VariableBase' => [qr/[\$@%&*]\w+/] ],  # All variable types with sigils
    [ 'VariableBase' => [qr/\$#\w+/] ],       # Array length variables ($#array)

    # Global variables following guacamole GlobalVariables pattern
    [ 'VariableBase' => [qr/\$\$/] ],         # $$ - process ID (special case)
    [ 'VariableBase' => [qr/\$[!"#%&'()*+,\-.\/:;<=>?\@\[\\\]^_`|~]/] ],
    [ 'VariableBase' => [qr/\$\^\w+/] ]  # Special caret variables like $^X
    ,                                         # Global special vars

    # Caret variables in braces: ${^NAME}, $ {^NAME}, @{^NAME}, %{^NAME}
    [ 'VariableBase' => [ '${', '^', 'Identifier', '}' ], 1.0 ],  # ${^NAME}
    [ 'VariableBase' => [ '$', '{', '^', 'Identifier', '}' ], 1.0 ],  # $ {^NAME}
    [ 'VariableBase' => [ '@{', '^', 'Identifier', '}' ], 1.0 ],  # @{^NAME}
    [ 'VariableBase' => [ '@', '{', '^', 'Identifier', '}' ], 1.0 ],  # @ {^NAME}
    [ 'VariableBase' => [ '%{', '^', 'Identifier', '}' ], 1.0 ],  # %{^NAME}
    [ 'VariableBase' => [ '%', '{', '^', 'Identifier', '}' ], 1.0 ],  # % {^NAME}

    # Scalar dereference patterns: @$var, %$var, *$var, &$var, $$var, $#$var
    [ 'VariableBase' => [qr/[@%&*]\$\w+/] ],    # All dereference types except $$
    [ 'VariableBase' => [qr/\$\$\w+/] ],        # Scalar dereference ($$ref)
    [ 'VariableBase' => [qr/\$#\$\w+/] ],       # Array length of dereferenced scalar ($#$ref)

 # Complex dereference patterns from guacamole: ${ Expression }, @{ Expression }, %{ Expression }
    [ 'VariableBase' => [ '${', 'Expression', '}' ], 1.0 ]
    ,                                           # Scalar deref: ${ expr }
    [ 'VariableBase' => [ '$', '{', 'Expression', '}' ], 1.0 ]
    ,                                           # Scalar deref with space: $ { expr }
    [ 'VariableBase' => [ '@{', 'Expression', '}' ], 1.0 ]
    ,                                           # Array deref: @{ expr }
    [ 'VariableBase' => [ '%{', 'Expression', '}' ], 1.0 ]
    ,                                           # Hash deref: %{ expr }
    [ 'VariableBase' => [ '@[', 'Expression', ']' ], 1.0 ]
    ,                                           # Array slice: @[ expr ]
    [ 'VariableBase' => [ '%[', 'Expression', ']' ], 1.0 ]
    ,                                           # Hash slice: %[ expr ]

    # Element sequences for subscripting
    [ 'ElemSeq0' => [],                        0.1 ], # Empty sequence (epsilon)
    [ 'ElemSeq0' => ['Element'],               1.0 ],
    [ 'ElemSeq0' => [ 'Element', 'ElemSeq0' ], 0.8 ], # Multiple subscripts

    [ 'Element' => ['ArrayElem'], 1.0 ],
    [ 'Element' => ['HashElem'],  1.0 ],

    [ 'ArrayElem'    => [ '[', 'Expression', ']' ], 1.0 ],
    [ 'HashElem'     => [ '{', 'Expression', '}' ], 1.0 ],
    [ 'Identifier'   => [qr/[a-zA-Z_][a-zA-Z0-9_]*/] ],
    [ 'Number'       => [qr/(?:0[bB][01]+|0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[0-7]+|\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/] ],
    [ 'QuotedString' => [qr/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/] ],
    # q{} and qq{} quote operators with balanced brace matching (supports nested braces)
    # \s* allows whitespace (including newlines) between operator and delimiter
    # Pattern matches balanced braces up to 3 levels deep
    [ 'QuotedString' => [qr/q\s*\{(?:[^{}]++|\{(?:[^{}]++|\{(?:[^{}]++|\{[^{}]*+\})*+\})*+\})*+\}/] ],   # q{} with balanced braces
    [ 'QuotedString' => [qr/qq\s*\{(?:[^{}]++|\{(?:[^{}]++|\{(?:[^{}]++|\{[^{}]*+\})*+\})*+\})*+\}/] ],  # qq{} with balanced braces
    # Alternative quote delimiters - q(...), qq(...), q[...], qq[...], q<...>, qq<...>
    # \s* allows whitespace (including newlines) between operator and delimiter
    [ 'QuotedString' => [qr/q\s*\((?:[^)]|\n)*\)/] ],   # q() single-quote
    [ 'QuotedString' => [qr/qq\s*\((?:[^)]|\n)*\)/] ],  # qq() double-quote
    [ 'QuotedString' => [qr/q\s*\[(?:[^\]]|\n)*\]/] ],  # q[] single-quote
    [ 'QuotedString' => [qr/qq\s*\[(?:[^\]]|\n)*\]/] ], # qq[] double-quote
    [ 'QuotedString' => [qr/q\s*<(?:[^>]|\n)*>/] ],     # q<> single-quote
    [ 'QuotedString' => [qr/qq\s*<(?:[^>]|\n)*>/] ],    # qq<> double-quote

    # Punctuation
    [ 'PackageSeparator' => ['::'] ],
    
    # Qualified identifiers for package method calls like utf8::native_to_unicode
    # Made recursive to support multi-level package names like Chalk::Semiring::Boolean
    [ 'QualifiedIdentifier' => [ 'Identifier', 'PackageSeparator', 'QualifiedIdentifier' ], 1.0 ],
    [ 'QualifiedIdentifier' => [ 'Identifier', 'PackageSeparator', 'Identifier' ], 0.9 ],

    # ParameterList for method calls - simplified using ExpressionList
    [ 'ParameterList' => ['ExpressionList'],       1.0 ],
    [ 'ParameterList' => [ 'OpComma', 'Comment' ], 1.0 ]
    ,                                           # Just comma with comment
    [ 'ParameterList' => ['Comment'], 1.0 ],    # Just a comment
    [ 'ParameterList' => [],          1.0 ],    # Empty parameter list

    # ArrayRef and HashRef
    [ 'ArrayRef' => [ '[', 'ExpressionList', ']' ],  1.0 ],
    [ 'ArrayRef' => [ '[', ']' ],                    1.0 ],    # Empty array
    [ 'HashRef'  => [ '{', 'HashElementList', '}' ], 1.0 ],
    [ 'HashRef'  => [ '{', '}' ],                    1.0 ],    # Empty hash

    # Optimal 3-rule ExpressionList - balances functionality with performance
    [ 'ExpressionList' => ['Expression'], 1.0 ],                # Single expression 
    [ 'ExpressionList' => [ 'Expression', 'OpComma', 'ExpressionList' ], 1.0 ], # Standard recursion
    [ 'ExpressionList' => [ 'Comment', 'ExpressionList' ], 1.0 ], # Comment-prefixed lists

    [ 'HashElementList' => ['HashElement'], 1.0 ],
    [
        'HashElementList' => [ 'HashElement', 'OpComma', 'HashElementList' ],
        1.0
    ],
    [ 'HashElementList' => [ 'HashElement', 'OpComma' ], 1.0 ], # Trailing comma

    [ 'HashElement' => [ 'Expression', 'OpComma', 'Expression' ], 1.0 ]
    ,                                                           # key => value

    # File test operators - unary operators that test file properties
    [ 'FileTestOp' => [qr/-[rwxoRWXOezsfdlpSbctugkTBMAC]/] ],
    [ 'OpUnaryKeywordExpr' => [qr/-[rwxoRWXOezsfdlpSbctugkTBMAC]/] ],  # File test operators
    
    # Keyword expressions - termination points for Expression chain
    # For chalk, we only need basic ones that could appear
    [ 'OpUnaryKeywordExpr' => [qr/return|last|next|redo|chdir|mkdir|rmdir|unlink|chmod|chown|utime|rename|link|symlink|readlink|stat|lstat|sleep|exit|system|exec|fork|wait|waitpid|kill|alarm|umask|exists|defined|delete|ref|bless|tied|untie|tie|scalar|wantarray|caller|reset|undef|length|chr|ord|uc|lc|ucfirst|lcfirst|quotemeta|abs|int|sqrt|exp|log|sin|cos|atan2|rand|srand|time|localtime|gmtime|times|close|eof|tell|seek|truncate|fileno|flock|binmode/] ],

    [ 'OpAssignKeywordExpr' => [qr/goto|last/] ],

    [ 'OpListKeywordExpr' => [qr/die|warn|print|say|printf|sprintf|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|splice|pack|unpack|read|write|sysread|syswrite|recv|send|select/] ],

    # Whitespace rules (needed for auto_insert)
    [ 'WS_OPT' => [],         0.1 ],
    [ 'WS_OPT' => ['WS'],     1.0 ],
    [ 'WS'     => [qr/\s+/m], 1.0 ],
    [ 'WS'     => [qr/#.*$/m], 1.0 ],    # Comments count as whitespace
    [ 'WS'     => [qr/#.*\n\s+/m], 1.0 ], # Comment followed by whitespace
    ]
);

1;
