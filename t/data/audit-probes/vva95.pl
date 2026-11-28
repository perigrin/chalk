our $x = 1; sub chg { $x++ } { local $x = $x; chg(); chg(); print $x } print "$x\n";
