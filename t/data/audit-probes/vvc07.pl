our $x = 1; my %h = (k=>4); *x = \$h{k}; $x++; print "$h{k}\n";
