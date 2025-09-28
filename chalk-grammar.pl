#!/usr/bin/env perl
# ABOUTME: Clean chalk grammar based on Guacamole grammar structure from guacamole.pm
# ABOUTME: Using exact Guacamole naming conventions and patterns for consistency
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);

our $chalk_grammar = Grammar->build_grammar(
    [],    # No auto-insertion - explicit WS_OPT placement

    # Program structure - adapted from original chalk grammar
    [ 'Program' => ['StatementList'],             0.5 ],
    [ 'Program' => [ 'StatementList', 'WS_OPT' ], 0.5 ]
    ,              # With trailing whitespace (lower priority than shebang rules)
    [ 'Program' => [ 'Shebang', 'StatementList', 'WS_OPT' ], 2.0 ],         # Shebang + statements + optional trailing whitespace
    [ 'Program' => [ 'Shebang', 'WS_OPT', 'StatementList', 'WS_OPT' ], 2.1 ] # Shebang + optional whitespace + statements + optional trailing whitespace
    ,              # Shebang with trailing whitespace

  # Statement lists - adapted for chalk with reduced ambiguity
  # Prioritize simpler patterns to prevent parsing explosion
  # StatementList following Perl semicolon rules
  # Semicolons required between statements, optional for last statement in block
    [ 'StatementList' => [], 0.1 ],    # Empty statement list (for empty blocks)
    [ 'StatementList' => [ 'Statement', ';', 'WS_OPT', 'StatementList' ], 1.0 ]
    ,    # Statement + semicolon + more statements (explicit WS_OPT - auto-insertion insufficient)
    [ 'StatementList' => ['Statement'], 0.9 ]
    ,    # Single statement (last in block, no semicolon needed)
    [ 'StatementList' => ['BlockStatement'], 0.95 ],    # Single block statement
    [ 'StatementList' => [ 'BlockStatement', 'WS_OPT', 'StatementList' ], 0.8 ]
    ,    # Block + more statements
    [ 'StatementList' => [ 'LineStatement', 'WS_OPT', 'StatementList' ], 1.1 ]
    ,    # Line + more (higher priority than semicolon statements)

# BlockStatement - statements that contain blocks and don't need semicolons (following guacamole)
    [ 'BlockStatement' => ['ClassDecl'],  1.0 ],
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
    [ 'BlockStatement' => ['EndBlock'],           1.0 ],  # END blocks
    [ 'BlockStatement' => ['Block'],              1.0 ],  # Bare blocks
    ,    # Comments can appear in block contexts

  # Conditional statements (if/unless/while/until) - following guacamole pattern
    [ 'ConditionStatement' => ['IfStatement'],     1.0 ],
    [ 'ConditionStatement' => ['UnlessStatement'], 1.0 ],
    [ 'ConditionStatement' => ['ElsifStatement'],  1.0 ],

    # If statement rules with proper elsif chaining
    [ 'IfStatement' => [ 'if', 'WS_OPT', '(', 'Expression', ')', 'WS_OPT', 'Block' ], 1.0 ],
    [
        'IfStatement' =>
          [ 'if', 'WS_OPT', '(', 'Expression', ')', 'WS_OPT', 'Block', 'ElsifChain' ],
        1.0
    ],
    [
        'IfStatement' =>
          [ 'if', 'WS_OPT', '(', 'Expression', ')', 'WS_OPT', 'Block', 'WS_OPT', 'else', 'WS_OPT', 'Block' ],
        1.0
    ],
    [
        'IfStatement' => [
            'if', 'WS_OPT', '(', 'Expression', ')', 'WS_OPT',
            'Block', 'ElsifChain', 'WS_OPT', 'else', 'WS_OPT', 'Block'
        ],
        1.0
    ],

    # Elsif chain can be one or more elsif blocks
    [ 'ElsifChain' => [ 'elsif', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [
        'ElsifChain' =>
          [ 'elsif', '(', 'Expression', ')', 'Block', 'ElsifChain' ],
        1.0
    ],

    # Standalone elsif statement (for backwards compatibility)
    [ 'ElsifStatement' => [ 'elsif', '(', 'Expression', ')', 'Block' ], 1.0 ],

    # Unless statement rules following guacamole ConditionUnlessExpr pattern
    [ 'UnlessStatement' => [ 'unless', '(', 'Expression', ')', 'Block' ], 1.0 ],
    [ 'UnlessStatement' => [ 'unless', 'Expression' ], 1.0 ],    # Postfix form

    # Block structure for conditional statements
    [ 'Block' => [ '{', 'WS_OPT', 'StatementList', 'WS_OPT', '}' ], 1.0 ],
    [ 'Block' => [ '{', 'WS_OPT', '}' ], 1.0 ],

    # ADJUST block for class initialization
    [ 'AdjustBlock' => [ 'ADJUST', 'Block' ], 1.0 ],
    [ 'BeginBlock'  => [ 'BEGIN',  'Block' ], 1.0 ],
    [ 'EndBlock'    => [ 'END',    'Block' ], 1.0 ],

    # Loop statements (following guacamole pattern)
    [ 'LoopStatement' => ['ForStatement'],   1.0 ],
    [ 'LoopStatement' => ['WhileStatement'], 1.0 ],

    # For statement - foreach style variations
    [
        'ForStatement' =>
          [ 'for', 'my', 'VariableBase', '(', 'Expression', ')', 'Block' ],
        1.0
    ],
    [
        'ForStatement' =>
          [ 'foreach', 'my', 'VariableBase', '(', 'Expression', ')', 'Block' ],
        1.0
    ],
    [
        'ForStatement' =>
          [ 'for', 'VariableBase', '(', 'Expression', ')', 'Block' ],
        1.0
    ],
    [
        'ForStatement' =>
          [ 'foreach', 'VariableBase', '(', 'Expression', ')', 'Block' ],
        1.0
    ],

    # While statement - while ( condition ) { ... }
    [ 'WhileStatement' => [ 'while', '(', 'Expression', ')', 'Block' ], 1.0 ],

    # Statements - chalk specific with expression support
    [ 'Statement' => ['UseStatement'],     2.0 ],    # Higher priority than FunctionCall for 'use'
    [ 'Statement' => ['RequireStatement'], 2.0 ],    # Higher priority than FunctionCall for 'require'
    [ 'Statement' => ['FunctionCall'],     1.0 ],    # Function calls like print
    [ 'Statement' => ['PrintExpr'],        1.0 ],
    [ 'Statement' => ['DieExpr'],          1.0 ],
    [ 'Statement' => [ 'DieExpr', 'StatementModifier' ],      1.0 ],
    [ 'Statement' => [ 'FunctionCall', 'StatementModifier' ], 1.0 ]
    ,    # Print statements without parentheses
    [ 'Statement' => ['BlockLevelExpression'], 1.0 ],   # Block-level expression
    [ 'Statement' => ['EllipsisStatement'],    1.0 ],   # Ellipsis (...)
    [ 'Statement' => ['FieldDecl'],            1.0 ],   # Field declarations
    [ 'Statement' => ['VariableDecl'],       1.0 ], # my/our/local declarations
    [ 'Statement' => ['ReturnStatement'],    1.0 ], # Return statements
    [ 'Statement' => ['SubroutineDecl'],     1.0 ], # Subroutine declarations
    [ 'Statement' => ['ConditionStatement'], 2.0 ], # If/unless/while statements
    [ 'Statement' => [ 'ReturnStatement', 'StatementModifier' ], 1.0 ]
    ,                                               # Return with modifier
    [ 'Statement' => [ 'BlockLevelExpression', 'StatementModifier' ], 1.0 ]
    ,                                               # Expression with modifier

    # Line-terminated statements (don't require semicolons)
    [ 'LineStatement' => ['Shebang'], 1.0 ],
    [ 'LineStatement' => ['Comment'], 1.0 ],

    # Also allow comments directly as statements (higher accessibility)
    [ 'Statement' => ['Comment'], 1.0 ],

    # Class structure following guacamole PackageStatement pattern
    [
        'ClassDecl' => [ 'class', 'WS_OPT', 'Identifier', 'WS_OPT', 'Inheritance', 'WS_OPT', 'Block' ],
        1.0
    ],
    [ 'ClassDecl' => [ 'class', 'WS_OPT', 'Identifier', 'WS_OPT', 'Block' ], 1.0 ],

# Method declarations are identical to subroutine declarations (following guacamole)
    [ 'MethodDecl' => [ 'method', 'WS_OPT', 'Identifier', 'WS_OPT', 'SubDefinition' ], 1.0 ],
    [ 'MethodDecl' => [ 'method', 'WS_OPT', 'Identifier' ], 1.0 ],   # Forward declaration
    [ 'MethodDecl' => [ 'method', 'WS_OPT', 'SubDefinition' ], 1.0 ],   # anonymous method

    # Subroutine declarations
    [ 'SubroutineDecl' => [ 'sub', 'WS_OPT', 'Identifier', 'WS_OPT', 'SubDefinition' ], 1.0 ],
    [ 'SubroutineDecl' => [ 'sub', 'WS_OPT', 'Identifier' ], 1.0 ],  # Forward declaration
    [ 'SubroutineDecl' => [ 'my', 'WS_OPT', 'sub', 'WS_OPT', 'Identifier', 'WS_OPT', 'SubDefinition' ], 1.0 ]
    ,                                                      # my sub
    [ 'SubroutineDecl' => [ 'my', 'WS_OPT', 'sub', 'WS_OPT', 'Identifier' ], 1.0 ]
    ,                                                      # my sub forward decl
    [ 'SubrouteneDecl' => [ 'sub', 'WS_OPT', 'SubDefinition' ], 1.0 ],    # anonymous sub

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
          [ 'use', 'WS_OPT', 'ClassIdent', 'WS_OPT', 'VersionExpr', 'WS_OPT', 'Expression' ],
        0.9
    ],
    [ 'UseStatement' => [ 'use', 'WS_OPT', 'ClassIdent', 'WS_OPT', 'Expression' ],  0.8 ],
    [ 'UseStatement' => [ 'use', 'WS_OPT', 'VersionExpr' ],               0.7 ],
    [ 'UseStatement' => [ 'use', 'WS_OPT', 'ClassIdent', 'WS_OPT', 'VersionExpr' ], 0.6 ],
    [ 'UseStatement' => [ 'use', 'WS_OPT', 'ClassIdent' ],                0.5 ],

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

    # Require statements - similar to UseStatement but simpler
    [ 'RequireStatement' => [ 'require', 'Expression' ], 1.0 ],

    # Statement modifiers - following Guacamole postfix patterns
    [ 'StatementModifier' => [ qr/unless|if|while|for/, 'Expression' ], 2.0 ],

    # Guacamole UseStatement components
    # Removed OpKeywordUse - using 'use' directly in rules
    [ 'ClassIdent'   => ['SubNameExpr'] ],

    # SubNameExpr and VersionExpr definitions (simplified for chalk)
    [ 'SubNameExpr' => ['Identifier'] ],
    [ 'SubNameExpr' => [ 'Identifier', 'PackageSeparator', 'SubNameExpr' ] ],
    [ 'VersionExpr' => [qr/v?(?:\d+\.?){1,3}/] ],

   # QLikeValue - qw() expressions and regex patterns matching Guacamole pattern
    [ 'QLikeValue' => [qr/qw\([^)]*\)/] ],                        # qw(...)
    [ 'QLikeValue' => [qr/qr\{[^}]*\}[a-z]*/] ],                  # qr{...}flags
    [ 'QLikeValue' => [qr/qr\/((?:[^\/]|(?<=\\)\/)*)\/[a-z]*/] ]
    ,    # qr/.../flags with escapes
    [ 'QLikeValue' => [qr/\/((?:[^\/\\]|\\.)*)\/[gimsxoac]*/] ]
    ,    # /.../flags with escapes
    [ 'QLikeValue' => [qr/m![^!]*![a-z]*/] ],      # m!...!flags
    [ 'QLikeValue' => [qr/m#[^#]*#[a-z]*/] ],      # m#...#flags
    [ 'QLikeValue' => [qr/m\|[^|]*\|[a-z]*/] ],    # m|...|flags
    [ 'QLikeValue' => [qr/`[^`]*`/] ],             # `backticks`

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
          [ 'NonBraceExprCond0', 'WS_OPT', 'OpAssign', 'WS_OPT', 'ExprAssignR' ],
        0.8
    ],
    [ 'NonBraceExprAssignR' => ['NonBraceExprCondR'], 0.3 ],

 # NonBrace conditional expressions need to go through the full precedence chain
    [
        'NonBraceExprCondR' => [
            'NonBraceExprRange0', 'WS_OPT', 'OpTriThen', 'WS_OPT',
            'ExprRangeR',         'WS_OPT', 'OpTriElse', 'WS_OPT',
            'ExprCondR'
        ],
        0.8
    ],
    [ 'NonBraceExprCondR' => ['NonBraceExprRangeR'], 0.3 ],
    [
        'NonBraceExprCond0' => [
            'NonBraceExprRange0', 'WS_OPT', 'OpTriThen', 'WS_OPT',
            'ExprRange0',         'WS_OPT', 'OpTriElse', 'WS_OPT',
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
    [
        'NonBraceExprLogOrR' =>
          [ 'NonBraceExprLogOr0', 'WS_OPT', 'OpLogOr', 'WS_OPT', 'NonBraceExprLogAndR' ],
        0.8
    ],
    [ 'NonBraceExprLogOrR' => ['NonBraceExprLogAndR'], 0.3 ],
    [
        'NonBraceExprLogOr0' =>
          [ 'NonBraceExprLogOr0', 'WS_OPT', 'OpLogOr', 'WS_OPT', 'NonBraceExprLogAnd0' ],
        0.8
    ],
    [ 'NonBraceExprLogOr0' => ['NonBraceExprLogAnd0'], 0.3 ],

    # NonBrace logical AND expressions
    [
        'NonBraceExprLogAndR' =>
          [ 'NonBraceExprLogAnd0', 'WS_OPT', 'OpLogAnd', 'WS_OPT', 'NonBraceExprBinOrR' ],
        0.8
    ],
    [ 'NonBraceExprLogAndR' => ['NonBraceExprBinOrR'], 0.3 ],
    [
        'NonBraceExprLogAnd0' =>
          [ 'NonBraceExprLogAnd0', 'WS_OPT', 'OpLogAnd', 'WS_OPT', 'NonBraceExprBinOr0' ],
        0.8
    ],
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
          [ 'NonBraceExprNeq0', 'WS_OPT', 'OpEqual', 'WS_OPT', 'NonBraceExprNeqR' ],
        0.8
    ],
    [ 'NonBraceExprEqR' => ['NonBraceExprNeqR'], 0.3 ],
    [
        'NonBraceExprEq0' =>
          [ 'NonBraceExprNeq0', 'WS_OPT', 'OpEqual', 'WS_OPT', 'NonBraceExprNeq0' ],
        0.8
    ],
    [ 'NonBraceExprEq0' => ['NonBraceExprNeq0'], 0.3 ],

    # NonBrace inequality expressions
    [
        'NonBraceExprNeqR' =>
          [ 'NonBraceExprShift0', 'WS_OPT', 'OpInequal', 'WS_OPT', 'NonBraceExprShiftR' ],
        0.8
    ],
    [ 'NonBraceExprNeqR' => ['NonBraceExprShiftR'], 0.3 ],
    [
        'NonBraceExprNeq0' =>
          [ 'NonBraceExprShift0', 'WS_OPT', 'OpInequal', 'WS_OPT', 'NonBraceExprShift0' ],
        0.8
    ],
    [ 'NonBraceExprNeq0' => ['NonBraceExprShift0'], 0.3 ],

    # NonBrace shift expressions
    [
        'NonBraceExprShiftR' =>
          [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAddR' ],
        0.8
    ],
    [ 'NonBraceExprShiftR' => ['NonBraceExprAddR'], 0.3 ],
    [
        'NonBraceExprShift0' =>
          [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAdd0' ],
        0.8
    ],
    [ 'NonBraceExprShift0' => ['NonBraceExprAdd0'], 0.3 ],
    [
        'NonBraceExprShiftU' =>
          [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAddU' ],
        0.8
    ],
    [ 'NonBraceExprShiftU' => ['NonBraceExprAddU'], 0.3 ],

    # NonBrace addition expressions
    [
        'NonBraceExprAddR' =>
          [ 'NonBraceExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'NonBraceExprMulR' ],
        0.8
    ],
    [
        'NonBraceExprAddR' => [ 'NonBraceExprAddU', 'WS_OPT', '.', 'WS_OPT', 'NonBraceExprMulR' ],
        0.8
    ],
    [ 'NonBraceExprAddR' => ['NonBraceExprMulR'], 0.3 ],
    [
        'NonBraceExprAdd0' =>
          [ 'NonBraceExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'NonBraceExprMul0' ],
        0.8
    ],
    [
        'NonBraceExprAdd0' => [ 'NonBraceExprAddU', 'WS_OPT', '.', 'WS_OPT', 'NonBraceExprMul0' ],
        0.8
    ],
    [ 'NonBraceExprAdd0' => ['NonBraceExprMul0'], 0.3 ],
    [
        'NonBraceExprAddU' =>
          [ 'NonBraceExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'NonBraceExprMulU' ],
        0.8
    ],
    [
        'NonBraceExprAddU' => [ 'NonBraceExprAddU', 'WS_OPT', '.', 'WS_OPT', 'NonBraceExprMulU' ],
        0.8
    ],
    [ 'NonBraceExprAddU' => ['NonBraceExprMulU'], 0.3 ],

    # NonBrace multiplication expressions
    [
        'NonBraceExprMulR' =>
          [ 'NonBraceExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'NonBraceExprRegexR' ],
        0.8
    ],
    [ 'NonBraceExprMulR' => ['NonBraceExprRegexR'], 0.3 ],
    [
        'NonBraceExprMul0' =>
          [ 'NonBraceExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'NonBraceExprRegex0' ],
        0.8
    ],
    [ 'NonBraceExprMul0' => ['NonBraceExprRegex0'], 0.3 ],
    [
        'NonBraceExprMulU' =>
          [ 'NonBraceExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'NonBraceExprRegexU' ],
        0.8
    ],
    [ 'NonBraceExprMulU' => ['NonBraceExprRegexU'], 0.3 ],

    # NonBrace regex expressions
    [ 'NonBraceExprRegexR' => ['NonBraceExprUnaryR'], 0.3 ],
    [ 'NonBraceExprRegex0' => ['NonBraceExprUnary0'], 0.3 ],
    [ 'NonBraceExprRegexU' => ['NonBraceExprUnaryU'], 0.3 ],

    # NonBrace unary expressions
    [ 'NonBraceExprUnaryR' => [ 'OpUnary', 'NonBraceExprUnaryR' ], 0.8 ],
    [ 'NonBraceExprUnaryR' => ['NonBraceExprPowerR'],              0.3 ],
    [ 'NonBraceExprUnary0' => [ 'OpUnary', 'NonBraceExprUnary0' ], 0.8 ],
    [ 'NonBraceExprUnary0' => ['NonBraceExprPower0'],              0.3 ],
    [ 'NonBraceExprUnaryU' => [ 'OpUnary', 'NonBraceExprUnaryU' ], 0.8 ],
    [ 'NonBraceExprUnaryU' => ['NonBraceExprPowerU'],              0.3 ],

    # NonBrace power expressions
    [
        'NonBraceExprPowerR' =>
          [ 'NonBraceExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'NonBraceExprUnaryR' ],
        0.8
    ],
    [ 'NonBraceExprPowerR' => ['NonBraceExprIncR'], 0.3 ],
    [
        'NonBraceExprPower0' =>
          [ 'NonBraceExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'NonBraceExprUnary0' ],
        0.8
    ],
    [ 'NonBraceExprPower0' => ['NonBraceExprInc0'], 0.3 ],
    [
        'NonBraceExprPowerU' =>
          [ 'NonBraceExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'NonBraceExprUnaryU' ],
        0.8
    ],
    [ 'NonBraceExprPowerU' => ['NonBraceExprIncU'], 0.3 ],

    # NonBrace increment expressions
    [ 'NonBraceExprIncR' => [ 'OpInc', 'NonBraceExprIncR' ], 0.8 ],
    [ 'NonBraceExprIncR' => [ 'NonBraceExprIncR', 'OpInc' ], 0.8 ],
    [ 'NonBraceExprIncR' => ['NonBraceExprArrowR'],          0.3 ],
    [ 'NonBraceExprInc0' => [ 'OpInc', 'NonBraceExprInc0' ], 0.8 ],
    [ 'NonBraceExprInc0' => [ 'NonBraceExprInc0', 'OpInc' ], 0.8 ],
    [ 'NonBraceExprInc0' => ['NonBraceExprArrow0'],          0.3 ],
    [ 'NonBraceExprIncU' => [ 'OpInc', 'NonBraceExprIncU' ], 0.8 ],
    [ 'NonBraceExprIncU' => [ 'NonBraceExprIncU', 'OpInc' ], 0.8 ],
    [ 'NonBraceExprIncU' => ['NonBraceExprArrowU'],          0.3 ],

    # NonBrace arrow expressions
    [
        'NonBraceExprArrowR' => [ 'NonBraceExprArrowU', 'OpArrow', 'ArrowRHS' ],
        0.8
    ],
    [ 'NonBraceExprArrowR' => ['NonBraceExprValueR'], 0.3 ],
    [
        'NonBraceExprArrow0' => [ 'NonBraceExprArrowU', 'OpArrow', 'ArrowRHS' ],
        0.8
    ],
    [ 'NonBraceExprArrow0' => ['NonBraceExprValue0'], 0.3 ],
    [
        'NonBraceExprArrowU' => [ 'NonBraceExprArrowU', 'OpArrow', 'ArrowRHS' ],
        0.8
    ],
    [ 'NonBraceExprArrowU' => ['NonBraceExprValueU'], 0.3 ],

    # NonBraceExprValue* rules
    [ 'NonBraceExprValueU' => ['NonBraceValue'],       1.0 ],
    [ 'NonBraceExprValueR' => ['NonBraceValue'],       0.8 ],
    [ 'NonBraceExprValueR' => ['OpListKeywordExpr'],   0.5 ],
    [ 'NonBraceExprValueR' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'NonBraceExprValueR' => ['OpUnaryKeywordExpr'],  0.5 ],
    [ 'NonBraceExprValue0' => ['NonBraceValue'],       0.8 ],
    [ 'NonBraceExprValue0' => ['OpUnaryKeywordExpr'],  0.5 ],
    [ 'NonBraceValue'      => ['Variable'],            0.4 ],
    [ 'NonBraceValue'      => ['Identifier'],          0.4 ],
    [ 'NonBraceValue'      => ['Number'],              0.3 ],
    [ 'NonBraceValue'      => ['UnaryExpression'],     0.3 ],
    [ 'NonBraceValue'      => ['QuotedString'],        0.3 ],

    # Unary expressions (for things like -1e10, !$flag, etc.)
    [ 'UnaryExpression' => [ 'OpUnary', 'NonBraceValue' ], 1.0 ],
    [ 'NonBraceValue'   => [ '(', 'Expression', ')' ],     0.3 ],
    [ 'NonBraceValue'   => ['ArrayRef'],                   0.3 ],
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
    [ 'ExprAssignR' => [ 'ExprCond0', 'WS_OPT', 'OpAssign', 'WS_OPT', 'ExprAssignR' ], 0.8 ],
    [ 'ExprAssignR' => ['ExprCondR'],                              0.3 ],
    [ 'ExprAssignL' => [ 'ExprCond0', 'WS_OPT', 'OpAssign', 'WS_OPT', 'ExprAssignL' ], 0.8 ],
    [ 'ExprAssignL' => ['OpAssignKeywordExpr'],                    0.5 ],
    [ 'ExprAssignL' => ['ExprCondL'],                              0.3 ],
    [
        'ExprCondR' => [ 'ExprRange0', 'WS_OPT', '?', 'WS_OPT', 'ExprRangeR', 'WS_OPT', ':', 'WS_OPT', 'ExprCondR' ],
        0.8
    ],
    [ 'ExprCondR' => ['ExprRangeR'], 0.3 ],
    [
        'ExprCondL' => [ 'ExprRange0', 'WS_OPT', '?', 'WS_OPT', 'ExprRangeL', 'WS_OPT', ':', 'WS_OPT', 'ExprCondL' ],
        0.8
    ],
    [ 'ExprCondL' => ['ExprRangeL'], 0.3 ],
    [
        'ExprCond0' => [ 'ExprRange0', 'WS_OPT', '?', 'WS_OPT', 'ExprRange0', 'WS_OPT', ':', 'WS_OPT', 'ExprCond0' ],
        0.8
    ],
    [ 'ExprCond0'  => ['ExprRange0'],                             0.3 ],
    [ 'ExprRangeR' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrR' ],  0.8 ],
    [ 'ExprRangeR' => ['ExprLogOrR'],                             0.3 ],
    [ 'ExprRangeL' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrL' ],  0.8 ],
    [ 'ExprRangeL' => ['ExprLogOrL'],                             0.3 ],
    [ 'ExprRange0' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOr0' ],  0.8 ],
    [ 'ExprRange0' => ['ExprLogOr0'],                             0.3 ],
    [ 'ExprLogOrR' => [ 'ExprLogOr0', 'WS_OPT', 'OpLogOr', 'WS_OPT', 'ExprLogAndR' ], 0.8 ],
    [ 'ExprLogOrR' => ['ExprLogAndR'],                            0.3 ],
    [ 'ExprLogOrL' => [ 'ExprLogOr0', 'WS_OPT', 'OpLogOr', 'WS_OPT', 'ExprLogAndL' ], 0.8 ],
    [ 'ExprLogOrL' => ['ExprLogAndL'],                            0.3 ],
    [ 'ExprLogOr0' => [ 'ExprLogOr0', 'WS_OPT', 'OpLogOr', 'WS_OPT', 'ExprLogAnd0' ], 0.8 ],
    [ 'ExprLogOr0' => ['ExprLogAnd0'],                            0.3 ],

    # Continue the chain down to Value
    [ 'ExprLogAndR' => [ 'ExprLogAnd0', 'WS_OPT', 'OpLogAnd', 'WS_OPT', 'ExprBinOrR' ], 0.8 ],
    [ 'ExprLogAndR' => [ 'ExprBinOrR',  'Comment' ], 0.7 ]
    ,    # Expression with trailing comment
    [ 'ExprLogAndR' => ['ExprBinOrR'],                              0.3 ],
    [ 'ExprLogAndL' => [ 'ExprLogAnd0', 'WS_OPT', 'OpLogAnd', 'WS_OPT', 'ExprBinOrL' ], 0.8 ],
    [ 'ExprLogAndL' => ['ExprBinOrL'],                              0.3 ],
    [ 'ExprLogAnd0' => [ 'ExprLogAnd0', 'WS_OPT', 'OpLogAnd', 'WS_OPT', 'ExprBinOr0' ], 0.8 ],
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
    [ 'ExprEqR' => [ 'ExprNeq0', 'WS_OPT', 'OpEqual', 'WS_OPT', 'ExprNeqR' ], 0.8 ],
    [ 'ExprEqR' => ['ExprNeqR'],                          0.3 ],
    [ 'ExprEqL' => [ 'ExprNeq0', 'WS_OPT', 'OpEqual', 'WS_OPT', 'ExprNeqL' ], 0.8 ],
    [ 'ExprEqL' => ['ExprNeqL'],                          0.3 ],
    [ 'ExprEq0' => [ 'ExprNeq0', 'WS_OPT', 'OpEqual', 'WS_OPT', 'ExprNeq0' ], 0.8 ],
    [ 'ExprEq0' => ['ExprNeq0'],                          0.3 ],

    [ 'ExprNeqR' => [ 'ExprShift0', 'WS_OPT', 'OpInequal', 'WS_OPT', 'ExprShiftR' ], 0.8 ],
    [ 'ExprNeqR' => ['ExprShiftR'],                              0.3 ],
    [ 'ExprNeqL' => [ 'ExprShift0', 'WS_OPT', 'OpInequal', 'WS_OPT', 'ExprShiftL' ], 0.8 ],
    [ 'ExprNeqL' => ['ExprShiftL'],                              0.3 ],
    [ 'ExprNeq0' => [ 'ExprShift0', 'WS_OPT', 'OpInequal', 'WS_OPT', 'ExprShift0' ], 0.8 ],
    [ 'ExprNeq0' => ['ExprShift0'],                              0.3 ],

    [ 'ExprShiftR' => [ 'ExprShiftU', 'OpShift', 'ExprAddR' ], 0.8 ],
    [ 'ExprShiftR' => ['ExprAddR'],                            0.3 ],
    [ 'ExprShiftL' => [ 'ExprShiftU', 'OpShift', 'ExprAddL' ], 0.8 ],
    [ 'ExprShiftL' => ['ExprAddL'],                            0.3 ],
    [ 'ExprShift0' => [ 'ExprShiftU', 'OpShift', 'ExprAdd0' ], 0.8 ],
    [ 'ExprShift0' => ['ExprAdd0'],                            0.3 ],
    [ 'ExprShiftU' => [ 'ExprShiftU', 'OpShift', 'ExprAddU' ], 0.8 ],
    [ 'ExprShiftU' => ['ExprAddU'],                            0.3 ],

    [ 'ExprAddR' => [ 'ExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'ExprMulR' ], 0.8 ],
    [ 'ExprAddR' => [ 'ExprAddU', 'WS_OPT', '.', 'WS_OPT', 'ExprMulR' ], 0.8 ],
    [ 'ExprAddR' => ['ExprMulR'],                        0.3 ],
    [ 'ExprAddL' => [ 'ExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'ExprMulL' ], 0.8 ],
    [ 'ExprAddL' => [ 'ExprAddU', 'WS_OPT', '.', 'WS_OPT', 'ExprMulL' ], 0.8 ],
    [ 'ExprAddL' => ['ExprMulL'],                        0.3 ],
    [ 'ExprAdd0' => [ 'ExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'ExprMul0' ], 0.8 ],
    [ 'ExprAdd0' => [ 'ExprAddU', 'WS_OPT', '.', 'WS_OPT', 'ExprMul0' ], 0.8 ],
    [ 'ExprAdd0' => ['ExprMul0'],                        0.3 ],
    [ 'ExprAddU' => [ 'ExprAddU', 'WS_OPT', 'OpAdd', 'WS_OPT', 'ExprMulU' ], 0.8 ],
    [ 'ExprAddU' => [ 'ExprAddU', 'WS_OPT', '.', 'WS_OPT', 'ExprMulU' ], 0.8 ],
    [ 'ExprAddU' => ['ExprMulU'],                        0.3 ],

    [ 'ExprMulR' => [ 'ExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'ExprRegexR' ], 0.8 ],
    [ 'ExprMulR' => ['ExprRegexR'],                          0.3 ],
    [ 'ExprMulL' => [ 'ExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'ExprRegexL' ], 0.8 ],
    [ 'ExprMulL' => ['ExprRegexL'],                          0.3 ],
    [ 'ExprMul0' => [ 'ExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'ExprRegex0' ], 0.8 ],
    [ 'ExprMul0' => ['ExprRegex0'],                          0.3 ],
    [ 'ExprMulU' => [ 'ExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'ExprRegexU' ], 0.8 ],
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
    [ 'ExprUnaryR' => ['ExprPowerR'],              0.3 ],
    [ 'ExprUnaryL' => [ 'OpUnary', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprUnaryL' => ['ExprPowerL'],              0.3 ],
    [ 'ExprUnary0' => [ 'OpUnary', 'ExprUnary0' ], 0.8 ],
    [ 'ExprUnary0' => ['ExprPower0'],              0.3 ],
    [ 'ExprUnaryU' => [ 'OpUnary', 'ExprUnaryU' ], 0.8 ],
    [ 'ExprUnaryU' => ['ExprPowerU'],              0.3 ],

    [ 'ExprPowerR' => [ 'ExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'ExprUnaryR' ], 0.8 ],
    [ 'ExprPowerR' => ['ExprIncR'],                            0.3 ],
    [ 'ExprPowerL' => [ 'ExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprPowerL' => ['ExprIncL'],                            0.3 ],
    [ 'ExprPower0' => [ 'ExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'ExprUnary0' ], 0.8 ],
    [ 'ExprPower0' => ['ExprInc0'],                            0.3 ],
    [ 'ExprPowerU' => [ 'ExprIncU', 'WS_OPT', 'OpPower', 'WS_OPT', 'ExprUnaryU' ], 0.8 ],
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
    [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS', 'ArrowChain' ], 0.8 ],
    [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS' ], 0.3 ],

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
    [ 'ArrowRHS' => [ 'Identifier', '(', 'ParameterList', ')' ], 0.4 ],
    [ 'ArrowRHS' => [ 'Identifier', '(', ')' ],    0.4 ],    # ->method($args)
    [ 'ArrowRHS' => [ '(', 'ParameterList', ')' ], 0.4 ]
    ,    # ->($args) code ref call
    [ 'ArrowRHS' => [ '(', ')' ],               0.4 ],    # ->() code ref call
    [ 'ArrowRHS' => [ '[', 'Expression', ']' ], 0.3 ],
    [ 'ArrowRHS' => [ '{', 'Expression', '}' ], 0.3 ],
    [ 'ArrowRHS' => ['PostfixDeref'], 0.3 ], # ->@*, ->%*, ->$* (postfix derefs)

    # Postfix dereferencing operators - atomic tokens
    [ 'PostfixDeref' => [qr/[@%\$]\*/] ],

    # Value rules - basic terminals needed for chalk
    [ 'Value' => ['Variable'],   0.4 ], # Now includes $hash{key}, @array[index]
    [ 'Value' => ['Identifier'], 0.4 ],
    [ 'Value' => ['Number'],     0.3 ],
    [ 'Value' => ['QuotedString'],           0.3 ],
    [ 'Value' => [ '(', 'Expression', ')' ], 0.3 ],
    [ 'Value' => [ '(', ')' ],     0.3 ],    # Empty parentheses (empty list)
    [ 'Value' => ['ArrayRef'],     0.3 ],
    [ 'Value' => ['HashRef'],      0.3 ],
    [ 'Value' => ['FunctionCall'], 0.3 ],
    [ 'Value' => ['UnaryKeywordExpression'], 0.3 ],    # grep/map/sort etc.
    [ 'Value' => ['ExpressionBlock'],        0.3 ],    # { expr } blocks
    [ 'Value' => ['QLikeValue'],             0.8 ],
    [ 'Value' => ['DiamondExpr'],            0.3 ],    # <$fh> constructs
    [ 'Value' => ['@'],                      0.3 ],
    [ 'Value' => ['FieldDecl'],              0.3 ],
    [ 'Value' => ['VariableDecl'], 0.3 ], # my $var = expr as expression
    [ 'Value' => ['PrintExpr'],    0.3 ], # print statements without parentheses
    [ 'Value' => [ 'sub', 'SubDefinition' ], 0.3 ],    # Anonymous subroutines
    [ 'Value' => [ 'method', 'SubDefinition' ], 0.3 ], # Anonymous methods

    # Print expressions following guacamole OpKeywordPrintExpr pattern
    [ 'PrintExpr' => [ 'print', 'NonBraceExprComma' ], 1.0 ],   # print "string"
    [ 'PrintExpr' => ['print'],                        1.0 ],   # bare print

    # Print with filehandle: print FILEHANDLE "string"
    [ 'PrintExpr' => [ 'print', 'Identifier', 'NonBraceExprComma' ], 1.0 ]
    ,                                                     # print FH "string"
    [ 'PrintExpr' => [ 'print', 'Identifier' ], 1.0 ],    # print FH
    [
        'PrintExpr' => [ 'print', 'BuiltinFilehandle', 'NonBraceExprComma' ],
        1.0
    ],    # print STDOUT "string"
    [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle' ], 1.0 ],    # print STDOUT

    # Die expressions following same pattern as PrintExpr
    [ 'DieExpr' => [ 'die', 'NonBraceExprComma' ], 1.0 ],        # die "string"
    [ 'DieExpr' => ['die'],                        1.0 ],        # bare die

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
          [ 'NonBraceExprCond0', 'WS_OPT', 'OpAssign', 'WS_OPT', 'NonBraceExprAssignL' ],
        0.8
    ],
    [ 'NonBraceExprAssignL' => ['NonBraceExprCondL'], 0.3 ],

    # NonBraceExprCondL for conditional expressions in print context
    [
        'NonBraceExprCondL' => [
            'NonBraceExprRange0', 'WS_OPT', 'OpTriThen', 'WS_OPT',
            'NonBraceExprRangeL', 'WS_OPT', 'OpTriElse', 'WS_OPT',
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
    [
        'NonBraceExprEqL' =>
          [ 'NonBraceExprNeq0', 'WS_OPT', 'OpEqual', 'WS_OPT', 'NonBraceExprNeqL' ],
        0.8
    ],
    [ 'NonBraceExprEqL'     => ['NonBraceExprNeqL'],    0.3 ],
    [
        'NonBraceExprNeqL' =>
          [ 'NonBraceExprShift0', 'WS_OPT', 'OpInequal', 'WS_OPT', 'NonBraceExprShiftL' ],
        0.8
    ],
    [ 'NonBraceExprNeqL' => ['NonBraceExprShiftL'], 0.3 ],

    # NonBrace shift expressions (left-associative)
    [
        'NonBraceExprShiftL' =>
          [ 'NonBraceExprShiftU', 'OpShift', 'NonBraceExprAddL' ],
        0.8
    ],
    [ 'NonBraceExprShiftL' => ['NonBraceExprAddL'], 0.3 ],

    # NonBrace addition expressions (left-associative)
    [
        'NonBraceExprAddL' =>
          [ 'NonBraceExprAddU', 'OpAdd', 'NonBraceExprMulL' ],
        0.8
    ],
    [
        'NonBraceExprAddL' => [ 'NonBraceExprAddU', '.', 'NonBraceExprMulL' ],
        0.8
    ],
    [ 'NonBraceExprAddL' => ['NonBraceExprMulL'], 0.3 ],

    # NonBrace multiplication expressions (left-associative)
    [
        'NonBraceExprMulL' =>
          [ 'NonBraceExprMulU', 'WS_OPT', 'OpMulti', 'WS_OPT', 'NonBraceExprRegexL' ],
        0.8
    ],
    [ 'NonBraceExprMulL' => ['NonBraceExprRegexL'], 0.3 ],

    [ 'NonBraceExprRegexL' => ['NonBraceExprUnaryL'],          0.3 ],
    [ 'NonBraceExprUnaryL' => ['NonBraceExprPowerL'],          0.3 ],
    [ 'NonBraceExprPowerL' => ['NonBraceExprIncL'],            0.3 ],
    [ 'NonBraceExprIncL'   => [ 'OpInc', 'NonBraceExprIncL' ], 0.8 ]
    ,    # Pre-increment
    [ 'NonBraceExprIncL' => [ 'NonBraceExprIncL', 'OpInc' ], 0.8 ]
    ,    # Post-increment
    [ 'NonBraceExprIncL'   => ['NonBraceExprArrowL'], 0.3 ],
    [ 'NonBraceExprArrowL' => ['NonBraceExprValueL'], 0.3 ],
    [ 'NonBraceExprValueL' => ['NonBraceValue'],      0.8 ],

    # Add missing operators for ternary expressions
    [ 'OpTriThen' => ['?'] ],
    [ 'OpTriElse' => [':'] ],

    # Diamond expressions following guacamole pattern
    [ 'DiamondExpr' => ['Diamond'], 1.0 ],

    # Diamond operator: <$fh>, <STDIN>, <>, <try>
    [ 'Diamond' => [ '<', 'Variable',          '>' ], 1.0 ],
    [ 'Diamond' => [ '<', 'BuiltinFilehandle', '>' ], 1.0 ],
    [ 'Diamond' => [ '<', 'Identifier', '>' ], 1.0 ],    # Bareword filehandles
    [ 'Diamond' => [ '<', '>' ], 1.0 ],                  # Empty diamond <>

    # Built-in filehandles
    [ 'BuiltinFilehandle' => [qr/STDIN|STDOUT|STDERR|ARGV|ARGVOUT|DATA/] ],

    # Function calls following Guacamole SubCall pattern
    [
        'FunctionCall' => [ 'Identifier', '(', 'ParameterList', ')' ],
        1.0
    ],                                                   # func(args)
    [ 'FunctionCall' => [ 'Identifier', '(', ')' ], 1.0 ],    # func()

    # Function calls without parentheses (common in Perl)
    [ 'FunctionCall' => [ 'Identifier', 'WS_OPT', 'NonBraceExprComma' ], 1.0 ]
    ,                                                         # func args

    # Qualified function calls for package methods
    [
        'FunctionCall' => [ 'QualifiedIdentifier', '(', 'ParameterList', ')' ],
        1.0
    ],                                                        # pkg::func(args)
    [ 'FunctionCall' => [ 'QualifiedIdentifier', '(', ')' ], 1.0 ]
    ,                                                         # pkg::func()
    [ 'FunctionCall' => [ 'QualifiedIdentifier', 'WS_OPT', 'NonBraceExprComma' ], 1.0 ]
    ,                                                         # pkg::func args

# Expression block for grep/map/sort - supports both single expressions and statement lists
    [ 'ExpressionBlock' => [ '{', 'Expression',    '}' ], 1.0 ],
    [ 'ExpressionBlock' => [ '{', 'StatementList', '}' ], 1.0 ],

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
    [ 'OpComma'   => [qr/,|=>/] ],
    [ 'OpAssign'  => [qr/\/\/=|\|\|=|&&=|\.=|=(?!>)/] ],  # Assignment operators, = not followed by >
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
    [ 'OpRegex'   => [qr/=~|!~/] ],
    [ 'OpUnary'   => [qr/[!~\\+\-]/] ],
    [ 'OpUnary'   => [qr/-[rwxoRWXOezsfdlpSbctugkTBMAC]/] ],
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
    [ 'VariableBase' => [qr/\$[!"#%&'()*+,\-.\/:;<=>?\@\[\\\]^_`|~]/] ],
    [ 'VariableBase' => [qr/\$\^\w+/] ]       # Special caret variables like $^X
    ,                                         # Global special vars

    # Scalar dereference patterns: @$var, %$var, *$var, &$var
    [ 'VariableBase' => [qr/[@%&*]\$\w+/] ],    # All dereference types

 # Complex dereference patterns from guacamole: @{ Expression }, %{ Expression }
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

    [ 'ArrayElem'  => [ '[', 'Expression', ']' ], 1.0 ],
    [ 'HashElem'   => [ '{', 'Expression', '}' ], 1.0 ],
    # Identifier pattern excludes reserved keywords
    [ 'Identifier' => [qr/(?!(?:use|require|class|method|sub|if|while|for|foreach|unless|elsif|else|BEGIN|END|ADJUST|field|my|our|local|state|return|last|next|redo|and|or|not)\b)[a-zA-Z_][a-zA-Z0-9_]*/], 1.0 ],
    [
        'Number' => [
qr/(?:0[bB][01]+|0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[0-7]+|\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/
        ],
        1.0
    ],
    [ 'QuotedString' => [qr/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/] ],

    # Punctuation
    [ 'PackageSeparator' => ['::'] ],

   # Qualified identifiers for package method calls like utf8::native_to_unicode
    [
        'QualifiedIdentifier' =>
          [ 'Identifier', 'PackageSeparator', 'Identifier' ],
        1.0
    ],

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
    [ 'ExpressionList' => ['Expression'], 1.0 ],    # Single expression
    [ 'ExpressionList' => [ 'Expression', 'OpComma', 'ExpressionList' ], 1.0 ]
    ,                                               # Standard recursion
    [ 'ExpressionList' => [ 'Comment', 'ExpressionList' ], 1.0 ]
    ,                                               # Comment-prefixed lists

    [ 'HashElementList' => ['HashElement'], 1.0 ],
    [
        'HashElementList' => [ 'HashElement', 'OpComma', 'HashElementList' ],
        1.0
    ],
    [ 'HashElementList' => [ 'HashElement', 'OpComma' ], 1.0 ], # Trailing comma

    [ 'HashElement' => [ 'Expression', 'OpComma', 'Expression' ], 1.0 ]
    ,                                                           # key => value

    # File test operators - unary operators that test file properties
    [ 'OpUnaryKeywordExpr' => [qr/-[rwxoRWXOezsfdlpSbctugkTBMAC]/] ]
    ,    # File test operators

    # Keyword expressions - termination points for Expression chain
    # For chalk, we only need basic ones that could appear
    [
        'OpUnaryKeywordExpr' => [
qr/return|last|next|redo|chdir|mkdir|rmdir|unlink|chmod|chown|utime|rename|link|symlink|readlink|stat|lstat|sleep|exit|system|exec|fork|wait|waitpid|kill|alarm|umask|exists|defined|delete|ref|bless|tied|untie|tie|scalar|wantarray|caller|reset|undef|length|chr|ord|uc|lc|ucfirst|lcfirst|quotemeta|abs|int|sqrt|exp|log|sin|cos|atan2|rand|srand|time|localtime|gmtime|times|close|eof|tell|seek|truncate|fileno|flock|binmode/
        ]
    ],

    [ 'OpAssignKeywordExpr' => [qr/goto|last/] ],

    [
        'OpListKeywordExpr' => [
qr/warn|print|printf|sprintf|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|splice|pack|unpack|open|read|write|sysread|syswrite|recv|send|select/
        ],
        1.0
    ],

    # Whitespace rules (needed for auto_insert)
    [ 'WS_OPT' => [],         0.1 ],    # WS_OPT can be empty
    [ 'WS_OPT' => ['WS'],     1.0 ],    # WS_OPT can be whitespace
    [ 'WS'     => [qr/\s+/m], 1.0 ]     # Only actual whitespace characters
);

# Note: Semantic Action Classes are now defined in the main chalk file
