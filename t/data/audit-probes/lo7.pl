our $g = "a"; { local $g = "b"; { local $g = "c"; print $g } print $g } print "$g\n";
