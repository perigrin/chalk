my %g = my %h = (a=>1); $g{b} = 2; print join(",", sort keys %h), "|", join(",", sort keys %g), "\n";
