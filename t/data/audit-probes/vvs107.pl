my $s = "abc"; if ($s =~ /(a)/) { eval { "x" =~ /(x)/ }; print $1 } print "\n";
