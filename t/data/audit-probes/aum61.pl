package P; sub AUTOLOAD { print "auto\n" } package main; { my $x = bless {}, "P"; } print "e\n";
