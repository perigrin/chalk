package B1; sub DESTROY { print "d\n" } package K; our @ISA = ("B1"); package main; { my $x = bless {}, "K"; } print "e\n";
