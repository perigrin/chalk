my %h=(a=>1); my $e=\$h{a}; my $n = $h{a} + ($$e = 7); print "$n\n";
