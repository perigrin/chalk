$_ = "t"; for (1..2) { } print "$_\n"; { local $_ = "u"; print } print "$_\n";
