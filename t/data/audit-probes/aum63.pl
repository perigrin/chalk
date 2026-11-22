package B1; sub DESTROY { print "d\n" } package main; my $c = "B" . "1"; { my $x = bless {}, $c; } print "e\n";
