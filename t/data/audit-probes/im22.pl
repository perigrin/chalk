my %h; $h{a}{b}{c} = 1; push @{ $h{l} }, 2; print join(",", sort keys %h), " $h{l}[0]\n";
