my %h; my $r=\$h{k}; print exists $h{k} ? "e" : "n", defined $$r ? "d" : "u", "\n";
