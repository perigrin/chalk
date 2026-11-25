my @a = (1,2,3); if (@a > 2) { print "a" } if (@a) { print "b" } print @a ? "c" : "d", !@a ? "e" : "f", @a == 3 ? "g" : "h", scalar(@a) . "", "\n";
