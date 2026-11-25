my %h; for (1..2) { my @k=sort keys %h; $h{$_}=1; print scalar(@k) } print "\n";
