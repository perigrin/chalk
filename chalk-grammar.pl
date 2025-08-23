#!/usr/bin/env perl
# ABOUTME: Clean chalk grammar based on Guacamole grammar structure from guacamole.pm
# ABOUTME: Using exact Guacamole naming conventions and patterns for consistency
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);

our $chalk_grammar = Grammar->build_grammar(
    ['WS_OPT'],    # Auto-insert WS_OPT between all symbols

    # Program structure - adapted from original chalk grammar
    [ 'Program' => ['StatementList'], 1.0 ],

  # Statement lists - adapted for chalk with reduced ambiguity
  # Prioritize simpler patterns to prevent parsing explosion
  # StatementList following Perl semicolon rules
  # Semicolons required between statements, optional for last statement in block
    [ 'StatementList' => [], 0.1 ],    # Empty statement list (for empty blocks)
    [ 'StatementList' => ['Statement'], 1.0 ]
    ,    # Single statement (last in block, no semicolon needed)
    [ 'StatementList' => ['BlockStatement'], 0.95 ],    # Single block statement
    [ 'StatementList' => [ 'Statement', 'Semicolon', 'StatementList' ], 0.9 ]
    ,    # Statement + semicolon + more statements
    [ 'StatementList' => [ 'BlockStatement', 'StatementList' ], 0.8 ]
    ,    # Block + more statements
    [ 'StatementList' => [ 'LineStatement', 'StatementList' ], 0.7 ]
    ,    # Line + more

# BlockStatement - statements that contain blocks and don't need semicolons (following guacamole)
    [ 'BlockStatement' => ['ClassDecl'],  1.0 ],
    [ 'BlockStatement' => ['MethodDecl'], 1.0 ]
    ,    # Full method definitions with blocks
    [ 'BlockStatement' => ['SubroutineDecl'], 1.0 ],  # Subroutine declarations with blocks
    [ 'BlockStatement' => ['LoopStatement'], 1.0 ],  # Loop statements
    [ 'BlockStatement' => ['ConditionStatement'], 1.0 ],  # If/unless statements
    [ 'BlockStatement' => ['Comment'], 1.0 ],  # Comments can appear in block contexts

    # Conditional statements (if/unless/while/until) - following guacamole pattern
    [ 'ConditionStatement' => ['IfStatement'], 1.0 ],
    [ 'ConditionStatement' => ['UnlessStatement'], 1.0 ],
    [ 'ConditionStatement' => ['ElsifStatement'], 1.0 ],
    
    # If statement rules following guacamole ConditionIfExpr pattern
    [ 'IfStatement' => [ 'if', 'LParen', 'Expression', 'RParen', 'Block' ], 1.0 ],
    [ 'IfStatement' => [ 'if', 'LParen', 'Expression', 'RParen', 'Block', 'else', 'Block' ], 1.0 ],
    
    # Elsif statement
    [ 'ElsifStatement' => [ 'elsif', 'LParen', 'Expression', 'RParen', 'Block' ], 1.0 ],
    
    # Unless statement rules following guacamole ConditionUnlessExpr pattern
    [ 'UnlessStatement' => [ 'unless', 'LParen', 'Expression', 'RParen', 'Block' ], 1.0 ],
    [ 'UnlessStatement' => [ 'unless', 'Expression' ], 1.0 ],  # Postfix form
    
    # Block structure for conditional statements
    [ 'Block' => [ 'LBrace', 'StatementList', 'RBrace' ], 1.0 ],
    
    # Loop statements (following guacamole pattern)
    [ 'LoopStatement' => ['ForStatement'], 1.0 ],
    [ 'LoopStatement' => ['WhileStatement'], 1.0 ],
    
    # For statement - foreach style (for my $var (@list) { ... })
    [ 'ForStatement' => [ 'for', 'my', 'VariableBase', 'LParen', 'Expression', 'RParen', 'Block' ], 1.0 ],
    
    # While statement - while ( condition ) { ... }
    [ 'WhileStatement' => [ 'while', 'LParen', 'Expression', 'RParen', 'Block' ], 1.0 ],

    # Statements - chalk specific with expression support
    [ 'Statement' => ['UseStatement'], 1.0 ],
    [ 'Statement' => ['BlockLevelExpression'], 1.0 ],    # Block-level expression
    [ 'Statement' => ['EllipsisStatement'], 1.0 ],    # Ellipsis (...)
    [ 'Statement' => ['FieldDecl'],         1.0 ],    # Field declarations
    [ 'Statement' => ['VariableDecl'],      1.0 ],    # my/our/local declarations
    [ 'Statement' => ['ReturnStatement'],   1.0 ],    # Return statements
    [ 'Statement' => ['SubroutineDecl'],    1.0 ],    # Subroutine declarations
    [ 'Statement' => ['ConditionStatement'], 1.0 ],  # If/unless/while statements
    [ 'Statement' => [ 'ReturnStatement', 'StatementModifier' ], 1.0 ]
    ,                                                 # Return with modifier
    [ 'Statement' => [ 'BlockLevelExpression', 'StatementModifier' ], 1.0 ]
    ,                                                 # Expression with modifier

    # Line-terminated statements (don't require semicolons)
    [ 'LineStatement' => ['Shebang'], 1.0 ],
    [ 'LineStatement' => ['Comment'], 1.0 ],
    
    # Also allow comments directly as statements (higher accessibility)
    [ 'Statement' => ['Comment'], 1.0 ],

    # Class structure following guacamole PackageStatement pattern
    [
        'ClassDecl' => [ 'class', 'Identifier', 'Inheritance', 'Block' ],
        1.0
    ],
    [ 'ClassDecl' => [ 'class', 'Identifier', 'Block' ], 1.0 ],

# Method declarations are identical to subroutine declarations (following guacamole)
    [ 'MethodDecl' => [ 'method', 'Identifier', 'SubDefinition' ], 1.0 ],
    [ 'MethodDecl' => [ 'method', 'Identifier' ], 1.0 ],   # Forward declaration
    
    # Subroutine declarations
    [ 'SubroutineDecl' => [ 'sub', 'Identifier', 'SubDefinition' ], 1.0 ],
    [ 'SubroutineDecl' => [ 'sub', 'Identifier' ], 1.0 ],   # Forward declaration
    [ 'SubroutineDecl' => [ 'my', 'sub', 'Identifier', 'SubDefinition' ], 1.0 ],  # my sub
    [ 'SubroutineDecl' => [ 'my', 'sub', 'Identifier' ], 1.0 ],   # my sub forward decl

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
    [ 'VariableDecl' => [ 'my', 'Variable', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'my', 'Variable' ], 1.0 ],
    [ 'VariableDecl' => [ 'our', 'Variable', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'our', 'Variable' ], 1.0 ],
    [ 'VariableDecl' => [ 'local', 'Variable', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'local', 'Variable' ], 1.0 ],
    # Local can also be used with any lvalue expression (hash elements, array elements, etc.)
    [ 'VariableDecl' => [ 'local', 'Expression', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'state', 'Variable', '=', 'Expression' ], 1.0 ],
    [ 'VariableDecl' => [ 'state', 'Variable' ], 1.0 ],

  # Basic terminals - include newlines since comments/shebangs are line-oriented
  # TODO: Allow inline comments within parameter lists and expressions, not just after complete statements
    [ 'Shebang' => [qr/#!.*\n/] ],
    [ 'Comment' => [qr/#.*$/m] ],  # Whitespace already consumed by WS/WS_OPT

    # Ellipsis statement
    [ 'EllipsisStatement' => ['Ellipsis'] ],
    [ 'Ellipsis'          => ['...'] ],

    # Return statements - following Guacamole OpKeywordReturnExpr pattern
    [ 'ReturnStatement' => [ 'return', 'Expression' ], 1.0 ],
    [ 'ReturnStatement' => ['return'],                 0.1 ],

    # Statement modifiers - following Guacamole postfix patterns
    [ 'StatementModifier' => [ 'unless', 'Expression' ], 1.0 ],
    [ 'StatementModifier' => [ 'if',     'Expression' ], 1.0 ],

    # Guacamole UseStatement components
    [ 'OpKeywordUse' => ['use'] ],
    [ 'ClassIdent'   => ['SubNameExpr'] ],

    # SubNameExpr and VersionExpr definitions (simplified for chalk)
    [ 'SubNameExpr' => ['Identifier'] ],
    [ 'SubNameExpr' => [ 'Identifier', 'PackageSeparator', 'SubNameExpr' ] ],
    [ 'VersionExpr' => [qr/v?(?:\d+\.?){1,3}/] ],

    # QLikeValue - qw() expressions and regex patterns matching Guacamole pattern
    [ 'QLikeValue'         => [qr/qw\([^)]*\)/] ],
    [ 'QLikeValue'         => [qr{/[^/]*/[a-z]*}] ],  # /pattern/flags
    [ 'QLikeValue'         => [qr{qr/[^/]*/[a-z]*}] ],  # qr/pattern/flags
    # TODO: Handle escaped forward slashes \/ in regex patterns, but not needed for chalk
    [ 'FieldAttributeList' => ['FieldAttribute'] ],
    [ 'FieldAttributeList' => [ 'FieldAttribute', 'FieldAttributeList' ] ],
    [ 'FieldAttribute'     => [':param'] ],
    [ 'FieldAttribute'     => [':reader'] ],

# Expression hierarchy - Full Guacamole hierarchy with probabilities emulating action => ::first
    [ 'Expression' => ['ExprNameOr'], 0.8 ],
    [ 'ExprNameOr' => [ 'ExprNameOr', 'OpNameOr', 'ExprNameAnd' ], 0.8 ]
    ,                                             # First rule - higher prob
    [ 'ExprNameOr'  => ['ExprNameAnd'], 0.3 ],    # Fallback - lower prob
    
    # BlockLevelExpression - uses NonBraceExprAssignR to avoid brace ambiguity
    # TODO: Allow bare Expressions without an explicit return as the last statement in a block
    [ 'BlockLevelExpression' => ['BlockLevelExprNameOr'], 1.0 ],
    [ 'BlockLevelExprNameOr' => [ 'BlockLevelExprNameOr', 'OpNameOr', 'ExprNameAnd' ], 0.8 ],
    [ 'BlockLevelExprNameOr' => ['BlockLevelExprNameAnd'], 0.3 ],
    [ 'BlockLevelExprNameAnd' => [ 'BlockLevelExprNameAnd', 'OpNameAnd', 'ExprNameNot' ], 0.8 ],
    [ 'BlockLevelExprNameAnd' => ['BlockLevelExprNameNot'], 0.3 ],
    [ 'BlockLevelExprNameNot' => [ 'OpNameNot', 'ExprNameNot' ], 0.8 ],
    [ 'BlockLevelExprNameNot' => ['NonBraceExprAssignR'], 0.3 ],
    
    # NonBraceExprAssignR - avoids consuming braces as hash refs  
    [ 'NonBraceExprAssignR' => [ 'NonBraceExprCond0', 'OpAssign', 'ExprAssignR' ], 0.8 ],
    [ 'NonBraceExprAssignR' => ['NonBraceExprCondR'], 0.3 ],
    
    # NonBrace conditional expressions need to go through the full precedence chain
    [ 'NonBraceExprCondR' => [ 'NonBraceExprRange0', 'OpTriThen', 'ExprRangeR', 'OpTriElse', 'ExprCondR' ], 0.8 ],
    [ 'NonBraceExprCondR' => ['NonBraceExprRangeR'], 0.3 ],
    [ 'NonBraceExprCond0' => [ 'NonBraceExprRange0', 'OpTriThen', 'ExprRange0', 'OpTriElse', 'ExprCond0' ], 0.8 ],
    [ 'NonBraceExprCond0' => ['NonBraceExprRange0'], 0.3 ],
    
    # NonBrace range and other precedence levels 
    [ 'NonBraceExprRangeR' => [ 'NonBraceExprLogOr0', 'OpRange', 'ExprLogOrR' ], 0.8 ],
    [ 'NonBraceExprRangeR' => ['NonBraceExprLogOrR'], 0.3 ],
    [ 'NonBraceExprRange0' => [ 'NonBraceExprLogOr0', 'OpRange', 'ExprLogOr0' ], 0.8 ],
    [ 'NonBraceExprRange0' => ['NonBraceExprLogOr0'], 0.3 ],
    
    # Continue through precedence chain: LogOr -> LogAnd -> BinOr -> BinAnd -> Eq -> Neq -> Shift -> Add -> Mul -> Regex -> Power -> Inc -> Arrow -> Value
    [ 'NonBraceExprLogOrR' => ['NonBraceExprLogAndR'], 0.3 ],
    [ 'NonBraceExprLogOr0' => ['NonBraceExprLogAnd0'], 0.3 ],
    
    # NonBrace logical AND expressions  
    [ 'NonBraceExprLogAndR' => ['NonBraceExprBinOrR'], 0.3 ],
    [ 'NonBraceExprLogAnd0' => ['NonBraceExprBinOr0'], 0.3 ],
    
    # NonBrace binary OR expressions
    [ 'NonBraceExprBinOrR' => ['NonBraceExprBinAndR'], 0.3 ],
    [ 'NonBraceExprBinOr0' => ['NonBraceExprBinAnd0'], 0.3 ],
    
    # NonBrace binary AND expressions
    [ 'NonBraceExprBinAndR' => ['NonBraceExprEqR'], 0.3 ],
    [ 'NonBraceExprBinAnd0' => ['NonBraceExprEq0'], 0.3 ],
    
    # NonBrace equality expressions (this is what we were missing!)
    [ 'NonBraceExprEqR' => [ 'NonBraceExprNeq0', 'OpEqual', 'NonBraceExprNeqR' ], 0.8 ],
    [ 'NonBraceExprEqR' => ['NonBraceExprNeqR'], 0.3 ],
    [ 'NonBraceExprEq0' => [ 'NonBraceExprNeq0', 'OpEqual', 'NonBraceExprNeq0' ], 0.8 ],
    [ 'NonBraceExprEq0' => ['NonBraceExprNeq0'], 0.3 ],
    
    # NonBrace inequality expressions
    [ 'NonBraceExprNeqR' => ['NonBraceExprArrowR'], 0.3 ],
    [ 'NonBraceExprNeq0' => ['NonBraceExprArrow0'], 0.3 ],
    
    # NonBrace arrow expressions
    [ 'NonBraceExprArrowR' => [ 'NonBraceExprArrowU', 'OpArrow', 'ArrowRHS' ], 0.8 ],
    [ 'NonBraceExprArrowR' => ['NonBraceExprValueR'], 0.3 ],
    [ 'NonBraceExprArrow0' => [ 'NonBraceExprArrowU', 'OpArrow', 'ArrowRHS' ], 0.8 ],
    [ 'NonBraceExprArrow0' => ['NonBraceExprValue0'], 0.3 ],
    [ 'NonBraceExprArrowU' => [ 'NonBraceExprArrowU', 'OpArrow', 'ArrowRHS' ], 0.8 ],
    [ 'NonBraceExprArrowU' => ['NonBraceExprValueU'], 0.3 ],
    
    # NonBraceExprValue* rules
    [ 'NonBraceExprValueU' => ['NonBraceValue'], 1.0 ],
    [ 'NonBraceExprValueR' => ['NonBraceValue'], 0.8 ],
    [ 'NonBraceExprValueR' => ['OpListKeywordExpr'], 0.5 ],
    [ 'NonBraceExprValueR' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'NonBraceExprValueR' => ['OpUnaryKeywordExpr'], 0.5 ],
    [ 'NonBraceExprValue0' => ['NonBraceValue'], 0.8 ],
    [ 'NonBraceExprValue0' => ['OpUnaryKeywordExpr'], 0.5 ],
    [ 'NonBraceValue' => ['Variable'], 0.4 ],
    [ 'NonBraceValue' => ['Identifier'], 0.4 ],
    [ 'NonBraceValue' => ['Number'], 0.3 ],
    [ 'NonBraceValue' => ['UnaryExpression'], 0.3 ],
    [ 'NonBraceValue' => ['QuotedString'], 0.3 ],
    
    # Unary expressions (for things like -1e10, !$flag, etc.)
    [ 'UnaryExpression' => [ 'OpUnary', 'NonBraceValue' ], 1.0 ],
    [ 'NonBraceValue' => [ 'LParen', 'Expression', 'RParen' ], 0.3 ],
    [ 'NonBraceValue' => ['ArrayRef'], 0.3 ],
    [ 'NonBraceValue' => ['FunctionCall'], 0.3 ],
    [ 'NonBraceValue' => ['QLikeValue'], 0.8 ],
    [ 'NonBraceValue' => ['AtSymbol'], 0.3 ],
    [ 'NonBraceValue' => ['FieldDecl'], 0.3 ],
    
    [ 'ExprNameAnd' => [ 'ExprNameAnd', 'OpNameAnd', 'ExprNameNot' ], 0.8 ],
    [ 'ExprNameAnd' => ['ExprNameNot'],                               0.3 ],
    [ 'ExprNameNot' => [ 'OpNameNot', 'ExprNameNot' ],                0.8 ],
    [ 'ExprNameNot' => ['ExprComma'],                                 0.3 ],
    [ 'ExprComma'   => [ 'ExprAssignL', 'OpComma', 'ExprComma' ],     0.8 ]
    ,                                             # Comma list - higher prob
    [ 'ExprComma' => [ 'ExprAssignL', 'OpComma' ], 0.7 ], # Trailing comma
    [ 'ExprComma' => ['ExprAssignR'],              0.3 ], # Single item fallback
    [ 'ExprAssignR' => [ 'ExprCond0', 'OpAssign', 'ExprAssignR' ], 0.8 ],
    [ 'ExprAssignR' => ['ExprCondR'],                              0.3 ],
    [ 'ExprAssignL' => [ 'ExprCond0', 'OpAssign', 'ExprAssignL' ], 0.8 ],
    [ 'ExprAssignL' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'ExprAssignL' => ['ExprCondL'],                              0.3 ],
    [
        'ExprCondR' =>
          [ 'ExprRange0', 'OpTriThen', 'ExprRangeR', 'OpTriElse', 'ExprCondR' ],
        0.8
    ],
    [ 'ExprCondR' => ['ExprRangeR'], 0.3 ],
    [
        'ExprCondL' =>
          [ 'ExprRange0', 'OpTriThen', 'ExprRangeL', 'OpTriElse', 'ExprCondL' ],
        0.8
    ],
    [ 'ExprCondL' => ['ExprRangeL'], 0.3 ],
    [
        'ExprCond0' =>
          [ 'ExprRange0', 'OpTriThen', 'ExprRange0', 'OpTriElse', 'ExprCond0' ],
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

    [ 'ExprBinAndR' => [ 'ExprBinAnd0', 'OpBinAnd', 'ExprEqR' ], 0.8 ],
    [ 'ExprBinAndR' => ['ExprEqR'],                              0.3 ],
    [ 'ExprBinAndL' => [ 'ExprBinAnd0', 'OpBinAnd', 'ExprEqL' ], 0.8 ],
    [ 'ExprBinAndL' => ['ExprEqL'],                              0.3 ],
    [ 'ExprBinAnd0' => [ 'ExprBinAnd0', 'OpBinAnd', 'ExprEq0' ], 0.8 ],
    [ 'ExprBinAnd0' => ['ExprEq0'],                              0.3 ],

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
    [ 'ExprAddR' => [ 'ExprAddU', 'OpConcat', 'ExprMulR' ], 0.8 ],
    [ 'ExprAddR' => ['ExprMulR'],                        0.3 ],
    [ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ], 0.8 ],
    [ 'ExprAddL' => [ 'ExprAddU', 'OpConcat', 'ExprMulL' ], 0.8 ],
    [ 'ExprAddL' => ['ExprMulL'],                        0.3 ],
    [ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ], 0.8 ],
    [ 'ExprAdd0' => [ 'ExprAddU', 'OpConcat', 'ExprMul0' ], 0.8 ],
    [ 'ExprAdd0' => ['ExprMul0'],                        0.3 ],
    [ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ], 0.8 ],
    [ 'ExprAddU' => [ 'ExprAddU', 'OpConcat', 'ExprMulU' ], 0.8 ],
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
    [ 'ExprUnaryR' => ['ExprPowerR'],              0.3 ],
    [ 'ExprUnaryL' => [ 'OpUnary', 'ExprUnaryL' ], 0.8 ],
    [ 'ExprUnaryL' => ['ExprPowerL'],              0.3 ],
    [ 'ExprUnary0' => [ 'OpUnary', 'ExprUnary0' ], 0.8 ],
    [ 'ExprUnary0' => ['ExprPower0'],              0.3 ],
    [ 'ExprUnaryU' => [ 'OpUnary', 'ExprUnaryU' ], 0.8 ],
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
    [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS', 'ArrowChain' ], 0.8 ],
    [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS' ], 0.3 ],

    # Value rules - matching Guacamole ExprValue* rules exactly
    [ 'ExprValueU' => ['Value'], 1.0 ],
    [ 'ExprValue0' => ['Value'], 0.8 ],
    [ 'ExprValue0' => ['OpUnaryKeywordExpr'], 0.5 ],
    [ 'ExprValueL' => ['Value'], 0.8 ],
    [ 'ExprValueL' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'ExprValueL' => ['OpUnaryKeywordExpr'], 0.5 ],
    [ 'ExprValueR' => ['Value'], 0.8 ],
    [ 'ExprValueR' => ['OpListKeywordExpr'], 0.5 ],
    [ 'ExprValueR' => ['OpAssignKeywordExpr'], 0.5 ],
    [ 'ExprValueR' => ['OpUnaryKeywordExpr'], 0.5 ],

    # ArrowRHS - method calls, array/hash indexing, postfix dereferencing
    [ 'ArrowRHS' => ['Identifier'], 0.5 ],
    [ 'ArrowRHS' => [ 'Identifier', 'LParen', 'ParameterList', 'RParen' ], 0.4 ],
    [ 'ArrowRHS' => [ 'Identifier', 'LParen', 'RParen' ], 0.4 ],
    [ 'ArrowRHS' => [ 'LBracket', 'Expression', 'RBracket' ], 0.3 ],
    [ 'ArrowRHS' => [ 'LBrace',   'Expression', 'RBrace' ],   0.3 ],
    [ 'ArrowRHS' => ['PostfixDeref'], 0.3 ], # ->@*, ->%*, ->$* (postfix derefs)

    # Postfix dereferencing operators - atomic tokens
    [ 'PostfixDeref' => [qr/[@%\$]\*/] ],

    # Value rules - basic terminals needed for chalk
    [ 'Value' => ['Variable'],                         0.4 ],    # Now includes $hash{key}, @array[index]
    [ 'Value' => ['Identifier'],                       0.4 ],
    [ 'Value' => ['Number'],                           0.3 ],
    [ 'Value' => ['QuotedString'],                     0.3 ],
    [ 'Value' => [ 'LParen', 'Expression', 'RParen' ], 0.3 ],
    [ 'Value' => [ 'LParen', 'RParen' ],               0.3 ],  # Empty parentheses (empty list)
    [ 'Value' => ['ArrayRef'],                         0.3 ],
    [ 'Value' => ['HashRef'],                          0.3 ],
    [ 'Value' => ['FunctionCall'],                     0.3 ],
    [ 'Value' => ['UnaryKeywordExpression'],           0.3 ],    # grep/map/sort etc.
    [ 'Value' => ['ExpressionBlock'],                  0.3 ],    # { expr } blocks
    [ 'Value' => ['QLikeValue'],                       0.8 ],
    [ 'Value' => ['AtSymbol'],                         0.3 ],
    [ 'Value' => ['FieldDecl'],                        0.3 ],
    [ 'Value' => ['VariableDecl'],                     0.3 ],    # my $var = expr as expression

    # Function calls following Guacamole SubCall pattern
    [
        'FunctionCall' => [ 'Identifier', 'LParen', 'ParameterList', 'RParen' ],
        1.0
    ],    # func(args)
    [ 'FunctionCall' => [ 'Identifier', 'LParen', 'RParen' ], 1.0 ],    # func()
    
    # Expression block for grep/map/sort - supports both single expressions and statement lists
    [ 'ExpressionBlock' => [ 'LBrace', 'Expression', 'RBrace' ], 1.0 ],
    [ 'ExpressionBlock' => [ 'LBrace', 'StatementList', 'RBrace' ], 1.0 ],

    # Unary keyword expressions following guacamole.pm OpKeyword*Expr patterns
    [ 'UnaryKeywordExpression' => [ 'grep', 'ExpressionBlock', 'Expression' ], 1.0 ], # grep { ... } @list
    [ 'UnaryKeywordExpression' => [ 'grep', 'Expression' ], 1.0 ],                    # grep EXPR, @list
    [ 'UnaryKeywordExpression' => [ 'all', 'ExpressionBlock', 'Expression' ], 1.0 ],  # all { ... } @list
    [ 'UnaryKeywordExpression' => [ 'any', 'ExpressionBlock', 'Expression' ], 1.0 ],  # any { ... } @list
    [ 'UnaryKeywordExpression' => [ 'map', 'ExpressionBlock', 'Expression' ], 1.0 ],  # map { ... } @list
    [ 'UnaryKeywordExpression' => [ 'sort', 'ExpressionBlock', 'Expression' ], 1.0 ], # sort { ... } @list

    # Operators - basic ones needed for chalk
    [ 'OpComma'   => [qr/,|=>/] ],
    [ 'OpAssign'  => [qr/\/\/=|\|\|=|&&=|\.=|=/] ],    # Assignment operators
    [ 'OpArrow'   => ['->'] ],
    [ 'OpAdd'     => [qr/[+\-]/] ],
    [ 'OpConcat'  => ['.'] ],
    [ 'OpMulti'   => [qr/[*\/]/] ],
    [ 'OpLogOr'   => [qr/\|\||\/\//] ],    # Logical or and defined-or
    [ 'OpLogAnd'  => ['&&'] ],
    [ 'OpNameOr'  => ['or'] ],
    [ 'OpNameAnd' => ['and'] ],
    [ 'OpNameNot' => ['not'] ],
    [ 'OpTriThen' => ['?'] ],
    [ 'OpTriElse' => [':'] ],
    [ 'OpRange'   => ['..'] ],
    [ 'OpBinOr'   => [qr/[|^]/] ],
    [ 'OpBinAnd'  => ['&'] ],
    [ 'OpEqual'   => [qr/==|!=|<=>|eq|ne|cmp|isa/] ],
    [ 'OpInequal' => [qr/<=|>=|<|>|lt|gt|le|ge/] ],
    [ 'OpShift'   => [qr/<<|>>/] ],
    [ 'OpRegex'   => [qr/=~|!~/] ],
    [ 'OpUnary'   => [qr/[!~\\+\-]/] ],
    [ 'OpPower'   => ['**'] ],
    [ 'OpInc'     => [qr/\+\+|--/] ],

    # Terminal definitions for chalk - following guacamole.pm pattern
    # Variables with optional element sequences (subscripts)
    [ 'Variable' => [ 'VariableBase', 'ElemSeq0' ], 1.0 ],
    [ 'Variable' => [ 'VariableBase' ], 0.9 ],  # Lower priority for base case
    
    # Base variable patterns (without subscripts) - all sigils in one rule
    [ 'VariableBase' => [qr/[\$@%&*]\w+/] ],    # All variable types with sigils
    [ 'VariableBase' => [qr/\$#\w+/] ],         # Array length variables ($#array)
    
    # Scalar dereference patterns: @$var, %$var, *$var, &$var
    [ 'VariableBase' => [qr/[@%&*]\$\w+/] ],    # All dereference types
    
    # Complex dereference patterns from guacamole: @{ Expression }, %{ Expression }
    [ 'VariableBase' => [ '@{', 'Expression', '}' ], 1.0 ],   # Array deref: @{ expr }
    [ 'VariableBase' => [ '%{', 'Expression', '}' ], 1.0 ],   # Hash deref: %{ expr }
    [ 'VariableBase' => [ '@[', 'Expression', ']' ], 1.0 ],   # Array slice: @[ expr ]
    [ 'VariableBase' => [ '%[', 'Expression', ']' ], 1.0 ],   # Hash slice: %[ expr ]
    
    # Element sequences for subscripting
    [ 'ElemSeq0' => [], 0.1 ],  # Empty sequence (epsilon)
    [ 'ElemSeq0' => ['Element'], 1.0 ],
    [ 'ElemSeq0' => [ 'Element', 'ElemSeq0' ], 0.8 ],  # Multiple subscripts
    
    [ 'Element' => ['ArrayElem'], 1.0 ],
    [ 'Element' => ['HashElem'], 1.0 ],
    
    [ 'ArrayElem' => [ 'LBracket', 'Expression', 'RBracket' ], 1.0 ],
    [ 'HashElem' => [ 'LBrace', 'Expression', 'RBrace' ], 1.0 ],
    [ 'Identifier'   => [qr/[a-zA-Z_][a-zA-Z0-9_]*/] ],
    [ 'Number'       => [qr/\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/] ],
    [ 'QuotedString' => [qr/"[^"]*"|'[^']*'/] ],
    [ 'AtSymbol'     => ['@'] ],

    # Punctuation
    [ 'LParen'           => ['('] ],
    [ 'RParen'           => [')'] ],
    [ 'LBracket'         => ['['] ],
    [ 'RBracket'         => [']'] ],
    [ 'LBrace'           => ['{'] ],
    [ 'RBrace'           => ['}'] ],
    [ 'Semicolon'        => [';'] ],
    [ 'PackageSeparator' => ['::'] ],

    # ParameterList for method calls - simplified approach
    [ 'ParameterList' => ['HashElement'],                               1.0 ],
    [ 'ParameterList' => [ 'HashElement', 'OpComma', 'ParameterList' ], 1.0 ],
    [ 'ParameterList' => ['Expression'],                                1.0 ],
    [ 'ParameterList' => [ 'Expression', 'OpComma', 'ParameterList' ],  1.0 ],
    [ 'ParameterList' => [], 1.0 ],    # Empty parameter list

    # ArrayRef and HashRef
    [ 'ArrayRef' => [ 'LBracket', 'ExpressionList', 'RBracket' ], 1.0 ],
    [ 'ArrayRef' => [ 'LBracket', 'RBracket' ], 1.0 ],    # Empty array
    [ 'HashRef'  => [ 'LBrace', 'HashElementList', 'RBrace' ], 1.0 ],
    [ 'HashRef'  => [ 'LBrace', 'RBrace' ], 1.0 ],        # Empty hash

    [ 'ExpressionList' => ['Expression'],                                1.0 ],
    [ 'ExpressionList' => [ 'Expression', 'OpComma', 'ExpressionList' ], 1.0 ],

    [ 'HashElementList' => ['HashElement'], 1.0 ],
    [
        'HashElementList' => [ 'HashElement', 'OpComma', 'HashElementList' ],
        1.0
    ],

    [ 'HashElement' => [ 'Expression', 'OpComma', 'Expression' ], 1.0 ]
    ,                                                     # key => value

    # Keyword expressions - termination points for Expression chain
    # For chalk, we only need basic ones that could appear
    [ 'OpUnaryKeywordExpr' => [qr/return|last|next|redo/] ],
    
    [ 'OpAssignKeywordExpr' => [qr/goto|last/] ],
    
    [ 'OpListKeywordExpr' => [qr/print|warn|die/] ],

    # Whitespace rules (needed for auto_insert)
    [ 'WS_OPT' => [],         0.1 ],
    [ 'WS_OPT' => ['WS'],     1.0 ],
    [ 'WS'     => [qr/\s+/m], 1.0 ],
);
