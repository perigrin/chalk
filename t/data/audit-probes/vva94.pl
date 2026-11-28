our $x = 1; sub chg { $x = 9 } { local $x = 2; chg(); print $x } print "$x\n";
