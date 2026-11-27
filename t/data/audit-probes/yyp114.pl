my %h=(a=>1); my $s = join(",", values %h, $h{a}=9); print "$s\n";
