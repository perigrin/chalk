my %h; $h{a}++; $h{b} .= "x"; $h{c} //= 5; $h{d} ||= 6; push @{$h{e}}, 1; print join(",", map {"$_"} sort keys %h), "\n";
