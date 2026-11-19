package Ctr; our $c = 0; sub tick { $c++ } package main; for (1..3) { Ctr::tick(); $Ctr::c += 10 } print "$Ctr::c\n";
