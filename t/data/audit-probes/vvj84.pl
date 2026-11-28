my @a = (1,2,3); if (@a) { print "t" } if (@a > 2) { print "g" } unless (@a == 0) { print "n" } print scalar(@a) ? "y" : "n", "\n";
