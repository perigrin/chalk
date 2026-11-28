our $x = "a"; { local $x .= "b"; print $x } print "$x\n";
