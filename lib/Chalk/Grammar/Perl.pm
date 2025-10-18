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

my $RE_BALANCED_BRACES = qr/\{(?:[^{}]++|\{(?:[^{}]++|\{(?:[^{}]++|\{[^{}]*+\})*+\})*+\})*+\}/;
my $RE_BALANCED_BRACES_FLAGS = qr/\{(?:[^{}]++|\{(?:[^{}]++|\{(?:[^{}]++|\{[^{}]*+\})*+\})*+\})*+\}[a-z]*/;
my $RE_BUILTIN_FUNCTIONS = qr/chdir|mkdir|rmdir|unlink|chmod|chown|utime|rename|link|symlink|readlink|stat|lstat|sleep|exit|system|exec|fork|wait|waitpid|kill|alarm|umask|exists|defined|delete|ref|bless|tied|untie|tie|scalar|wantarray|caller|reset|undef|length|chr|ord|uc|lc|ucfirst|lcfirst|quotemeta|abs|int|sqrt|exp|log|sin|cos|atan2|rand|srand|time|localtime|gmtime|close|eof|tell|seek|truncate|fileno|flock|binmode|read|write|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|require/;
my $RE_UNARY_KEYWORDS = qr/return|last|next|redo|chdir|mkdir|rmdir|unlink|chmod|chown|utime|rename|link|symlink|readlink|stat|lstat|sleep|exit|system|exec|fork|wait|waitpid|kill|alarm|umask|exists|defined|delete|ref|bless|tied|untie|tie|scalar|wantarray|caller|reset|undef|length|chr|ord|uc|lc|ucfirst|lcfirst|quotemeta|abs|int|sqrt|exp|log|sin|cos|atan2|rand|srand|time|localtime|gmtime|times|close|eof|tell|seek|truncate|fileno|flock|binmode/;
my $RE_LIST_KEYWORDS = qr/die|warn|print|say|printf|sprintf|join|split|grep|map|sort|reverse|keys|values|each|push|pop|shift|unshift|splice|pack|unpack|read|write|sysread|syswrite|recv|send|select/;
my $RE_FOR = qr/for(?:each)?/;
my $RE_METHOD_SUB = qr/method|sub/;
my $RE_CLASS_PACKAGE = qr/class|package/;
my $RE_MY_OUR_STATE = qr/my|our|state/;
my $RE_CONTROL_FLOW = qr/next|last|redo/;
my $RE_STMT_MODIFIER = qr/unless|if|while|until|for(?:each)?|when/;
my $RE_IDENTIFIER = qr/[a-zA-Z_][a-zA-Z0-9_]*(?:::+[a-zA-Z_][a-zA-Z0-9_]*)*/;
my $RE_NUMBER = qr/(?:0[bB][01]+|0[xX][0-9a-fA-F]+|0[oO][0-7]+|0[0-7]+|\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/;
my $RE_FILETEST = qr/-[rwxoRWXOezsfdlpSbctugkTBMAC]/;

our $chalk_grammar = Chalk::Grammar->build_grammar(
    auto_insert => ['WS_OPT'],
    rules       => [

        [ 'Program' => ['StatementList'] ],
        [ 'Program' => [ 'WS_OPT',  'StatementList', 'WS_OPT' ] ],
        [ 'Program' => [ 'Shebang', 'StatementList', 'WS_OPT' ] ],

        [ 'StatementList' => [] ],
        [ 'StatementList' => ['Statement'] ],
        [ 'StatementList' => [ 'Statement', ';', 'StatementList' ] ],
        [ 'StatementList' => [ 'Statement', 'StatementList' ] ],

        [ 'Statement' => [ 'Statement',  'StatementModifier' ] ],
        [ 'Statement' => [ 'QLikeValue', 'ElementIndexChain' ] ], # qw"b"[0] as statement
        [ 'Statement' => ['AdjustBlock'] ],
        [ 'Statement' => ['Block'] ],                    # Bare blocks
        [ 'Statement' => ['BuiltinFunctionCall'] ],
        [ 'Statement' => ['ClassDecl'] ],
        [ 'Statement' => ['Comment'] ],
        [ 'Statement' => ['ControlFlowStatement'] ],     # next, last, redo
        [ 'Statement' => ['DieExpr'] ],   # Lower - prefer checking for modifier
        [ 'Statement' => ['EllipsisStatement'] ],
        [ 'Statement' => ['EvalBlock'] ],            # eval { ... } blocks
        [ 'Statement' => ['Expression'] ],
        [ 'Statement' => ['FieldDecl'] ],            # Field declarations
        [ 'Statement' => ['FunctionCall'] ],   # Function calls with parentheses
        [ 'Statement' => ['LineStatement'] ],
        [ 'Statement' => ['ListOperatorCall'] ],
        [ 'Statement' => ['LoopBlock'] ],           # Loop statements
        [ 'Statement' => ['PackageDecl'] ],
        [ 'Statement' => ['PrintExpr'] ],
        [ 'Statement' => ['QLikeValue'] ],
        [ 'Statement' => ['RequireStatement'] ],
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

        [ 'Block' => [ '{', 'StatementList', '}' ] ],
        [ 'Block' => [ '{', '}' ] ],

        [ 'AdjustBlock' => [ qr/ADJUST|BEGIN|END/, 'Block' ] ],

        [ 'LoopBlock' => ['ForStatement'] ],
        [ 'LoopBlock' => ['WhileStatement'] ],

        [
            'ForStatement' => [
                $RE_FOR, '(', 'Expression', ';',
                'Expression',     ';', 'Expression', ')',
                'Block'
            ]
        ],
        [
            'ForStatement' => [
                $RE_FOR, '(', ';', 'Expression', ';', 'Expression',
                ')', 'Block'
            ]
        ],
        [
            'ForStatement' => [
                $RE_FOR, '(', 'Expression', ';', ';', 'Expression',
                ')', 'Block'
            ]
        ],
        [
            'ForStatement' => [
                $RE_FOR, '(', 'Expression', ';',
                'Expression',     ';', ')',          'Block'
            ]
        ],
        [ 'ForStatement' => [ $RE_FOR, '(', ';', ';', ')', 'Block' ] ],

        [
            'ForStatement' => [
                $RE_FOR, 'VariableDecl',
                '(',              'Expression',
                ')',              'Block'
            ]
        ],
        [
            'ForStatement' =>
              [ $RE_FOR, '(', 'Expression', ')', 'Block' ]
        ],

        [ 'WhileStatement' => [ 'while', '(', 'Expression', ')', 'Block' ] ],

        [ 'LineStatement' => ['Comment'] ],

        [ 'ClassDecl' => [ 'class', 'QualifiedIdentifier', 'Inheritance', 'Block' ] ],
        [ 'ClassDecl' => [ 'class', 'QualifiedIdentifier', 'Block' ] ],
        [ 'PackageDecl' => [ $RE_CLASS_PACKAGE, 'Identifier', 'Inheritance', 'Block' ] ],
        [ 'PackageDecl' => [ $RE_CLASS_PACKAGE, 'Identifier', 'Block' ] ],
        [ 'PackageDecl' => [ 'package', 'QualifiedIdentifier' ] ],
        [ 'PackageDecl' => [ 'package', 'Identifier' ] ],

        [ 'SubroutineDecl' => [ $RE_METHOD_SUB, 'Identifier', 'SubDefinition' ] ],
        [ 'SubroutineDecl' => [ $RE_METHOD_SUB, 'Identifier' ] ],
        [ 'SubroutineDecl' => [ 'my', $RE_METHOD_SUB, 'Identifier', 'SubDefinition' ] ],
        [ 'SubroutineDecl' => [ 'my', $RE_METHOD_SUB, 'Identifier' ] ],

        [ 'SubDefinition' => [ 'SubSigsDefinition', 'Block' ] ],
        [ 'SubDefinition' => ['Block'] ],

        [ 'SubSigsDefinition' => [ '(', 'Expression', ')' ] ],
        [
            'SubSigsDefinition' => [
                '(', qr/\(\s*(?:\\\[[\$\@\%\&\*]+\s*\]|[\$\@\%\&\*\_;\s])*?\)/,
                ')'
            ]
        ],
        [ 'SubSigsDefinition' => [ '(', ')' ] ],

        [ 'Value' => [ 'sub', 'SubAttribute', 'SubDefinition' ] ]
        ,                                             # sub :lvalue { ... }
        [ 'Value' => [ 'sub', 'SubDefinition' ] ],

        [ 'SubAttribute' => [qr/:[a-zA-Z_]\w*/] ]
        ,

        [
            'UseStatement' =>
              [ 'OpKeywordUse', 'ClassIdent', 'VersionExpr', 'Expression' ]
        ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent', 'Expression' ] ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'VersionExpr' ] ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent', 'VersionExpr' ] ],
        [ 'UseStatement' => [ 'OpKeywordUse', 'ClassIdent' ] ],

        [ 'Inheritance' => [ ':isa(', 'ClassIdent', ')' ] ],

        [ 'FieldDecl' => [ 'field', 'Variable', 'FieldAttributeList' ] ],
        [ 'FieldDecl' => [ 'field', 'Variable' ] ],

        [ 'VariableDecl' => [ $RE_MY_OUR_STATE, 'Variable', '=', 'Expression' ] ],
        [ 'VariableDecl' => [ $RE_MY_OUR_STATE, 'Variable' ] ],
        [ 'VariableDecl' => [ 'local', 'Variable', '=', 'Expression' ] ],
        [ 'VariableDecl' => [ 'local', 'Variable' ] ],
        [ 'VariableDecl' => [ 'local', 'Expression', '=', 'Expression' ] ],

        [ 'Shebang' => [qr/#!.*$/m] ],
        [ 'Comment' => [qr/#.*$/m] ], # Whitespace already consumed by WS/WS_OPT

        [ 'EllipsisStatement' => ['Ellipsis'] ],
        [ 'Ellipsis'          => ['...'] ],

        [ 'ReturnStatement' => [ 'return', 'Expression' ] ],
        [ 'ReturnStatement' => ['return'] ],

        [ 'ControlFlowStatement' => [$RE_CONTROL_FLOW] ],
        [ 'ControlFlowStatement' => [ $RE_CONTROL_FLOW, 'Identifier' ] ],

        [ 'RequireStatement' => [ 'require', 'Expression' ] ],

        [ 'StatementModifier' => [ $RE_STMT_MODIFIER, 'Expression' ] ],

        [ 'OpKeywordUse' => ['use'] ],
        [ 'ClassIdent'   => ['SubNameExpr'] ],

        [ 'SubNameExpr' => ['Identifier'] ],
        [
            'SubNameExpr' => [ 'Identifier', 'PackageSeparator', 'SubNameExpr' ]
        ],
        [ 'VersionExpr' => [qr/v?(?:\d+\.?){1,3}/] ],

        [ 'QLikeValue' => [ 'QWOp', 'QDelimited' ] ],
        [ 'QLikeValue' => [ 'MOp', 'MDelimited' ] ]
        ,
        [ 'QLikeValue' => [ 'QROp', 'MDelimited' ] ]
        ,
        [
            'QLikeValue' =>
              [qr{s/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[msixpodualgcern]*}]
        ],
        [
            'QLikeValue' =>
              [qr{s\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[msixpodualgcern]*}]
        ],
        [
            'QLikeValue' =>
              [qr{s!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![msixpodualgcern]*}]
        ],
        [
            'QLikeValue' =>
              [qr{s#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[msixpodualgcern]*}]
        ],
        [ 'QLikeValue' => [ 'SOp', 'QDelimited', 'MDelimited' ] ]
        ,   # s with delimiters + optional flags on replacement (lower priority)
        [ 'QLikeValue' => [qr{tr/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[cdsr]*}] ]
        ,
        [
            'QLikeValue' =>
              [qr{tr\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[cdsr]*}]
        ],
        [ 'QLikeValue' => [qr{tr!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![cdsr]*}] ]
        ,     # tr!search!replace!flags
        [ 'QLikeValue' => [qr{tr#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[cdsr]*}] ]
        ,     # tr#search#replace#flags
        [ 'QLikeValue' => [qr{y/(?:[^/\\]|\\.)*+/(?:[^/\\]|\\.)*+/[cdsr]*}] ]
        ,     # y/search/replace/flags
        [
            'QLikeValue' => [qr{y\|(?:[^|\\]|\\.)*+\|(?:[^|\\]|\\.)*+\|[cdsr]*}]
        ],
        [ 'QLikeValue' => [qr{y!(?:[^!\\]|\\.)*+!(?:[^!\\]|\\.)*+![cdsr]*}] ]
        ,     # y!search!replace!flags
        [ 'QLikeValue' => [qr{y#(?:[^#\\]|\\.)*+#(?:[^#\\]|\\.)*+#[cdsr]*}] ]
        ,     # y#search#replace#flags
        [ 'QLikeValue' => [ 'TROp', 'QDelimited', 'QDelimited' ] ]
        ,
        [ 'QLikeValue' => [ 'YOp', 'QDelimited', 'QDelimited' ] ]
        ,
        [ 'QLikeValue' => [qr/\/((?:[^\/\\]|\\.)*)\/[gimsxoac]*/] ]
        ,                                     # /.../flags with escapes
        [ 'QLikeValue' => [qr/`[^`]*`/] ],

        [ 'FieldAttributeList' => ['FieldAttribute'] ],
        [ 'FieldAttributeList' => [ 'FieldAttribute', 'FieldAttributeList' ] ],
        [ 'FieldAttribute'     => [':param'] ],
        [ 'FieldAttribute'     => [':reader'] ],

        [ 'Expression' => ['ExprNameOr'] ],
        [ 'ExprNameOr' => [ 'ExprNameOr', 'OpNameOr', 'ExprNameAnd' ] ]
        ,                                       # First rule - higher prob
        [ 'ExprNameOr' => ['ExprNameAnd'] ],

        [ 'BlockLevelExpression' => ['Expression'] ],

        [ 'ExprNameAnd' => [ 'ExprNameAnd', 'OpNameAnd', 'ExprNameNot' ] ],
        [ 'ExprNameAnd' => ['ExprNameNot'] ],
        [ 'ExprNameNot' => [ 'OpNameNot', 'ExprNameNot' ] ],
        [ 'ExprNameNot' => ['ExprComma'] ],
        [ 'ExprComma'   => [ 'ExprAssign', 'OpComma', 'ExprComma' ] ]
        ,                                # Comma list - higher prob
        [ 'ExprComma' => [ 'ExprAssign', 'OpComma' ] ],  # Trailing comma
        [ 'ExprComma' => ['ExprAssign'] ],               # Single item fallback
        [ 'ExprAssign' => [ 'ExprCond', 'OpAssign', 'ExprAssign' ] ],  # Right-recursive
        [ 'ExprAssign' => ['ExprCond'] ],
        [ 'ExprCond' => [ 'ExprRange', '?', 'ExprRange', ':', 'ExprCond' ] ],  # Right-recursive
        [ 'ExprCond' => ['ExprRange'] ],

        [ 'ExprRange' => [ 'ExprLogOr', 'OpRange', 'ExprLogOr' ] ],
        [ 'ExprRange' => ['ExprLogOr'] ],

        [ 'ExprLogOr' => [ 'ExprLogOr', 'OpLogOr', 'ExprLogAnd' ] ],
        [ 'ExprLogOr' => ['ExprLogAnd'] ],

        [ 'ExprLogAnd' => [ 'ExprLogAnd', 'OpLogAnd', 'ExprBinOr' ] ],
        [ 'ExprLogAnd' => [ 'ExprBinOr',  'Comment' ] ]
        ,
        [ 'ExprLogAnd' => ['ExprBinOr'] ],

        [ 'ExprBinOr' => [ 'ExprBinOr', 'OpBinOr', 'ExprBinAnd' ] ],
        [ 'ExprBinOr' => ['ExprBinAnd'] ],

        [ 'ExprBinAnd' => [ 'ExprBinAnd', '&', 'ExprEq' ] ],
        [ 'ExprBinAnd' => ['ExprEq'] ],

        [ 'ExprEq' => [ 'ExprNeq', 'OpEqual', 'ExprNeq' ] ],
        [ 'ExprEq' => ['ExprNeq'] ],

        [ 'ExprNeq' => [ 'ExprShift', 'OpInequal', 'ExprShift' ] ],
        [ 'ExprNeq' => ['ExprShift'] ],

        [ 'ExprShift' => [ 'ExprShift', 'OpShift', 'ExprAdd' ] ],
        [ 'ExprShift' => ['ExprAdd'] ],

        [ 'ExprAdd' => [ 'ExprAdd', 'OpAdd', 'ExprMul' ] ],
        [ 'ExprAdd' => [ 'ExprAdd', '.',     'ExprMul' ] ],
        [ 'ExprAdd' => ['ExprMul'] ],

        [ 'ExprMul' => [ 'ExprMul', 'OpMulti', 'ExprRegex' ] ],
        [ 'ExprMul' => ['ExprRegex'] ],

        [ 'ExprRegex' => [ 'ExprRegex', 'OpRegex', 'ExprUnary' ] ],
        [ 'ExprRegex' => ['ExprUnary'] ],

        [ 'ExprUnary' => [ 'OpUnary',    'ExprUnary' ] ],
        [ 'ExprUnary' => [ 'FileTestOp', 'ExprUnary' ] ],
        [ 'ExprUnary' => ['ExprPower'] ],

        [ 'ExprPower' => [ 'ExprInc', 'OpPower', 'ExprPower' ] ],  # Right-recursive: RHS is ExprPower!
        [ 'ExprPower' => ['ExprInc'] ],

        [ 'ExprInc' => [ 'OpInc',    'ExprArrow' ] ],  # Pre-increment
        [ 'ExprInc' => [ 'ExprArrow', 'OpInc' ] ],     # Post-increment
        [ 'ExprInc' => ['ExprArrow'] ],

        [ 'ExprArrow' => [ 'ExprValue', 'ArrowChain' ] ],
        [ 'ExprArrow' => ['ExprValue'] ],

        [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS', 'ArrowChain' ] ],
        [ 'ArrowChain' => [ 'OpArrow', 'ArrowRHS' ] ]
        ,

        [ 'ExprValue' => ['Value'] ],
        [ 'ExprValue' => ['OpListKeywordExpr'] ],
        [ 'ExprValue' => ['OpAssignKeywordExpr'] ],
        [ 'ExprValue' => ['OpUnaryKeywordExpr'] ],

        [ 'ArrowRHS' => ['Identifier'] ],
        [ 'ArrowRHS' => [ 'Identifier', '(', 'ParameterList', ')' ] ]
        ,                                    # Match FunctionCall priority
        [ 'ArrowRHS' => [ 'Identifier', '(', ')' ] ]
        ,                                    # Match FunctionCall priority
        [ 'ArrowRHS' => [ '[', 'Expression', ']' ] ],
        [ 'ArrowRHS' => [ '{', 'Expression', '}' ] ],
        [ 'ArrowRHS' => ['PostfixDeref'] ],  # ->@*, ->%*, ->$* (postfix derefs)

        [ 'PostfixDeref' => [qr/[@%\$]\*/] ],

        [ 'Value' => ['Variable'] ],
        [ 'Value' => ['QualifiedIdentifier'] ],
        [ 'Value' => ['Identifier'] ],     # Plain identifiers (lower priority)
        [ 'Value' => ['Number'] ],
        [ 'Value' => ['QuotedString'] ],
        [ 'Value' => [ '(', 'Expression', ')', 'ElementIndexChain' ] ],  # (expr)[0] - subscripted parenthesized expression
        [ 'Value' => [ '(', 'Expression', ')' ] ],
        [ 'Value' => [ '(', ')' ] ],       # Empty parentheses (empty list)
        [ 'Value' => ['Ellipsis'] ],       # Yada-yada operator ... as value
        [ 'Value' => ['ArrayRef'] ],
        [ 'Value' => ['HashRef'] ],
        [ 'Value' => ['FunctionCall'] ],
        [ 'Value' => ['UnaryKeywordExpression'] ]
        ,
        [ 'Value' => ['Block'] ],        # Bare blocks as values (e.g., -l {0})
        [ 'Value' => ['EvalBlock'] ],
        [ 'Value' => [ 'QLikeValue', 'ElementIndexChain' ] ]
        ,
        [ 'Value' => ['QLikeValue'] ],
        [ 'Value' => ['Diamond'] ], # <$fh> constructs (merged from DiamondExpr)
        [ 'Value' => ['@'] ],
        [ 'Value' => ['FieldDecl'] ],
        [ 'Value' => ['VariableDecl'] ],  # my $var = expr as expression
        [ 'Value' => ['PrintExpr'] ],     # print statements without parentheses
        [ 'Value' => ['DieExpr'] ],       # die statements without parentheses
        [ 'Value' => ['WarnExpr'] ],      # warn statements without parentheses
        [ 'Value' => ['BuiltinFunctionCall'] ],

        [ 'PrintExpr' => [ 'print', 'ExprComma' ] ],
        [ 'PrintExpr' => ['print'] ],                   # bare print

        [ 'PrintExpr' => [ 'print', 'Identifier', 'ExprComma' ] ]
        ,                                                # print FH "string"
        [ 'PrintExpr' => [ 'print', 'Identifier' ] ],
        [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle', 'ExprComma' ] ]
        ,                                                # print STDOUT "string"
        [ 'PrintExpr' => [ 'print', 'BuiltinFilehandle' ] ],


        [ 'DieExpr' => [ 'die', 'ExprComma' ] ],
        [ 'DieExpr' => ['die'] ],                   # bare die

        [ 'WarnExpr' => [ 'warn', 'ExprComma' ] ],
        [ 'WarnExpr' => ['warn'] ],                   # bare warn

        [ 'BuiltinFunctionCall' => [ 'BuiltinFunction', 'ExprComma' ] ],
        [ 'BuiltinFunctionCall' => ['BuiltinFunction'] ],
        [ 'BuiltinFunctionCall' => ['OpenExpr'] ],
        [ 'BuiltinFunction' => [$RE_BUILTIN_FUNCTIONS] ],

        [
            'OpenExpr' =>
              [ 'open', 'my', 'VariableBase', 'OpComma', 'ExprComma' ]
        ],
        [
            'OpenExpr' =>
              [ 'open', 'our', 'VariableBase', 'OpComma', 'ExprComma' ]
        ],

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

        [ 'OpenExpr' => [ 'open', 'ExprComma' ] ],

        [ 'OpTriThen' => ['?'] ],
        [ 'OpTriElse' => [':'] ],

        [ 'Diamond' => [ '<', 'Variable',          '>' ] ],
        [ 'Diamond' => [ '<', 'BuiltinFilehandle', '>' ] ],
        [ 'Diamond' => [ '<', 'Identifier', '>' ] ],
        [ 'Diamond' => [ '<', '>' ] ],                  # Empty diamond <>

        [ 'BuiltinFilehandle' => [qr/STDIN|STDOUT|STDERR|ARGV|ARGVOUT|DATA/] ],

        [
            'FunctionCall' => [ 'Identifier', '(', 'ParameterList', ')' ]
        ],                                              # func(args)
        [ 'FunctionCall' => [ 'Identifier', '(', ')' ] ],

        [
            'FunctionCall' =>
              [ 'QualifiedIdentifier', '(', 'ParameterList', ')' ]
        ],                                                   # pkg::func(args)
        [ 'FunctionCall' => [ 'QualifiedIdentifier', '(', ')' ] ], # pkg::func()

        [ 'FunctionCall' => [ '&{', 'Expression', '}' ] ]
        ,

        [ 'ListOperatorCall' => [ 'Identifier', 'ExprComma' ] ]
        ,
        [ 'ListOperatorCall' => [ 'QualifiedIdentifier', 'ExprComma' ] ]
        ,


        [ 'EvalBlock' => [ 'eval', 'Block' ] ],       # eval { ... }
        [ 'EvalBlock' => [ 'eval', 'Expression' ] ]
        ,

        [
            'UnaryKeywordExpression' => [ 'grep', 'Block', 'Expression' ]
        ],
        [ 'UnaryKeywordExpression' => [ 'grep', 'Expression' ] ]
        ,     # grep EXPR, @list
        [
            'UnaryKeywordExpression' => [ 'all', 'Block', 'Expression' ]
        ],
        [
            'UnaryKeywordExpression' => [ 'any', 'Block', 'Expression' ]
        ],
        [
            'UnaryKeywordExpression' => [ 'map', 'Block', 'Expression' ]
        ],
        [
            'UnaryKeywordExpression' => [ 'sort', 'Block', 'Expression' ]
        ],

        [ 'OpRegex' => [qr/!~|=~/] ],
        [ 'OpComma' => [qr/,|=>/] ],
        [
            'OpAssign' =>
              [qr/\+=|-=|\*=|\/=|%=|\/\/=|\|\|=|&&=|\.=|&=|\|=|\^=|<<=|>>=|=/]
        ],
        [ 'OpArrow' => ['->'] ],
        [ 'OpAdd'   => [qr/[+\-]/] ],
        [ 'OpMulti' => [qr/[*\/x]/] ]
        ,     # Multiplication, division, and repetition (x)
        [ 'OpLogOr'   => [qr/\|\||\/\//] ],
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
        ,
        [ 'OpUnary' => ['!'] ],           # Define ! separately
        [ 'OpUnary' => ['~'] ],           # Define ~ separately
        [ 'OpPower' => ['**'] ],
        [ 'OpInc'   => [qr/\+\+|--/] ],

        [ 'Variable' => [ 'VariableBase', 'MaybeElementIndexChain' ] ],
        [ 'Variable' => ['VariableBase'] ],

        [ 'VariableBase' => [qr/[\$@%&*]\w+(?:::\w+)*::/] ]
        ,
        [ 'VariableBase' => [qr/[\$@%&*]\w+(?:::\w+)*/] ]
        , # All variable types with sigils, including qualified (e.g., *Package::Name)
        [ 'VariableBase' => [qr/\$#\w+/] ],   # Array length variables ($#array)

        [ 'VariableBase' => [qr/\$::/] ],     # $:: - main package symbol table
        [ 'VariableBase' => [qr/\$\$/] ],     # $$ - process ID (special case)
        [ 'VariableBase' => [qr/\$[!"#%&'()*+,\-.\/:;<=>?\@\[\\\]^_`|~]/] ],
        [ 'VariableBase' => [qr/\$\^\w+/] ]   # Special caret variables like $^X
        ,                                     # Global special vars

        [ 'VariableBase' => [ '${', '^', 'Identifier', '}' ] ],      # ${^NAME}
        [ 'VariableBase' => [ '$',  '{', '^', 'Identifier', '}' ] ], # $ {^NAME}
        [ 'VariableBase' => [ '@{', '^', 'Identifier', '}' ] ],      # @{^NAME}
        [ 'VariableBase' => [ '@',  '{', '^', 'Identifier', '}' ] ], # @ {^NAME}
        [ 'VariableBase' => [ '%{', '^', 'Identifier', '}' ] ],      # %{^NAME}
        [ 'VariableBase' => [ '%',  '{', '^', 'Identifier', '}' ] ], # % {^NAME}

        [ 'VariableBase' => [qr/[@%&*]\$\w+/] ]
        ,
        [ 'VariableBase' => [qr/\$\$\w+/] ],
        [ 'VariableBase' => [qr/\$#\$\w+/] ]
        ,

        [ 'VariableBase' => [ '${', 'Expression', '}' ] ]
        ,
        [ 'VariableBase' => [ '$', '{', 'Expression', '}' ] ]
        ,
        [ 'VariableBase' => [ '@{', 'Expression', '}' ] ]
        ,
        [ 'VariableBase' => [ '%{', 'Expression', '}' ] ]
        ,
        [ 'VariableBase' => [ '@[', 'Expression', ']' ] ]
        ,
        [ 'VariableBase' => [ '%[', 'Expression', ']' ] ]
        ,

        [ 'MaybeElementIndexChain' => [] ],                         # Empty chain (epsilon)
        [ 'MaybeElementIndexChain' => ['Element'] ],
        [ 'MaybeElementIndexChain' => [ 'Element', 'MaybeElementIndexChain' ] ],  # Multiple subscripts

        [ 'ElementIndexChain' => ['Element'] ],
        [ 'ElementIndexChain' => [ 'Element', 'MaybeElementIndexChain' ] ],

        [ 'Element' => ['ArrayElem'] ],
        [ 'Element' => ['HashElem'] ],

        [ 'ArrayElem' => [ '[', 'Expression', ']' ] ],
        [ 'HashElem'  => [ '{', 'Expression', '}' ] ],
        [
            'Identifier' =>
              [$RE_IDENTIFIER]
        ]
        , # Support qualified identifiers, including pathological cases like foo::::bar
        [
            'Number' => [
$RE_NUMBER
            ]
        ],
        [ 'QuotedString' => [qr/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/] ],

        [ 'QuotedString' => [ 'QOp',  'QDelimited' ] ],
        [ 'QuotedString' => [ 'QQOp', 'QDelimited' ] ],

        [ 'QOp'  => [qr/q(?!q)/] ],
        [ 'QQOp' => [qr/qq/] ],
        [ 'QWOp' => [qr/qw/] ],        # qw word list operator
        [ 'MOp'  => [qr/m(?!s)/] ]
        , # m match operator (not ms - negative lookahead for future s/// support)
        [ 'QROp' => [qr/qr/] ],
        [ 'SOp'  => [qr/s/] ],     # s substitution operator
        [ 'TROp' => [qr/tr/] ],
        [ 'YOp'  => [qr/y/] ],     # y transliteration operator (alias for tr)

        [ 'QDelimited' => [$RE_BALANCED_BRACES] ],  # {} with balanced braces
        [ 'QDelimited' => [qr/\((?:[^)]|\n)*\)/] ],       # ()
        [ 'QDelimited' => [qr/\[(?:[^\]]|\n)*\]/] ],      # []
        [ 'QDelimited' => [qr/<(?:[^>]|\n)*>/] ],         # <>
        [ 'QDelimited' => [qr/"(?:[^"\\]|\\.)*"/] ],      # ""
        [ 'QDelimited' => [qr/'(?:[^'\\]|\\.)*'/] ],      # ''
        [ 'QDelimited' => [qr{/(?:[^/\\]|\\.)*+/}] ],     # /.../
        [ 'QDelimited' => [qr/!(?:[^!\\]|\\.)*!/] ],      # !...!
        [ 'QDelimited' => [qr/#(?:[^#\\]|\\.)*#/] ],      # #...#
        [ 'QDelimited' => [qr/\|(?:[^|\\]|\\.)*\|/] ],

        [ 'MDelimited' => [$RE_BALANCED_BRACES_FLAGS] ],  # {} with balanced braces + flags
        [ 'MDelimited' => [qr/\((?:[^)]|\\.)*+\)[a-z]*/] ],         # () + flags
        [ 'MDelimited' => [qr/\[(?:[^\]]|\\.)*+\][a-z]*/] ],        # [] + flags
        [ 'MDelimited' => [qr/<(?:[^>]|\\.)*+>[a-z]*/] ],           # <> + flags
        [ 'MDelimited' => [qr/"(?:[^"\\]|\\.)*+"[a-z]*/] ],         # "" + flags
        [ 'MDelimited' => [qr/'(?:[^'\\]|\\.)*+'[a-z]*/] ],         # '' + flags
        [ 'MDelimited' => [qr{/(?:[^/\\]|\\.)*+/[a-z]*}] ],         # /.../flags
        [ 'MDelimited' => [qr/!(?:[^!\\]|\\.)*+![a-z]*/] ],         # !...!flags
        [ 'MDelimited' => [qr/#(?:[^#\\]|\\.)*+#[a-z]*/] ],         # #...#flags
        [ 'MDelimited' => [qr/\|(?:[^|\\]|\\.)*+\|(?![|])[a-z]*/] ]
        ,

        [ 'PackageSeparator' => ['::'] ],

        [
            'QualifiedIdentifier' =>
              [ 'Identifier', 'PackageSeparator', 'QualifiedIdentifier' ]
        ],
        [
            'QualifiedIdentifier' =>
              [ 'Identifier', 'PackageSeparator', 'Identifier' ]
        ],

        [ 'ParameterList' => ['ExpressionList'] ],
        [ 'ParameterList' => [ 'OpComma', 'Comment' ] ]
        ,                                      # Just comma with comment
        [ 'ParameterList' => ['Comment'] ],
        [ 'ParameterList' => [] ],             # Empty parameter list

        [ 'ArrayRef' => [ '[', 'ExpressionList', ']' ] ],
        [ 'ArrayRef' => [ '[', ']' ] ],        # Empty array
        [ 'HashRef'  => [ '{', 'HashElementList', '}' ] ],
        [ 'HashRef'  => [ '{', '}' ] ],        # Empty hash

        [ 'ExpressionList' => ['Expression'] ],
        [ 'ExpressionList' => [ 'Expression', 'OpComma', 'ExpressionList' ] ]
        ,                                          # Standard recursion
        [ 'ExpressionList' => [ 'Comment', 'ExpressionList' ] ]
        ,                                          # Comment-prefixed lists

        [ 'HashElementList' => ['HashElement'] ],
        [
            'HashElementList' =>
              [ 'HashElement', 'OpComma', 'HashElementList' ]
        ],
        [ 'HashElementList' => [ 'HashElement', 'OpComma' ] ],  # Trailing comma

        [ 'HashElement' => [ 'Expression', 'OpComma', 'Expression' ] ]
        ,                                                       # key => value

        [ 'FileTestOp'         => [$RE_FILETEST] ],
        [ 'OpUnaryKeywordExpr' => [$RE_FILETEST] ]
        ,

        [ 'OpUnaryKeywordExpr' => [$RE_UNARY_KEYWORDS] ],

        [ 'OpAssignKeywordExpr' => [qr/goto|last/] ],
        [ 'OpListKeywordExpr' => [$RE_LIST_KEYWORDS] ],

        [ 'WS_OPT' => [] ],
        [ 'WS_OPT' => ['WS'] ],
        [ 'WS_OPT' => [ 'WS', 'WS_OPT' ] ]
        ,
        [ 'WS' => [qr/\s+/m] ],
        [ 'WS' => [qr/#[^\n]*\n?/m] ]
        ,
        [ 'WS' => [qr/#.*\n\s+/m] ],
        [ 'WS' => [qr/\n=[a-z]\w+\b.*?\n=cut\b.*?\n/s] ]
        ,                               # POD blocks (with leading newline)
        [ 'WS' => [qr/=[a-z]\w+\b.*?\n=cut\b.*?\n/s] ]
        ,
    ]
);

1;
