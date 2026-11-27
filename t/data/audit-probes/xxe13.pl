our %hh = (a=>1); *HA = \%hh; our %HA; $HA{b} = 2; print join(",", sort keys %hh), "\n";
