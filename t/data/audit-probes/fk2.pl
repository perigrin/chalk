our @g = (1, 2); if (@g > 5) { @g = () } print scalar(@g), "\n"; if (@g) { @g = (7) } print "@g\n";
