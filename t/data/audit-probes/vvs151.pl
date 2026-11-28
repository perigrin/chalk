package O; sub m { return } package main; my %h = (a => O->m, b => 1); print join(",", map { "$_=" . ($h{$_} // "u") } sort keys %h), "\n";
