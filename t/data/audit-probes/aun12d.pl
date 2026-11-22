my %h = (a=>1); my $s = ""; for my $k (sort keys %h) { $h{b} = 2; $s .= $k } $s .= join "", sort keys %h; print "$s\n";
