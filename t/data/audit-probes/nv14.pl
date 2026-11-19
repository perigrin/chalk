our @g = (1,2); sub f { return (@g, 9) } my @r = f(); @g = (); print "@r\n";
