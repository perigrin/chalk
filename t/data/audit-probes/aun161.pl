sub AUTOLOAD { our $AUTOLOAD; print "$AUTOLOAD\n" if $AUTOLOAD =~ /DESTROY/ } { my $x = bless [], "main"; } print "e\n";
