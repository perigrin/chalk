"abc" =~ /(b)/; my @l = ($1, "xyz" =~ /(y)/, $1); print "@l\n";
