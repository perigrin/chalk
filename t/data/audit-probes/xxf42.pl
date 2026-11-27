our $g = "a"; { local $g = $g . "b"; { local $g = $g . "c"; print $g } print $g } print "$g\n";
