sub AUTOLOAD { our $AUTOLOAD; print "A:$AUTOLOAD\n" } { my $x = bless [], "main"; } print "e\n";
