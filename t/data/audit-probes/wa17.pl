my %h = (a=>1); my %g = %h; $g{a} = 2; $h{c} = 3; print join(",", map {"$_$h{$_}"} sort keys %h), "|", join(",", map {"$_$g{$_}"} sort keys %g), "\n";
