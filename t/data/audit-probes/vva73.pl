our $x = 1; if ($x) { local $x = 2; print $x } else { local $x = 3 } print "$x\n";
