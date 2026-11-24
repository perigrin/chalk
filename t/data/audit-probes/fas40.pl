my $x=1; sub n { $x++ } if ($x == 1) { n(); print $x; } elsif ($x == 2) { print "no" } print "$x\n";
