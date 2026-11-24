#!/usr/bin/env perl
# ABOUTME: A builtin Call answers Perl's facts about its builtin (from TypeLibrary's signatures and
# ABOUTME: BuiltinTable), and an EntryDef whether its name is perl's own: no backend keeps the lists.

use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::IR::NodeFactory;

my $f = Chalk::IR::NodeFactory->new;
sub builtin ($name) { $f->make('Call', dispatch_kind => 'builtin', name => $name, inputs => []) }
sub sub_call ($kind, $name = 'main::f') { $f->make('Call', dispatch_kind => $kind, name => $name, inputs => []) }

subtest 'is_sub_call: a call of a sub (named, a method, a code value), not a builtin' => sub {
    ok( sub_call($_)->is_sub_call, "$_ is a sub call" ) for qw(direct method indirect);
    ok( !builtin('push')->is_sub_call, 'a builtin is not' );
};

subtest 'mutates_array: from the signature -- an Array operand first' => sub {
    ok( builtin($_)->mutates_array, "$_ changes its array" ) for qw(push pop shift unshift splice);
    ok( !builtin($_)->mutates_array, "$_ does not" ) for qw(keys join sort reverse lc);
    ok( !sub_call( 'direct', 'push' )->mutates_array, 'a sub named push is not the builtin' );
};

subtest 'result_type: the signature\'s, else the table\'s' => sub {
    is( builtin('join')->result_type, 'Str', 'join: a Str (TypeLibrary)' );
    is( builtin('keys')->result_type, 'List', 'keys: a List (TypeLibrary)' );
    is( builtin('lc')->result_type, 'Str', 'lc: a Str (BuiltinTable: no signature)' );
    is( builtin('quotemeta')->result_type, 'Str', 'quotemeta: a Str (BuiltinTable)' );
    is( builtin('no_such_builtin')->result_type, undef, 'an unknown builtin: undef' );
    is( sub_call('direct')->result_type, undef, 'a sub: undef (no builtin signature)' );
};

subtest 'returns_string: its result type is Str' => sub {
    ok( builtin($_)->returns_string, "$_ returns a string" )
        for qw(join sprintf substr lc uc lcfirst ucfirst quotemeta chr);
    ok( !builtin($_)->returns_string, "$_ does not" ) for qw(keys push length shift);
};

subtest 'changes_case: lc, uc, lcfirst, ucfirst' => sub {
    ok( builtin($_)->changes_case, "$_ changes case" ) for qw(lc uc lcfirst ucfirst);
    ok( !builtin($_)->changes_case, "$_ does not" ) for qw(quotemeta join substr);
};

subtest 'is_tie_builtin: tie, tied, untie' => sub {
    ok( builtin($_)->is_tie_builtin, "$_ is of a tie" ) for qw(tie tied untie);
    ok( !builtin($_)->is_tie_builtin, "$_ is not" ) for qw(bless push);
};

subtest 'takes_a_list: what it is given (after its first operand) is a LIST' => sub {
    ok( builtin($_)->takes_a_list, "$_ takes a list" ) for qw(push unshift join sprintf printf die warn);
    ok( !builtin($_)->takes_a_list, "$_ does not" ) for qw(shift pop lc length);
    ok( !sub_call('direct', 'join')->takes_a_list, 'a sub named join is not the builtin' );
};

subtest 'makes_a_string: a builtin returning a string makes one (chr and chop too, as their signatures say)' => sub {
    ok( builtin($_)->makes_a_string, "$_ makes a string" ) for qw(join sprintf substr lc quotemeta chr chop);
    ok( !builtin($_)->makes_a_string, "$_ does not" ) for qw(keys shift length);
    my $s = $f->make('Constant', value => 'a', const_type => 'string');
    my $q = $f->make('Constant', value => 'a', const_type => 'regex');
    ok( $s->makes_a_string, 'a string constant does' );
    ok( !$q->makes_a_string, 'a qr constant does not' );
    ok( $f->make('DefinedOr', inputs => [ $s, builtin('chr') ])->makes_a_string, 'a default of strings does' );
    ok( !$f->make('DefinedOr', inputs => [ $s, $q ])->makes_a_string, 'a default of a qr does not' );
};

subtest 'takes_a_hash: from the signature -- a Hash operand first, taken whole' => sub {
    ok( builtin($_)->takes_a_hash, "$_ takes its hash" ) for qw(keys values each);
    ok( !builtin($_)->takes_a_hash, "$_ does not" ) for qw(push join sort delete lc);
    ok( !sub_call( 'direct', 'keys' )->takes_a_hash, 'a sub named keys is not the builtin' );
};

subtest 'lists_a_hash: keys and values -- its keys or its values, a count in scalar context' => sub {
    ok( builtin($_)->lists_a_hash, "$_ lists a hash" ) for qw(keys values);
    ok( !builtin($_)->lists_a_hash, "$_ does not" ) for qw(each sort join);
    ok( !sub_call( 'method', 'keys' )->lists_a_hash, 'a method named keys is not the builtin' );
};

subtest 'resets_iterator: keys and values start a hash\'s each over' => sub {
    ok( builtin($_)->resets_iterator, "$_ resets it" ) for qw(keys values);
    ok( !builtin($_)->resets_iterator, "$_ does not" ) for qw(each delete sort);
};

subtest 'reorders_list: sort and reverse -- its LIST in another order' => sub {
    ok( builtin($_)->reorders_list, "$_ reorders" ) for qw(sort reverse);
    ok( !builtin($_)->reorders_list, "$_ does not" ) for qw(keys join map);
    ok( !sub_call( 'direct', 'sort' )->reorders_list, 'a sub named sort is not the builtin' );
};

subtest 'reads_its_list: join, sort and reverse -- its LIST read, no element of it written' => sub {
    ok( builtin($_)->reads_its_list, "$_ only reads its list" ) for qw(join sort reverse);
    ok( !builtin($_)->reads_its_list, "$_ is not listed" ) for qw(push shift splice map);
    ok( !sub_call( 'direct', 'join' )->reads_its_list, 'a sub named join is not the builtin' );
};

subtest 'returns_a_list: in list context its value is a list (the signature\'s List, else the table\'s)' => sub {
    ok( builtin($_)->returns_a_list, "$_ returns a list" )
        for qw(keys values each sort splice split reverse caller readline unpack glob localtime);
    ok( !builtin($_)->returns_a_list, "$_ does not" ) for qw(join shift lc length push);
    ok( !sub_call('direct', 'sort')->returns_a_list, 'a sub named sort is not the builtin' );
};

subtest 'gives_a_list: a builtin returning a list, called in list context' => sub {
    my $each = sub ($want) { $f->make('Call', dispatch_kind => 'builtin', name => 'each', want => $want, inputs => []) };
    ok( $each->('list')->gives_a_list, 'each in list context' );
    ok( !$each->('scalar')->gives_a_list, 'each in scalar context: its key alone' );
};

subtest 'does_handle_io: an operation on a filehandle' => sub {
    ok( builtin($_)->does_handle_io, "$_ works a handle" ) for qw(open close eof readline select sselect);
    ok( !builtin($_)->does_handle_io, "$_ does not" ) for qw(formline join chdir);
    ok( !sub_call( 'method', 'close' )->does_handle_io, 'a method named close is not the builtin' );
};

subtest 'result_type: what each builtin returns, where the signatures do not say' => sub {
    is( builtin($_)->result_type, 'Num', "$_: a number (an IV, a UV or an NV)" ) for qw(int abs rand hex oct);
    is( builtin('require')->result_type, 'Int', 'require: 1' );
    is( builtin('index')->result_type, 'Int', 'index: a position (-1 for none)' );
    is( builtin($_)->result_type, 'Boolean', "$_: yes or no" ) for qw(chdir ftdir ftis);
    is( builtin('blessed')->result_type, 'Str', 'blessed: a class name' );
    is( builtin('reftype_of_ref')->result_type, 'Str', 'ref \\$x: a kind of thing' );
};

subtest 'may_be_undef: a builtin whose value may be undef' => sub {
    ok( builtin($_)->may_be_undef, "$_ may be undef" ) for qw(substr blessed ftdir ftis);
    ok( !builtin($_)->may_be_undef, "$_ is not" ) for qw(index join chdir require reftype_of_ref);
    ok( !sub_call( 'direct', 'substr' )->may_be_undef, 'a sub named substr is not the builtin' );
};

subtest 'builtin_family: the kind of builtin it is' => sub {
    my %want = (
        number    => [qw(int abs rand hex oct)],
        path      => [qw(ftdir ftis chdir require)],
        substring => [qw(substr index)],
        object    => [qw(bless blessed reftype_of_ref)],
        array     => [qw(shift pop)],
        list      => [qw(join unpack glob each)],
        warning   => [qw(warn)],
        scalar    => [qw(chr ord time reverse sprintf lock prototype pack formline)],
    );
    for my $fam ( sort keys %want ) { is( builtin($_)->builtin_family, $fam, "$_: $fam" ) for $want{$fam}->@* }
    is( builtin('lc')->builtin_family, undef, 'lc: none' );
    is( sub_call( 'direct', 'int' )->builtin_family, undef, 'a sub named int: none' );
};

subtest 'number_kind: what number a numeric builtin makes of its operand' => sub {
    is( builtin('int')->number_kind,  'integer_part', 'int: its integer part' );
    is( builtin('abs')->number_kind,  'absolute',     'abs: its absolute value' );
    is( builtin('rand')->number_kind, 'random',       'rand: a random number below it' );
    is( builtin($_)->number_kind, 'numeral', "$_: a numeral read" ) for qw(hex oct);
    is( builtin('substr')->number_kind, undef, 'substr: none' );
};

subtest 'case_change: which case, of what' => sub {
    is( builtin('uc')->case_change,      'upper',       'uc' );
    is( builtin('lc')->case_change,      'lower',       'lc' );
    is( builtin('ucfirst')->case_change, 'upper_first', 'ucfirst' );
    is( builtin('lcfirst')->case_change, 'lower_first', 'lcfirst' );
    is( builtin('quotemeta')->case_change, undef, 'quotemeta: none' );
};

subtest 'reads_state: its value is of state a later store may change' => sub {
    ok( builtin($_)->reads_state, "$_ reads it" )
        for qw(keys values each sort caller pos tie untie bless formline join warn time rand);
    ok( !builtin($_)->reads_state, "$_ does not" ) for qw(chdir require int substr lc);
    ok( !sub_call( 'direct', 'keys' )->reads_state, 'a sub named keys is not the builtin' );
};

subtest 'changes_state: it changes state a later read sees' => sub {
    ok( builtin($_)->changes_state, "$_ changes it" ) for qw(chdir require);
    ok( !builtin($_)->changes_state, "$_ does not" ) for qw(ftdir keys int);
    ok( !sub_call( 'direct', 'chdir' )->changes_state, 'a sub named chdir is not the builtin' );
};

subtest 'builtin_kind: what it does, among its family (or the builtins of its column)' => sub {
    my %want = (
        # path
        ftdir => 'is_directory', ftis => 'is_present', chdir => 'changes_directory', require => 'loads_file',
        # substring
        substr => 'piece', index => 'position',
        # object
        bless => 'blesses', blessed => 'class_name', reftype_of_ref => 'referent_kind',
        # list
        join => 'joined', unpack => 'unpacked', glob => 'file_names', each => 'next_pair',
        # scalar
        chr => 'character', ord => 'code_point', time => 'epoch_seconds', reverse => 'reversed',
        sprintf => 'formatted', lock => 'operand', prototype => 'prototype_of', pack => 'packed', formline => 'format_line',
        # an array's end
        shift => 'takes_first', pop => 'takes_last', push => 'adds_last', unshift => 'adds_first', set_arylen => 'sets_last_index',
        # a list's order
        sort => 'sorted',
        # a handle's
        open => 'opens', close => 'closes', eof => 'at_end', readline => 'reads_lines',
        select => 'selects_output', sselect => 'waits_for_handles',
        # a tie's
        tie => 'binds', tied => 'tied_object', untie => 'unbinds',
    );
    is( builtin($_)->builtin_kind, $want{$_}, "$_: $want{$_}" ) for sort keys %want;
    is( builtin('lc')->builtin_kind, undef, 'lc: none (case_change says)' );
    is( builtin('int')->builtin_kind, undef, 'int: none (number_kind says)' );
    is( sub_call( 'direct', 'open' )->builtin_kind, undef, 'a sub named open: none' );
    my %kinds;
    for ( sort keys %want ) { my $fam = builtin($_)->builtin_family // ''; ok( !$kinds{$fam}{ $want{$_} }++, "$_: one of its family's kinds" ) }
    # A KIND SAYS WHAT A BUILTIN DOES, not which it is: none is a builtin's name.
    require Pod::Functions;
    my %perlfunc = map { ( $_ => 1 ) } keys %Pod::Functions::Type, Chalk::Grammar::Perl::BuiltinTable::names();
    is_deeply( [ grep { $perlfunc{$_} } sort values %want ], [], 'no kind is the name of a builtin' );
};

subtest 'a fact true of one builtin a backend asks about' => sub {
    my @facts = (
        [ reads_call_stack         => 'caller',    'the call stack: the site of a call N frames up' ],
        [ gives_match_offset       => 'pos',       'where the last m//g on a variable left off' ],
        [ quotes_metacharacters    => 'quotemeta', 'its string with every regex metacharacter backslashed' ],
        [ ends_program             => 'exit',      'the program ends, with a status' ],
        [ does_nothing_unthreaded  => 'lock',      'without threads, nothing: its value its operand' ],
        [ splits_a_string          => 'split',     'a string\'s fields, between a pattern\'s matches' ],
        [ gives_local_time         => 'localtime', 'a time\'s nine fields, or its text' ],
        [ loads_a_file             => 'require',   'a file compiled in, entered in %INC' ],
        [ advances_iterator        => 'each',      'a hash\'s next pair, by its iterator' ],
    );
    for my $f (@facts) {
        my ( $m, $name, $what ) = @$f;
        ok( builtin($name)->$m, "$m: $name ($what)" );
        ok( !builtin($_)->$m, "$m: not $_" ) for grep { $_ ne $name } qw(caller pos quotemeta exit lock split localtime require each keys);
        ok( !sub_call( 'direct', $name )->$m, "$m: not a sub named $name" );
    }
};

subtest 'defaults_to_topic: of no operand, of $_' => sub {
    ok( builtin($_)->defaults_to_topic, "$_ of nothing is of \$_" ) for qw(int abs hex oct chr ord lc uc length quotemeta);
    ok( !builtin($_)->defaults_to_topic, "$_ is not" ) for qw(rand time shift push);
    ok( !sub_call( 'direct', 'int' )->defaults_to_topic, 'a sub named int is not the builtin' );
};

subtest 'numeral_base: the base a numeral is read in' => sub {
    is( builtin('hex')->numeral_base, 16, 'hex: 16' );
    is( builtin('oct')->numeral_base, 8,  'oct: 8 (or 16, 2 by its prefix)' );
    is( builtin('int')->numeral_base, undef, 'int: none' );
};

subtest 'is_perls_own: a name perl gives its own meaning, by sigil' => sub {
    my $e = sub ($sigil, $symbol) { $f->make('EntryDef', sigil => $sigil, symbol => $symbol, package => 'main') };
    ok( $e->( '$', $_ )->is_perls_own, "\$$_ is perl's" ) for qw(ENV INC ARGV STDIN STDOUT STDERR 0 AUTOLOAD);
    ok( $e->( '@', $_ )->is_perls_own, "\@$_ is perl's" ) for qw(ISA ARGV INC _);
    ok( $e->( '%', $_ )->is_perls_own, "%$_ is perl's" ) for qw(ENV SIG INC);
    ok( !$e->( '$', $_ )->is_perls_own, "\$$_ is the program's" ) for qw(_ a b x ISA);
    ok( !$e->( '@', $_ )->is_perls_own, "\@$_ is the program's" ) for qw(a AUTOLOAD);
};

done_testing;
