my %h = (a=>1,b=>2); my %g = %h; $g{a} = 9; delete $h{b}; print join(",", map {"$_$h{$_}"} sort keys %h), "|", join(",", map {"$_$g{$_}"} sort keys %g), "\n";
