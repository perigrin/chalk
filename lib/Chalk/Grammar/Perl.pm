# ABOUTME: Chalk grammar for parsing Modern Perl (5.42+) with class syntax
# ABOUTME: Based on Guacamole grammar structure with chalk-specific extensions
package Chalk::Grammar::Perl;
use 5.42.0;
use utf8;
use open qw(:std :utf8);
use experimental qw(class builtin keyword_any keyword_all defer);
use Exporter 'import';
use Chalk::Grammar;

our @EXPORT = qw($chalk_grammar);

our $chalk_grammar = Chalk::Grammar->build_grammar(
    auto_insert => ['WS_OPT'],
    rules       => [

        # Program structure - adapted from original chalk grammar
        [ 'Program' => ['StatementList'] ],
        [ 'Program' => [ 'WS_OPT',  'StatementList', 'WS_OPT' ] ],
        [ 'Program' => [ 'Shebang', 'StatementList', 'WS_OPT' ] ],

  # Statement lists -
  # Semicolons required between statements, optional for last statement in block
        [ 'StatementList' => [] ],
        [ 'StatementList' => ['Statement'] ],
        [ 'StatementList' => [ 'Statement', ';', 'StatementList' ] ],
        [ 'StatementList' => [ 'Statement', 'StatementList' ] ],

        # Base statements
        [ 'Statement' => [ 'Statement',  'StatementModifier' ] ],
        [ 'Statement' => [ 'QLikeValue', 'ElemSeq1' ] ], # qw"b"[0] as statement
        [ 'Statement' => ['AdjustBlock'] ],
        [ 'Statement' => ['BeginBlock'] ],
        [ 'Statement' => ['Block'] ],                    # Bare blocks
        [ 'Statement' => ['BlockStatement'] ],
        [ 'Statement' => ['BuiltinFunctionCall'] ],
        [ 'Statement' => ['ClassDecl'] ],
        [ 'Statement' => ['Comment'] ],
        [ 'Statement' => ['ControlFlowStatement'] ],     # next, last, redo
        [ 'Statement' => ['DieExpr'] ],   # Lower - prefer checking for modifier
        [ 'Statement' => ['EllipsisStatement'] ],    # Ellipsis (...)
        [ 'Statement' => ['EndBlock'] ],
        [ 'Statement' => ['EvalBlock'] ],            # eval { ... } blocks
        [ 'Statement' => ['Expression'] ],
        [ 'Statement' => ['FieldDecl'] ],            # Field declarations
        [ 'Statement' => ['FunctionCall'] ],   # Function calls with parentheses
        [ 'Statement' => ['LineStatement'] ],
        [ 'Statement' => ['ListOperatorCall'] ],    # calls sans-parentheses
        [ 'Statement' => ['LoopBlock'] ],           # Loop statements
        [ 'Statement' => ['MethodDecl'] ],
        [ 'Statement' => ['PackageDecl'] ],
        [ 'Statement' => ['PrintExpr'] ],
        [ 'Statement' => ['QLikeValue'] ],
        [ 'Statement' => ['RequireStatement'] ],    # Require statements
        [ 'Statement' => ['ReturnStatement'] ],     # Return statements
        [ 'Statement' => ['SubroutineDecl'] ],
        [ 'Statement' => ['UseStatement'] ],
        [ 'Statement' => ['VariableDecl'] ],        # my/our/local declarations
        [ 'Statement' => ['WarnExpr'] ],
        [ 'Statement' => ['IfStatement'] ],
        [ 'Statement' => ['UnlessStatement'] ],

        [ 'IfStatement'     => [ 'if',     'ConditionalStatement' ] ],
        [ 'UnlessStatement' => [ 'unless', 'ConditionalStatement' ] ],

        [ 'ConditionalStatement' => [ '(', 'Expression', ')', 'Block' ] ],
        [ 'ConditionalStatement' => [ 'ConditionalStatement', 'ElsifChain' ] ],
        [ 'ConditionalStatement' => [ 'ConditionalStatement', 'ElseBlock' ] ],

        [ 'ElsifChain' => [ 'elsif', 'ConditionalStatement' ] ],

        [ 'ElseBlock' => [ 'else', 'Block' ] ],

        # Block structure for conditional statements
        [ 'Block' => [ '{', 'StatementList', '}' ] ],
        [ 'Block' => [ '{', '}' ] ],

        # ADJUST block for class initialization
        [ 'AdjustBlock' => [ 'ADJUST', 'Block' ] ],
        [ 'BeginBlock'  => [ 'BEGIN',  'Block' ] ],
        [ 'EndBlock'    => [ 'END',    'Block' ] ],

        # Loop statements (following guacamole pattern)
        [ 'LoopBlock' => ['ForStatement'] ],
        [ 'LoopBlock' => ['WhileStatement'] ],

        # For statement - C-style and foreach style variations
        # C-style for loops: for (init; condition; increment) { ... }
        [
            'ForStatement' => [
                qr/for(?:each)?/, '(', 'Expression', ';',
                'Expression',     ';', 'Expression', ')',
                'Block'
            ]
        ],
        [
            'ForStatement' => [
                qr/for(?:each)?/, '(', ';', 'Expression', ';', 'Expression',
                ')', 'Block'
            ]
        ],    # No init
        [
            'ForStatement' => [
                qr/for(?:each)?/, '(', 'Expression', ';', ';', 'Expression',
                ')', 'Block'
            ]
        ],    # No condition
        [
            'ForStatement' => [
                qr/for(?:each)?/, '(', 'Expression', ';',
                'Expression',     ';', ')',          'Block'
            ]
        ],    # No increment
        [ 'ForStatement' => [ qr/for(?:each)?/, '(', ';', ';', ')', 'Block' ] ]
        ,     # Infinite loop: for (;;)

        # Foreach style variations
        [
            'ForStatement' => [
                qr/for(?:each)?/, 'VariableDecl',
                '(',              'Expression',
                ')',              'Block'
            ]
        ],
        [
            'ForStatement' =>
              [ qr/for(?:each)?/, '(', 'Expression', ')', 'Block' ]
        ],

        # While statement - while ( condition ) { ... }
        [ 'WhileStatement' => [ 'while', '(', 'Expression', ')', 'Block' ] ],

        # Line-terminated statements (don't require semicolons)
        [ 'LineStatement' => ['Comment'] ],

        # Class structure following guacamole PackageStatement pattern
        [
            'ClassDecl' =>
              [ 'class', 'QualifiedIdentifier', 'Inheritance', 'Block' ],
        ],
        [ 'ClassDecl' => [ 'class', 'QualifiedIdentifier', 'Block' ] ],
        [ 'ClassDecl' => [ 'class', 'Identifier', 'Inheritance', 'Block' ] ],
        [ 'ClassDecl' => [ 'class', 'Identifier', 'Block' ] ],

        # Package declarations (traditional Perl OO)
        # With block - no semicolon needed (BlockStatement)
        [ 'PackageDecl' => [ 'package', 'QualifiedIdentifier', 'Block' ] ],
        [ 'PackageDecl' => [ 'package', 'Identifier',          'Block' ] ],

# Without block - these need semicolons, so they're Statements not BlockStatements
        [ 'PackageDecl' => [ 'package', 'QualifiedIdentifier' ] ],
        [ 'PackageDecl' => [ 'package', 'Identifier' ] ],

# Method declarations are identical to subroutine declarations (following guacamole)
        [ 'MethodDecl' => [ 'method', 'Identifier', 'SubDefinition' ] ],
        [ 'MethodDecl' => [ 'method', 'Identifier' ] ],    # Forward declaration

        # Subroutine declarations
        [ 'SubroutineDecl' => [ 'sub', 'Identifier', 'SubDefinition' ] ],
        [ 'SubroutineDecl' => [ 'sub', 'Identifier' ] ],   # Forward declaration
        [ 'SubroutineDecl' => [ 'my',  'sub', 'Identifier', 'SubDefinition' ] ]
        ,                                                  # my sub
        [ 'SubroutineDecl' => [ 'my', 'sub', 'Identifier' ] ]
        ,                                                  # my sub forward decl

        # SubDefinition from guacamole grammar
        [ 'SubDefinition' => [ 'SubSigsDefinition', 'Block' ] ],
        [ 'SubDefinition' => ['Block'] ],

        # SubSigsDefinition is just a parenthetical expression
        [ 'SubSigsDefinition' => [ '(', 'Expression', ')' ] ],
        [
            'SubSigsDefinition' => [
                '(', qr/\(\s*(?:\\\[[\$\@\%\&\*]+\s*\]|[\$\@\%\&\*\_;\s])*?\)/,
                ')'
            ]
        ],
        [ 'SubSigsDefinition' => [ '(', ')' ] ],

        # Anonymous subroutines as values - with optional attributes
        [ 'Value' => [ 'sub', 'SubAttribute', 'SubDefinition' ] ]
        ,                                             # sub :lvalue { ... }
        [ 'Value' => [ 'sub', 'SubDefinition' ] ],    # sub { ... }

        # Subroutine attributes
        [ 'SubAttribute' => [qr/:[a-zA-Z_]\w*/] ]
        ,    # :lvalue, :method, :prototype(...), etc.

 # UseStatement - reordered with higher probabilities for more specific patterns
 # to reduce parsing ambiguity and prevent exponential explosion
        [
            'UseStatement' =>
              [ 'OpKeywordUse', 'ClassIdent', 'VersionExpr', 'Expression' ],
            0.9
        ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent', 'Expression' ] ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'VersionExpr' ] ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent', 'VersionExpr' ] ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent' ] ],

        [ 'Inheritance' => [ ':isa(', 'ClassIdent', ')' ] ],

      # Field declarations - simplified like Guacamole Modifier Variable pattern
        [ 'FieldDecl' => [ 'field', 'Variable', 'FieldAttributeList' ] ],
        [ 'FieldDecl' => [ 'field', 'Variable' ] ],

        # Variable declarations - my/our/local/state
        [ 'VariableDecl' => [ 'my',    'Variable', '=', 'Expression' ] ],
        [ 'VariableDecl' => [ 'my',    'Variable' ] ],
        [ 'VariableDecl' => [ 'our',   'Variable', '=', 'Expression' ] ],
        [ 'VariableDecl' => [ 'our',   'Variable' ] ],
        [ 'VariableDecl' => [ 'local', 'Variable', '=', 'Expression' ] ],
        [ 'VariableDecl' => [ 'local', 'Variable' ] ],

# Local can also be used with any lvalue expression (hash elements, array elements, etc.)
        [ 'VariableDecl' => [ 'local', 'Expression', '=', 'Expression' ] ],
        [ 'VariableDecl' => [ 'state', 'Variable',   '=', 'Expression' ] ],
        [ 'VariableDecl' => [ 'state', 'Variable' ] ],

# Basic terminals - include newlines since comments/shebangs are line-oriented
# TODO: Allow inline comments within parameter lists and expressions, not just after complete statements
        [ 'Shebang' => [qr/#!.*$/m] ],
        [ 'Comment' => [qr/#.*$/m] ], # Whitespace already consumed by WS/WS_OPT

        # Ellipsis statement
        [ 'EllipsisStatement' => ['Ellipsis'] ],
        [ 'Ellipsis'          => ['...'] ],

        # Return statements - following Guacamole OpKeywordReturnExpr pattern
        [ 'ReturnStatement' => [ 'return', 'Expression' ] ],
        [ 'ReturnStatement' => ['return'] ],

        [ 'ControlFlowStatement' => ['next'] ],
        [ 'ControlFlowStatement' => ['last'] ],
        [ 'ControlFlowStatement' => ['redo'] ],
        [ 'ControlFlowStatement' => [ 'next', 'Identifier' ] ],    # next LABEL
        [ 'ControlFlowStatement' => [ 'last', 'Identifier' ] ],    # last LABEL
        [ 'ControlFlowStatement' => [ 'redo', 'Identifier' ] ],    # redo LABEL

        # Require statements - similar to UseStatement but simpler
        [ 'RequireStatement' => [ 'require', 'Expression' ] ],

        # Statement modifiers - following Guacamole postfix patterns
        [ 'StatementModifier' => [ 'unless',  'Expression' ] ],
        [ 'StatementModifier' => [ 'if',      'Expression' ] ],
        [ 'StatementModifier' => [ 'while',   'Expression' ] ],
        [ 'StatementModifier' => [ 'until',   'Expression' ] ],
        [ 'StatementModifier' => [ 'for',     'Expression' ] ],
        [ 'StatementModifier' => [ 'foreach', 'Expression' ] ],
        [ 'StatementModifier' => [ 'when',    'Expression' ] ],

        # Guacamole UseStatement components
        [ 'OpKeywordUse' => ['use'] ],
        [ 'ClassIdent'   => ['SubNameExpr'] ],

        # SubNameExpr and VersionExpr definitions (simplified for chalk)
        [ 'SubNameExpr' => ['Identifier'] ],
        [
            'SubNameExpr' => [ 'Identifier', 'PackageSeparator', 'SubNameExpr' ]
        ],
        [ 'VersionExpr' => [qr/v?(?:\d+\.?){1,3}/] ],

  # QLikeValue - qw() expressions and regex patterns matching Guacamole pattern
  # qw operator split like q/qq to allow comments between operator and delimiter
        [ 'QLikeValue' => [ 'QWOp', 'QDelimited' ] ],    # qw with any delimiter
         # m operator split like q/qq/qw to allow comments between operator and delimiter
        [ 'QLikeValue' => [ 'MOp', 'MDelimited' ] ]
        ,    # m with any delimiter + optional flags
         # qr operator split like m to allow comments between operator and delimiter
        [ 'QLikeValue' => [ 'QROp', 'MDelimited' ] ]
        ,    # qr with any delimiter + optional flags
         # s operator with specific delimiters - specific patterns to avoid greedy QDelimited matching
         # Higher probabilities (2.0) to prefer these over the general SOp + QDelimited + MDelimited rule
        [
            'QLikeValue' =>
              [qr{s/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[msixpodualgcern]*}]
        ],    # s/search/replace/flags
        [
            'QLikeValue' =>
              [qr{s\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[msixpodualgcern]*}]
        ],    # s|search|replace|flags
        [
            'QLikeValue' =>
              [qr{s!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![msixpodualgcern]*}]
        ],    # s!search!replace!flags
        [
            'QLikeValue' =>
              [qr{s#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[msixpodualgcern]*}]
        ],    # s#search#replace#flags
         # s operator split to allow comments - works with paired delimiters like s[...][...] (search, replacement)
        [ 'QLikeValue' => [ 'SOp', 'QDelimited', 'MDelimited' ] ]
        ,   # s with delimiters + optional flags on replacement (lower priority)
         # tr and y operators with specific delimiters - similar to s/// patterns
         # Higher probabilities (2.0) to prefer these over the general TROp/YOp + QDelimited + QDelimited rule
        [ 'QLikeValue' => [qr{tr/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[cdsr]*}] ]
        ,    # tr/search/replace/flags
        [
            'QLikeValue' =>
              [qr{tr\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[cdsr]*}]
        ],    # tr|search|replace|flags
        [ 'QLikeValue' => [qr{tr!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![cdsr]*}] ]
        ,     # tr!search!replace!flags
        [ 'QLikeValue' => [qr{tr#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[cdsr]*}] ]
        ,     # tr#search#replace#flags
        [ 'QLikeValue' => [qr{y/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[cdsr]*}] ]
        ,     # y/search/replace/flags
        [
            'QLikeValue' => [qr{y\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[cdsr]*}]
        ],    # y|search|replace|flags
        [ 'QLikeValue' => [qr{y!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![cdsr]*}] ]
        ,     # y!search!replace!flags
        [ 'QLikeValue' => [qr{y#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[cdsr]*}] ]
        ,     # y#search#replace#flags
         # tr/y operators split to allow comments - works with paired delimiters like tr[...][...] (search, replacement)
        [ 'QLikeValue' => [ 'TROp', 'QDelimited', 'QDelimited' ] ]
        ,    # tr with delimiters + optional flags
        [ 'QLikeValue' => [ 'YOp', 'QDelimited', 'QDelimited' ] ]
        ,    # y with delimiters + optional flags
        [ 'QLikeValue' => [qr/\/((?:[^\/\\]|\\.)*)\/[gimsxoac]*/] ]
        ,                                     # /.../flags with escapes
        [ 'QLikeValue' => [qr/`[^`]*`/] ],    # `backticks`

        [ 'FieldAttributeList' => ['FieldAttribute'] ],
        [ 'FieldAttributeList' => [ 'FieldAttribute', 'FieldAttributeList' ] ],
        [ 'FieldAttribute'     => [':param'] ],
        [ 'FieldAttribute'     => [':reader'] ],

# Expression hierarchy - Full Guacamole hierarchy with probabilities emulating action => ::first
        [ 'Expression' => ['ExprNameOr'] ],
        [ 'ExprNameOr' => [ 'ExprNameOr', 'OpNameOr', 'ExprNameAnd' ] ]
        ,                                       # First rule - higher prob
        [ 'ExprNameOr' => ['ExprNameAnd'] ],    # Fallback - lower prob

     # BlockLevelExpression - simplified to use regular Expression hierarchy
     # Experiment: Remove BlockLevel* intermediates to reduce parser state
     # Previously used ExprAssignR to avoid brace ambiguity, but testing shows
     # the regular Expression hierarchy handles this correctly via probabilities
        [ 'BlockLevelExpression' => ['Expression'] ],

        # ExprAssignR - avoids consuming braces as hash refs
        [
            'ExprAssignR' => [ 'ExprCond0', 'OpAssign', 'ExprAssignR' ],
            0.8
        ],
        [ 'ExprAssignR' => ['ExprCondR'] ],

 # NonBrace conditional expressions need to go through the full precedence chain
        [
            'ExprCondR' => [
                'ExprRange0', 'OpTriThen', 'ExprRangeR', 'OpTriElse',
                'ExprCondR'
            ],
            0.8
        ],
        [ 'ExprCondR' => ['ExprRangeR'] ],
        [
            'ExprCond0' => [
                'ExprRange0', 'OpTriThen', 'ExprRange0', 'OpTriElse',
                'ExprCond0'
            ],
            0.8
        ],
        [ 'ExprCond0' => ['ExprRange0'] ],

        # NonBrace range and other precedence levels
        [
            'ExprRangeR' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrR' ],
            0.8
        ],
        [ 'ExprRangeR' => ['ExprLogOrR'] ],
        [
            'ExprRange0' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOr0' ],
            0.8
        ],
        [ 'ExprRange0' => ['ExprLogOr0'] ],

# Continue through precedence chain: LogOr -> LogAnd -> BinOr -> BinAnd -> Eq -> Neq -> Shift -> Add -> Mul -> Regex -> Power -> Inc -> Arrow -> Value
        [ 'ExprLogOrR' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndR' ] ],
        [ 'ExprLogOrR' => ['ExprLogAndR'] ],
        [ 'ExprLogOr0' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAnd0' ] ],
        [ 'ExprLogOr0' => ['ExprLogAnd0'] ],

        # NonBrace logical AND expressions
        [ 'ExprLogAndR' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOrR' ] ],
        [ 'ExprLogAndR' => ['ExprBinOrR'] ],
        [ 'ExprLogAnd0' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOr0' ] ],
        [ 'ExprLogAnd0' => ['ExprBinOr0'] ],

        # NonBrace binary OR expressions
        [ 'ExprBinOrR' => ['ExprBinAndR'] ],
        [ 'ExprBinOr0' => ['ExprBinAnd0'] ],

        # NonBrace binary AND expressions
        [ 'ExprBinAndR' => ['ExprEqR'] ],
        [ 'ExprBinAnd0' => ['ExprEq0'] ],

        # NonBrace equality expressions (this is what we were missing!)
        [
            'ExprEqR' => [ 'ExprNeq0', 'OpEqual', 'ExprNeqR' ],
            0.8
        ],
        [ 'ExprEqR' => ['ExprNeqR'] ],
        [
            'ExprEq0' => [ 'ExprNeq0', 'OpEqual', 'ExprNeq0' ],
            0.8
        ],
        [ 'ExprEq0' => ['ExprNeq0'] ],

        # NonBrace inequality expressions
        [ 'ExprNeqR' => [ 'ExprShift0', 'OpInequal', 'ExprShiftR' ] ],
        [ 'ExprNeqR' => ['ExprShiftR'] ],
        [ 'ExprNeq0' => [ 'ExprShift0', 'OpInequal', 'ExprShift0' ] ],
        [ 'ExprNeq0' => ['ExprShift0'] ],

        # NonBrace shift expressions
        [ 'ExprShiftR' => [ 'ExprShiftU', 'OpShift', 'ExprAddR' ] ],
        [ 'ExprShiftR' => ['ExprAddR'] ],
        [ 'ExprShift0' => [ 'ExprShiftU', 'OpShift', 'ExprAdd0' ] ],
        [ 'ExprShift0' => ['ExprAdd0'] ],
        [ 'ExprShiftU' => [ 'ExprShiftU', 'OpShift', 'ExprAddU' ] ],
        [ 'ExprShiftU' => ['ExprAddU'] ],

        # NonBrace addition expressions
        [ 'ExprAddR' => [ 'ExprAddU', 'OpAdd', 'ExprMulR' ] ],
        [ 'ExprAddR' => [ 'ExprAddU', '.',     'ExprMulR' ] ],
        [ 'ExprAddR' => ['ExprMulR'] ],
        [ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ] ],
        [ 'ExprAdd0' => [ 'ExprAddU', '.',     'ExprMul0' ] ],
        [ 'ExprAdd0' => ['ExprMul0'] ],
        [ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ] ],
        [ 'ExprAddU' => [ 'ExprAddU', '.',     'ExprMulU' ] ],
        [ 'ExprAddU' => ['ExprMulU'] ],

        # NonBrace multiplication expressions
        [ 'ExprMulR' => [ 'ExprMulU', 'OpMulti', 'ExprRegexR' ] ],
        [ 'ExprMulR' => ['ExprRegexR'] ],
        [ 'ExprMul0' => [ 'ExprMulU', 'OpMulti', 'ExprRegex0' ] ],
        [ 'ExprMul0' => ['ExprRegex0'] ],
        [ 'ExprMulU' => [ 'ExprMulU', 'OpMulti', 'ExprRegexU' ] ],
        [ 'ExprMulU' => ['ExprRegexU'] ],

        # NonBrace regex expressions - ADD OpRegex support for print statements
        [ 'ExprRegexR' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryR' ] ],
        [ 'ExprRegexR' => ['ExprUnaryR'] ],
        [ 'ExprRegex0' => [ 'ExprRegexU', 'OpRegex', 'ExprUnary0' ] ],
        [ 'ExprRegex0' => ['ExprUnary0'] ],
        [ 'ExprRegexU' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryU' ] ],
        [ 'ExprRegexU' => ['ExprUnaryU'] ],

        # NonBrace unary expressions
        [ 'ExprUnaryR' => [ 'OpUnary',    'ExprUnaryR' ] ],
        [ 'ExprUnaryR' => [ 'FileTestOp', 'ExprUnaryR' ] ],
        [ 'ExprUnaryR' => ['ExprPowerR'] ],
        [ 'ExprUnary0' => [ 'OpUnary',    'ExprUnary0' ] ],
        [ 'ExprUnary0' => [ 'FileTestOp', 'ExprUnary0' ] ],
        [ 'ExprUnary0' => ['ExprPower0'] ],
        [ 'ExprUnaryU' => [ 'OpUnary',    'ExprUnaryU' ] ],
        [ 'ExprUnaryU' => [ 'FileTestOp', 'ExprUnaryU' ] ],
        [ 'ExprUnaryU' => ['ExprPowerU'] ],

        # NonBrace power expressions
        [ 'ExprPowerR' => [ 'ExprIncU', 'OpPower', 'ExprUnaryR' ] ],
        [ 'ExprPowerR' => ['ExprIncR'] ],
        [ 'ExprPower0' => [ 'ExprIncU', 'OpPower', 'ExprUnary0' ] ],
        [ 'ExprPower0' => ['ExprInc0'] ],
        [ 'ExprPowerU' => [ 'ExprIncU', 'OpPower', 'ExprUnaryU' ] ],
        [ 'ExprPowerU' => ['ExprIncU'] ],

        # NonBrace increment expressions
        [ 'ExprIncR' => [ 'OpInc',    'ExprIncR' ] ],
        [ 'ExprIncR' => [ 'ExprIncR', 'OpInc' ] ],
        [ 'ExprIncR' => ['ExprArrowR'] ],
        [ 'ExprInc0' => [ 'OpInc',    'ExprInc0' ] ],
        [ 'ExprInc0' => [ 'ExprInc0', 'OpInc' ] ],
        [ 'ExprInc0' => ['ExprArrow0'] ],
        [ 'ExprIncU' => [ 'OpInc',    'ExprIncU' ] ],
        [ 'ExprIncU' => [ 'ExprIncU', 'OpInc' ] ],
        [ 'ExprIncU' => ['ExprArrowU'] ],

     # NonBrace arrow expressions - use ArrowChain like regular ExprArrow* rules
        [ 'ExprArrowR' => [ 'ExprValueUR', 'ArrowChain' ] ],
        [ 'ExprArrowR' => ['ExprValueUR'] ],
        [ 'ExprArrow0' => [ 'ExprValueU0', 'ArrowChain' ] ],
        [ 'ExprArrow0' => ['ExprValueU0'] ],
        [ 'ExprArrowU' => [ 'ExprValueUU', 'ArrowChain' ] ],
        [ 'ExprArrowU' => ['ExprValueUU'] ],

        # ExprValueU* rules
        [ 'ExprValueUU' => ['Value'] ],
        [ 'ExprValueUR' => ['Value'] ],
        [ 'ExprValueUR' => ['BuiltinFunctionCall'] ]
        ,    # Built-in functions for or/and contexts
        [ 'ExprValueUR' => ['OpListKeywordExpr'] ],
        [ 'ExprValueUR' => ['OpAssignKeywordExpr'] ],
        [ 'ExprValueUR' => ['OpUnaryKeywordExpr'] ],
        [ 'ExprValueU0' => ['Value'] ],
        [ 'ExprValueU0' => ['OpUnaryKeywordExpr'] ],
        [ 'Value'       => ['Variable'] ],
        [ 'Value' => ['QualifiedIdentifier'] ],    # Foo::Bar for method calls
        [ 'Value' => ['Identifier'] ],      # Plain identifiers (lower priority)
        [ 'Value' => ['Number'] ],
        [ 'Value' => ['UnaryExpression'] ],
        [ 'Value' => ['QuotedString'] ],
        [ 'Value' => ['Ellipsis'] ],        # Yada-yada operator ... as value

        # Unary expressions (for things like -1e10, !$flag, -d 't', etc.)
        [ 'UnaryExpression' => [ 'OpUnary',    'Value' ] ],
        [ 'UnaryExpression' => [ 'FileTestOp', 'Value' ] ],
        [ 'Value'           => [ '(',          'Expression', ')', 'ElemSeq1' ] ]
        ,    # (expr)[0] - subscripted parenthesized expression
        [ 'Value' => [ '(', 'Expression', ')' ] ],
        [ 'Value' => ['ArrayRef'] ],
        [ 'Value' => ['HashRef'] ],                # Allow hash refs in push/etc
        [ 'Value' => ['EvalBlock'] ]
        ,    # eval { } - keyword disambiguates from bare block
        [ 'Value' => ['FunctionCall'] ],
        [ 'Value' => [ 'QLikeValue', 'ElemSeq1' ] ]
        ,    # qw"b"[0], etc. in expressions
        [ 'Value' => ['QLikeValue'] ],
        [ 'Value' => ['Diamond'] ],      # <$fh>, <STDIN>, <> constructs
        [ 'Value' => ['@'] ],
        [ 'Value' => ['FieldDecl'] ],

        [ 'ExprNameAnd' => [ 'ExprNameAnd', 'OpNameAnd', 'ExprNameNot' ] ],
        [ 'ExprNameAnd' => ['ExprNameNot'] ],
        [ 'ExprNameNot' => [ 'OpNameNot', 'ExprNameNot' ] ],
        [ 'ExprNameNot' => ['ExprComma'] ],
        [ 'ExprComma'   => [ 'ExprAssignL', 'OpComma', 'ExprComma' ] ]
        ,                                # Comma list - higher prob
        [ 'ExprComma' => [ 'ExprAssignL', 'OpComma' ] ],  # Trailing comma
        [ 'ExprComma' => ['ExprAssignR'] ],               # Single item fallback
        [ 'ExprAssignR' => [ 'ExprCond0', 'OpAssign', 'ExprAssignR' ] ],
        [ 'ExprAssignR' => ['ExprCondR'] ],
        [ 'ExprAssignL' => [ 'ExprCond0', 'OpAssign', 'ExprAssignL' ] ],
        [ 'ExprAssignL' => ['OpAssignKeywordExpr'] ],
        [ 'ExprAssignL' => ['ExprCondL'] ],
        [
            'ExprCondR' =>
              [ 'ExprRange0', '?', 'ExprRangeR', ':', 'ExprCondR' ],
            0.8
        ],
        [ 'ExprCondR' => ['ExprRangeR'] ],
        [
            'ExprCondL' =>
              [ 'ExprRange0', '?', 'ExprRangeL', ':', 'ExprCondL' ],
            0.8
        ],
        [ 'ExprCondL' => ['ExprRangeL'] ],
        [
            'ExprCond0' =>
              [ 'ExprRange0', '?', 'ExprRange0', ':', 'ExprCond0' ],
            0.8
        ],
        [ 'ExprCond0'  => ['ExprRange0'] ],
        [ 'ExprRangeR' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrR' ] ],
        [ 'ExprRangeR' => ['ExprLogOrR'] ],
        [ 'ExprRangeL' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrL' ] ],
        [ 'ExprRangeL' => ['ExprLogOrL'] ],
        [ 'ExprRange0' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOr0' ] ],
        [ 'ExprRange0' => ['ExprLogOr0'] ],
        [ 'ExprLogOrR' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndR' ] ],
        [ 'ExprLogOrR' => ['ExprLogAndR'] ],
        [ 'ExprLogOrL' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAndL' ] ],
        [ 'ExprLogOrL' => ['ExprLogAndL'] ],
        [ 'ExprLogOr0' => [ 'ExprLogOr0', 'OpLogOr', 'ExprLogAnd0' ] ],
        [ 'ExprLogOr0' => ['ExprLogAnd0'] ],

        # Continue the chain down to Value
        [ 'ExprLogAndR' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOrR' ] ],
        [ 'ExprLogAndR' => [ 'ExprBinOrR',  'Comment' ] ]
        ,    # Expression with trailing comment
        [ 'ExprLogAndR' => ['ExprBinOrR'] ],
        [ 'ExprLogAndL' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOrL' ] ],
        [ 'ExprLogAndL' => ['ExprBinOrL'] ],
        [ 'ExprLogAnd0' => [ 'ExprLogAnd0', 'OpLogAnd', 'ExprBinOr0' ] ],
        [ 'ExprLogAnd0' => ['ExprBinOr0'] ],

        [ 'ExprBinOrR' => [ 'ExprBinOr0', 'OpBinOr', 'ExprBinAndR' ] ],
        [ 'ExprBinOrR' => ['ExprBinAndR'] ],
        [ 'ExprBinOrL' => [ 'ExprBinOr0', 'OpBinOr', 'ExprBinAndL' ] ],
        [ 'ExprBinOrL' => ['ExprBinAndL'] ],
        [ 'ExprBinOr0' => [ 'ExprBinOr0', 'OpBinOr', 'ExprBinAnd0' ] ],
        [ 'ExprBinOr0' => ['ExprBinAnd0'] ],

        [ 'ExprBinAndR' => [ 'ExprBinAnd0', '&', 'ExprEqR' ] ],
        [ 'ExprBinAndR' => ['ExprEqR'] ],
        [ 'ExprBinAndL' => [ 'ExprBinAnd0', '&', 'ExprEqL' ] ],
        [ 'ExprBinAndL' => ['ExprEqL'] ],
        [ 'ExprBinAnd0' => [ 'ExprBinAnd0', '&', 'ExprEq0' ] ],
        [ 'ExprBinAnd0' => ['ExprEq0'] ],

        # Complete the missing expression hierarchy levels
        [ 'ExprEqR' => [ 'ExprNeq0', 'OpEqual', 'ExprNeqR' ] ],
        [ 'ExprEqR' => ['ExprNeqR'] ],
        [ 'ExprEqL' => [ 'ExprNeq0', 'OpEqual', 'ExprNeqL' ] ],
        [ 'ExprEqL' => ['ExprNeqL'] ],
        [ 'ExprEq0' => [ 'ExprNeq0', 'OpEqual', 'ExprNeq0' ] ],
        [ 'ExprEq0' => ['ExprNeq0'] ],

        [ 'ExprNeqR' => [ 'ExprShift0', 'OpInequal', 'ExprShiftR' ] ],
        [ 'ExprNeqR' => ['ExprShiftR'] ],
        [ 'ExprNeqL' => [ 'ExprShift0', 'OpInequal', 'ExprShiftL' ] ],
        [ 'ExprNeqL' => ['ExprShiftL'] ],
        [ 'ExprNeq0' => [ 'ExprShift0', 'OpInequal', 'ExprShift0' ] ],
        [ 'ExprNeq0' => ['ExprShift0'] ],

        [ 'ExprShiftR' => [ 'ExprShiftU', 'OpShift', 'ExprAddR' ] ],
        [ 'ExprShiftR' => ['ExprAddR'] ],
        [ 'ExprShiftL' => [ 'ExprShiftU', 'OpShift', 'ExprAddL' ] ],
        [ 'ExprShiftL' => ['ExprAddL'] ],
        [ 'ExprShift0' => [ 'ExprShiftU', 'OpShift', 'ExprAdd0' ] ],
        [ 'ExprShift0' => ['ExprAdd0'] ],
        [ 'ExprShiftU' => [ 'ExprShiftU', 'OpShift', 'ExprAddU' ] ],
        [ 'ExprShiftU' => ['ExprAddU'] ],

        [ 'ExprAddR' => [ 'ExprAddU', 'OpAdd', 'ExprMulR' ] ],
        [ 'ExprAddR' => [ 'ExprAddU', '.',     'ExprMulR' ] ],
        [ 'ExprAddR' => ['ExprMulR'] ],
        [ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ] ],
        [ 'ExprAddL' => [ 'ExprAddU', '.',     'ExprMulL' ] ],
        [ 'ExprAddL' => ['ExprMulL'] ],
        [ 'ExprAdd0' => [ 'ExprAddU', 'OpAdd', 'ExprMul0' ] ],
        [ 'ExprAdd0' => [ 'ExprAddU', '.',     'ExprMul0' ] ],
        [ 'ExprAdd0' => ['ExprMul0'] ],
        [ 'ExprAddU' => [ 'ExprAddU', 'OpAdd', 'ExprMulU' ] ],
        [ 'ExprAddU' => [ 'ExprAddU', '.',     'ExprMulU' ] ],
        [ 'ExprAddU' => ['ExprMulU'] ],

        [ 'ExprMulR' => [ 'ExprMulU', 'OpMulti', 'ExprRegexR' ] ],
        [ 'ExprMulR' => ['ExprRegexR'] ],
        [ 'ExprMulL' => [ 'ExprMulU', 'OpMulti', 'ExprRegexL' ] ],
        [ 'ExprMulL' => ['ExprRegexL'] ],
        [ 'ExprMul0' => [ 'ExprMulU', 'OpMulti', 'ExprRegex0' ] ],
        [ 'ExprMul0' => ['ExprRegex0'] ],
        [ 'ExprMulU' => [ 'ExprMulU', 'OpMulti', 'ExprRegexU' ] ],
        [ 'ExprMulU' => ['ExprRegexU'] ],

        [ 'ExprRegexR' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryR' ] ],
        [ 'ExprRegexR' => ['ExprUnaryR'] ],
        [ 'ExprRegexL' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryL' ] ],
        [ 'ExprRegexL' => ['ExprUnaryL'] ],
        [ 'ExprRegex0' => [ 'ExprRegexU', 'OpRegex', 'ExprUnary0' ] ],
        [ 'ExprRegex0' => ['ExprUnary0'] ],
        [ 'ExprRegexU' => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryU' ] ],
        [ 'ExprRegexU' => ['ExprUnaryU'] ],

        [ 'ExprUnaryR' => [ 'OpUnary',    'ExprUnaryR' ] ],
        [ 'ExprUnaryR' => [ 'FileTestOp', 'ExprUnaryR' ] ],
        [ 'ExprUnaryR' => ['ExprPowerR'] ],
        [ 'ExprUnaryL' => [ 'OpUnary',    'ExprUnaryL' ] ],
        [ 'ExprUnaryL' => [ 'FileTestOp', 'ExprUnaryL' ] ],
        [ 'ExprUnaryL' => ['ExprPowerL'] ],
        [ 'ExprUnary0' => [ 'OpUnary',    'ExprUnary0' ] ],
        [ 'ExprUnary0' => [ 'FileTestOp', 'ExprUnary0' ] ],
        [ 'ExprUnary0' => ['ExprPower0'] ],
        [ 'ExprUnaryU' => [ 'OpUnary',    'ExprUnaryU' ] ],
        [ 'ExprUnaryU' => [ 'FileTestOp', 'ExprUnaryU' ] ],
        [ 'ExprUnaryU' => ['ExprPowerU'] ],

        [ 'ExprPowerR' => [ 'ExprIncU', 'OpPower', 'ExprUnaryR' ] ],
        [ 'ExprPowerR' => ['ExprIncR'] ],
        [ 'ExprPowerL' => [ 'ExprIncU', 'OpPower', 'ExprUnaryL' ] ],
        [ 'ExprPowerL' => ['ExprIncL'] ],
        [ 'ExprPower0' => [ 'ExprIncU', 'OpPower', 'ExprUnary0' ] ],
        [ 'ExprPower0' => ['ExprInc0'] ],
        [ 'ExprPowerU' => [ 'ExprIncU', 'OpPower', 'ExprUnaryU' ] ],
        [ 'ExprPowerU' => ['ExprIncU'] ],

        [ 'ExprIncR' => [ 'OpInc',      'ExprArrowR' ] ],
        [ 'ExprIncR' => [ 'ExprArrowL', 'OpInc' ] ],
        [ 'ExprIncR' => ['ExprArrowR'] ],
        [ 'ExprIncL' => [ 'OpInc',      'ExprArrowL' ] ],
        [ 'ExprIncL' => [ 'ExprArrowR', 'OpInc' ] ],
        [ 'ExprIncL' => ['ExprArrowL'] ],
        [ 'ExprInc0' => [ 'OpInc',      'ExprArrow0' ] ],
        [ 'ExprInc0' => [ 'ExprArrowR', 'OpInc' ] ],
        [ 'ExprInc0' => ['ExprArrow0'] ],
        [ 'ExprIncU' => [ 'OpInc',      'ExprArrowU' ] ],
        [ 'ExprIncU' => [ 'ExprArrowR', 'OpInc' ] ],
        [ 'ExprIncU' => ['ExprArrowU'] ],

     # Arrow expressions - eliminate left recursion to prevent parsing explosion
        [ 'ExprArrowR' => [ 'ExprValueR', 'ArrowChain' ] ],
        [ 'ExprArrowR' => ['ExprValueR'] ],
        [ 'ExprArrowL' => [ 'ExprValueL', 'ArrowChain' ] ],
        [ 'ExprArrowL' => ['ExprValueL'] ],
        [ 'ExprArrow0' => [ 'ExprValue0', 'ArrowChain' ] ],
        [ 'ExprArrow0' => ['ExprValue0'] ],
        [ 'ExprArrowU' => [ 'ExprValueU', 'ArrowChain' ] ],
        [ 'ExprArrowU' => ['ExprValueU'] ],

        # ArrowChain - right-recursive chain of arrow operations
        [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS', 'ArrowChain' ] ],
        [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS' ] ]
        ,    # Prefer continuing chain over terminating

        # Value rules - matching Guacamole ExprValue* rules exactly
        [ 'ExprValueU' => ['Value'] ],
        [ 'ExprValue0' => ['Value'] ],
        [ 'ExprValue0' => ['OpUnaryKeywordExpr'] ],
        [ 'ExprValueL' => ['Value'] ],
        [ 'ExprValueL' => ['OpAssignKeywordExpr'] ],
        [ 'ExprValueL' => ['OpUnaryKeywordExpr'] ],
        [ 'ExprValueR' => ['Value'] ],
        [ 'ExprValueR' => ['OpListKeywordExpr'] ],
        [ 'ExprValueR' => ['OpAssignKeywordExpr'] ],
        [ 'ExprValueR' => ['OpUnaryKeywordExpr'] ],

        # ArrowRHS - method calls, array/hash indexing, postfix dereferencing
        [ 'ArrowRHS' => ['Identifier'] ],
        [ 'ArrowRHS' => [ 'Identifier', '(', 'ParameterList', ')' ] ]
        ,                                    # Match FunctionCall priority
        [ 'ArrowRHS' => [ 'Identifier', '(', ')' ] ]
        ,                                    # Match FunctionCall priority
        [ 'ArrowRHS' => [ '[', 'Expression', ']' ] ],
        [ 'ArrowRHS' => [ '{', 'Expression', '}' ] ],
        [ 'ArrowRHS' => ['PostfixDeref'] ],  # ->@*, ->%*, ->$* (postfix derefs)

        # Postfix dereferencing operators - atomic tokens
        [ 'PostfixDeref' => [qr/[@%\$]\*/] ],

        # Value rules - basic terminals needed for chalk
        [ 'Value' => ['Variable'] ],    # Now includes $hash{key}, @array[index]
        [ 'Value' => ['QualifiedIdentifier'] ],    # Foo::Bar for method calls
        [ 'Value' => ['Identifier'] ],     # Plain identifiers (lower priority)
        [ 'Value' => ['Number'] ],
        [ 'Value' => ['QuotedString'] ],
        [ 'Value' => [ '(', 'Expression', ')' ] ],
        [ 'Value' => [ '(', ')' ] ],       # Empty parentheses (empty list)
        [ 'Value' => ['ArrayRef'] ],
        [ 'Value' => ['HashRef'] ],
        [ 'Value' => ['FunctionCall'] ],
        [ 'Value' => ['UnaryKeywordExpression'] ]
        ,    # grep/map/sort etc. (blocks explicitly after keywords)
        [ 'Value' => ['Block'] ],        # Bare blocks as values (e.g., -l {0})
        [ 'Value' => ['EvalBlock'] ],    # eval { ... } blocks
        [ 'Value' => [ 'QLikeValue', 'ElemSeq1' ] ]
        ,    # qw"b"[0], qw()[1], etc. - subscripted qw/regex
        [ 'Value' => ['QLikeValue'] ],
        [ 'Value' => ['Diamond'] ], # <$fh> constructs (merged from DiamondExpr)
        [ 'Value' => ['@'] ],
        [ 'Value' => ['FieldDecl'] ],
        [ 'Value' => ['VariableDecl'] ],  # my $var = expr as expression
        [ 'Value' => ['PrintExpr'] ],     # print statements without parentheses
        [ 'Value' => ['DieExpr'] ],       # die statements without parentheses
        [ 'Value' => ['WarnExpr'] ],      # warn statements without parentheses
        [ 'Value' => ['BuiltinFunctionCall'] ],    # Built-in function calls

        # Print expressions following guacamole OpKeywordPrintExpr pattern
        [ 'PrintExpr' => [ 'print', 'ExprComma' ] ],    # print "string"
        [ 'PrintExpr' => ['print'] ],                   # bare print

        # Print with filehandle: print FILEHANDLE "string"
        [ 'PrintExpr' => [ 'print', 'Identifier', 'ExprComma' ] ]
        ,                                                # print FH "string"
        [ 'PrintExpr' => [ 'print', 'Identifier' ] ],    # print FH
        [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle', 'ExprComma' ] ]
        ,                                                # print STDOUT "string"
        [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle' ] ],    # print STDOUT

# Pattern match statements merged into Statement => QLikeValue (removed wrapper)

        # Die expressions following same pattern as PrintExpr
        [ 'DieExpr' => [ 'die', 'ExprComma' ] ],    # die "string"
        [ 'DieExpr' => ['die'] ],                   # bare die

        # Warn expressions following same pattern as DieExpr
        [ 'WarnExpr' => [ 'warn', 'ExprComma' ] ],    # warn "string"
        [ 'WarnExpr' => ['warn'] ],                   # bare warn

        # Built-in function calls (chdir, mkdir, etc.)
        [ 'BuiltinFunctionCall' => [ 'BuiltinFunction', 'ExprComma' ] ],
        [ 'BuiltinFunctionCall' => ['BuiltinFunction'] ],
        [ 'BuiltinFunctionCall' => ['OpenExpr'] ],   # Special handling for open
        [
            'BuiltinFunction' => [
qr/chdir|mkdir|rmdir|unlink|chmod|chown|utime|rename|link|symlink|readlink|stat|lstat|sleep|exit|system|exec|fork|wait|waitpid|kill|alarm|umask|exists|defined|delete|ref|bless|tied|untie|tie|scalar|wantarray|caller|reset|undef|length|chr|ord|uc|lc|ucfirst|lcfirst|quotemeta|abs|int|sqrt|exp|log|sin|cos|atan2|rand|srand|time|localtime|gmtime|close|eof|tell|seek|truncate|fileno|flock|binmode|read|write|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|require/
            ]
        ],

        # Open expressions with inline variable declarations
        # Two-argument open: open my $fh, "file" or open our $fh, "file"
        [
            'OpenExpr' =>
              [ 'open', 'my', 'VariableBase', 'OpComma', 'ExprComma' ]
        ],
        [
            'OpenExpr' =>
              [ 'open', 'our', 'VariableBase', 'OpComma', 'ExprComma' ]
        ],

        # Three-argument open with inline declarations: open my $fh, "<", $file
        [
            'OpenExpr' => [
                'open',      'my',      'VariableBase', 'OpComma',
                'ExprComma', 'OpComma', 'ExprComma'
            ]
        ],
        [
            'OpenExpr' => [
                'open',      'our',     'VariableBase', 'OpComma',
                'ExprComma', 'OpComma', 'ExprComma'
            ]
        ],

        # Standard open patterns (already working, kept for completeness)
        [ 'OpenExpr' => [ 'open', 'ExprComma' ] ],

  # ExprComma for print arguments (following guacamole OpListKeywordArgNonBrace)
        [
            'ExprComma' => [ 'ExprAssignL', 'OpComma', 'ExprComma' ],
            0.8
        ],
        [ 'ExprComma' => [ 'ExprAssignL', 'OpComma' ] ],    # Trailing comma
        [ 'ExprComma' => ['ExprAssignR'] ],                 # Single item

        # ExprAssignL for left-associative assignments in print context
        [
            'ExprAssignL' => [ 'ExprCond0', 'OpAssign', 'ExprAssignL' ],
            0.8
        ],
        [ 'ExprAssignL' => ['ExprCondL'] ],

        # ExprCondL for conditional expressions in print context
        [
            'ExprCondL' => [
                'ExprRange0', 'OpTriThen', 'ExprRangeL', 'OpTriElse',
                'ExprCondL'
            ],
            0.8
        ],
        [ 'ExprCondL' => ['ExprRangeL'] ],

        # ExprRangeL for range expressions in print context
        [
            'ExprRangeL' => [ 'ExprLogOr0', 'OpRange', 'ExprLogOrL' ],
            0.8
        ],
        [ 'ExprRangeL' => ['ExprLogOrL'] ],

        # Continue chain for NonBrace left-associative expressions
        [ 'ExprLogOrL'  => ['ExprLogAndL'] ],
        [ 'ExprLogAndL' => ['ExprBinOrL'] ],
        [ 'ExprBinOrL'  => ['ExprBinAndL'] ],
        [ 'ExprBinAndL' => ['ExprEqL'] ],
        [ 'ExprEqL'     => ['ExprNeqL'] ],
        [ 'ExprNeqL'    => [ 'ExprShift0', 'OpInequal', 'ExprShiftL' ] ],
        [ 'ExprNeqL'    => ['ExprShiftL'] ],

        # NonBrace shift expressions (left-associative)
        [ 'ExprShiftL' => [ 'ExprShiftU', 'OpShift', 'ExprAddL' ] ],
        [ 'ExprShiftL' => ['ExprAddL'] ],

        # NonBrace addition expressions (left-associative)
        [ 'ExprAddL' => [ 'ExprAddU', 'OpAdd', 'ExprMulL' ] ],
        [ 'ExprAddL' => [ 'ExprAddU', '.',     'ExprMulL' ] ],
        [ 'ExprAddL' => ['ExprMulL'] ],

        # NonBrace multiplication expressions (left-associative)
        [ 'ExprMulL' => [ 'ExprMulU', 'OpMulti', 'ExprRegexL' ] ],
        [ 'ExprMulL' => ['ExprRegexL'] ],

        [ 'ExprRegexL'  => [ 'ExprRegexU', 'OpRegex', 'ExprUnaryL' ] ],
        [ 'ExprRegexL'  => ['ExprUnaryL'] ],
        [ 'ExprUnaryL'  => [ 'OpUnary',    'ExprUnaryL' ] ],
        [ 'ExprUnaryL'  => [ 'FileTestOp', 'ExprUnaryL' ] ],
        [ 'ExprUnaryL'  => ['ExprPowerL'] ],
        [ 'ExprPowerL'  => ['ExprIncL'] ],
        [ 'ExprIncL'    => [ 'OpInc',    'ExprIncL' ] ],    # Pre-increment
        [ 'ExprIncL'    => [ 'ExprIncL', 'OpInc' ] ],       # Post-increment
        [ 'ExprIncL'    => ['ExprArrowL'] ],
        [ 'ExprArrowL'  => ['ExprValueUL'] ],
        [ 'ExprValueUL' => ['Value'] ],

        # Add missing operators for ternary expressions
        [ 'OpTriThen' => ['?'] ],
        [ 'OpTriElse' => [':'] ],

 # Diamond operator: <$fh>, <STDIN>, <>, <try> (DiamondExpr merged into Diamond)
        [ 'Diamond' => [ '<', 'Variable',          '>' ] ],
        [ 'Diamond' => [ '<', 'BuiltinFilehandle', '>' ] ],
        [ 'Diamond' => [ '<', 'Identifier', '>' ] ],    # Bareword filehandles
        [ 'Diamond' => [ '<', '>' ] ],                  # Empty diamond <>

        # Built-in filehandles
        [ 'BuiltinFilehandle' => [qr/STDIN|STDOUT|STDERR|ARGV|ARGVOUT|DATA/] ],

        # Function calls following Guacamole SubCall pattern
        [
            'FunctionCall' => [ 'Identifier', '(', 'ParameterList', ')' ],
            1.0
        ],                                              # func(args)
        [ 'FunctionCall' => [ 'Identifier', '(', ')' ] ],    # func()

        # Qualified function calls for package methods
        [
            'FunctionCall' =>
              [ 'QualifiedIdentifier', '(', 'ParameterList', ')' ]
        ],                                                   # pkg::func(args)
        [ 'FunctionCall' => [ 'QualifiedIdentifier', '(', ')' ] ], # pkg::func()

        # Code reference calls: &{expr}()
        [ 'FunctionCall' => [ '&{', 'Expression', '}' ] ]
        ,    # &{$coderef} or &{sub {...}}

      # List operator syntax for user-defined functions (statement context only)
      # This allows function calls without parentheses like: func "arg", $var
      # Only available in Statement, not in Value/Expression to avoid ambiguity
        [ 'ListOperatorCall' => [ 'Identifier', 'ExprComma' ] ]
        ,    # func "arg", $var
        [ 'ListOperatorCall' => [ 'QualifiedIdentifier', 'ExprComma' ] ]
        ,    # Pkg::func "arg", $var

# Expression block for grep/map/sort merged into Block
# Removed ExpressionBlock - Block already handles both Expression and StatementList
# since expressions can appear in StatementList through BlockLevelExpression

        # Eval - supports both block and string/expression forms
        [ 'EvalBlock' => [ 'eval', 'Block' ] ],       # eval { ... }
        [ 'EvalBlock' => [ 'eval', 'Expression' ] ]
        ,    # eval 'string' or eval $expr

      # Unary keyword expressions following guacamole.pm OpKeyword*Expr patterns
        [
            'UnaryKeywordExpression' => [ 'grep', 'Block', 'Expression' ],
            1.0
        ],    # grep { ... } @list
        [ 'UnaryKeywordExpression' => [ 'grep', 'Expression' ] ]
        ,     # grep EXPR, @list
        [
            'UnaryKeywordExpression' => [ 'all', 'Block', 'Expression' ],
            1.0
        ],    # all { ... } @list
        [
            'UnaryKeywordExpression' => [ 'any', 'Block', 'Expression' ],
            1.0
        ],    # any { ... } @list
        [
            'UnaryKeywordExpression' => [ 'map', 'Block', 'Expression' ],
            1.0
        ],    # map { ... } @list
        [
            'UnaryKeywordExpression' => [ 'sort', 'Block', 'Expression' ],
            1.0
        ],    # sort { ... } @list

        # Operators - basic ones needed for chalk
        # OpRegex needs longer match (!~) before shorter (=~)
        [ 'OpRegex' => [qr/!~|=~/] ],    # Regex binding operators: !~ and =~
        [ 'OpComma' => [qr/,|=>/] ],
        [
            'OpAssign' =>
              [qr/\+=|-=|\*=|\/=|%=|\/\/=|\|\|=|&&=|\.=|&=|\|=|\^=|<<=|>>=|=/]
        ],    # Assignment operators (compound before simple)
        [ 'OpArrow' => ['->'] ],
        [ 'OpAdd'   => [qr/[+\-]/] ],
        [ 'OpMulti' => [qr/[*\/x]/] ]
        ,     # Multiplication, division, and repetition (x)
        [ 'OpLogOr'   => [qr/\|\||\/\//] ],    # Logical or and defined-or
        [ 'OpLogAnd'  => [qr/&&/] ],
        [ 'OpNameOr'  => ['or'] ],
        [ 'OpNameAnd' => ['and'] ],
        [ 'OpNameNot' => ['not'] ],
        [ 'OpRange'   => ['..'] ],
        [ 'OpBinOr'   => [qr/[|^]/] ],
        [ 'OpEqual'   => [qr/==|!=|<=>|eq|ne|cmp|isa/] ],
        [ 'OpInequal' => [qr/<=|>=|<|>|lt|gt|le|ge/] ],
        [ 'OpShift'   => [qr/<<|>>/] ],
        [ 'OpUnary'   => [qr/[\\+\-]/] ]
        ,    # Removed ! and ~ to avoid conflict with !~
        [ 'OpUnary' => ['!'] ],           # Define ! separately
        [ 'OpUnary' => ['~'] ],           # Define ~ separately
        [ 'OpPower' => ['**'] ],
        [ 'OpInc'   => [qr/\+\+|--/] ],

        # Variables with optional element sequences (subscripts)
        [ 'Variable' => [ 'VariableBase', 'ElemSeq0' ] ],
        [ 'Variable' => ['VariableBase'] ],    # Lower priority for base case

        # Base variable patterns (without subscripts) - all sigils in one rule
        [ 'VariableBase' => [qr/[\$@%&*]\w+(?:::\w+)*::/] ]
        ,    # Variables with trailing :: (e.g., $foo::) - must come first
        [ 'VariableBase' => [qr/[\$@%&*]\w+(?:::\w+)*/] ]
        , # All variable types with sigils, including qualified (e.g., *Package::Name)
        [ 'VariableBase' => [qr/\$#\w+/] ],   # Array length variables ($#array)

        # Global variables following guacamole GlobalVariables pattern
        [ 'VariableBase' => [qr/\$::/] ],     # $:: - main package symbol table
        [ 'VariableBase' => [qr/\$\$/] ],     # $$ - process ID (special case)
        [ 'VariableBase' => [qr/\$[!"#%&'()*+,\-.\/:;<=>?\@\[\\\]^_`|~]/] ],
        [ 'VariableBase' => [qr/\$\^\w+/] ]   # Special caret variables like $^X
        ,                                     # Global special vars

        # Caret variables in braces: ${^NAME}, $ {^NAME}, @{^NAME}, %{^NAME}
        [ 'VariableBase' => [ '${', '^', 'Identifier', '}' ] ],      # ${^NAME}
        [ 'VariableBase' => [ '$',  '{', '^', 'Identifier', '}' ] ], # $ {^NAME}
        [ 'VariableBase' => [ '@{', '^', 'Identifier', '}' ] ],      # @{^NAME}
        [ 'VariableBase' => [ '@',  '{', '^', 'Identifier', '}' ] ], # @ {^NAME}
        [ 'VariableBase' => [ '%{', '^', 'Identifier', '}' ] ],      # %{^NAME}
        [ 'VariableBase' => [ '%',  '{', '^', 'Identifier', '}' ] ], # % {^NAME}

        # Scalar dereference patterns: @$var, %$var, *$var, &$var, $$var, $#$var
        [ 'VariableBase' => [qr/[@%&*]\$\w+/] ]
        ,    # All dereference types except $$
        [ 'VariableBase' => [qr/\$\$\w+/] ],    # Scalar dereference ($$ref)
        [ 'VariableBase' => [qr/\$#\$\w+/] ]
        ,    # Array length of dereferenced scalar ($#$ref)

# Complex dereference patterns from guacamole: ${ Expression }, @{ Expression }, %{ Expression }
        [ 'VariableBase' => [ '${', 'Expression', '}' ] ]
        ,    # Scalar deref: ${ expr }
        [ 'VariableBase' => [ '$', '{', 'Expression', '}' ] ]
        ,    # Scalar deref with space: $ { expr }
        [ 'VariableBase' => [ '@{', 'Expression', '}' ] ]
        ,    # Array deref: @{ expr }
        [ 'VariableBase' => [ '%{', 'Expression', '}' ] ]
        ,    # Hash deref: %{ expr }
        [ 'VariableBase' => [ '@[', 'Expression', ']' ] ]
        ,    # Array slice: @[ expr ]
        [ 'VariableBase' => [ '%[', 'Expression', ']' ] ]
        ,    # Hash slice: %[ expr ]

        # Element sequences for subscripting
        [ 'ElemSeq0' => [] ],                         # Empty sequence (epsilon)
        [ 'ElemSeq0' => ['Element'] ],
        [ 'ElemSeq0' => [ 'Element', 'ElemSeq0' ] ],  # Multiple subscripts

        # Non-empty element sequence (one or more subscripts) - for qw()[0] etc.
        [ 'ElemSeq1' => ['Element'] ],
        [ 'ElemSeq1' => [ 'Element', 'ElemSeq0' ] ],

        [ 'Element' => ['ArrayElem'] ],
        [ 'Element' => ['HashElem'] ],

        [ 'ArrayElem' => [ '[', 'Expression', ']' ] ],
        [ 'HashElem'  => [ '{', 'Expression', '}' ] ],
        [
            'Identifier' =>
              [qr/[a-zA-Z_][a-zA-Z0-9_]*(?:::+[a-zA-Z_][a-zA-Z0-9_]*)*/]
        ]
        , # Support qualified identifiers, including pathological cases like foo::::bar
        [
            'Number' => [
qr/(?:0[bB][01]+|0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[0-7]+|\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/
            ]
        ],
        [ 'QuotedString' => [qr/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/] ],

# q/qq quote operators - split into operator and delimited content
# This allows auto_insert WS_OPT to handle comments between operator and delimiter
        [ 'QuotedString' => [ 'QOp',  'QDelimited' ] ],
        [ 'QuotedString' => [ 'QQOp', 'QDelimited' ] ],

      # Quote operators as terminals (not literals, so auto_insert WS_OPT works)
        [ 'QOp'  => [qr/q(?!q)/] ],    # q but not qq (negative lookahead)
        [ 'QQOp' => [qr/qq/] ],
        [ 'QWOp' => [qr/qw/] ],        # qw word list operator
        [ 'MOp'  => [qr/m(?!s)/] ]
        , # m match operator (not ms - negative lookahead for future s/// support)
        [ 'QROp' => [qr/qr/] ],    # qr compiled regex operator
        [ 'SOp'  => [qr/s/] ],     # s substitution operator
        [ 'TROp' => [qr/tr/] ],    # tr transliteration operator
        [ 'YOp'  => [qr/y/] ],     # y transliteration operator (alias for tr)

        # Delimited quote content - various delimiters
        [
            'QDelimited' => [
qr/\{(?:[^{}]++|\{(?:[^{}]++|\{(?:[^{}]++|\{[^{}]*+\})*+\})*+\})*+\}/
            ]
        ],                         # {} with balanced braces
        [ 'QDelimited' => [qr/\((?:[^)]|\n)*\)/] ],       # ()
        [ 'QDelimited' => [qr/\[(?:[^\]]|\n)*\]/] ],      # []
        [ 'QDelimited' => [qr/<(?:[^>]|\n)*>/] ],         # <>
        [ 'QDelimited' => [qr/"(?:[^"\\]|\\.)*"/] ],      # ""
        [ 'QDelimited' => [qr/'(?:[^'\\]|\\.)*'/] ],      # ''
        [ 'QDelimited' => [qr{/(?:[^/\\]|\\.)*+/}] ],     # /.../
        [ 'QDelimited' => [qr/!(?:[^!\\]|\\.)*!/] ],      # !...!
        [ 'QDelimited' => [qr/#(?:[^#\\]|\\.)*#/] ],      # #...#
        [ 'QDelimited' => [qr/\|(?:[^|\\]|\\.)*\|/] ],    # |...|

       # Delimited match content - like QDelimited but with optional regex flags
       # Possessive quantifiers (*+) prevent backtracking across large spans
        [
            'MDelimited' => [
qr/\{(?:[^{}]++|\{(?:[^{}]++|\{(?:[^{}]++|\{[^{}]*+\})*+\})*+\})*+\}[a-z]*/
            ]
        ],    # {} with balanced braces + flags
        [ 'MDelimited' => [qr/\((?:[^)]|\\.)*+\)[a-z]*/] ],         # () + flags
        [ 'MDelimited' => [qr/\[(?:[^\]]|\\.)*+\][a-z]*/] ],        # [] + flags
        [ 'MDelimited' => [qr/<(?:[^>]|\\.)*+>[a-z]*/] ],           # <> + flags
        [ 'MDelimited' => [qr/"(?:[^"\\]|\\.)*+"[a-z]*/] ],         # "" + flags
        [ 'MDelimited' => [qr/'(?:[^'\\]|\\.)*+'[a-z]*/] ],         # '' + flags
        [ 'MDelimited' => [qr{/(?:[^/\\]|\\.)*+/[a-z]*}] ],         # /.../flags
        [ 'MDelimited' => [qr/!(?:[^!\\]|\\.)*+![a-z]*/] ],         # !...!flags
        [ 'MDelimited' => [qr/#(?:[^#\\]|\\.)*+#[a-z]*/] ],         # #...#flags
        [ 'MDelimited' => [qr/\|(?:[^|\\]|\\.)*+\|(?![|])[a-z]*/] ]
        ,    # |...|flags (negative lookahead to prevent matching ||)

        # Punctuation
        [ 'PackageSeparator' => ['::'] ],

# Qualified identifiers for package method calls like utf8::native_to_unicode
# Made recursive to support multi-level package names like Chalk::Semiring::Boolean
        [
            'QualifiedIdentifier' =>
              [ 'Identifier', 'PackageSeparator', 'QualifiedIdentifier' ]
        ],
        [
            'QualifiedIdentifier' =>
              [ 'Identifier', 'PackageSeparator', 'Identifier' ]
        ],

        # ParameterList for method calls - simplified using ExpressionList
        [ 'ParameterList' => ['ExpressionList'] ],
        [ 'ParameterList' => [ 'OpComma', 'Comment' ] ]
        ,                                      # Just comma with comment
        [ 'ParameterList' => ['Comment'] ],    # Just a comment
        [ 'ParameterList' => [] ],             # Empty parameter list

        # ArrayRef and HashRef
        [ 'ArrayRef' => [ '[', 'ExpressionList', ']' ] ],
        [ 'ArrayRef' => [ '[', ']' ] ],        # Empty array
        [ 'HashRef'  => [ '{', 'HashElementList', '}' ] ],
        [ 'HashRef'  => [ '{', '}' ] ],        # Empty hash

       # Optimal 3-rule ExpressionList - balances functionality with performance
        [ 'ExpressionList' => ['Expression'] ],    # Single expression
        [ 'ExpressionList' => [ 'Expression', 'OpComma', 'ExpressionList' ] ]
        ,                                          # Standard recursion
        [ 'ExpressionList' => [ 'Comment', 'ExpressionList' ] ]
        ,                                          # Comment-prefixed lists

        [ 'HashElementList' => ['HashElement'] ],
        [
            'HashElementList' =>
              [ 'HashElement', 'OpComma', 'HashElementList' ],
            1.0
        ],
        [ 'HashElementList' => [ 'HashElement', 'OpComma' ] ],  # Trailing comma

        [ 'HashElement' => [ 'Expression', 'OpComma', 'Expression' ] ]
        ,                                                       # key => value

        # File test operators - unary operators that test file properties
        [ 'FileTestOp'         => [qr/-[rwxoRWXOezsfdlpSbctugkTBMAC]/] ],
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
qr/die|warn|print|say|printf|sprintf|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|splice|pack|unpack|read|write|sysread|syswrite|recv|send|select/
            ]
        ],

        # Whitespace rules (needed for auto_insert)
        [ 'WS_OPT' => [] ],
        [ 'WS_OPT' => ['WS'] ],
        [ 'WS_OPT' => [ 'WS', 'WS_OPT' ] ]
        ,    # Multiple WS tokens (space + comment, etc.)
        [ 'WS' => [qr/\s+/m] ],
        [ 'WS' => [qr/#[^\n]*\n?/m] ]
        ,    # Comments count as whitespace (includes optional newline)
        [ 'WS' => [qr/#.*\n\s+/m] ],    # Comment followed by whitespace
        [ 'WS' => [qr/\n=[a-z]\w+\b.*?\n=cut\b.*?\n/s] ]
        ,                               # POD blocks (with leading newline)
        [ 'WS' => [qr/=[a-z]\w+\b.*?\n=cut\b.*?\n/s] ]
        ,    # POD blocks (at start of parsing or after WS)
    ]
);

1;
